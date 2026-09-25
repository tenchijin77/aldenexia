# Caster travel, evacuations, gates, binding (player_travel.gd).
extends "res://tools/tests/test_base.gd"


func _finish(p) -> void:
	var start: Vector3 = p.global_position
	for i in 250:
		if not p.combat_node.is_casting:
			break
		p.global_position = Vector3(start.x, p.global_position.y, start.z)
		await get_tree().create_timer(0.1).timeout
	await frames(2)


func run() -> void:
	make_floor(3000.0)
	# The Outskirts has no ley-line sites any more (the first is in Dustwind): the test puts a stand-in one in the zone.
	# The test isn't inside a zone scene: give it the Outskirts' travel data.
	PlayerTravel.zone()
	var outskirts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerTravel.LEY_LINES_PATH))["lumora_outskirts"]
	PlayerTravel._zone_cache.merge(outskirts, true)
	var saved_nodes = PlayerTravel._zone_cache.get("nodes", [])
	PlayerTravel._zone_cache["nodes"] = [{"id": "ztest_ring", "name": "Test Ruins", "class": "Wildspeaker", "position": [-300, -955]},
		{"id": "ztest_spire", "name": "Test Spire", "class": "Arcanist", "position": [100, 100]}]
	# attuned to the Arcanist's spire too (an old save): a Wildspeaker still can't travel there
	var p = await make_player({"player_class": "Wildspeaker", "player_level": 10, "attuned_ley_lines": {"ztest_ring": true, "ztest_spire": true}})

	# Sites belong to one class
	check(LeyLineNode.usable_by("Wildspeaker", "Wildspeaker") and not LeyLineNode.usable_by("Arcanist", "Wildspeaker"), "Ruins are the Wildspeaker's only")
	check(LeyLineNode.usable_by("", "Chaosborn") and not LeyLineNode.usable_by("", "Blademaster"), "a site with no class: any travel class")
	eq(LeyLineNode.site_phrase("Chaosborn"), "Chaosborn Rift", "Chaosborn Rift")
	var spire := LeyLineNode.new()
	spire.setup({"id": "ztest_spire2", "name": "Test Spire 2", "class": "Arcanist"})
	add_child(spire)
	spire.interact(p)
	check(not LeyLineNode.is_attuned("ztest_spire2"), "a Wildspeaker can't attune to an Arcanist Spire")
	var ruins := LeyLineNode.new()
	ruins.setup({"id": "ztest_ring2", "name": "Test Ruins 2", "class": "Wildspeaker"})
	add_child(ruins)
	ruins.interact(p)
	check(LeyLineNode.is_attuned("ztest_ring2"), "a Wildspeaker attunes to Wildspeaker Ruins")
	spire.queue_free()
	ruins.queue_free()
	await frames(1)
	p.combat_node.max_mana = 500; p.combat_node.current_mana = 500
	p.cast_spell("root_tunnel")
	var menu = get_tree().root.get_node_or_null("TravelDestinations")
	check(menu != null, "destination menu opens")
	if menu:
		eq(menu.item_count, 2, "only the Wildspeaker's own site is offered (plus the heading)")
	if menu:
		menu.id_pressed.emit(0)
	await frames(2)
	check(p.combat_node.is_casting, "Root-Tunnel channels")
	await _finish(p)
	eq(Vector2(p.global_position.x, p.global_position.z).round(), Vector2(-300, -955), "arrive at the attuned site")
	check(p.combat_node.active_effects.has("natures_ward"), "Nature's Ward on arrival")
	p._spell_cooldowns.clear()
	p.cast_spell("wormhole")
	await _finish(p)
	eq(Vector2(p.global_position.x, p.global_position.z).round(), Vector2(20, 13), "Wormhole lands at the town gate")
	p.cast_spell("call_of_nature")
	await _finish(p)
	eq(Vector2(p.global_position.x, p.global_position.z).round(), Vector2(5, 5), "gate to the bind point")
	p.global_position = Vector3(-50, 1, 30)
	p.cast_spell("attune_spirit")
	await _finish(p)
	eq(float(Global.player_data["bind_point"][0]), -50.0, "Attune Spirit binds here")
	p._spell_cooldowns.clear()
	check(not p.cast_spell("attune_spirit"), "rebinding within the hour is refused")
	var pm = get_tree().root.get_node_or_null("TravelDestinations")
	if pm:
		pm.queue_free()
	PlayerTravel._zone_cache["nodes"] = saved_nodes
