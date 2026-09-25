# Character models rebuilt smooth in Blender (tools/smooth_models.sh, 2026-09-25): each race's <scene>_smooth_mesh.res
# must fit the FBX's own skeleton and skin (the animations drive it), sit exactly where the old mesh was, and be used.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var built := 0
	for key in Player3D.CHARACTER_MODELS:
		var info: Dictionary = Player3D.CHARACTER_MODELS[key]
		var scene_path := str(info["scene"])
		var res_path := MeshSmoothing.rebuilt_mesh_path(scene_path)
		if not ResourceLoader.exists(res_path):
			continue
		built += 1
		var model: Node = load(scene_path).instantiate()
		var mi := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var old_mesh: Mesh = mi.mesh
		check(MeshSmoothing.use_rebuilt_mesh(model), "%s: the rebuilt mesh is swapped in" % key)
		var new_mesh: Mesh = mi.mesh
		check(new_mesh != old_mesh and new_mesh.resource_path == res_path, "%s: it's the .res" % key)
		var arrays := new_mesh.surface_get_arrays(0)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var binds := mi.skin.get_bind_count()
		var bad_bone := false
		for b in bones:
			bad_bone = bad_bone or b < 0 or b >= binds
		check(not bad_bone, "%s: every vertex's bones are in the FBX skin (%d binds)" % [key, binds])
		var per := bones.size() / (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var off_weight := 0
		for v in range(0, weights.size(), per * 97):
			var sum := 0.0
			for k in per:
				sum += weights[v + k]
			if absf(sum - 1.0) > 0.02:
				off_weight += 1
		eq(off_weight, 0, "%s: skin weights add up to 1" % key)
		# vertex for vertex where the old one was (catches a mirrored / turned-round mesh a bounding box wouldn't)
		var old_v: PackedVector3Array = old_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var new_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var total := 0.0
		var samples := 0
		for i in range(0, old_v.size(), maxi(1, old_v.size() / 40)):
			var best := INF
			for j in range(0, new_v.size(), 2):
				best = minf(best, old_v[i].distance_squared_to(new_v[j]))
			total += sqrt(best)
			samples += 1
		var mean := total / samples
		check(mean < 0.02, "%s: the new mesh sits on the old one (mean gap %.3f m)" % [key, mean])
		check(new_mesh.surface_get_array_index_len(0) > old_mesh.surface_get_array_index_len(0) * 3, "%s: subdivided" % key)
		model.free()
	check(built >= 12, "every race model has a rebuilt mesh (%d)" % built)

	# The elf male's run: his feet used to land on / across the middle (knees knocking in, "pigeon toed"); tools/widen_stride.gd
	# swung his thighs out 2 degrees. His feet now stay apart like the other races'.
	var lib := load("res://models/Elf Male/elf_male_animations.res") as AnimationLibrary
	check(lib.get_animation("run").has_meta("stride_widened"), "the elf male's run has the stride fix")
	var elf: Node3D = load("res://models/Elf Male/Elf Male Breathing Idle.fbx").instantiate()
	add_child(elf)
	await frames(1)
	var sk := elf.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap := elf.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	ap.remove_animation_library("")
	ap.add_animation_library("", lib)
	ap.play("run")
	var gap := INF
	for i in 40:
		ap.seek(ap.get_animation("run").length * i / 40.0, true)
		gap = minf(gap, sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin.x - sk.get_bone_global_pose(sk.find_bone("RightFoot")).origin.x)
	check(gap > 0.05, "his feet never cross when he runs (closest %.3f m, was 0.028)" % gap)
	elf.queue_free()
