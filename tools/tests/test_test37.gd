# Test 37 (Zozuur, Maedianie): ailment ticks are reported, you arrive facing INTO a zone, appraising always tells you
# something, and /who, /tell and the world announcements work across zones (world_link.gd).
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var lines: Array = []
	var grab := func(t): lines.append(str(t))
	GameLog.general_message.connect(grab)
	GameLog.combat_message.connect(func(t, _h, _p): lines.append(str(t)))

	make_floor()
	var p = await make_player({"player_class": "Voidknight", "player_level": 5})
	p.global_position = Vector3(0, 1, 0)

	# a disease ticking says so
	p.combat_node.apply_effect("disease", 3.0, {}, 5, 0.5)
	await get_tree().create_timer(0.8).timeout
	check(lines.any(func(l): return l.contains("You have taken 5 points of damage from Disease")), "a disease tick is reported in the log")
	p.combat_node.remove_effect("disease")

	# arriving at a zone line faces away from it, across the line (a wide line's middle may be off to one side)
	var line := ZoneLine.new()
	line.size = Vector3(1040, 60, 8)
	add_child(line)
	line.global_position = Vector3(300, 0, -505)   # its middle far to the side of where we arrive
	p.global_position = Vector3(0, 1, -474)
	p.look_at(p.global_position + Vector3(0, 0, -1), Vector3.UP)   # facing back over the line (north)
	p.face_into_zone()
	var forward: Vector3 = -p.global_transform.basis.z
	check(forward.z > 0.99, "arriving from a line to the north, you face south into the zone (%s)" % str(forward.snapped(Vector3.ONE * 0.01)))
	line.queue_free()

	# appraising: even a failed roll says what it is and how it regards you
	var rat = load("res://Scenes/monster_template.tscn").instantiate()
	rat.monster_name = "grukka_bonechewer"
	add_child(rat)
	rat.global_position = Vector3(3, 1, 3)
	await frames(3)
	p.current_target = rat
	for i in 6:
		lines.clear()
		p._appraisal_cooldowns.clear()
		p.try_appraise_target()
		check(lines.any(func(l): return l.contains("Estimated threat")) or lines.any(func(l): return l.contains("seems")), "an appraisal always tells you something")
	var learned := false
	for i in 30:
		lines.clear()
		p._appraisal_cooldowns.clear()
		p.try_appraise_target()
		if lines.any(func(l): return l.contains("It can:") and l.contains("Bone Shard") and l.contains("stun or silence")):
			learned = true
			break
	check(learned, "a good appraisal lists the monster's abilities and how to stop its spells")
	rat.queue_free()

	# the world link's /who and "where is this player" read the whole world's list
	var link := preload("res://Scripts/world_link.gd").new()
	add_child(link)
	link._world = {"dustwind_plateaus": [{"name": "Zozuur", "surname": "", "level": 12, "class": "Voidknight"}],
			"ashfall_dunes": [{"name": "Maedianie", "surname": "Starfall", "level": 9, "class": "Wildspeaker"}]}
	eq(link.zone_of("zozuur"), "dustwind_plateaus", "a player in another zone is found (any case)")
	eq(link.zone_of("Nobody"), "", "someone offline is not")
	var who: String = link.who_text("Zozuur")
	check(who.contains("Players in Aldenexia (") and who.contains("Dustwind Plateaus") and who.contains("Maedianie Starfall") \
			and who.contains("Ashfall Dunes") and who.contains("(you)"), "/who lists every zone's players with their zone")
	eq(link.link_port(), int(Net.base_port) + 9, "the hub listens on the base port + 9 (local only)")
	link.queue_free()

	GameLog.general_message.disconnect(grab)
	p.queue_free()
	await frames(2)
