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
	var p = await make_player({"player_class": "Wildspeaker", "player_level": 10, "attuned_ley_lines": {"lumora_palm_grove": true}})
	p.combat_node.max_mana = 500; p.combat_node.current_mana = 500
	p.cast_spell("root_tunnel")
	var menu = get_tree().root.get_node_or_null("TravelDestinations")
	check(menu != null, "destination menu opens")
	if menu:
		menu.id_pressed.emit(0)
	await frames(2)
	check(p.combat_node.is_casting, "Root-Tunnel channels")
	await _finish(p)
	eq(Vector2(p.global_position.x, p.global_position.z).round(), Vector2(-300, -955), "arrive at the palm grove stone")
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
