# Group run-speed buffs (2026-09-26; the user: "our world is very large like eq, and we will need similar run-speed buffs
# for the groups"). Windrunner's Blessing (Spiritweaver / Wildspeaker 8: +30% on a friend, 36 minutes) and Ludwig's Steadfast
# March (Troubadour 8: a song, +30% to every ally near while it plays). "travel_speed" buffs don't add up: the strongest
# one counts (Ghost Wolf's 15% is one too).
extends "res://tools/tests/test_base.gd"


func _finish(p) -> void:
	var start: Vector3 = p.global_position
	for i in 80:
		if not p.combat_node.is_casting:
			break
		p.global_position = Vector3(start.x, p.global_position.y, start.z)
		await get_tree().create_timer(0.1).timeout
	await frames(2)


func _run_speed(p: Node) -> float:
	p.autorun_enabled = true
	for i in 30:
		await get_tree().physics_frame
	var v: Vector3 = p.velocity
	p.autorun_enabled = false
	for i in 20:
		await get_tree().physics_frame
	return Vector2(v.x, v.z).length()


func run() -> void:
	var spells: Dictionary = {}
	for s in JSON.parse_string(FileAccess.get_file_as_string("res://Data/player_spells.json")):
		spells[s["spell_name"]] = s
	eq(spells["windrunners_blessing"]["class_level_requirements"], {"Spiritweaver": 8.0, "Wildspeaker": 8.0}, "Windrunner's Blessing: Spiritweaver and Wildspeaker 8")
	eq(spells["ludwigs_steadfast_march"]["class_level_requirements"], {"Troubadour": 8.0}, "Ludwig's Steadfast March: Troubadour 8")
	var shops: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/vendor_shop.json"))
	for pair in [["trainer_spiritweaver", "windrunners_blessing"], ["trainer_wildspeaker", "windrunners_blessing"], ["trainer_troubadour", "ludwigs_steadfast_march"]]:
		check(shops[pair[0]]["stock"].has("scroll_of_" + pair[1]) and Inventory.get_item_definition("scroll_of_" + pair[1]).get("teaches_spell") == pair[1], "%s sells the scroll of %s" % pair)
	eq(Player3D.spell_display_name("windrunners_blessing"), "Windrunner's Blessing", "its name")
	# scaled by the caster's level, like EverQuest's (Spirit of Wolf 34-55%, Selo's 16-80%)
	eq(Player3D.scaled_travel_spell(spells["windrunners_blessing"], 8)["modifiers"]["travel_speed"], 0.3, "Windrunner's Blessing from a level 8: +30%")
	eq(Player3D.scaled_travel_spell(spells["windrunners_blessing"], 50)["modifiers"]["travel_speed"], 0.55, "from a level 50: +55%")
	check(absf(Player3D.scaled_travel_spell(spells["ludwigs_steadfast_march"], 29)["modifiers"]["travel_speed"] - 0.41) < 0.011, "Ludwig's march from a level 29: halfway, about +41%")
	eq(Player3D.scaled_travel_spell(spells["ludwigs_steadfast_march"], 60)["modifiers"]["travel_speed"], 0.65, "capped at +65%")

	make_floor(200.0)
	var p = await make_player({"player_name": "Zweaver", "player_class": "Spiritweaver", "player_level": 8, "known_spells": ["windrunners_blessing", "ghost_wolf"]})
	p.combat_node.max_mana = 500; p.combat_node.current_mana = 500
	var base: float = await _run_speed(p)
	check(p.cast_spell("windrunners_blessing"), "a level 8 Spiritweaver casts Windrunner's Blessing (on themself, no target)")
	await _finish(p)
	check(p.combat_node.active_effects.has("windrunners_blessing"), "the buff is on")
	check(float(p.combat_node.active_effects.get("windrunners_blessing", {}).get("remaining", 0.0)) > 2100.0, "for 36 minutes")
	var fast: float = await _run_speed(p)
	check(absf(fast / base - 1.3) < 0.03, "+30%% run speed (%.2f vs %.2f m/s)" % [fast, base])
	p.combat_node.apply_effect("ghost_wolf", 900.0, {"travel_speed": 0.15})
	var both: float = await _run_speed(p)
	check(absf(both - fast) < 0.05, "with Ghost Wolf too: still +30%%, they don't add up (%.2f)" % both)
	p.combat_node.remove_effect("windrunners_blessing")
	var wolf: float = await _run_speed(p)
	check(absf(wolf / base - 1.15) < 0.03, "Ghost Wolf alone: +15%%")
	# underground (a zone whose DayNightCycle has outdoors off): no run-speed buffs at all
	var cycle := Node.new()
	cycle.set_script(load("res://Scripts/day_night_cycle.gd"))
	cycle.set("outdoors", false)
	add_child(cycle)
	p._outdoors_cache = {}
	var under: float = await _run_speed(p)
	check(absf(under - base) < 0.05, "underground, Ghost Wolf does nothing (%.2f vs %.2f)" % [under, base])
	cycle.queue_free()
	await frames(1)
	p._outdoors_cache = {}
	p.queue_free()
	await frames(2)

	# the song: every ally near the Troubadour
	var bard = await make_player({"player_name": "Zbard", "player_class": "Troubadour", "player_level": 8, "known_spells": ["ludwigs_steadfast_march"]})
	bard.combat_node.max_mana = 500; bard.combat_node.current_mana = 500
	check(bard.cast_spell("ludwigs_steadfast_march"), "a level 8 Troubadour plays Ludwig's Steadfast March")
	await _finish(bard)
	eq(bard.combat_node.get_strongest_modifier("travel_speed"), 0.16, "a level 8 bard's march: +16%")
	check(bard._active_songs.has("ludwigs_steadfast_march"), "it's a song (keeps playing until stopped)")
	bard.cast_spell("ludwigs_steadfast_march")
	check(not bard._active_songs.has("ludwigs_steadfast_march"), "and stops when clicked again")
	bard.queue_free()
	await frames(2)
