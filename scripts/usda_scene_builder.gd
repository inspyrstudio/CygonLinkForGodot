@tool
extends RefCounted
class_name UsdaSceneBuilder

## Builds a Node3D scene tree from a parsed USDA scene. Caches referenced
## meshes per build — create a fresh instance for each import.

var _mesh_cache: Dictionary = {}

## Builds the scene root.
func build(tree: Dictionary, base_dir: String) -> Node3D:
	_mesh_cache.clear()
	var root: Node3D = Node3D.new()
	root.name = "Root"
	var materials: Dictionary = _collect_materials(tree, base_dir)
	for prim: Dictionary in tree.get("prims", []):
		_build_prim(prim, root, root, materials, base_dir)
	return root


# =============================================================================
# MATERIALS
# =============================================================================

## Read the tree and builds a StandardMaterial3D for every `def Material`.
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

## Builds a StandardMaterial3D from a `def Material`. The diffuse input takes
## one of two forms:
##   * `inputs:diffuseColor = (r, g, b)`      -> flat albedo color
##   * `inputs:diffuseColor.connect = <path>` -> follows to a UsdUVTexture
##                                               shader and loads its PNG
func _build_material(prim: Dictionary, base_dir: String) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	var surface: Dictionary = _find_shader(prim, "UsdPreviewSurface")
	if surface.is_empty():
		return mat
		
	var attrs: Dictionary = surface.attrs
	var diffuse: Variant = attrs.get("inputs:diffuseColor", null)
	if diffuse is Array and diffuse.size() == 3:
		mat.albedo_color = Color(diffuse[0], diffuse[1], diffuse[2])
	
	var connect: Variant = attrs.get("inputs:diffuseColor.connect", null)
	if connect is Dictionary and connect.has("_path"):
		var tex_shader: Dictionary = _find_shader_by_name(prim, _prim_name_from_path(connect["_path"]))
		var tex: Texture2D = _load_texture(tex_shader, base_dir)
		if tex != null:
			mat.albedo_texture = tex
	
	var metallic: Variant = attrs.get("inputs:metallic", null)
	if metallic != null:
		mat.metallic = float(metallic)
	
	return mat

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

## Extracts the prim name from a connection path, dropping the output port.
## `/World/Materials/X/diffuseTexture.outputs:rgb` -> `diffuseTexture`
func _prim_name_from_path(path: String) -> String:
	var segments: PackedStringArray = path.split("/")
	var last: String = segments[segments.size() - 1]
	return last.get_slice(".", 0)

## Loads the PNG referenced by a UsdUVTexture shader's `inputs:file`.
## Prefers Godot's imported texture (shared, mipmapped); falls back to a raw
## image load so import order can't leave the texture missing.
func _load_texture(shader: Dictionary, base_dir: String) -> Texture2D:
	if shader.is_empty():
		return null
		
	var file_val: Variant = shader.attrs.get("inputs:file", null)
	if not (file_val is Dictionary and file_val.has("_asset")):
		return null
	
	var abs_path: String = "%s/%s" % [base_dir, file_val["_asset"]]
	if ResourceLoader.exists(abs_path):
		var res: Resource = load(abs_path)
		if res is Texture2D:
			return res
	
	if not FileAccess.file_exists(abs_path):
		push_warning("CygonLink: missing texture %s" % abs_path)
		return null
	
	var img: Image = Image.load_from_file(abs_path)
	if img == null:
		push_warning("CygonLink: cannot load texture %s" % abs_path)
		return null
	return ImageTexture.create_from_image(img)



# =============================================================================
# SCENE
# =============================================================================

func _build_prim(prim: Dictionary, parent: Node3D, owner_root: Node3D, materials: Dictionary, base_dir: String) -> void:
	if prim.name == "Materials":
		return
	
	if prim.get("kind", "def") == "over":
		return
	
	var node: Node3D = _instantiate_reference(prim, base_dir)
	if node == null:
		node = Node3D.new()
		
	node.name = prim.name
	_apply_transform(node, prim.attrs)
	parent.add_child(node)
	_claim_owner_recursive(node, owner_root)
	_apply_material(node, prim.attrs, materials)
	
	for child: Dictionary in prim.children:
		_build_prim(child, node, owner_root, materials, base_dir)

## Parses the prim's referenced file inline and returns a StaticBody3D wrapping the mesh + collider. null if there's no reference or the load fails.
func _instantiate_reference(prim: Dictionary, base_dir: String) -> Node3D:
	var ref: Variant = prim.metadata.get("prepend references", null)
	if not (ref is Dictionary and ref.has("_asset")):
		return null
	
	var abs_path: String = "%s/%s" % [base_dir, ref["_asset"]]
	var mesh: ArrayMesh = _load_referenced_mesh(abs_path)
	if mesh == null:
		return null
	return UsdaMeshBuilder.build_static_body(mesh, "Body")

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

## Builds T * R * S from `xformOp:translate / rotateZYX / scale`. Rotation in degrees.
func _apply_transform(node: Node3D, attrs: Dictionary) -> void:
	var t: Vector3 = _vec3_from(attrs.get("xformOp:translate", null), Vector3.ZERO)
	var r_deg: Vector3 = _vec3_from(attrs.get("xformOp:rotateZYX", null), Vector3.ZERO)
	var s: Vector3 = _vec3_from(attrs.get("xformOp:scale", null), Vector3.ONE)
	var basis: Basis = Basis.from_euler(Vector3(deg_to_rad(r_deg.x), deg_to_rad(r_deg.y), deg_to_rad(r_deg.z)), EULER_ORDER_ZYX).scaled(s)
	node.transform = Transform3D(basis, t)

func _vec3_from(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(value[0], value[1], value[2])
	return fallback

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

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null
