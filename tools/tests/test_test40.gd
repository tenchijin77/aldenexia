# Test 40 (Zozuur, Maedianie): Taunt is a strike and says so, a pet left far behind catches up, the shield hangs clear of
# the arm at rest, and campfires / torches burn with fire_fx.gd (flickering light, no shadow-casting cost).
extends "res://tools/tests/test_base.gd"


func run() -> void:
	# Taunt: "Zozuur hits a desert goblin with a mighty strike for 20 damage, drawing its ire!"
	var mine := CombatLogFormatter.spell_damage("You", "Taunt", "a desert goblin", 20)
	check(mine.contains("You hit a desert goblin with a mighty strike") and mine.contains("drawing its ire"), "your Taunt reads as a strike (%s)" % mine)
	var theirs := CombatLogFormatter.spell_damage("Zozuur", "Taunt", "a desert goblin", 20)
	check(theirs.begins_with("Zozuur hits a desert goblin with a mighty strike"), "and someone else's too")
	check(CombatLogFormatter.spell_damage("You", "Flame Lance", "a rat", 9).contains("You cast"), "other spells still say cast")
	var spells = JSON.parse_string(FileAccess.get_file_as_string("res://Data/player_spells.json"))
	var taunt: Dictionary = spells.filter(func(s): return s["spell_name"] == "taunt")[0]
	check(str(taunt["description"]).to_lower().contains("strike"), "the spell says it's a strike")

	# a pet far behind catches up (it stayed 100 m back at the goblin camp)
	make_floor(400.0)
	var p = await make_player({"player_class": "Voidknight", "player_name": "Zpetowner"})
	p.global_position = Vector3(0, 1, 0)
	p._summon_pet("spectral_minion")
	await frames(10)
	var pet: Node3D = p.active_pet
	check(is_instance_valid(pet), "a pet")
	if is_instance_valid(pet):
		pet.global_position = Vector3(120, 1, 0)
		pet.set_physics_process(false)   # stuck: it doesn't walk
		for i in 7:
			pet._tick_catch_up(1.0)
		check(pet.global_position.distance_to(p.global_position) < 5.0, "after %d s more than %d m behind it joins its owner" % [int(pet.CATCH_UP_SECONDS), int(pet.CATCH_UP_DISTANCE)])
		pet.global_position = Vector3(30, 1, 0)
		pet._behind_for = 0.0
		for i in 7:
			pet._tick_catch_up(1.0)
		check(pet.global_position.distance_to(p.global_position) > 20.0, "30 m behind and still walking: no jump")
		pet.attack_target = p   # anything valid: it's fighting
		pet.global_position = Vector3(120, 1, 0)
		for i in 7:
			pet._tick_catch_up(1.0)
		check(pet.global_position.distance_to(p.global_position) > 50.0, "never pulled out of a fight")
	p.queue_free()
	await frames(2)

	# the shield hangs on the outside of the left arm at rest (it poked through the arm), fitted to the idle pose
	var src := FileAccess.get_file_as_string("res://Scripts/held_gear.gd")
	check(src.contains("_idle_poses") and src.contains("face * forearm * 0.45"), "held gear is fitted to the idle pose, the shield clear of the arm")

	# fire: every campfire and torch uses fire_fx.gd; its light flickers and casts no shadow
	for scene in ["res://Scenes/campfire.tscn", "res://Scenes/torch.tscn", "res://Scenes/hand-torch.tscn"]:
		var inst: Node3D = load(scene).instantiate()
		add_child(inst)
		await frames(3)
		var fx := inst.find_children("*", "FireFX", true, false)
		check(fx.size() == 1, "%s burns with fire_fx.gd" % scene.get_file())
		if fx.size() == 1:
			var f: FireFX = fx[0]
			check(f.get_node_or_null("Flames") != null and f.get_node_or_null("Smoke") != null and f.get_node_or_null("Embers") != null, "flames, smoke and embers")
			var light: OmniLight3D = inst.find_children("*", "OmniLight3D", true, false)[0]
			check(not light.shadow_enabled, "its light casts no shadow (the costly part)")
			var e0 := light.light_energy
			f._process(0.37)
			f._process(0.41)
			check(not is_equal_approx(light.light_energy, e0), "and flickers")
			var flames: GPUParticles3D = f.get_node("Flames")
			check(flames.visibility_range_end > 0.0 and flames.randomness > 0.0, "drawn only up close, and never the same twice")
		for old in inst.find_children("*", "GPUParticles3D", true, false):
			if old.name in ["flames", "smoke"]:
				check(not old.visible, "the old single-sprite %s is off" % old.name)
		inst.queue_free()
		await frames(2)
