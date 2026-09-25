# Test 38 (Zozuur, Maedianie): hail a player or pet, who cast a buff on you, game master mode that survives zoning,
# the Lumora zone and the Outskirts' north wall, groups that survive zoning (world_link.gd), rain in every zone.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var lines: Array = []
	var grab := func(t): lines.append(str(t))
	GameLog.general_message.connect(grab)
	make_floor()
	var p = await make_player({"player_name": "Zozuur", "player_class": "Voidknight"})

	# hail: a targeted player or pet is greeted by name
	var other = await make_player({"player_name": "Maedianie", "player_class": "Wildspeaker"})
	Global.player_data["player_name"] = "Zozuur"
	p.current_target = other
	lines.clear()
	p.try_hail_nearby_npc()
	check(lines.any(func(l): return l.contains("Hail, Maedianie!")), "hailing a targeted player greets them by name")
	var pet = load("res://Scenes/monster_template.tscn").instantiate()
	pet.monster_name = "rat"
	add_child(pet)
	await frames(2)
	pet.pet_name = "Whiskers"
	p.current_target = pet
	lines.clear()
	p.try_hail_nearby_npc()
	check(lines.any(func(l): return l.contains("Hail, ") and l.contains("!")), "hailing a pet greets it")
	pet.queue_free()
	other.queue_free()

	# a buff someone else cast shows "Caster: <name>" on its tooltip; your own doesn't
	p.combat_node.apply_effect("test_blessing", 30.0, {})
	p.combat_node.effect_casters["test_blessing"] = "Maedianie"
	eq(p.combat_node.effect_casters.get("test_blessing"), "Maedianie", "the caster is remembered")
	p.combat_node.remove_effect("test_blessing")
	check(not p.combat_node.effect_casters.has("test_blessing"), "and forgotten with the effect")
	check(not FileAccess.get_file_as_string("res://Scripts/buff_bar.gd").contains("(from your group)"), "no more '(from your group)' in buff names")

	# the ailment icons: the user's own art, one per effect, in Assets/icons/effects (every mapped icon loads)
	const BUFF_BAR := preload("res://Scripts/buff_bar.gd")
	for e in BUFF_BAR.ENVIRONMENTAL_EFFECT_SPELL_ICONS:
		check(load(BUFF_BAR.ENVIRONMENTAL_EFFECT_SPELL_ICONS[e]) is Texture2D, "%s has an icon" % e)
	check(str(BUFF_BAR.ENVIRONMENTAL_EFFECT_SPELL_ICONS["kenjis_blessing"]).ends_with("effects/kenjis_blessing.png"), "Kenji's blessing: the grey cat")

	# game master mode is the character's: a flag file on the server, next to its password file
	const GM_RELAY := preload("res://Scripts/gm_relay.gd")
	eq(GM_RELAY.flag_path("srv_zozuur"), Net.CHARACTER_DIR + "/srv_zozuur_gm.json", "the GM flag lives with the character on the server")
	check(preload("res://Scripts/gm_commands.gd").RESTORED == "@restored", "carried over quietly")

	# Lumora: its own zone; the Outskirts' town reaches it at its north end; the north wall stands at x 118
	check(ZoneInfo.exists("lumora") and ZoneInfo.port_for("lumora", 8910) == 8922, "Lumora is a zone on port 8922 (in the opened range)")
	var outskirts: Node = load("res://Scenes/lumora_outskirts3d.tscn").instantiate()
	var line: Node3D = null
	for l in outskirts.find_children("*", "Area3D", true, false):
		if str(l.get("target_zone")) == "lumora":
			line = l
	add_child(outskirts)
	await frames(6)
	check(line != null, "the Outskirts has a zone line to Lumora")
	if line:
		check(line.covers(Vector3(113, 0, 14)) and line.covers(Vector3(113, 0, -28)) and line.covers(Vector3(113, 0, 56)), "it spans the town's north end")
		check(not line.covers(Vector3(80, 0, 14)), "and not the middle of town")
		eq(str(line.get("target_marker")), "lumora_outskirts_zone", "arriving at Lumora's marker")
	check(outskirts.get_node_or_null("Markers/lumora_zone") != null, "the Outskirts has the arrival marker from Lumora")
	outskirts.queue_free()
	var city: Node = load("res://Scenes/zones/lumora.tscn").instantiate()
	check(city.get_node_or_null("Markers/lumora_outskirts_zone") != null, "Lumora has the arrival marker from the Outskirts")
	check(city.get_node_or_null("WeatherManager") != null and city.get_node_or_null("WorldLink") != null, "Lumora has weather and the world link")
	city.free()

	# rain: every zone scene has a weather manager that can rain
	for id in ZoneInfo.zones():
		var z: Node = load(ZoneInfo.scene_for(id)).instantiate()
		var w: Node = z.get_node_or_null("WeatherManager")
		check(w != null, "%s has weather" % id)
		if w:
			add_child(z)
			await frames(2)
			w.set_weather(true)
			await frames(2)
			check(w.raining and w.get("_rain") != null, "%s: it rains (particles built)" % id)
			w.set_weather(false)
			z.queue_free()
			await frames(2)

	# groups on the hub: set, members moving between groups, a member leaving, the next member leading
	var link := preload("res://Scripts/world_link.gd").new()
	add_child(link)
	link._hub_group({"t": "group_set", "by": "Zozuur", "members": ["Zozuur", "Maedianie", "Tenchijin"]})
	eq(link._group_of("maedianie"), "zozuur", "a member's group is found by name")
	link._hub_group({"t": "group_leave", "by": "Zozuur"})
	eq(link._group_of("tenchijin"), "maedianie", "the leader logging out passes the lead on")
	link._hub_group({"t": "group_set", "by": "Annadaeus", "members": ["Annadaeus", "Tenchijin"]})
	eq(link._group_of("tenchijin"), "annadaeus", "joining another group leaves the old one")
	eq(link._group_of("maedianie"), "", "a group of one is no group")
	link._hub_group({"t": "group_set", "by": "Annadaeus", "members": ["Annadaeus"]})
	eq(link.groups.size(), 0, "the leader disbanding ends it")
	link.queue_free()

	# the client takes the server's word: members here by connection, the rest by zone
	p.apply_group_state(["Zozuur", "Maedianie"], [], [{"name": "Maedianie", "zone": "Dustwind Plateaus"}])
	eq(p.group_members, [p.get_multiplayer_authority()], "only you are in this zone")
	eq(p.group_remote.size(), 1, "Maedianie is in the group, in another zone")
	p.apply_group_state([], [], [])
	eq(p.group_remote.size(), 0, "no group: nobody elsewhere")

	# players pass through each other: nobody stands on a head (and is carried off, or climbs 140 m into the sky)
	var under = await make_player({"player_name": "Maedianie", "player_class": "Wildspeaker"})
	under.set_multiplayer_authority(999)   # someone else's player: this machine doesn't steer it
	under.global_position = Vector3(20, 1, 20)
	p.global_position = Vector3(20, 3.2, 20)
	for i in 40:
		await get_tree().physics_frame
	check(p.global_position.y < under.global_position.y + 0.5, "dropped onto another player, you fall through to the ground (%s)" % str(p.global_position.snapped(Vector3.ONE * 0.1)))
	check(p.get_collision_exceptions().has(under) and under.get_collision_exceptions().has(p), "both ways")
	eq(p.platform_floor_layers, 0, "and nothing underfoot carries you")
	under.queue_free()

	# held gear (models/Weapons, tools/blender/fix_props.py): one name per weapon type; the grip at the origin, pointing up
	for w in ["shortsword", "two_handed_sword", "one_handed_axe", "staff", "dagger", "bow"]:
		var box := _model_box("res://models/Weapons/%s.glb" % w)
		check(box.size.y > box.size.x and box.size.y > box.size.z, "%s stands along +Y" % w)
		if w == "bow":
			check(absf(box.get_center().y) < 0.05, "the bow: held in the middle")
		else:
			check(box.position.y < 0.0 and box.end.y > 0.0 and box.end.y > -box.position.y, "%s: the grip at the origin, most of it above (%s)" % [w, str(box)])
	for sh in ["buckler", "round_shield", "tower_shield", "kite_shield"]:
		var box := _model_box("res://models/Weapons/%s.glb" % sh)
		check(box.size.z < box.size.x and box.end.z > 0.0 and box.position.z > -0.02, "%s faces +Z from its handle (%s)" % [sh, str(box)])
	var arrow := _model_box("res://models/Weapons/arrow.glb")
	check(arrow.size.z > 1.0 and absf(arrow.get_center().z) < 0.05, "the arrow lies along Z, centred")
	# scenery (models/Environmental, fix_props.py "prop"): standing up, the base on the origin
	for prop in ["wrecked_caravan", "medieval_signpost", "desert_tent", "medieval_banner", "old_foundation_stone", "warning_sign",
			"stone_circles", "abandoned_watchtower", "old_bleached_banners", "destroyed_caravan", "nomad_camp"]:
		var box := _model_box("res://models/Environmental/%s.glb" % prop)
		check(absf(box.position.y) < 0.02 and absf(box.get_center().x) < 0.05 and absf(box.get_center().z) < 0.05, "%s stands on the origin (%s)" % [prop, str(box)])
	check(_model_box("res://models/Environmental/abandoned_watchtower.glb").size.y > 7.0, "the watchtower is tower-sized")
	check(_model_box("res://models/Environmental/medieval_signpost.glb").size.y > 2.0, "the signpost stands up")

	# scenery placed from the Solgrave Expanse drawio (Scenes/props/*.tscn under each zone's "Terrain Art", movable in the editor)
	var dw: Node = load("res://Scenes/zones/dustwind_plateaus.tscn").instantiate()
	var art: Node = dw.get_node_or_null("Terrain Art")
	check(art != null and art.get_child_count() == 18, "Dustwind has its scenery")
	if art:
		for place in [["Warning Sign", Vector2(6, -458)], ["Stone Circles", Vector2(-440, -195)], ["Abandoned Watchtower", Vector2(301, 140)],
				["Old Bleached Banners", Vector2(399, 223)], ["Nomad Camp", Vector2(-400, 380)], ["Destroyed Caravan", Vector2(-17, 380)]]:
			var n: Node3D = art.get_node_or_null(str(place[0]))
			check(n != null and Vector2(n.position.x, n.position.z).distance_to(place[1]) < 1.0 and n.scene_file_path.begins_with("res://Scenes/props/"), "Dustwind: %s at the drawio's spot" % place[0])
	dw.free()
	var af: Node = load("res://Scenes/zones/ashfall_dunes.tscn").instantiate()
	check(af.get_node_or_null("Terrain Art/Djhanid Encampment") != null and af.get_node_or_null("Terrain Art/Vendor Camp Tent 1") != null, "Ashfall: the Djhanid Encampment and the vendor camp")
	af.free()
	var ley = JSON.parse_string(FileAccess.get_file_as_string("res://Data/ley_lines.json"))
	var spire: Dictionary = ley["dustwind_plateaus"]["nodes"][0]
	check(spire["class"] == "Arcanist" and Vector2(spire["position"][0], spire["position"][1]) == Vector2(-211, 391), "the Dustwind Spire stands at the drawio's Arcanist Portal")

	# Lumora's city wall continues the Outskirts' gate walls across the zone line: the Outskirts (x, z) -> Lumora (z - 14, 618 - x)
	var outs: Node = load("res://Scenes/lumora_outskirts3d.tscn").instantiate()
	var gates: Node3D = outs.get_node("Lumora Gates")
	var lum: Node = load("res://Scenes/zones/lumora.tscn").instantiate()
	var wall: Node3D = null
	for c in lum.get_children():
		if c is Node3D and str(c.scene_file_path).ends_with("City Wall.glb"):
			wall = c
	check(wall != null, "Lumora has the city wall")
	if wall:
		for local in [Vector3(-42, 0, 51.25), Vector3(42, 0, 51.25), Vector3(0, 0, 51.25)]:
			var o: Vector3 = gates.transform * local
			var l: Vector3 = wall.transform * local
			check(Vector2(l.x, l.z).distance_to(Vector2(o.z - 14.0, 618.0 - o.x)) < 0.1, "the wall's end %s meets the Outskirts' across the line" % str(local))
		check(absf(wall.position.y) < 0.01, "standing on the ground")
		var arrive: Node3D = lum.get_node("Markers/lumora_outskirts_zone")
		var inside: Vector3 = wall.transform.affine_inverse() * arrive.position
		check(inside.x > -40.0 and inside.x < 40.0, "you arrive between the walls (%.1f m across)" % inside.x)
	check(lum.get_node_or_null("StructureCollision") != null, "the wall is solid (structure collision in every zone)")
	outs.free()
	lum.free()
	const SC := preload("res://Scripts/structure_collision.gd")
	var sc := SC.new()
	var prop_node: Node = load("res://Scenes/props/desert_tent.tscn").instantiate()
	check(sc._is_model(prop_node), "prop scenes are made solid too")
	prop_node.free()
	sc.free()

	# travel sites wear their models
	for cls in ["Arcanist", "Wildspeaker", "Chaosborn"]:
		var site := LeyLineNode.new()
		site.setup({"id": "t_" + cls, "name": "Test", "class": cls})
		add_child(site)
		var meshes := site.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= 1 and meshes.all(func(m): return not (m.mesh is PrimitiveMesh)), "a %s site shows its model" % cls)
		site.queue_free()

	GameLog.general_message.disconnect(grab)
	p.queue_free()
	await frames(2)


# The combined bounds of a model's meshes, in the model's own space.
func _model_box(path: String) -> AABB:
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var box := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).get_aabb()
		var t: Transform3D = Transform3D.IDENTITY
		var n: Node = m
		while n != root:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		b = t * b
		box = b if first else box.merge(b)
		first = false
	root.free()
	return box
