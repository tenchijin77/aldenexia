# Monster abilities (monster3d.gd "Abilities", monsters.json "abilities", 2026-09-25): named monsters cast (and a stun
# breaks it), curse, heal, call adds and enrage; a silence stops a player's spells.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/monsters.json"))
	monsters.erase("_comment")
	for id in monsters:
		var m: Dictionary = monsters[id]
		if bool(m.get("is_boss", false)):
			check(not m.get("abilities", []).is_empty(), "named %s has abilities" % id)
		for a in m.get("abilities", []):
			var what := "%s's %s" % [id, a.get("name", "?")]
			check(Monster.ABILITY_TYPES.has(str(a.get("type", ""))), "%s: a known type" % what)
			check(not str(a.get("name", "")).is_empty(), "%s: has a name" % what)
			if a.get("type") == "summon":
				check(monsters.has(str(a.get("summon", ""))), "%s calls a real monster" % what)
			if a.has("effect"):
				check(Player3D.MONSTER_AILMENTS.has(str(a["effect"].get("name", ""))), "%s leaves a known ailment (cures, buff bar)" % what)
			if a.has("school"):
				check(["fire", "cold", "acid", "lightning", "poison", "disease", "magic", "divine", "psychic", "spirit", "physical"].has(str(a["school"])), "%s: a real resist" % what)
			var msg := str(a.get("message", "%s"))
			check(msg.count("%s") <= 1 and str(a.get("say", "%s")).count("%s") <= 1, "%s: message has at most one name slot" % what)

	make_floor()
	var p = await make_player({"player_class": "Arcanist", "player_level": 10})
	p.global_position = Vector3(0, 1, 0)

	# The tomb guardian casts Void Bolt: shows it, stands, and a stun breaks it
	var guardian := await _mob("tomb_guardian", p)
	_fight(guardian, 4.1)
	eq(guardian.casting, "Void Bolt", "four seconds in, it begins to cast Void Bolt")
	guardian.interrupt_cast(2.0)
	eq(guardian.casting, "", "a stun breaks the cast")
	_fight(guardian, 1.5)
	eq(guardian.casting, "", "and nothing starts while stunned")
	var hp_before: int = p.combat_node.current_hp
	for i in 12:
		_fight(guardian, 5.0)
		if p.combat_node.current_hp < hp_before:
			break
	check(p.combat_node.current_hp < hp_before, "a Void Bolt lands in the end (%d -> %d)" % [hp_before, p.combat_node.current_hp])
	# a silence stops it casting at all
	p.combat_node.current_hp = p.combat_node.max_hp
	guardian._reset_abilities()
	guardian.combat_node.apply_effect("silence_test", 30.0, {"silenced": 1.0})
	_fight(guardian, 4.5)
	eq(guardian.casting, "", "a silenced monster doesn't cast")
	guardian.combat_node.remove_effect("silence_test")
	guardian.queue_free()

	# Landing on a player: damage, the ailment, and a school-less skill is never resisted
	var halvek := await _mob("sergeant_halvek", p)
	eq(Monster.ability_resisted(p.combat_node, "", 50), false, "a skill (no school) can't be resisted")
	var web := await _mob("weavemother_vhessa", p)
	web.land_ability(p, 0, 0)   # Ensnaring Web
	check(p.combat_node.active_effects.has("ensnared") or p.combat_node.race_negative_effect_resist > 0.0, "Ensnaring Web ensnares you")
	halvek.queue_free()
	await frames(2)

	# Summons come when she's hurt, and go when she dies
	web.combat_node.current_hp = int(web.combat_node.max_hp * 0.4)
	var before := get_tree().get_nodes_in_group("monsters").size()
	_fight(web, 0.2)
	await frames(3)
	eq(get_tree().get_nodes_in_group("monsters").size() - before, 2, "The Den Stirs: two broodlings")
	eq(str(web._summons[0].monster_name), "broodling", "they're broodlings")
	var adds: Array = web._summons.duplicate()
	web.die(false, false)
	await frames(3)
	check(adds.all(func(a): return not is_instance_valid(a) or a.is_queued_for_deletion()), "her broodlings go when she dies")

	# Heal (Grukka's Marrow Feast, a 3 s cast) and enrage (the abomination near death)
	var grukka := await _mob("grukka_bonechewer", p)
	grukka.combat_node.current_hp = int(grukka.combat_node.max_hp * 0.3)
	var low: int = grukka.combat_node.current_hp
	for i in 60:
		_fight(grukka, 0.5)
		if grukka.combat_node.current_hp > low:
			break
	check(grukka.combat_node.current_hp > low, "Grukka heals himself (%d -> %d)" % [low, grukka.combat_node.current_hp])
	grukka.queue_free()
	var abom := await _mob("grave_abomination", p)
	abom.combat_node.current_hp = int(abom.combat_node.max_hp * 0.15)
	for i in 20:
		_fight(abom, 0.5)
	check(abom.combat_node.active_effects.has("enraged"), "the abomination frenzies near death")
	abom.current_state = abom.State.IDLE
	_fight(abom, 0.1)
	check(not abom.combat_node.active_effects.has("enraged"), "and calms when the fight is over")
	abom.queue_free()

	# A silenced player can't cast a spell
	var spell := ""
	for s in p.known_spells if "known_spells" in p else []:
		if int(p._spell_by_name.get(s, {}).get("mana_cost", 0)) > 0:
			spell = s
			break
	if spell.is_empty():
		for s in p._spell_by_name:
			if int(p._spell_by_name[s].get("mana_cost", 0)) > 0 and int(p._spell_by_name[s].get("level", 1)) <= 1:
				spell = s
				break
	p.combat_node.apply_effect("silenced", 10.0, {"silenced": 1.0})
	check(not spell.is_empty() and not p.cast_spell(spell), "silenced: %s won't cast" % spell)
	p.combat_node.remove_effect("silenced")
	p.queue_free()
	await frames(2)


func _mob(id: String, p: Node) -> Node:
	var m = load("res://Scenes/monster_template.tscn").instantiate()
	m.monster_name = id
	add_child(m)
	m.global_position = p.global_position + Vector3(2, 0, 0)
	await frames(3)
	m.set_physics_process(false)   # the test drives the fight clock itself
	m.player = p
	m.current_state = m.State.ATTACK
	m.can_attack = true
	return m


# Runs `seconds` of the monster's fight in small steps.
func _fight(m: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		m._tick_abilities(0.1)
		t += 0.1
