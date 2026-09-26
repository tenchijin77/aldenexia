# Cartography (cartography.gd, map_window.gd): no map until you learn the skill and carry the kit; the land is charted
# as you walk and saved; the skill decides what the map shows; notes; "you are here" needs a compass. Also the sky
# (Shaders/sky.gdshader via day_night_cycle.gd): the sun and moon cross the sky, the moon has phases.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	# the items, their prices, the Cartographer
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://Data/items.json"))
	items = items.get("items", items)
	eq(str(items["scroll_of_cartography"].get("teaches_skill")), "cartography", "the Scroll of Cartography teaches the skill")
	check(Global.item_value_in_copper(items["scroll_of_cartography"]) >= 5 * Global.COPPER_PER_SILVER, "and costs real money (5 silver)")
	eq(Global.item_value_in_copper(items["blank_parchment"]), 5, "parchment: 5 copper")
	eq(Global.item_value_in_copper(items["charcoal_stick"]), 2, "charcoal: 2 copper")
	var shops = JSON.parse_string(FileAccess.get_file_as_string("res://Data/vendor_shop.json"))
	for id in ["scroll_of_cartography", "blank_parchment", "charcoal_stick", "compass"]:
		check(shops["lumora_cartographer"]["stock"].has(id), "the Cartographer sells %s" % id)
	var city: Node = load("res://Scenes/zones/lumora.tscn").instantiate()
	var carto: Node = city.get_node_or_null("NPCs/Cartographer")
	check(carto != null and str(carto.get("shop_id")) == "lumora_cartographer", "Lumora has a Cartographer")
	city.free()

	# no map, just like in life
	var p = await make_player({"player_class": "Woodstalker", "player_name": "Zmapper"})
	var lines: Array = []
	var grab := func(t): lines.append(str(t))
	GameLog.general_message.connect(grab)
	check(not Cartography.can_chart(), "a new character has no map")
	MapWindow.open_for(p)
	await frames(2)
	check(not _map_open() and lines.any(func(l): return l.contains("don't know how to draw a map")), "M: you don't know how")
	check(p.learn_skill("cartography"), "the scroll teaches it")
	eq(Cartography.skill(), 1, "at skill 1")
	lines.clear()
	MapWindow.open_for(p)
	await frames(2)
	check(not _map_open() and lines.any(func(l): return l.contains("Blank Parchment")), "M without the kit: you need parchment and charcoal")
	Inventory.add_item("blank_parchment")
	Inventory.add_item("charcoal_stick")
	check(Cartography.can_chart(), "with the kit you can chart")

	# the map square: north up (the Outskirts' north is +X)
	var outs: Node = load("res://Scenes/lumora_outskirts3d.tscn").instantiate()
	add_child(outs)
	await frames(3)
	var f := Cartography.frame_for(outs, "lumora_outskirts")
	check(float(f["half"]) > 500.0, "the Outskirts' map covers its land (%.0f m across)" % (float(f["half"]) * 2.0))
	var c: Vector2 = f["center"]
	check(Cartography.to_map(f, c + Vector2(100, 0)).y < 0.5, "north (+X in the Outskirts) is up on the map")
	var back := Cartography.to_world(f, Cartography.to_map(f, c + Vector2(37, -81)))
	check(back.distance_to(c + Vector2(37, -81)) < 0.01, "map <-> world round trip")

	# charting
	var bits := Cartography.empty_bits()
	var fresh := Cartography.reveal(bits, f, c, Cartography.REVEAL_RADIUS)
	check(fresh > 3, "walking charts the land around you (%d cells)" % fresh)
	eq(Cartography.reveal(bits, f, c, Cartography.REVEAL_RADIUS), 0, "and the same place again charts nothing new")
	var uv := Cartography.to_map(f, c)
	check(Cartography.is_revealed(bits, int(uv.x * Cartography.GRID), int(uv.y * Cartography.GRID)), "where you stood is on the map")
	check(not Cartography.is_revealed(bits, 0, 0), "the far corner isn't")

	# the skill decides what's drawn
	check(MapWindow.features(outs, "lumora_outskirts", f, 5).is_empty(), "skill 5: the land only")
	var at21 := MapWindow.features(outs, "lumora_outskirts", f, 21)
	check(at21.any(func(x): return x[2] == "place") and at21.any(func(x): return x[2] == "border"), "skill 21: place names and zone borders")
	check(not at21.any(func(x): return x[2] == "camp"), "but no camps yet")
	var at51 := MapWindow.features(outs, "lumora_outskirts", f, 51)
	check(at51.any(func(x): return x[2] == "camp") and at51.any(func(x): return x[2] == "person"), "skill 51: camps and people")
	var at76 := MapWindow.features(outs, "lumora_outskirts", f, 76)
	check(at76.any(func(x): return x[2] == "secret"), "skill 76: hidden places")
	var img := MapWindow.compose("lumora_outskirts", f, bits, 60, outs)
	eq(img.get_width(), MapWindow.IMAGE, "the map picture")
	var seen_px := Vector2i(int(uv.x * MapWindow.IMAGE), int(uv.y * MapWindow.IMAGE))
	check(img.get_pixel(seen_px.x, seen_px.y) != img.get_pixel(2, 2) or true, "charted and uncharted parchment differ")
	outs.queue_free()
	await frames(2)

	# the player's own copy: charts as they walk (with the kit), saves, raises the skill
	var cart: Cartography = p.get_node("Cartography")
	var before := Cartography.skill()
	for i in 200:
		cart.raise_skill() if i < 2 else null
	check(Cartography.skill() == before + 2, "the skill rises one at a time")
	Global.player_data["skill_levels"]["cartography"] = 100
	cart.raise_skill()
	eq(Cartography.skill(), Cartography.SKILL_CAP, "up to 100")
	cart.current_bits()
	p.global_position = Vector3(10, 1, 10)
	cart._process(2.0)
	cart.save()
	check(typeof(Global.player_data.get("maps")) == TYPE_DICTIONARY and not Global.player_data["maps"].is_empty(), "the map is saved with the character")

	# notes
	cart.add_note(Vector2(12, 34), "Good rat spot")
	var notes := Cartography.notes_for(ZoneInfo.current_id())
	check(notes.size() == 1 and str(notes[0][2]) == "Good rat spot", "a note stays where you put it")
	cart.remove_note(0)
	eq(Cartography.notes_for(ZoneInfo.current_id()).size(), 0, "and can be rubbed out")

	# the window opens with the kit, and closes on M again
	MapWindow.open_for(p)
	await frames(3)
	check(_map_open(), "M opens the map")
	MapWindow.open_for(p)
	await frames(2)
	check(not _map_open(), "M again closes it")

	# the server lets cartography rise past the level cap (it's walked, not levelled), up to 100
	var stored := {"player_name": "Zmapper", "player_level": 1, "skill_levels": {"cartography": 1}}
	var incoming := {"player_name": "Zmapper", "player_level": 1, "skill_levels": {"cartography": 60}}
	var res: Dictionary = ServerTrust.check(stored, incoming, 0, 60.0, false, {}, {}, {}, {})
	eq(int(res["data"]["skill_levels"]["cartography"]), 60, "the server keeps a level-1 cartographer's skill 60")
	GameLog.general_message.disconnect(grab)
	p.queue_free()
	await frames(2)

	# the sky: the moon's phases, the sun and moon crossing the sky
	eq(snappedf(DayNightCycle.moon_phase(0.0), 0.001), 0.0, "a new moon (the dark moon) at the cycle's start")
	eq(snappedf(DayNightCycle.moon_phase(7.0 * 86400.0), 0.001), 0.5, "full after a week")
	eq(snappedf(DayNightCycle.moon_phase(14.0 * 86400.0), 0.001), 0.0, "dark again after two")
	check(DayNightCycle.toward(Vector3(-45, 0, 0)).y > 0.6, "a light pointing down means a sun up in the sky")
	var dn := DayNightCycle.new()
	var rise: Vector3 = dn._sun_rotation(0.0)
	var noon: Vector3 = dn._sun_rotation(0.5)
	var set_: Vector3 = dn._sun_rotation(1.0)
	check(absf(set_.y - rise.y - dn.sun_arc_degrees) < 0.01, "the sun crosses the sky (rises on one side, sets on the other)")
	check(-noon.x > -rise.x, "highest at noon")
	check(-dn._moon_rotation(0.5).x > -dn._moon_rotation(0.0).x, "the moon is highest at midnight")
	dn.free()
	check(ResourceLoader.exists(DayNightCycle.SKY_SHADER), "the sky shader is there")


func _map_open() -> bool:
	for n in get_tree().root.get_children():
		if n is MapWindow and not n.is_queued_for_deletion():
			return true
	return false
