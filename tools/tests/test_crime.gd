# Crime and the courthouse (2026-09-26, crime.gd): a PvP blow in town that a guard sees is a crime: a bounty and lost
# Warden standing. A guard asks for the fine (pay or resist); resisting gets you attacked; a guard's killing blow takes the
# fine from your purse; the Magistrate takes a bounty and sells back the standing crimes cost.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	make_floor(200.0)
	# this test scene becomes "town" inside a rectangle, as a zone's spawn file makes its walls one
	Monster._zones_loaded_for = ZoneInfo.current_id()
	Monster._no_monster_zones = [{"name": "test town", "min": [-50, -50], "max": [50, 50]}]
	var p = await make_player({"player_name": "Zozuur", "player_class": "Voidknight", "player_level": 10})
	p.global_position = Vector3(0, 1, 0)
	Global._set_total_copper(200)
	check(Crime.in_town(p), "inside the walls is town")
	p.global_position = Vector3(90, 1, 0)
	check(not Crime.in_town(p), "outside isn't")
	eq(Crime.commit(p, "assault", "Maedianie"), false, "out of town: no crime")
	p.global_position = Vector3(0, 1, 0)
	eq(Crime.commit(p, "assault", "Maedianie"), false, "in town but no guard saw it: no crime")
	eq(Crime.bounty(), 0, "no bounty")

	var guard = load("res://Scenes/guard_npc.tscn").instantiate()
	guard.npc_name = "Oasis Warden"
	add_child(guard)
	guard.global_position = Vector3(10, 1, 0)
	await frames(3)
	var before: int = p.get_faction_standing("Wardens of the Sacred Flame")
	eq(Crime.commit(p, "assault", "Maedianie"), true, "a guard saw it: a crime")
	eq(Crime.bounty(), 50, "a 5 silver bounty")
	eq(p.wanted, 50, "replicated for the guards")
	eq(p.get_faction_standing("Wardens of the Sacred Flame"), before - 15, "Wardens standing -15")
	eq(int(Crime.standing_lost().get("Wardens of the Sacred Flame", 0)), 15, "the standing crimes cost is remembered")
	eq(Crime.commit(p, "assault", "Maedianie"), false, "the same blow on the same player counts once a minute")
	check(FileAccess.get_file_as_string("res://Scripts/player_versus.gd").contains('Crime.commit(player, "assault", n)'), "PvP blows are checked (duels aren't crimes)")

	# the guard: someone wanted nearby is stopped (the demand), someone resisting is attacked
	check(guard._outlaw_near(guard.global_position) == null, "not resisting yet: not attacked")
	guard._demanded.clear()
	guard._check_wanted()
	check(guard._demanded.has("zozuur"), "a guard stops the wanted player and asks for the fine")
	for popup in get_tree().root.get_children():
		if popup.has_method("expire"):
			popup.queue_free()
	Crime.resist(p)
	check(p.resisting, "resisting")
	check(guard._outlaw_near(guard.global_position) == p, "now every guard attacks on sight")
	check(not guard._target_gone(p), "and keeps at it")
	p.global_position = Vector3(90, 1, 0)
	check(guard._target_gone(p), "until they flee town")
	p.global_position = Vector3(0, 1, 0)

	# a guard's blows land on the player's own game (rolled there, like a monster's)
	var hp_before: int = p.combat_node.current_hp
	for i in 100:   # (a tank misses or blocks plenty: enough swings that one lands)
		guard._strike_local(p)
		if p.combat_node.current_hp < hp_before:
			break
	check(p.combat_node.current_hp < hp_before, "a guard's blow hurts the one resisting")
	# killed by a guard: the fine comes from the purse, what's short stays
	Global._set_total_copper(30)
	p.combat_node.current_hp = 1
	for i in 200:
		guard._strike_local(p)
		if p.dying:
			break
	check(p.dying, "a guard can strike them down")
	eq(Crime.bounty(), 20, "30 of 50 taken, 20 still owed")
	eq(Global.get_total_copper(), 0, "the purse emptied")
	check(not p.resisting, "resisting ends with the fight")
	p.dying = false
	p.is_incapacitated = false
	p.combat_node.current_hp = p.combat_node.max_hp

	# paying
	Global._set_total_copper(10)
	eq(Crime.pay(p), false, "a short purse can't pay")
	Global._set_total_copper(100)
	eq(Crime.pay(p), true, "paid")
	eq(Crime.bounty(), 0, "record clear")
	eq(p.wanted, 0, "the guards see it")
	eq(Global.get_total_copper(), 80, "20 copper paid")

	# the Magistrate: amends for the standing crimes cost
	eq(Crime.amends_cost(), 30, "15 points at 2 copper")
	eq(Crime.make_amends(p), true, "amends made")
	eq(p.get_faction_standing("Wardens of the Sacred Flame"), before, "the standing is back")
	eq(Crime.amends_cost(), 0, "nothing more to buy back")
	var lumora := FileAccess.get_file_as_string("res://Scenes/zones/lumora.tscn")
	check(lumora.contains('npc_name = "Magistrate Corvane"') and lumora.contains("magistrate_npc.gd"), "the Magistrate is at the Lumora courthouse")
	check(load("res://Scripts/magistrate_npc.gd") != null, "and their script loads")

	guard.queue_free()
	p.queue_free()
	Monster._zones_loaded_for = ""
	Monster._no_monster_zones = []
	Global.player_data.erase("bounty")
	Global.player_data.erase("crime_standing")
	await frames(2)
