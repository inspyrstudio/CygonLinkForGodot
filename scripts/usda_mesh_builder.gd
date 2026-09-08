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
	var counts: Array = attrs.get("faceVertexCounts", [])
	
	# Precompute each face's start offset into the corner arrays.
	var face_offsets: Array = []
	var offset: int = 0
	for count: int in counts:
		face_offsets.append(offset)
		offset += count
	
	var geo: Dictionary = {
		"points": attrs.get("points", []),
		"normals": attrs.get("normals", []),
		"uvs": attrs.get("primvars:st", []),
		"counts": counts,
		"indices": attrs.get("faceVertexIndices", []),
		"face_offsets": face_offsets,
		"normals_fv": _interpolation_of(attrs, "normals") == "faceVarying",
		"uvs_fv": _interpolation_of(attrs, "primvars:st") == "faceVarying",
		"left_handed": attrs.get("orientation", "rightHanded") == "leftHanded",
	}
	
	var mesh: ArrayMesh = ArrayMesh.new()
	var subsets: Array = _collect_subsets(mesh_prim)
	
	if subsets.is_empty():
		var all_faces: Array = range(counts.size())
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _build_surface(geo, all_faces))
	else:
		for subset: Dictionary in subsets:
			var idx: int = mesh.get_surface_count()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _build_surface(geo, subset.indices))
			mesh.surface_set_name(idx, subset.name)
	return mesh

## Builds the surface arrays for a given list of face indices.
static func _build_surface(geo: Dictionary, faces: Array) -> Array:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var tangents: PackedFloat32Array = PackedFloat32Array()
	var has_normals: bool = not geo.normals.is_empty()
	var has_uvs: bool = not geo.uvs.is_empty()
	var want_tangents: bool = has_normals and has_uvs
	
	for face: int in faces:
		var count: int = geo.counts[face]
		var corner_base: int = geo.face_offsets[face]
		for tri: int in range(1, count - 1):
			var corners: Array = [0, tri, tri + 1]
			_orient_triangle(geo, corner_base, corners, has_normals)
			
			var c0: int = corner_base + corners[0]
			var c1: int = corner_base + corners[1]
			var c2: int = corner_base + corners[2]
			
			var p0: Vector3 = _point_at(geo, c0)
			var p1: Vector3 = _point_at(geo, c1)
			var p2: Vector3 = _point_at(geo, c2)
			verts.append(p0)
			verts.append(p1)
			verts.append(p2)
			
			var n0: Vector3 = Vector3.UP
			var n1: Vector3 = Vector3.UP
			var n2: Vector3 = Vector3.UP
			if has_normals:
				n0 = _normal_at(geo, c0)
				n1 = _normal_at(geo, c1)
				n2 = _normal_at(geo, c2)
				normals.append(n0)
				normals.append(n1)
				normals.append(n2)
				
			var uv0: Vector2 = Vector2.ZERO
			var uv1: Vector2 = Vector2.ZERO
			var uv2: Vector2 = Vector2.ZERO
			if has_uvs:
				uv0 = _uv_at(geo, c0)
				uv1 = _uv_at(geo, c1)
				uv2 = _uv_at(geo, c2)
				uvs.append(uv0)
				uvs.append(uv1)
				uvs.append(uv2)
			
			if want_tangents:
				var basis: Array = _triangle_tangent(p0, p1, p2, uv0, uv1, uv2)
				_append_tangent(tangents, n0, basis[0], basis[1])
				_append_tangent(tangents, n1, basis[0], basis[1])
				_append_tangent(tangents, n2, basis[0], basis[1])
	
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	
	if normals.size() == verts.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
		
	if uvs.size() == verts.size():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	
	if tangents.size() == verts.size() * 4:
		arrays[Mesh.ARRAY_TANGENT] = tangents
	return arrays

## UV of a corner, with V flipped to Godot's top-left origin. Tangents are
## derived from these same values, so both stay consistent.
static func _uv_at(geo: Dictionary, corner: int) -> Vector2:
	var idx: int = corner if geo.uvs_fv else geo.indices[corner]
	var uv: Array = geo.uvs[idx]
	return Vector2(uv[0], 1.0 - uv[1])

## Tangent and bitangent of a triangle, from how its UVs vary across it.
## Returns [tangent, bitangent], both unnormalized.
static func _triangle_tangent(p0: Vector3, p1: Vector3, p2: Vector3, uv0: Vector2, uv1: Vector2, uv2: Vector2) -> Array:
	var e1: Vector3 = p1 - p0
	var e2: Vector3 = p2 - p0
	var d1: Vector2 = uv1 - uv0
	var d2: Vector2 = uv2 - uv0
	
	var det: float = d1.x * d2.y - d2.x * d1.y
	if absf(det) < 1e-12:
		return [e1, e2]
	
	var r: float = 1.0 / det
	return [(e1 * d2.y - e2 * d1.y) * r, (e2 * d1.x - e1 * d2.x) * r]

## Writes one tangent, made perpendicular to [param normal], plus the binormal
## sign Godot uses to rebuild the third axis.
static func _append_tangent(
	out: PackedFloat32Array, normal: Vector3, tangent: Vector3, bitangent: Vector3
) -> void:
	var t: Vector3 = tangent - normal * normal.dot(tangent)
	if t.length_squared() < 1e-16:
		t = normal.cross(Vector3.UP)
		if t.length_squared() < 1e-16:
			t = normal.cross(Vector3.RIGHT)
	t = t.normalized()
	
	out.append(t.x)
	out.append(t.y)
	out.append(t.z)
	out.append(-1.0 if normal.cross(t).dot(bitangent) < 0.0 else 1.0)

## Reorders a triangle's corners in place so its geometric winding faces the
## same direction as its provided normal.
## Falls back to the declared `orientation` when the mesh has no normals.
static func _orient_triangle(geo: Dictionary, corner_base: int, corners: Array, has_normals: bool) -> void:
	if not has_normals:
		if geo.left_handed:
			corners.reverse()
		return
	
	var p0: Vector3 = _point_at(geo, corner_base + corners[0])
	var p1: Vector3 = _point_at(geo, corner_base + corners[1])
	var p2: Vector3 = _point_at(geo, corner_base + corners[2])
	
	var geometric: Vector3 = (p1 - p0).cross(p2 - p0)
	var provided: Vector3 = _normal_at(geo, corner_base + corners[0])
	
	if geometric.dot(provided) > 0.0:
		corners.reverse()

## World-space position of the point referenced by a corner index.
static func _point_at(geo: Dictionary, corner: int) -> Vector3:
	var v: Array = geo.points[geo.indices[corner]]
	return Vector3(v[0], v[1], v[2])

## Provided normal for a corner (per-corner if faceVarying, else per-vertex).
static func _normal_at(geo: Dictionary, corner: int) -> Vector3:
	var idx: int = corner if geo.normals_fv else geo.indices[corner]
	var n: Array = geo.normals[idx]
	return Vector3(n[0], n[1], n[2])

## Collects `GeomSubset` children of the materialBind family. Each entry is
## `{ "name": String, "indices": Array }` where indices are FACE indices.
static func _collect_subsets(mesh_prim: Dictionary) -> Array:
	var out: Array = []
	for child: Dictionary in mesh_prim.get("children", []):
		if child.get("type", "") != "GeomSubset":
			continue
		if child.attrs.get("familyName", "") != "materialBind":
			continue
		var indices: Variant = child.attrs.get("indices", [])
		if indices is Array:
			out.append({"name": child.name, "indices": indices})
	return out

## Returns the `interpolation` value from an attribute's `.meta`, or "" if absent.
static func _interpolation_of(attrs: Dictionary, attr_name: String) -> String:
	var meta: Variant = attrs.get(attr_name + ".meta", {})
	if meta is Dictionary:
		return meta.get("interpolation", "")
	return ""

## Wraps a mesh in a StaticBody3D with a MeshInstance3D and a CollisionShape3D child.
## [param local_transform] is the mesh prim's own transform — Cygon uses it to
## carry an off-center pivot. It goes on the geometry children rather than the
## body so the body's origin stays the prim's pivot.
static func build_static_body(mesh: ArrayMesh, body_name: String, local_transform: Transform3D = Transform3D.IDENTITY,) -> StaticBody3D:
	if mesh == null:
		return null
	var body: StaticBody3D = StaticBody3D.new()
	body.name = body_name

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "MeshInstance"
	mi.transform = local_transform
	mi.mesh = mesh
	body.add_child(mi)

	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.name = "CollisionShape"
	cs.transform = local_transform
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)

	return body
