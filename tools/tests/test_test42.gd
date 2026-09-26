# Test 42 (Zozuur, Maedianie): the hub pushes groups when someone zones back in; death wipes you off monsters' hate
# lists; heals name the healer and the spell; rats stop turning between a player and a pet; Auto-Loot on Kill; the Kenji
# tail and troll shoulders; the Lightmender's Spiritual Weapon from level 1 (holding nothing); 14 characters an account;
# player-lit campfires; respawn timers that start at death and never pop a monster on a player; Halvek in the mausoleum.
extends "res://tools/tests/test_base.gd"


var _n := 0


func _monster(name: String, at: Vector3) -> Node3D:
	var m = load("res://Scenes/monster_template.tscn").instantiate()
	m.monster_name = name
	_n += 1
	m.name = "%s_t42_%d" % [name, _n]
	add_child(m)
	m.global_position = at
	await frames(3)
	return m


func run() -> void:
	make_floor(300.0)
	var src := func(path: String) -> String: return FileAccess.get_file_as_string(path)

	# the hub pushes the groups when someone arrives in its own zone (Maedianie zoned out and back: still grouped)
	check(src.call("res://Scripts/world_link.gd").contains("_hub_send_world()\n\t\t_push_groups()"), "the hub re-sends groups when its own zone's roster changes")

	# threat: a newcomer needs 10% more to pull it off; a taunt takes it outright
	var p = await make_player({"player_name": "Zozuur", "player_class": "Voidknight"})
	p.global_position = Vector3(0, 1, 0)
	var pal = await make_player({"player_name": "Maedianie", "player_class": "Wildspeaker"})
	pal.global_position = Vector3(3, 1, 0)
	pal.set_multiplayer_authority(900)
	var rat := await _monster("rat", Vector3(1.5, 1, 1.5))
	rat.add_threat(p, 100.0)
	check(rat.get_current_target() == p, "it fights the first to hit it")
	rat.add_threat(pal, 105.0)
	check(rat.get_current_target() == p, "5% more threat doesn't turn it (no more spinning between player and pet)")
	rat.add_threat(pal, 10.0)
	check(rat.get_current_target() == pal, "10% more does")
	rat.taunt(p, 1.0)
	check(rat.get_current_target() == p, "a taunt takes it back at once")

	# death wipes you off its list
	p._wipe_aggro()
	check(not rat.aggro_table.has(p), "dying wipes your aggro")
	# the one it stuck to vanishes (a pet dismissed): no error, it picks another
	var gone := Node3D.new()
	add_child(gone)
	rat.add_threat(gone, 1000.0)
	rat.get_current_target()
	gone.free()
	check(rat.get_current_target() == pal, "its remembered target freed: it moves on cleanly")
	rat.queue_free()

	# fear, EverQuest-style: a save decides Shaken (lower stats) or running blind
	eq(Player3D.fear_save_chance(5, 5, 10, 0), 0.5, "an even chance at the caster's level")
	check(Player3D.fear_save_chance(5, 5, 10, 2) > Player3D.fear_save_chance(5, 5, 10, 0), "the Lizardkin's racial fear save helps")
	check(not Player3D.RACIAL_TRAITS_NOT_YET_USED.has("fear_resistance_save_bonus"), "and is live")
	eq(Player3D.fear_save_chance(1, 30, 10, 0), 0.1, "never hopeless")
	check(not p.receive_fear(10.0, 5, "Sergeant Halvek", {"hit_chance": -15.0}, 0.0), "a made save: you keep your nerve")
	check(p.combat_node.active_effects.has("shaken") and not p.is_feared(), "Shaken, and still in control")
	eq(p.combat_node.get_modifier("stat_strength"), -2.0, "Shaken costs 2 Strength")
	p.combat_node.remove_effect("shaken")
	check(p.receive_fear(10.0, 5, "Sergeant Halvek", {"hit_chance": -15.0}, 0.99), "a failed save: you break and run")
	check(p.is_feared() and p.combat_node.active_effects.has("terrified"), "Terrified")
	check(not p.cast_spell("life_siphon"), "no casting while running")
	var at: Vector3 = p.global_position
	for i in 40:
		await get_tree().physics_frame
	check(p.global_position.distance_to(at) > 1.0, "you run on your own (%.1f m)" % p.global_position.distance_to(at))
	p.combat_node.active_effects.erase("terrified")
	p.handle_movement(0.05)
	check(not p.is_feared(), "a cure (the effect removed) ends the running")
	check(src.call("res://Scripts/monster3d.gd").contains("target.receive_fear("), "monsters' fear on a player goes through the save")

	# heals: personal lines
	var ps: String = src.call("res://Scripts/player3d.gd")
	check(ps.contains("You heal %s for [b]%d[/b] with %s.") and ps.contains("%s heals you for [b]%d[/b] with %s."), "heals name healer, target and spell")

	# Auto-Loot on Kill
	check(src.call("res://Scripts/global.gd").contains('"auto_loot": false,'), "auto-loot is off by default")   # (not the live settings: the tester's own file)
	var auto_loot_was = Global.settings.get("auto_loot", false)
	check(src.call("res://Scripts/pause_menu.gd").contains('"Auto-Loot on Kill", "auto_loot"'), "an Options toggle")
	Global.settings["auto_loot"] = true
	var goblin := await _monster("desert_goblin", Vector3(4, 1, 0))
	goblin.target_key = "someone"
	goblin._watch_for_auto_loot()
	goblin.die(false, true)
	goblin._watch_for_auto_loot()
	check(goblin._seen_dead, "the corpse was noticed")
	check(goblin._personal_loot.has(multiplayer.get_unique_id()), "and looted on its own (its loot was rolled and taken)")
	Global.settings["auto_loot"] = auto_loot_was
	goblin.queue_free()

	# Kenji's tail tip and the troll's shoulders
	check(FileAccess.file_exists("res://models/Kenji/kenji_animated.glb"), "Kenji re-exported")
	check(src.call("res://tools/blender/animate_sitting_cat.py").contains("TAIL_FRONT_Y"), "his tail mask reaches the curled tip")
	var troll: AnimationLibrary = load("res://models/Troll Male/troll_male_animations_pack.res")
	check(troll.get_animation("run").has_meta("shoulders_relaxed") and troll.get_animation("walk").has_meta("shoulders_relaxed"), "the troll's run and walk shoulders relaxed")

	# sitting: three ways for every model (share_sit.gd), picked at random; the cross-legged one upright (straighten_sit.gd)
	var model_src: String = src.call("res://Scripts/player3d.gd")
	var re := RegEx.new()
	re.compile('"library":\\s*"(res://models/[^"]+_pack\\.res)"')
	var libs := re.search_all(model_src)
	var missing := []
	var not_upright := []
	for m in libs:
		var lib: AnimationLibrary = load(m.get_string(1))
		for slot in ["sit", "sit_2", "sit_3"]:
			if not lib.has_animation(slot) or not lib.get_animation(slot).has_meta("sit_kind"):
				missing.append("%s:%s" % [m.get_string(1).get_file(), slot])
		if lib.has_animation("sit") and not lib.get_animation("sit").has_meta("sit_upright"):
			not_upright.append(m.get_string(1).get_file())
	check(libs.size() >= 22 and missing.is_empty(), "every model has all three sits (%s)" % str(missing))
	check(not_upright.is_empty(), "the cross-legged one sits upright (%s)" % str(not_upright))
	check(model_src.contains('_sit_anim = pick_variant(animation_player, "sit")'), "a random one each time you sit")
	check(src.call("res://Scripts/pet_minion.gd").contains("func rescue_spot(") and src.call("res://Scripts/pet_minion.gd").contains("_last_fall_line_ms > 60000"), "a fallen pet is put back ON the ground, and says so once a minute at most")

	# lizardkin tails: bones fitted to the tail, weights on them, a rig that swings them
	for sex in ["Male", "Female"]:
		var tail_path := "res://models/Lizardkin %s/lizardkin_%s_breathing_idle_tail_mesh.res" % [sex, sex.to_lower()]
		check(ResourceLoader.exists(tail_path), "the lizardkin %s has a tail mesh" % sex.to_lower())
		if ResourceLoader.exists(tail_path):
			var tm: ArrayMesh = load(tail_path)
			var rows: Array = tm.get_meta("tail_bones", [])
			var tskin: Skin = tm.get_meta("tail_skin", null)
			eq(rows.size(), 5, "five tail bones")
			check(tskin != null and str(tskin.get_bind_name(tskin.get_bind_count() - 1)) == "Tail5", "its skin binds them")
			var bw: PackedInt32Array = tm.surface_get_arrays(0)[Mesh.ARRAY_BONES]
			var on_tail := 0
			for b in bw:
				if b >= tskin.get_bind_count() - 5:
					on_tail += 1
			check(on_tail > 2000, "thousands of vertices ride the tail bones (%d)" % on_tail)
	check(model_src.contains("TailRig.attach(character)"), "player models get their tail rig")

	# the Lightmender's Spiritual Weapon: level 1, a starting spell, holds nothing
	var spells = JSON.parse_string(src.call("res://Data/player_spells.json"))
	var sw: Dictionary = {}
	for s in (spells if spells is Array else spells.values()):
		if s.get("spell_name") == "spiritual_weapon":
			sw = s
	eq(int(sw.get("level", 0)), 1, "Spiritual Weapon is level 1")
	eq(int(sw.get("class_level_requirements", {}).get("Lightmender", 0)), 1, "for a level 1 Lightmender")
	check(load("res://Scripts/character_creation.gd").STARTING_SPELLS["Lightmender"].has("spiritual_weapon"), "new Lightmenders start with it")
	check(SummonedPet.HOLDS_NO_GEAR.has("spiritual_weapon"), "it shows no weapon in hand")
	var mender = await make_player({"player_name": "Zmender", "player_class": "Lightmender"})
	mender._summon_from_spell(sw)
	await frames(10)
	if is_instance_valid(mender.active_pet):
		# the Lightmender's pet IS the weapon (2026-09-26: "the spiritual weapon was meant to be the lightmender's pet"):
		# models/Summoned Pets/spiritual_weapon.glb floating, glowing and lit, not a tinted ghost
		var body: Node = mender.active_pet.get_node_or_null("Character")
		check(body != null and body.find_children("*", "OmniLight3D", true, false).size() == 1, "the Spiritual Weapon is a glowing sword")
		check(body != null and body.get_child(0).scene_file_path.ends_with("spiritual_weapon.glb"), "its own model (spiritual_weapon.glb)")
		mender.pet_equipment["primary"] = Inventory.get_item_definition("copper_sword").duplicate()
		mender.pet_equipment["primary"]["item_id"] = "copper_sword"
		mender._apply_pet_gear_bonus()
		eq(mender.active_pet.held_gear, "", "its gear counts but isn't held")
	else:
		check(false, "the Spiritual Weapon was summoned")
	mender.queue_free()

	# 14 characters: one of each class
	eq(AccountRelay.MAX_CHARACTERS, 14, "an account holds 14 characters")
	eq(load("res://Scripts/character_creation.gd").STARTING_SPELLS.size(), AccountRelay.MAX_CHARACTERS, "one per class")

	# player-lit campfires
	var world_items = load("res://Scripts/world_items.gd").new()
	add_child(world_items)
	await frames(2)
	var fires := CampfireRelay.relay(get_tree())
	check(fires != null, "the campfire relay rides on WorldItems")
	p.global_position = Vector3(100, 1, 100)
	p.last_attacked_msec = -100000
	await frames(2)
	eq(CampfireRelay.refusal(p), "", "you can make camp out in the wilds")
	var guard := Node3D.new()
	guard.add_to_group("npc_guard")
	add_child(guard)
	guard.global_position = Vector3(110, 1, 100)
	check(CampfireRelay.refusal(p).contains("town"), "not in town")
	guard.queue_free()
	await frames(2)
	p.last_attacked_msec = Time.get_ticks_msec()
	check(CampfireRelay.refusal(p).contains("fighting"), "not in combat")
	p.last_attacked_msec = -100000
	check(p.light_campfire("ironwood_firewood_bundle"), "lit")
	await frames(3)
	eq(get_tree().get_nodes_in_group("campfires").filter(func(f): return (f as Node3D).global_position.distance_to(p.global_position) < 5.0).size(), 1, "a campfire burns in front of you")
	check(CampfireRelay.refusal(p).contains("already"), "not a second one beside it")
	eq(CampfireRelay.xp_bonus_at(get_tree(), p.global_position), 0.06, "ironwood: +6% XP within its warmth")
	eq(CampfireRelay.xp_bonus_at(get_tree(), p.global_position + Vector3(30, 0, 0)), 0.0, "none beyond 15 m")
	check(src.call("res://Scripts/slot_button.gd").contains('light_btn.text = "Light"'), "a Light button on the bundle")
	check(src.call("res://Scripts/monster3d.gd").contains("CampfireRelay.xp_bonus_at"), "kills by the fire pay the bonus (on the server)")
	world_items.queue_free()

	# respawns: timed from death, never on a player
	var sp: String = src.call("res://Scripts/mob_spawner3d.gd")
	check(sp.contains("mob.died.connect(gone)"), "a spawn point's respawn timer starts when its monster dies")
	check(load("res://Scripts/mob_spawner3d.gd")._near_a_player(Vector3(5, 0, 0), [Vector2(0, 0)]), "a spot 5 m from a player is refused")
	check(not load("res://Scripts/mob_spawner3d.gd")._near_a_player(Vector3(20, 0, 0), [Vector2(0, 0)]), "20 m away is fine")
	var spawns = JSON.parse_string(src.call("res://Data/lumora_outskirts_spawns.json"))
	var quickest := 99999
	var halvek: Dictionary = {}
	for e in spawns["spawns"]:
		quickest = mini(quickest, int(e["respawn_time"]))
		if e["mob_type"] == "sergeant_halvek":
			halvek = e
	check(quickest >= 60, "no Outskirts monster respawns in under a minute (quickest %d s)" % quickest)
	# (2026-09-26: he moved down into the Warden Crypts under the mausoleum: test_warden_crypts.gd)
	check(halvek.is_empty(), "Halvek waits below the mausoleum now, not on the Outskirts map")

	p.queue_free()
	pal.queue_free()
	await frames(2)
