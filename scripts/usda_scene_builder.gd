@tool
extends RefCounted
class_name UsdaSceneBuilder

## Builds a Node3D scene tree from a parsed USDA scene. Caches referenced
## meshes per build — create a fresh instance for each import.

## Shader file name, loaded relative to this script so the plugin keeps working
## even if its folder is renamed or moved out of `addons/`.
const _MATERIAL_SHADER_FILE: String = "cygon_material.gdshader"

var _mesh_cache: Dictionary = {}
var _material_shader: Shader = null

var _prototypes: Dictionary = {}

## Lazily loads the shared material shader sitting next to this script.
func _get_material_shader() -> Shader:
	if _material_shader == null:
		var dir: String = get_script().resource_path.get_base_dir()
		_material_shader = load(dir.path_join(_MATERIAL_SHADER_FILE)) as Shader
	return _material_shader

## Builds the scene root.
func build(tree: Dictionary, base_dir: String) -> Node3D:
	_mesh_cache.clear()
	_prototypes.clear()
	for prim: Dictionary in tree.get("prims", []):
		_index_prims(prim, "")
	
	var root: Node3D = Node3D.new()
	root.name = "Root"
	var materials: Dictionary = _collect_materials(tree, base_dir)
	for prim: Dictionary in tree.get("prims", []):
		_build_prim(prim, root, root, materials, base_dir)
	return root

## Records every prim by USD path, which is what reference targets are written
## against. Done in one pass up front because a reference can point at a
## prototype declared later in the file than the prim using it.
func _index_prims(prim: Dictionary, parent_path: String) -> void:
	var path: String = "%s/%s" % [parent_path, prim.name]
	_prototypes[path] = prim
	for child: Dictionary in prim.get("children", []):
		_index_prims(child, path)



# =============================================================================
# MATERIALS
# =============================================================================

## Read the tree and builds a ShaderMaterial for every `def Material`.
func _collect_materials(tree: Dictionary, base_dir: String) -> Dictionary:
	var out: Dictionary = {}
	for prim: Dictionary in tree.get("prims", []):
		_walk_materials(prim, "", base_dir, out)
	return out

func _walk_materials(prim: Dictionary, parent_path: String, base_dir: String, out: Dictionary) -> void:
	var path: String = "%s/%s" % [parent_path, prim.name]
	if prim.type == "Material":
		out[path] = _build_material(prim, base_dir)
	
	for child: Dictionary in prim.children:
		_walk_materials(child, path, base_dir, out)

## Builds a ShaderMaterial from a `def Material`. Reads the UsdPreviewSurface
## shader and, for each input, either a flat value or a connected UsdUVTexture:
##   * diffuseColor -> albedo_color / albedo_tex
##   * normal       -> normal_tex
##   * metallic / roughness -> scalar
## UV scale/rotation/translation come from the connected UsdTransform2d.
func _build_material(prim: Dictionary, base_dir: String) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _get_material_shader()
	var surface: Dictionary = _find_shader(prim, "UsdPreviewSurface")
	if surface.is_empty():
		return mat
		
	var attrs: Dictionary = surface.attrs
	
	var diffuse: Variant = attrs.get("inputs:diffuseColor", null)
	if diffuse is Array and diffuse.size() == 3:
		mat.set_shader_parameter("albedo_color", Color(diffuse[0], diffuse[1], diffuse[2]))
	
	var diffuse_shader: Dictionary = _connected_shader(prim, attrs, "inputs:diffuseColor")
	if not diffuse_shader.is_empty():
		var tex: Texture2D = _load_texture(diffuse_shader, base_dir)
		if tex != null:
			mat.set_shader_parameter("albedo_tex", tex)
			mat.set_shader_parameter("use_albedo_tex", true)
			_apply_texture_transform(mat, prim, diffuse_shader)
	
	var normal_shader: Dictionary = _connected_shader(prim, attrs, "inputs:normal")
	if not normal_shader.is_empty():
		var normal_tex: Texture2D = _load_texture(normal_shader, base_dir)
		if normal_tex != null:
			mat.set_shader_parameter("normal_tex", normal_tex)
			mat.set_shader_parameter("use_normal_tex", true)
	
	var metallic: Variant = attrs.get("inputs:metallic", null)
	if metallic != null:
		mat.set_shader_parameter("metallic_value", float(metallic))
	
	var roughness: Variant = attrs.get("inputs:roughness", null)
	if roughness != null:
		mat.set_shader_parameter("roughness_value", float(roughness))
	
	return mat

## Sets the UV scale/rotation/translation shader parameters from the connected
## UsdTransform2d shader. Rotation is in degrees in USD, converted to radians.
func _apply_texture_transform(mat: ShaderMaterial, material_prim: Dictionary, tex_shader: Dictionary) -> void:
	if tex_shader.is_empty():
		return
	
	var st_connect: Variant = tex_shader.attrs.get("inputs:st.connect", null)
	if not (st_connect is Dictionary and st_connect.has("_path")):
		return
	
	var xform: Dictionary = _find_shader_by_name(material_prim, _prim_name_from_path(st_connect["_path"]))
	if xform.is_empty():
		return
	
	var scale: Variant = xform.attrs.get("inputs:scale", null)
	if scale is Array and scale.size() == 2:
		mat.set_shader_parameter("uv_scale", Vector2(scale[0], scale[1]))
	
	var translation: Variant = xform.attrs.get("inputs:translation", null)
	if translation is Array and translation.size() == 2:
		mat.set_shader_parameter("uv_offset", Vector2(translation[0], translation[1]))
	
	var rotation: Variant = xform.attrs.get("inputs:rotation", null)
	if rotation != null:
		mat.set_shader_parameter("uv_rotation", deg_to_rad(float(rotation)))

## Finds the first child Shader whose `info:id` matches [param info_id].
func _find_shader(material_prim: Dictionary, info_id: String) -> Dictionary:
	for child: Dictionary in material_prim.children:
		if child.type == "Shader" and child.attrs.get("info:id", "") == info_id:
			return child
	return {}

## Finds a child Shader by prim name.
func _find_shader_by_name(material_prim: Dictionary, shader_name: String) -> Dictionary:
	for child: Dictionary in material_prim.children:
		if child.type == "Shader" and child.name == shader_name:
			return child
	return {}

## Returns the shader connected to `input_name` (e.g. "inputs:normal"), or {}
## if that input is absent or not wired to a shader.
func _connected_shader(material_prim: Dictionary, attrs: Dictionary, input_name: String) -> Dictionary:
	var connect: Variant = attrs.get(input_name + ".connect", null)
	if not (connect is Dictionary and connect.has("_path")):
		return {}
	return _find_shader_by_name(material_prim, _prim_name_from_path(connect["_path"]))

## Extracts the prim name from a connection path, dropping the output port.
## `/World/Materials/X/diffuseTexture.outputs:rgb` -> `diffuseTexture`
func _prim_name_from_path(path: String) -> String:
	var segments: PackedStringArray = path.split("/")
	var last: String = segments[segments.size() - 1]
	return last.get_slice(".", 0)

## Loads the texture referenced by a UsdUVTexture shader's `inputs:file`.
## References Godot's imported texture instead of reading the PNG into an
## ImageTexture. Referencing the import also shares one texture between materials and keeps VRAM compression.
func _load_texture(shader: Dictionary, base_dir: String) -> Texture2D:
	if shader.is_empty():
		return null
	
	var file_val: Variant = shader.attrs.get("inputs:file", null)
	if not (file_val is Dictionary and file_val.has("_asset")):
		return null
	
	var abs_path: String = "%s/%s" % [base_dir, file_val["_asset"]]
	if not FileAccess.file_exists(abs_path):
		push_warning("CygonLink: missing texture %s" % abs_path)
		return null
	
	if not ResourceLoader.exists(abs_path):
		push_warning("CygonLink: texture not imported yet, reimport to apply: %s" % abs_path)
		return null
	
	var res: Resource = load(abs_path)
	if res is Texture2D:
		return res
	
	push_warning("CygonLink: %s did not import as a texture" % abs_path)
	return null



# =============================================================================
# SCENE
# =============================================================================

func _build_prim(prim: Dictionary, parent: Node3D, owner_root: Node3D, materials: Dictionary, base_dir: String) -> void:
	if prim.name == "Materials":
		return
	
	var kind: String = prim.get("kind", "def")
	if kind == "over" or kind == "class":
		return
	
	var mesh_prim: Dictionary = _resolve_mesh_prim(prim)
	var node: Node3D = _build_geometry_node(prim, mesh_prim, base_dir)
	if node == null:
		node = Node3D.new()
		
	node.name = prim.name
	_apply_transform(node, prim.attrs)
	parent.add_child(node)
	_claim_owner_recursive(node, owner_root)
	
	for child: Dictionary in prim.children:
		if child.get("type", "") == "Mesh":
			continue
		_build_prim(child, node, owner_root, materials, base_dir)
	
	var subset_bindings: Dictionary = _collect_subset_bindings(prim, mesh_prim)
	if subset_bindings.is_empty():
		_apply_material(node, prim.attrs, materials)
	else:
		_apply_subset_materials(node, subset_bindings, materials)
	
## Finds the Mesh prim supplying this prim's geometry, either inline as a child
## or through a `prepend references` path into the `class` prototypes. Returns {}
## for a prim with no geometry of its own.
func _resolve_mesh_prim(prim: Dictionary) -> Dictionary:
	var inline_mesh: Dictionary = _inline_mesh_child(prim)
	if not inline_mesh.is_empty():
		return inline_mesh

	var proto_path: String = _reference_path(prim)
	if proto_path.is_empty():
		return {}

	var prototype: Variant = _prototypes.get(proto_path, null)
	if prototype == null:
		push_warning("CygonLink: unresolved reference %s" % proto_path)
		return {}
	return UsdaMeshBuilder.find_first_mesh(prototype)

## Builds a StaticBody3D wrapping the prim's geometry + collider.
func _build_geometry_node(prim: Dictionary, mesh_prim: Dictionary, base_dir: String) -> Node3D:
	if not mesh_prim.is_empty():
		# Prototypes are shared by many instances, so build each one once.
		var cache_key: String = _reference_path(prim)
		var mesh: ArrayMesh = null
		if not cache_key.is_empty() and _mesh_cache.has(cache_key):
			mesh = _mesh_cache[cache_key]
		else:
			mesh = UsdaMeshBuilder.build(mesh_prim)
			if not cache_key.is_empty():
				_mesh_cache[cache_key] = mesh
		if mesh == null:
			return null
		return UsdaMeshBuilder.build_static_body(mesh, "Body", _transform_from(mesh_prim.attrs))
	
	var file_mesh: ArrayMesh = _referenced_mesh(prim, base_dir)
	if file_mesh == null:
		return null
	return UsdaMeshBuilder.build_static_body(file_mesh, "Body")

## Returns the prim's direct `def Mesh` child, or {} if it has none.
func _inline_mesh_child(prim: Dictionary) -> Dictionary:
	for child: Dictionary in prim.get("children", []):
		if child.get("type", "") == "Mesh":
			return child
	return {}

## Prim path a `prepend references` points at, or "" when the reference is
## absent or names an external file rather than a path in this scene.
func _reference_path(prim: Dictionary) -> String:
	var ref: Variant = prim.get("metadata", {}).get("prepend references", null)
	if ref is Dictionary and ref.has("_path"):
		return ref["_path"]
	return ""

## Loads the mesh from the prim's `prepend references` asset, or null if the
## prim has no reference.
func _referenced_mesh(prim: Dictionary, base_dir: String) -> ArrayMesh:
	var ref: Variant = prim.metadata.get("prepend references", null)
	if not (ref is Dictionary and ref.has("_asset")):
		return null
	return _load_referenced_mesh("%s/%s" % [base_dir, ref["_asset"]])

## Sets owner_root as owner of node and all descendants missing one — so the StaticBody3D's children save into the packed scene.
func _claim_owner_recursive(node: Node, owner_root: Node) -> void:
	if node.owner == null:
		node.owner = owner_root
	
	for child: Node in node.get_children():
		_claim_owner_recursive(child, owner_root)

## Reads and parses a referenced mesh file from disk.
func _load_referenced_mesh(abs_path: String) -> ArrayMesh:
	if _mesh_cache.has(abs_path):
		return _mesh_cache[abs_path]
	
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		push_warning("CygonLink: cannot open referenced mesh %s" % abs_path)
		_mesh_cache[abs_path] = null
		return null
	
	var parser: UsdaParser = UsdaParser.new()
	var tree: Dictionary = parser.parse(file.get_as_text())
	if not parser.error.is_empty():
		push_warning("CygonLink: %s — %s" % [abs_path, parser.error])
		_mesh_cache[abs_path] = null
		return null
	
	var mesh_prim: Dictionary = UsdaMeshBuilder.find_first_mesh_in_tree(tree)
	if mesh_prim.is_empty():
		_mesh_cache[abs_path] = null
		return null
	
	var mesh: ArrayMesh = UsdaMeshBuilder.build(mesh_prim)
	_mesh_cache[abs_path] = mesh
	return mesh



# =============================================================================
# TRANSFORM & MATERIAL APPLICATION
# =============================================================================

## Euler rotation ops, mapped to the Godot rotation order that reproduces them.
## The letters are reversed on purpose. USD names the op after the order its
## rotations are *applied* in (`rotateZXY` = Z first, then X, then Y), while
## Godot's EULER_ORDER_ZXY *composes* the matrix Z*X*Y, which applies Y first.
## Reversing the name gives the matching composition order.
const _ROTATION_OPS: Dictionary = {
	"xformOp:rotateXYZ": EULER_ORDER_ZYX,
	"xformOp:rotateXZY": EULER_ORDER_YZX,
	"xformOp:rotateYXZ": EULER_ORDER_ZXY,
	"xformOp:rotateYZX": EULER_ORDER_XZY,
	"xformOp:rotateZXY": EULER_ORDER_YXZ,
	"xformOp:rotateZYX": EULER_ORDER_XYZ,
}

func _apply_transform(node: Node3D, attrs: Dictionary) -> void:
	node.transform = _transform_from(attrs)

## Builds T * R * S from `xformOp:translate / rotate<Order> / scale`
func _transform_from(attrs: Dictionary) -> Transform3D:
	var t: Vector3 = _vec3_from(attrs.get("xformOp:translate", null), Vector3.ZERO)
	var s: Vector3 = _vec3_from(attrs.get("xformOp:scale", null), Vector3.ONE)
	
	var r_deg: Vector3 = Vector3.ZERO
	var order: int = EULER_ORDER_XYZ
	for op: String in _ROTATION_OPS:
		if attrs.has(op):
			r_deg = _vec3_from(attrs[op], Vector3.ZERO)
			order = _ROTATION_OPS[op]
			break
	
	var euler: Vector3 = Vector3(deg_to_rad(r_deg.x), deg_to_rad(r_deg.y), deg_to_rad(r_deg.z))
	var basis: Basis = Basis.from_euler(euler, order) * Basis.from_scale(s)
	return Transform3D(basis, t)

func _vec3_from(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(value[0], value[1], value[2])
	return fallback

## Applies a single `material:binding` attribute as a material_override,
## covering every surface of the mesh.
func _apply_material(node: Node3D, attrs: Dictionary, materials: Dictionary) -> void:
	var binding: Variant = attrs.get("material:binding", null)
	if not (binding is Dictionary and binding.has("_path")):
		return
	var mat: Variant = materials.get(binding["_path"], null)
	if mat == null:
		return
	var mi: MeshInstance3D = _find_mesh_instance(node)
	if mi != null:
		mi.material_override = mat

## Collects per-subset material bindings, keyed by subset name. Bindings live
## either on the GeomSubsets of the mesh itself (whether inline or reached
## through a prototype) or, in legacy files, on an `over` block mirroring it.
func _collect_subset_bindings(prim: Dictionary, mesh_prim: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	
	if not mesh_prim.is_empty():
		_read_subset_bindings(mesh_prim, out)
	
	for over_block: Dictionary in prim.get("children", []):
		if over_block.get("kind", "def") == "over":
			_read_subset_bindings(over_block, out)
	return out

## Reads `material:binding` off every child of [param container] that declares
## one, into [param out] keyed by child name.
func _read_subset_bindings(container: Dictionary, out: Dictionary) -> void:
	for subset: Dictionary in container.get("children", []):
		var binding: Variant = subset.attrs.get("material:binding", null)
		if binding is Dictionary and binding.has("_path"):
			out[subset.name] = binding["_path"]

## Applies per-subset materials as surface overrides, matching subset names to
## the mesh's named surfaces (set by [UsdaMeshBuilder]).
func _apply_subset_materials(node: Node3D, bindings: Dictionary, materials: Dictionary) -> void:
	var mi: MeshInstance3D = _find_mesh_instance(node)
	if mi == null or mi.mesh == null:
		return
	
	var mesh: ArrayMesh = mi.mesh as ArrayMesh
	if mesh == null:
		return
	
	for i: int in mesh.get_surface_count():
		var surface_name: String = mesh.surface_get_name(i)
		if not bindings.has(surface_name):
			continue
		
		var mat: Variant = materials.get(bindings[surface_name], null)
		if mat != null:
			mi.set_surface_override_material(i, mat)

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null
