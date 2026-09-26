# Test 39 (Zozuur, Maedianie): /tell and group invites across zones, stances without a "0:00" timer, the group window
# fading members out of heal range, and weapons and shields shown in the hands (Scripts/held_gear.gd).
extends "res://tools/tests/test_base.gd"


func run() -> void:
	# /tell to someone in another zone isn't refused by the chat box (the world link finds them)
	var chat := FileAccess.get_file_as_string("res://Scripts/game_log_window.gd")
	check(chat.contains("not has_link and player._find_player_by_name(target_name) == null"), "the chat box only refuses an unknown name when there's no world link")

	# buffs with no duration show no time
	const BUFF_BAR := preload("res://Scripts/buff_bar.gd")
	eq(BUFF_BAR.time_text("stance_defensive", INF), "", "your stance: no time")
	eq(BUFF_BAR.time_text("group_stance_defensive", 2.4), "", "a tank's group stance (renewed every few seconds): no time")
	eq(BUFF_BAR.time_text("starving", INF), "", "no end, no time")
	eq(BUFF_BAR.time_text("blessing", 125.0), "2:05", "a real buff still counts down")

	# the group window fades members beyond a heal's reach
	const GROUP_FRAME := preload("res://Scripts/group_frame.gd")
	check(GROUP_FRAME.IN_RANGE_M >= 15.0 and GROUP_FRAME.IN_RANGE_M <= 20.0 and GROUP_FRAME.OUT_OF_RANGE_ALPHA < 1.0, "out of heal range fades")

	# invites across zones: the hub adds the one who accepted to the leader's group (making one if there's none)
	var link := preload("res://Scripts/world_link.gd").new()
	add_child(link)
	link._hub_group({"t": "group_join", "leader": "Zozuur", "member": "Maedianie"})
	eq(link._group_of("maedianie"), "zozuur", "accepting an invite from another zone joins the leader's group")
	link._hub_group({"t": "group_join", "leader": "Zozuur", "member": "Tenchijin"})
	eq(link.groups["zozuur"]["members"].size(), 3, "a second one joins the same group")
	link._hub_group({"t": "group_set", "by": "Annadaeus", "members": ["Annadaeus", "Epheo"]})
	link._hub_group({"t": "group_join", "leader": "Annadaeus", "member": "Tenchijin"})
	eq(link._group_of("tenchijin"), "annadaeus", "joining another group leaves the old one")
	eq(link.groups["zozuur"]["members"].size(), 2, "and the old group carries on without them")
	for i in 6:
		link._hub_group({"t": "group_join", "leader": "Annadaeus", "member": "Extra%d" % i})
	check(link.groups["annadaeus"]["members"].size() <= 6, "a group never goes past six")
	link.queue_free()
	check(FileAccess.get_file_as_string("res://Scripts/player3d.gd").contains("link.request_invite(player_name_query)"), "/invite <name> reaches another zone")

	# held gear: every weapon with a held_model has its model
	var defs = JSON.parse_string(FileAccess.get_file_as_string("res://Data/items.json"))
	var items: Dictionary = defs.get("items", defs)
	var shown := 0
	for id in items:
		if typeof(items[id]) == TYPE_DICTIONARY and items[id].has("held_model"):
			shown += 1
			check(ResourceLoader.exists(HeldGear.MODEL_DIR + str(items[id]["held_model"]) + ".glb"), "%s's model exists" % id)
	check(shown >= 20, "the swords, daggers, axes, staves and shields all show (%d)" % shown)
	check(not items["worn_hand_wraps"].has("held_model"), "hand-to-hand wraps show nothing")

	# binding: casters bind anywhere (themselves, or a friendly player next to them); everyone else asks a caster or a
	# Soul Binder in town, for a silver; once an hour either way
	var spells = JSON.parse_string(FileAccess.get_file_as_string("res://Data/player_spells.json"))
	var attune: Dictionary = spells.filter(func(sp): return sp.get("spell_name") == "attune_spirit")[0]
	var casters: Array = attune["class_level_requirements"].keys()
	casters.sort()
	eq(casters, ["Arcanist", "Chaosborn", "Gravecaller", "Lightmender", "Runecaster", "Spiritweaver", "Wildspeaker"], "Attune Spirit is the casters' (EverQuest's Bind Affinity)")
	var fighter = await make_player({"player_class": "Blademaster", "player_name": "Zbinder"})
	var lines: Array = []
	var grab := func(t): lines.append(str(t))
	GameLog.general_message.connect(grab)
	check(not fighter.get_node("Travel").pre_cast("attune_spirit", attune), "a Blademaster who learned it before can't cast it")
	check(lines.any(func(l): return l.contains("Soul Binder")), "and is sent to a caster or a Soul Binder")
	fighter.queue_free()
	var mage = await make_player({"player_class": "Arcanist", "player_name": "Zbinder"})
	Global.player_data.erase("bind_attuned_at")
	check(mage.get_node("Travel").pre_cast("attune_spirit", attune), "an Arcanist can")
	mage.global_position = Vector3(12, 1, 7)
	mage.get_node("Travel").resolve("attune_spirit", attune)
	eq(Global.player_data.get("bind_point"), [12.0, 1.0, 7.0], "bound where they stand")
	check(PlayerTravel.bind_wait_minutes() > 55, "then the spirit settles for an hour")
	check(not PlayerTravel.bind_spirit(Vector3.ZERO, "x"), "and can't be bound again straight away")
	mage.queue_free()
	var city: Node = load("res://Scenes/zones/lumora.tscn").instantiate()
	var binder: Node = city.get_node_or_null("NPCs/SoulBinder")
	check(binder != null and binder.get_script().resource_path.ends_with("soul_binder_npc.gd"), "Lumora has a Soul Binder")
	if binder:
		var altar: Vector3 = city.get_node("Markers/Dawnspire Altar").position
		check(binder.position.distance_to(altar) < 20.0, "at the Dawnspire Altar")
	city.free()
	var walker = await make_player({"player_class": "Blademaster", "player_name": "Zbinder"})
	var sb: Node = load("res://Scenes/talking_vendor.tscn").instantiate()
	sb.set_script(load("res://Scripts/soul_binder_npc.gd"))
	sb.config_path = "res://Data/soul_binder.json"
	add_child(sb)
	await frames(2)
	Global.player_data.erase("bind_attuned_at")
	Global.player_data["copper"] = Global.COPPER_PER_SILVER - 1
	Global.player_data["silver"] = 0
	Global.player_data["gold"] = 0
	Global.player_data["platinum"] = 0
	Global.player_data.erase("bind_point")
	sb._bind(walker, true)
	check(not Global.player_data.has("bind_point"), "not a silver to spare, no binding")
	Global.player_data["copper"] = 50
	Global.player_data["silver"] = 2
	walker.global_position = Vector3(-3, 1, 4)
	sb._bind(walker, true)
	eq(Global.player_data.get("bind_point"), [-3.0, 1.0, 4.0], "a Soul Binder binds anyone")
	eq(Global.get_total_copper(), 50 + 2 * Global.COPPER_PER_SILVER - Global.COPPER_PER_SILVER, "for one silver")
	GameLog.general_message.disconnect(grab)
	sb.queue_free()
	walker.queue_free()
	await frames(2)

	make_floor()
	for race_sex in [["human", "male"], ["dwarf", "male"], ["ogre", "male"], ["gnome", "female"], ["elf", "female"]]:
		var p = await make_player({"player_race": race_sex[0], "player_sex": race_sex[1], "player_name": "Zheld"})
		p.global_position = Vector3(0, 1, 0)
		Inventory.equipped["primary"] = Inventory.get_item_definition("copper_sword").duplicate()
		Inventory.equipped["primary"]["item_id"] = "copper_sword"
		Inventory.equipped["offhand"] = Inventory.get_item_definition("bronze_shield").duplicate()
		Inventory.equipped["offhand"]["item_id"] = "bronze_shield"
		p._apply_equipment_from_inventory()
		eq(p.held_gear, "copper_sword|bronze_shield", "%s %s: the equipment is what's held (replicated)" % race_sex)
		await frames(20)   # the idle animation is playing
		var character: Node3D = p.get_node("Character")
		var sk: Skeleton3D = character.find_children("*", "Skeleton3D", true, false)[0]
		var sword: Node3D = sk.get_node_or_null("Held_shortsword")
		var shield: Node3D = sk.get_node_or_null("Held_kite_shield")
		check(sword != null and shield != null, "%s %s holds a sword and a shield" % race_sex)
		if sword and shield:
			var gear: Node3D = sword.get_child(0)
			var hand: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
			var height: float = character.global_transform.basis.get_scale().y
			check(gear.global_position.distance_to(hand) < 0.3 * maxf(height, 0.5), "%s %s: the grip is in the right hand" % race_sex)
			var tip: Vector3 = gear.global_transform * Vector3(0, 0.85, 0)
			var axis := Vector2(p.global_position.x, p.global_position.z)
			check(Vector2(tip.x, tip.z).distance_to(axis) > 0.25, "%s %s: the blade's tip is clear of the body (%.2f m out)" % [race_sex[0], race_sex[1], Vector2(tip.x, tip.z).distance_to(axis)])
			check(tip.y > p.global_position.y - 0.9, "%s %s: and not through the ground" % race_sex)
			var face: Vector3 = shield.get_child(0).global_transform * Vector3(0, 0, 0.05)
			check(Vector2(face.x, face.z).distance_to(axis) > 0.15, "%s %s: the shield is out from the body" % race_sex)
			var mi: MeshInstance3D = gear.find_children("*", "MeshInstance3D", true, false)[0]
			check(mi.is_in_group(HeldGear.GROUP) and mi.get_surface_override_material(0) == null, "%s %s: the sword keeps its own look (no skin recolour)" % race_sex)
		Inventory.equipped["primary"] = null
		Inventory.equipped["offhand"] = null
		p._apply_equipment_from_inventory()
		await frames(2)
		check(sk.get_node_or_null("Held_shortsword") == null, "%s %s: unequipped, the hands are empty" % race_sex)
		p.queue_free()
		await frames(2)
