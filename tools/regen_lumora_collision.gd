# regen_lumora_collision.gd
# Regenerates physics collision for the LumoraOutskirts zone from the current
# zones/LumoraOutskirts.glb and text-splices the result into
# Scenes/lumora_outskirts3d.tscn (a full PackedScene.pack()+save() strips
# ext_resource UIDs and doesn't persist edits inside the instanced glb
# sub-scene, so this edits the .tscn text directly instead).
#
# Run after every Blender re-export of LumoraOutskirts.glb:
#   godot --headless --path . --script res://tools/regen_lumora_collision.gd
# Then sanity-check physics didn't break:
#   godot --headless --path . res://Scenes/lumora_outskirts3d.tscn --quit-after 60
# ...and check stderr for "det == 0" / "cannot be normalized" (singular
# transform from a 0-scale axis on some Blender object — see game_flow.txt).
extends SceneTree

const GLB_PATH := "res://zones/LumoraOutskirts.glb"
const SCENE_PATH := "res://Scenes/lumora_outskirts3d.tscn"
const COLLISION_PARENT_PATH := "NavigationRegion3D/LumoraOutskirts_Collision"
const SUBRES_ID_PREFIX := "ConcavePolygonShape3D_gen"


func _initialize() -> void:
	var packed: PackedScene = load(GLB_PATH)
	if packed == null:
		printerr("Could not load ", GLB_PATH)
		quit(1)
		return

	var glb_root: Node = packed.instantiate()

	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(glb_root, mesh_instances)

	if mesh_instances.is_empty():
		printerr("No MeshInstance3D nodes found in ", GLB_PATH, " — aborting.")
		glb_root.free()
		quit(1)
		return

	var used_names := {}
	var subres_blocks: Array[String] = []
	var node_blocks: Array[String] = []
	var index := 0
	var skipped := 0

	for mi in mesh_instances:
		if not mi.visible:
			skipped += 1
			continue
		var mesh: Mesh = mi.mesh
		if mesh == null:
			skipped += 1
			continue
		var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
		if shape == null or shape.data.is_empty():
			skipped += 1
			continue

		var shape_name := _unique_shape_name(mi.name, used_names)
		var xform := _manual_global_transform(mi)
		var sub_id := "%s%d" % [SUBRES_ID_PREFIX, index]

		# backface_collision = true: without it, ConcavePolygonShape3D only
		# collides on the side the triangle winding/normal faces. Hand-built
		# or edited geometry (e.g. a doorway patched into a deleted cube face)
		# easily ends up with flipped normals, which silently makes that
		# collision one-sided (walkable from one direction, solid wall from
		# the other, or vice versa) instead of erroring — see game_flow.txt.
		subres_blocks.append(
			'[sub_resource type="ConcavePolygonShape3D" id="%s"]\ndata = %s\nbackface_collision = true'
			% [sub_id, _format_vec3_array(shape.data)]
		)
		node_blocks.append(
			'[node name="%s" type="CollisionShape3D" parent="%s" unique_id=%d]\ntransform = %s\nshape = SubResource("%s")'
			% [shape_name, COLLISION_PARENT_PATH, randi() % 2000000000, _format_transform(xform), sub_id]
		)
		index += 1

	glb_root.free()

	print("Generated %d collision shapes (skipped %d hidden/empty meshes)." % [node_blocks.size(), skipped])

	var ok := _splice_into_scene(subres_blocks, node_blocks)
	quit(0 if ok else 1)


func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)


func _unique_shape_name(raw_name: String, used_names: Dictionary) -> String:
	var base := raw_name
	var forbidden := [".", ":", "@", "/", "%", "\""]
	for ch in forbidden:
		base = base.replace(ch, "_")
	var candidate := base + "_shape"
	var n := 2
	while used_names.has(candidate):
		candidate = "%s_shape_%d" % [base, n]
		n += 1
	used_names[candidate] = true
	return candidate


# Manually walks the parent chain multiplying Node3D.transform.
# NOT Node3D.global_transform — that returns identity/errors on a node
# that was never added to a live SceneTree (see game_flow.txt gotcha).
func _manual_global_transform(node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p != null and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _format_transform(t: Transform3D) -> String:
	return "Transform3D(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)" % [
		t.basis.x.x, t.basis.x.y, t.basis.x.z,
		t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	]


func _format_vec3_array(data: PackedVector3Array) -> String:
	var parts: Array[String] = []
	for v in data:
		parts.append(str(v.x))
		parts.append(str(v.y))
		parts.append(str(v.z))
	return "PackedVector3Array(%s)" % ", ".join(parts)


func _splice_into_scene(subres_blocks: Array[String], node_blocks: Array[String]) -> bool:
	var file := FileAccess.open(SCENE_PATH, FileAccess.READ)
	if file == null:
		printerr("Could not open ", SCENE_PATH)
		return false
	var text := file.get_as_text()
	file.close()

	var had_trailing_newline := text.ends_with("\n")
	var blocks := text.split("\n\n")

	var new_blocks: Array[String] = []
	var inserted_subres := false
	var inserted_nodes := false

	for block in blocks:
		if block.begins_with('[sub_resource type="ConcavePolygonShape3D" id="%s' % SUBRES_ID_PREFIX):
			if not inserted_subres:
				new_blocks.append_array(subres_blocks)
				inserted_subres = true
			continue
		if block.begins_with('[node name="') \
				and block.find('parent="%s"' % COLLISION_PARENT_PATH) != -1 \
				and block.find('type="CollisionShape3D"') != -1:
			if not inserted_nodes:
				new_blocks.append_array(node_blocks)
				inserted_nodes = true
			continue
		new_blocks.append(block)

	if not inserted_subres or not inserted_nodes:
		printerr("Could not locate existing collision sub_resource/node blocks in ", SCENE_PATH,
			" — scene structure may have changed. Aborting without writing.")
		return false

	var new_text := "\n\n".join(new_blocks)
	if had_trailing_newline and not new_text.ends_with("\n"):
		new_text += "\n"

	var out := FileAccess.open(SCENE_PATH, FileAccess.WRITE)
	if out == null:
		printerr("Could not open ", SCENE_PATH, " for writing")
		return false
	out.store_string(new_text)
	out.close()

	print("Wrote ", SCENE_PATH)
	return true
