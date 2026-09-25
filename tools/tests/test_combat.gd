# Combat bits that went wrong once: damage over time doesn't keep you "in a fight" (combat music), languages learn at a
# sensible rate, /stuck moves you (and your pet) out of scenery.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var cn := CombatNode.new()
	add_child(cn)
	cn.max_hp = 100; cn.current_hp = 100
	cn.apply_effect("weak_poison", 3.0, {}, 5, 0.5)
	await get_tree().create_timer(1.2).timeout
	check(cn.current_hp < 100, "poison ticks")
	check(cn.seconds_since_engaged() > 60.0, "poison ticks don't count as fighting")
	cn.take_damage(5)
	check(cn.seconds_since_engaged() < 1.0, "a real hit does")
	# Language rate: a Troll at Common 15 gains roughly one point per 4-5 lines
	make_floor()   # before the player, so it never falls (a falling player keeps its speed through a teleport)
	var p = await make_player({"player_race": "troll", "languages": {"grommish": 100.0, "common": 15.0}})
	p.combat_node.intelligence = 8; p.combat_node.wisdom = 10
	var gains := 0
	for i in 400:
		Languages._last_practice.clear()
		Global.player_data["languages"]["common"] = 15.0
		Languages.practice("common")
		if Languages.skill("common") > 15.0:
			gains += 1
	check(gains > 50 and gains < 160, "Common 15 learning rate sane (%d gains in 400 lines)" % gains)
	# /stuck
	var wall := StaticBody3D.new(); var c := CollisionShape3D.new(); var b := BoxShape3D.new(); b.size = Vector3(20, 6, 8)
	c.shape = b; wall.add_child(c); add_child(wall); wall.position = Vector3(0, 3, -6)
	for i in 3:
		await get_tree().physics_frame
	p.global_position = Vector3(0, 0.1, 0)
	p.velocity = Vector3.ZERO
	p.last_attacked_msec = -100000
	await get_tree().physics_frame
	var start: Vector3 = p.global_position
	p.cmd_stuck()
	check(absf(Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length() - 5.0) < 0.1, "/stuck moves 5 m")
	# The wall's face is at z -2: the player (a capsule of this radius) is in it only if its centre is closer than that.
	# (This used -1.5, and a spot /stuck rightly found at z -1.52, clear of the wall, failed about 1 run in 3.)
	var radius: float = (p.get_node("CollisionShape3D").shape as CapsuleShape3D).radius
	check(not (p.global_position.z < -2.0 + radius - 0.02 and absf(p.global_position.x) < 10.0 + radius), "/stuck doesn't land inside the wall (at %s)" % str(p.global_position))
