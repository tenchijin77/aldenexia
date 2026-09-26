# Kenji and Oni move (test 40: "it would be great to see Oni walking / running, her tail moving, and the same for Kenji").
# Oni: the user's rig with idle, walk and run (tools/blender/animate_cat.py); Kenji, sculpted sitting: tail flicks, looks
# around and breathes (tools/blender/animate_sitting_cat.py).
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var host := Node3D.new()
	add_child(host)
	var oni := CatModel.build_animated(host, "res://models/Oni/oni_animated.glb", "res://models/Oni/Meshy_AI_oni_3d_model_0919110654_image-to-3d-texture", 0.5)
	var ap := CatModel.animation_player(oni)
	check(ap != null, "Oni's model has animations")
	if ap:
		for n in ["idle", "walk", "run"]:
			check(ap.has_animation(n) and ap.get_animation(n).loop_mode == Animation.LOOP_LINEAR, "Oni: %s, looping" % n)
		check(oni.find_children("*", "Skeleton3D", true, false).size() == 1, "on her own skeleton")
		CatModel.animate_by_speed(ap, 0.0)
		eq(ap.current_animation, "idle", "standing still: idle")
		CatModel.animate_by_speed(ap, 3.5)
		eq(ap.current_animation, "walk", "patrolling (3.5 m/s): walk")
		CatModel.animate_by_speed(ap, 7.0)
		eq(ap.current_animation, "run", "chasing (7 m/s): run")
		var mi: MeshInstance3D = oni.find_children("*", "MeshInstance3D", true, false)[0]
		check(mi.material_override is StandardMaterial3D and mi.material_override.albedo_texture != null, "wearing her own fur")
	var host2 := Node3D.new()
	add_child(host2)
	var kenji := CatModel.build_animated(host2, "res://models/Kenji/kenji_animated.glb", "res://models/Kenji/Meshy_AI_kenji_3d_model_0919110711_image-to-3d-texture", 0.5)
	var kap := CatModel.animation_player(kenji)
	check(kap != null and kap.has_animation("idle"), "Kenji has his idle")
	var km: MeshInstance3D = kenji.find_children("*", "MeshInstance3D", true, false)[0]
	var shapes := []
	for i in km.mesh.get_blend_shape_count():
		shapes.append(str(km.mesh.get_blend_shape_name(i)))
	for n in ["tail_left", "tail_right", "look_left", "look_right", "breathe"]:
		check(shapes.has(n), "Kenji can %s" % n.replace("_", " "))
	check(FileAccess.get_file_as_string("res://Scripts/kenji_npc.gd").contains("MODEL_ANIMATED") and FileAccess.get_file_as_string("res://Scripts/oni_npc.gd").contains("CatModel.animate_by_speed"), "both NPCs use them")
	host.queue_free()
	host2.queue_free()
	await frames(2)
