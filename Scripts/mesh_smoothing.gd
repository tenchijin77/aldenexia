# mesh_smoothing.gd — smooth shading for character models (test 35: faces looked "low poly"). The Meshy/Mixamo FBX exports
# carry hard edges on many triangles (a third of the half-elf female's were flat-shaded), so every facet was lit on its
# own. Blender and Mixamo draw them smoothed; Godot draws the file as it is. This recomputes each vertex normal as the
# area-weighted average of the triangles touching that POINT (vertices split along UV seams count together) that are
# within 60 degrees of it — Blender's auto smooth — so real creases stay sharp. Keeps skinning, UVs and blend shapes,
# and re-aligns the tangents. Each mesh is done once and cached: every character using
# that model shares the smoothed copy.
class_name MeshSmoothing
extends RefCounted

static var _cache: Dictionary = {}   # original Mesh -> smoothed ArrayMesh
const SMOOTH_ANGLE := 60.0           # degrees: like Blender's auto smooth
static var SMOOTH_COS := cos(deg_to_rad(SMOOTH_ANGLE))


# Smooths every MeshInstance3D under `root` (a character model just instantiated).
static func smooth_model(root: Node) -> void:
	if root == null or Net.is_dedicated_server or DisplayServer.get_name() == "headless":
		return   # nothing is drawn there
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh is ArrayMesh:
			inst.mesh = smoothed(inst.mesh)


static func smoothed(mesh: ArrayMesh) -> ArrayMesh:
	if _cache.has(mesh):
		return _cache[mesh]
	var out := ArrayMesh.new()
	out.blend_shape_mode = mesh.blend_shape_mode
	for i in mesh.get_blend_shape_count():
		out.add_blend_shape(mesh.get_blend_shape_name(i))
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES and arrays[Mesh.ARRAY_NORMAL] != null:
			_smooth_arrays(arrays)
		var flags := mesh.surface_get_format(s) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, mesh.surface_get_blend_shape_arrays(s), {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
		out.surface_set_name(out.get_surface_count() - 1, mesh.surface_get_name(s))
	_cache[mesh] = out
	return out


static func _smooth_arrays(arrays: Array) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var original := normals.duplicate()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tri_count := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
	# one bucket per point in space (vertices split along seams share it), holding the faces that touch that point
	var bucket_of := PackedInt32Array()
	bucket_of.resize(verts.size())
	var bucket_index := {}
	var faces: Array = []   # per bucket: [face vector (area-weighted), ...]
	for v in verts.size():
		var key := Vector3i(roundi(verts[v].x * 10000.0), roundi(verts[v].y * 10000.0), roundi(verts[v].z * 10000.0))
		if not bucket_index.has(key):
			bucket_index[key] = faces.size()
			faces.append([])
		bucket_of[v] = bucket_index[key]
	for t in tri_count:
		var i0 := idx[t * 3] if idx.size() > 0 else t * 3
		var i1 := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
		var i2 := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
		var face := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])   # length = twice the area: bigger faces count more
		if face.length_squared() < 1e-14:
			continue
		# keep the file's winding: face normals point the way the original normals do
		if face.dot(original[i0] + original[i1] + original[i2]) < 0.0:
			face = -face
		for i in [i0, i1, i2]:
			faces[bucket_of[i]].append(face)
	# Each vertex: the faces at its point that are within SMOOTH_ANGLE of its own original normal. A flat-shaded facet
	# blends with its gently-angled neighbours; a real crease (armour rims, fingers) stays sharp.
	for v in verts.size():
		var sum := Vector3.ZERO
		for face in faces[bucket_of[v]]:
			if face.normalized().dot(original[v]) >= SMOOTH_COS:
				sum += face
		if sum.length_squared() > 1e-14:
			normals[v] = sum.normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	# tangents: keep their direction and handedness, made perpendicular to the new normal again
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for v in verts.size():
			var t := Vector3(tangents[v * 4], tangents[v * 4 + 1], tangents[v * 4 + 2])
			t = (t - normals[v] * normals[v].dot(t))
			if t.length_squared() < 1e-12:
				t = normals[v].cross(Vector3.UP if absf(normals[v].y) < 0.9 else Vector3.RIGHT)
			t = t.normalized()
			tangents[v * 4] = t.x
			tangents[v * 4 + 1] = t.y
			tangents[v * 4 + 2] = t.z
		arrays[Mesh.ARRAY_TANGENT] = tangents
