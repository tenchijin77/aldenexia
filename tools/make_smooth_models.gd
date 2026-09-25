# make_smooth_models.gd — turns a smoothed character mesh from Blender (tools/blender/smooth_character.py -> .glb) into
# <model folder>/<key>_smooth_mesh.res, which MeshSmoothing swaps in for the Meshy FBX's faceted mesh (2026-09-25).
# Only the MESH is replaced: the FBX's skeleton, skin (bind poses, by bone name) and animations stay as they are, so the
# glb's bone indices are remapped onto the FBX skin's binds by name. Adds distance LODs (Godot's own, keeps UVs).
#   godot --headless --path . --script res://tools/make_smooth_models.gd -- "<res://...Breathing Idle.fbx>" <smoothed.glb>
# (tools/smooth_models.sh runs Blender and this for every character model.)
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <model scene .fbx (the CHARACTER_MODELS 'scene')> <smoothed.glb>")
		quit(1)
		return
	var err := build(args[0].get_file(), {"scene": args[0]}, args[1])
	if not err.is_empty():
		printerr(err)
		quit(1)
		return
	quit(0)


static func build(key: String, info: Dictionary, glb_path: String) -> String:
	var fbx: Node = load(str(info["scene"])).instantiate()
	var fbx_mi := _first_mesh(fbx)
	if fbx_mi == null or fbx_mi.skin == null:
		return "%s: no skinned mesh in %s" % [key, info["scene"]]
	var bind_of := {}   # bone name -> the FBX skin's bind index
	for b in fbx_mi.skin.get_bind_count():
		var name := str(fbx_mi.skin.get_bind_name(b))
		if name.is_empty():
			var sk := fbx_mi.get_node_or_null(fbx_mi.skeleton) as Skeleton3D
			name = sk.get_bone_name(fbx_mi.skin.get_bind_bone(b)) if sk else ""
		bind_of[name] = b

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(glb_path, state) != OK:
		return "%s: can't read %s" % [key, glb_path]
	var glb: Node = doc.generate_scene(state)
	var glb_mi := _first_mesh(glb)
	if glb_mi == null or glb_mi.skin == null:
		return "%s: no skinned mesh in %s" % [key, glb_path]
	var glb_sk := glb_mi.get_node_or_null(glb_mi.skeleton) as Skeleton3D
	var remap := PackedInt32Array()
	for b in glb_mi.skin.get_bind_count():
		var name := str(glb_mi.skin.get_bind_name(b))
		if name.is_empty() and glb_sk:
			name = glb_sk.get_bone_name(glb_mi.skin.get_bind_bone(b))
		if not bind_of.has(name):
			return "%s: bone '%s' of the smoothed mesh isn't in the FBX skin" % [key, name]
		remap.append(bind_of[name])

	# The two meshes must sit in the same space (feet on 0, same facing): compare their bounds.
	var a: AABB = fbx_mi.mesh.get_aabb()
	var src_mesh: Mesh = glb_mi.mesh
	var out_mesh := ImporterMesh.new()
	# the appearance sliders' shapes (bust, waist, hips, weight, muscle: tools/blender/shape_body.py) come along as blend
	# shapes; skinning is untouched by them
	out_mesh.set_blend_shape_mode(Mesh.BLEND_SHAPE_MODE_RELATIVE)
	for b in src_mesh.get_blend_shape_count():
		out_mesh.add_blend_shape(src_mesh.get_blend_shape_name(b))
	for s in src_mesh.get_surface_count():
		var arrays := src_mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for i in bones.size():
			bones[i] = remap[bones[i]]
		arrays[Mesh.ARRAY_BONES] = bones
		out_mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, src_mesh.surface_get_blend_shape_arrays(s), {}, fbx_mi.mesh.surface_get_material(mini(s, fbx_mi.mesh.get_surface_count() - 1)), "smooth")
	out_mesh.generate_lods(25.0, 60.0, [])
	var mesh := out_mesh.get_mesh()
	# the base vertices' bounds (the mesh's own AABB also covers its blend shapes at full strength)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b2 := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		b2 = b2.expand(v)
	if a.size.distance_to(b2.size) > 0.05 * a.size.length() or a.position.distance_to(b2.position) > 0.05 * a.size.length():
		return "%s: the smoothed mesh doesn't line up with the FBX's (%s vs %s)" % [key, str(b2), str(a)]
	var out_path := smooth_mesh_path(info)
	var e := ResourceSaver.save(mesh, out_path, ResourceSaver.FLAG_COMPRESS)
	if e != OK:
		return "%s: can't save %s" % [key, out_path]
	var tris := 0
	for s in mesh.get_surface_count():
		tris += mesh.surface_get_array_index_len(s) / 3
	var shapes := []
	for b in mesh.get_blend_shape_count():
		shapes.append(mesh.get_blend_shape_name(b))
	print("%s: %s (%d triangles, shapes %s; was %d)" % [key, out_path, tris, str(shapes),
			fbx_mi.mesh.surface_get_array_index_len(0) / 3])
	fbx.free()
	glb.free()
	return ""


# Same as MeshSmoothing.rebuilt_mesh_path() (not called: that script needs the game's autoloads, which --script lacks).
static func smooth_mesh_path(info: Dictionary) -> String:
	var scene := str(info["scene"])
	return scene.get_base_dir().path_join(scene.get_file().get_basename().to_snake_case() + "_smooth_mesh.res")


static func _first_mesh(root: Node) -> MeshInstance3D:
	var found := root.find_children("*", "MeshInstance3D", true, false)
	return found[0] as MeshInstance3D if not found.is_empty() else null
