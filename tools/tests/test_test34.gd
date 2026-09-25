# Test 34 (Tenchijin, Arcanist): the fixes from that playtest.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	# One XP table for the game and the server: a new character reaches level 2 where the server agrees it has.
	var first := int(Global.xp_table.get("2", 0))
	check(first > 0, "the XP table has level 2")
	eq(ServerTrust.level_for_xp(240, Global.xp_table), 2 if first <= 240 else 1, "240 XP is the level the table says")
	var old := {"player_name": "Ztest", "player_class": "Arcanist", "player_race": "elf", "player_level": 1, "xp": 0,
		"skill_levels": {"defense": 4, "hand_to_hand": 3, "meditation": 5}}
	var new := old.duplicate(true)
	new["xp"] = 240
	new["player_level"] = 2
	new["skill_levels"] = {"defense": 7, "hand_to_hand": 5, "meditation": 8}
	var r := ServerTrust.check(old, new, 240, 600.0, false, {}, Global.xp_table, {}, {})
	eq(r["anomalies"], [], "Tenchijin's real level 2 and skills (7, 5, 8) are accepted")
	var cc = load("res://Scripts/character_creation.gd")
	check(FileAccess.get_file_as_string("res://Scripts/character_creation.gd").contains('Global.xp_table.get("2"'), "new characters take level 2 from the XP table")

	# Arcane Armor: absorbs, says so, and is gone once the 100 points are used up.
	var p = await make_player({"player_class": "Arcanist"})
	var cn: CombatNode = p.combat_node
	cn.apply_effect("arcane_armor", 900.0, {"absorb_amount": 100})
	eq(cn.absorb_incoming_damage(60), 0, "the first 60 absorbed")
	check(cn.active_effects.has("arcane_armor"), "still up with 40 left")
	eq(cn.absorb_incoming_damage(60), 20, "the next hit: 40 absorbed, 20 gets through")
	check(not cn.active_effects.has("arcane_armor"), "spent: it falls off")

	# Death: every spell effect goes (not the stance), the pet too.
	cn.apply_effect("inner_fire", 600.0, {"damage_mult": 0.1})
	cn.apply_effect("weak_poison", 60.0, {}, 5, 6.0)
	cn.apply_effect("stance_test", INF, {})
	p._clear_on_death()
	check(not cn.active_effects.has("inner_fire") and not cn.active_effects.has("weak_poison"), "death removes buffs and debuffs")
	check(cn.active_effects.has("stance_test"), "a stance isn't a spell: it stays")

	# Buying 4 of something that doesn't stack gives 4.
	Inventory.reset_for_new_character()
	Inventory.basic_inventory[0] = Inventory.create_item_instance("small_bag")
	check(Inventory.add_item("small_bag", 4), "bought 4 small bags")
	eq(Inventory.last_added_count, 4, "all 4 placed")
	var bags := 0
	for slot in Inventory.basic_inventory:
		if slot != null and str(slot.get("item_id", "")) == "small_bag":
			bags += 1
			eq(int(slot.get("quantity", 1)), 1, "each bag is one bag")
	eq(bags, 5, "5 small bags now (1 + 4)")

	# Casters start with a weapon.
	var creator: Control = cc.new()
	for cls in ["Arcanist", "Chaosborn", "Gravecaller", "Troubadour", "Lightmender", "Wildspeaker", "Spiritweaver"]:
		var inv: Dictionary = creator.build_starting_inventory(cls)
		var has_weapon := false
		for slot in inv.get("basic_inventory", []):
			if slot is Dictionary and str(slot.get("type", "")) == "weapon":
				has_weapon = true
		check(has_weapon, "%s starts with a weapon" % cls)
	creator.free()

	# W and S move you; they don't scroll a focused list or chat log.
	for action in ["ui_up", "ui_down"]:
		for ev in InputMap.action_get_events(action):
			check(not (ev is InputEventKey and (ev.physical_keycode in [KEY_W, KEY_S] or ev.keycode in [KEY_W, KEY_S])), "%s has no W/S" % action)

	# Magic Missile: the arcane icon, three bolts, 15 m, and it flies as a volley.
	var mm: Dictionary = p._spell_by_name["magic_missile"]
	check(str(mm["icon"]).ends_with("arcane_target.png"), "Magic Missile has the arcane icon")
	eq(int(mm["bolt_count"]), 3, "three bolts")
	eq(Player3D.spell_range_m(mm), 15.0, "15 m range")
	check(load("res://Scripts/spell_projectile.gd").flies(mm), "it flies")
