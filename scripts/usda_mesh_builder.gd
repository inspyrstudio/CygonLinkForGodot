@tool
extends RefCounted
class_name UsdaMeshBuilder

## Builds Godot [ArrayMesh] resources from parsed USDA Mesh prims.

## Searches the entire tree for the first `def Mesh` prim. Returns {} if none is found.
static func find_first_mesh_in_tree(tree: Dictionary) -> Dictionary:
	for prim: Dictionary in tree.get("prims", []):
		var found: Dictionary = find_first_mesh(prim)
		if not found.is_empty():
			return found
	return {}

## Recursive search rooted at prim.
static func find_first_mesh(prim: Dictionary) -> Dictionary:
	if prim.get("type", "") == "Mesh":
		return prim
	
	for child: Dictionary in prim.get("children", []):
		var found: Dictionary = find_first_mesh(child)
		if not found.is_empty():
			return found
	return {}

## Builds an [ArrayMesh] from a parsed Mesh.
static func build(mesh_prim: Dictionary) -> ArrayMesh:
	var attrs: Dictionary = mesh_prim.attrs
	var points: Array = attrs.get("points", [])
	var normals_src: Array = attrs.get("normals", [])
	var uvs_src: Array = attrs.get("primvars:st", [])
	var counts: Array = attrs.get("faceVertexCounts", [])
	var indices: Array = attrs.get("faceVertexIndices", [])

	var normals_face_varying: bool = _interpolation_of(attrs, "normals") == "faceVarying"
	var uvs_face_varying: bool = _interpolation_of(attrs, "primvars:st") == "faceVarying"

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()

	var corner_base: int = 0
	for count: int in counts:
		for tri: int in range(1, count - 1):
			for k: int in [0, tri, tri + 1]:
				var corner: int = corner_base + k
				var vertex_index: int = indices[corner]
				var p: Array = points[vertex_index]
				verts.append(Vector3(p[0], p[1], p[2]))
				
				if not normals_src.is_empty():
					var n_idx: int = corner if normals_face_varying else vertex_index
					var n: Array = normals_src[n_idx]
					normals.append(Vector3(n[0], n[1], n[2]))
				
				if not uvs_src.is_empty():
					var uv_idx: int = corner if uvs_face_varying else vertex_index
					var uv: Array = uvs_src[uv_idx]
					uvs.append(Vector2(uv[0], 1.0 - uv[1]))
		corner_base += count

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	
	if normals.size() == verts.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
		
	if uvs.size() == verts.size():
		arrays[Mesh.ARRAY_TEX_UV] = uvs

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Returns the `interpolation` value from an attribute's `.meta`, or "" if absent.
static func _interpolation_of(attrs: Dictionary, attr_name: String) -> String:
	var meta: Variant = attrs.get(attr_name + ".meta", {})
	if meta is Dictionary:
		return meta.get("interpolation", "")
	return ""

## Wraps a mesh in a StaticBody3D with a MeshInstance3D and a CollisionShape3D child.
static func build_static_body(mesh: ArrayMesh, body_name: String) -> StaticBody3D:
	if mesh == null:
		return null
	var body: StaticBody3D = StaticBody3D.new()
	body.name = body_name

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "MeshInstance"
	mi.mesh = mesh
	body.add_child(mi)

	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.name = "CollisionShape"
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)

	return body
