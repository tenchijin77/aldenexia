# The unrigged critters move (user, test 41: "can you animate the static enemies as well"): Shaders/critter_motion.gdshader
# on the rat, snake, bat, slime, spiders and scarab, driven by monster3d.gd (_update_critter_motion).
extends "res://tools/tests/test_base.gd"


func run() -> void:
	make_floor(100.0)
	var modes := {"rat": 0, "spider": 1, "spiderling": 1, "dune_scarab": 1, "snake": 2, "bat": 3, "slime": 4}
	var i := 0
	for key in modes:
		var m = load("res://Scenes/monster_template.tscn").instantiate()
		m.monster_name = key
		m.name = "crit_%d" % i
		add_child(m)
		m.global_position = Vector3(i * 3.0, 1, 0)
		i += 1
		await frames(3)
		check(m._critter_meshes.size() >= 1, "%s has its motion" % key)
		if m._critter_meshes.is_empty():
			m.queue_free()
			continue
		var mi: MeshInstance3D = m._critter_meshes[0]
		var mat := mi.get_surface_override_material(0) as ShaderMaterial
		check(mat != null and mat.shader.resource_path.ends_with("critter_motion.gdshader"), "%s: the motion shader, with its textures" % key)
		if mat:
			eq(int(mat.get_shader_parameter("mode")), int(modes[key]), "%s moves like a %s" % [key, ["rat", "legged creature", "snake", "bat", "slime"][modes[key]]])
			check(mat.get_shader_parameter("albedo_tex") != null, "%s keeps its skin" % key)
		m.set_physics_process(false)
		var t0: float = m._critter_time
		m._critter_last_pos = m.global_position - Vector3(0.05, 0, 0)   # moving
		m._update_critter_motion(0.016)
		check(m._critter_time > t0 and m._critter_speed > 0.0, "%s: its clock runs, faster when it moves" % key)
		m._play_attack_animation()
		eq(m.anim_state, "attack", "%s: an attack sets off its lunge (replicated)" % key)
		for f in 30:
			m._update_critter_motion(0.02)
		eq(m.anim_state, "idle", "%s: and the lunge ends" % key)
		m.queue_free()
		await frames(2)
