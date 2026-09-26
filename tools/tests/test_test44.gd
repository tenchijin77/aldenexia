# Test 44 (Leeia, Woodstalker): a jump keeps its take-off speed and every jump clip fits the real jump; the reclining sit's
# neck and head stay natural on everyone who got it by retargeting.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	make_floor(200.0)
	var p = await make_player({"player_name": "Leeia", "player_class": "Woodstalker"})
	p.global_position = Vector3(0, 8, 0)   # in the air
	await frames(2)
	for i in 3:
		await get_tree().physics_frame
	p.velocity = Vector3(0, 3, -7)          # running forward as it jumped
	p.handle_movement(0.1)                  # no keys held
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	check(speed > 6.0, "in the air a running jump keeps its speed (%.1f m/s; it used to drop to ~2)" % speed)
	for i in 10:
		p.handle_movement(0.1)
	speed = Vector2(p.velocity.x, p.velocity.z).length()
	check(speed > 2.5 and speed < 7.0, "and it only eases off slowly without keys (%.1f m/s after 1 s)" % speed)
	# summoned animal pets move like the critters (a wolf on the rat mesh, a hawk on the bat)
	for kind in ["wolf", "hawk"]:
		p._summon_from_spell({"pet_kind": kind, "pet_hp_pct": 0.4})
		await frames(8)
		var pet = p.active_pet
		var ok: bool = is_instance_valid(pet) and not pet._critter_meshes.is_empty() \
				and (pet._critter_meshes[0] as MeshInstance3D).get_surface_override_material(0) is ShaderMaterial
		check(ok, "a summoned %s uses the critter motion shader" % kind)
	p.queue_free()

	var src := FileAccess.get_file_as_string("res://Scripts/player3d.gd")
	var re := RegEx.new()
	re.compile('"library":\\s*"(res://models/[^"]+_pack\\.res)"')
	var libs := re.search_all(src)
	var airtime := 2.0 * 6.0 / float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var bad_jump := []
	var bad_neck := []
	for m in libs:
		var lib: AnimationLibrary = load(m.get_string(1))
		var j := lib.get_animation("jump")
		if not j.has_meta("jump_fitted") or absf(j.length - airtime) > 0.02:
			bad_jump.append(m.get_string(1).get_file())
		var s3 := lib.get_animation("sit_3")
		if s3.has_meta("sit_from") and int(s3.get_meta("neck_neutral", 0)) < 2:
			bad_neck.append(m.get_string(1).get_file())
	check(libs.size() >= 22 and bad_jump.is_empty(), "every jump clip is fitted to the %.2f s the jump really lasts (%s)" % [airtime, str(bad_jump)])
	check(bad_neck.is_empty(), "the reclining sit's neck and head are natural on every retargeted model (%s)" % str(bad_neck))
	for lib_path in ["res://models/Troll Female/troll_female_animations_pack.res", "res://models/Ogre Female/ogre_female_animations_pack.res"]:
		check((load(lib_path) as AnimationLibrary).get_animation("run").has_meta("shoulders_relaxed"), "no running hump: %s" % lib_path.get_file())
	await _shadowblade()


# ── The Shadowblade (Jaessa, test 44) ──
func _shadowblade() -> void:
	make_floor(200.0)
	var p = await make_player({"player_name": "Jaessa", "player_class": "Shadowblade", "known_spells": ["backstab", "shadowstep"]})
	p.global_position = Vector3(0, 1, 0)
	p._grant_missing_starting_spells()
	check(p.known_spells.has("blindside"), "an existing Shadowblade learns Blindside at login")
	# stealth: flagged (replicated), shown, and monsters don't notice
	var rat = load("res://Scenes/monster_template.tscn").instantiate()
	rat.monster_name = "rat"
	rat.name = "rat_t44"
	add_child(rat)
	rat.global_position = Vector3(2, 1, 0)
	await frames(3)
	rat.player = p
	check(rat.can_see_player(), "in the open, a rat 2 m away notices you")
	p.combat_node.apply_effect("stance_stealth", 3600.0, {"stealthed": 1.0})
	for i in 3:
		await get_tree().physics_frame
	check(p.stealthed, "hidden: the flag is up (replicated)")
	check(not rat.can_see_player(), "a stealthed player isn't noticed by sight")
	# test 45: "in stealth, rogues should move a bit slower... 70% of normal run speed"
	p.combat_node.remove_effect("stance_stealth")
	var open_speed: float = await _run_speed(p)
	p.combat_node.apply_effect("stance_stealth", 3600.0, {"stealthed": 1.0})
	var sneak_speed: float = await _run_speed(p)
	check(absf(sneak_speed / maxf(open_speed, 0.01) - 0.7) < 0.03, "moving in Stealth: 70%% of the speed (%.2f vs %.2f m/s)" % [sneak_speed, open_speed])
	check(p.sight_appraisal(rat).contains("can't see you"), "appraisal: you think it can't see you")
	rat.combat_node.apply_effect("zt_see_invis", 60.0, {"see_invisible": 1.0})
	check(rat.can_see_player() and p.sight_appraisal(rat).contains("can see you"), "one that sees invisible does, and appraisal says so")
	rat.combat_node.remove_effect("zt_see_invis")
	var plate := TargetFrame.nameplate_name(p)
	check(plate.begins_with("[") and plate.ends_with("]") and not plate.contains("stealth"), "the nameplate shows the name in square brackets (%s)" % plate)
	p.combat_node.apply_effect("zt_invis", 60.0, {"invisible": 1.0})
	eq(TargetFrame.nameplate_name(p), "(%s)" % TargetFrame.display_name(p), "invisible: the name in round brackets")
	p.combat_node.remove_effect("zt_invis")
	var mi := p.get_node("Character").find_children("*", "GeometryInstance3D", true, false)
	check(not mi.is_empty() and (mi[0] as GeometryInstance3D).transparency > 0.5, "and the model is a faint shape")
	p.combat_node.remove_effect("stance_stealth")
	for i in 3:
		await get_tree().physics_frame
	check(not p.stealthed and (mi[0] as GeometryInstance3D).transparency == 0.0, "out of stealth: solid again")
	# a stun holds a monster still: it doesn't turn to face anyone, so you can get behind it
	rat.change_state(rat.State.ATTACK)
	rat.add_threat(p, 10.0)
	rat.look_at(Vector3(p.global_position.x, rat.global_position.y, p.global_position.z), Vector3.UP)
	rat.interrupt_cast(3.0)
	var facing: Vector3 = -rat.global_transform.basis.z
	p.global_position = Vector3(2, 1, 3)   # step round the side
	for i in 10:
		await get_tree().physics_frame
	check((-rat.global_transform.basis.z).distance_to(facing) < 0.01, "stunned: it stays facing where it was")
	rat.queue_free()
	# the data: instant physical skills, the stun
	var spells = JSON.parse_string(FileAccess.get_file_as_string("res://Data/player_spells.json"))
	var by := {}
	for s in spells:
		by[s["spell_name"]] = s
	for n in ["shadowstep", "backstab", "evasion", "ambush", "garrote", "shadow_cloak"]:
		check(float(by[n]["casting_time"]) == 0.0 and float(by[n]["mana_cost"]) == 0.0, "%s is instant and free" % n)
	check(str(by["blindside"]["effect_type"]) == "stun" and int(by["blindside"]["duration"]) >= 3 and int(by["blindside"]["level"]) == 1, "Blindside: a level 1, 3 s stun")
	check(spells.all(func(s): return s.has("cast_message")), "every spell has a cast_message field")
	check(FileAccess.get_file_as_string("res://Scripts/player3d.gd").contains("if not is_skill:\n\t\tGameLog.log_combat(CombatLogFormatter.begin_cast(\"You\"))"), "a physical skill doesn't say \"You begin casting a spell\"")
	check(load("res://Data/class_stances.json") != null and FileAccess.get_file_as_string("res://Data/class_stances.json").contains("master_stealth.png"), "Stealth has its own (hooded) icon")
	p.queue_free()
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
