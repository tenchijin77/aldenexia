# Zone scenes (Scenes/zones/, built on zone_template.tscn): each knows its id, has its own terrain and a baked navmesh,
# and the zone-keyed data follows it (ZoneInfo) instead of always meaning the Outskirts.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	eq(ZoneInfo.id_of_scene(null), "lumora_outskirts", "no scene: the starting zone")
	var outskirts = load("res://Scenes/lumora_outskirts3d.tscn").instantiate()
	eq(ZoneInfo.id_of_scene(outskirts), "lumora_outskirts", "the Outskirts id comes from its file name")
	outskirts.free()
	var template = load("res://Scenes/zones/zone_template.tscn").instantiate()
	eq(str(template.get_node("Terrain3D").data_directory), "", "the template has no terrain of its own")
	for node_name in ["RemotePlayers", "PlayerSpawner", "DayNightCycle", "monster_spawner/SpawnedMobs", "monster_spawner/MobSpawner",
			"NavigationRegion3D", "GMRelay", "WorldItems", "CraftingWorld", "NPCs", "Markers", "ZoneLines"]:
		check(template.has_node(node_name), "template has %s" % node_name)
	template.free()

	for file in DirAccess.get_files_at("res://Scenes/zones/"):
		if not file.ends_with(".tscn") or file == "zone_template.tscn":
			continue
		var id := file.get_basename()
		var zone = load("res://Scenes/zones/" + file).instantiate()
		eq(str(zone.zone_id), id, "%s: zone_id matches the file name" % file)
		check(not str(zone.zone_name).is_empty(), "%s: has a display name" % id)
		var terrain = zone.get_node("Terrain3D")
		eq(str(terrain.data_directory), "res://zones/%s_terrain" % id, "%s: its own terrain folder" % id)
		var nav: NavigationMesh = zone.get_node("NavigationRegion3D").navigation_mesh
		check(nav != null and nav.resource_path == "res://Data/%s_navmesh.tres" % id, "%s: its own navmesh file" % id)
		check(nav != null and nav.get_polygon_count() > 0, "%s: navmesh is baked (tools/bake_lumora_navmesh.gd)" % id)
		add_child(zone)
		await frames(3)
		check(terrain.data.get_region_count() > 0, "%s: terrain has regions" % id)
		eq(ZoneInfo.id_for(zone.get_node("monster_spawner")), id, "%s: spawners know their zone" % id)
		eq(zone.get_node("monster_spawner/SpawnedMobs").get_child_count(), 0, "%s: no Outskirts monsters" % id)
		zone.queue_free()
		await frames(2)

	# NPCs placed by dragging them in the editor: the preview is editor-only, and a vendor stands on the ground in play.
	make_floor(60.0)
	var vendor = load("res://Scenes/talking_vendor.tscn").instantiate()
	vendor.set("model_key", "dwarf_male")
	add_child(vendor)
	vendor.global_position = Vector3(3, 2.5, 3)   # dropped 2.5 m above the ground
	await frames(4)
	check(vendor.get_node_or_null("EditorPreview") == null, "the editor preview removes itself in the game")
	check(absf(vendor.global_position.y) < 0.05, "a vendor placed above the ground stands on it (y %.2f)" % vendor.global_position.y)
	vendor.queue_free()
	for scene in ["talking_vendor", "tobble_npc", "kenji_npc", "oni_npc", "harbour_master", "vendor_npc"]:
		var npc: Node = load("res://Scenes/%s.tscn" % scene).instantiate()
		check(npc.has_node("EditorPreview"), "%s shows in the editor" % scene)
		npc.free()

	# The zone list (Data/zones.json) and every zone line
	var ports := {}
	for id in ZoneInfo.zones():
		check(ResourceLoader.exists(ZoneInfo.scene_for(id)), "zones.json %s: scene exists" % id)
		var port := ZoneInfo.port_for(id, 8910)
		check(not ports.has(port), "zones.json %s: its own port (%d)" % [id, port])
		ports[port] = id
	eq(ZoneInfo.port_for("dustwind_plateaus", 8910), 8920, "Dustwind on 8920")
	eq(ZoneInfo.of_character({}), "lumora_outskirts", "a character from before zones is in the Outskirts")
	eq(ZoneInfo.of_character({"zone": "nowhere"}), "lumora_outskirts", "an unknown zone means the Outskirts")
	eq(ZoneInfo.of_character({"zone": "dustwind_plateaus"}), "dustwind_plateaus", "a saved zone")
	var lines := 0
	for id in ZoneInfo.zones():
		var zone: Node = load(ZoneInfo.scene_for(id)).instantiate()
		for line in zone.find_children("*", "Area3D", true, false):
			if not (line is ZoneLine):
				continue
			lines += 1
			check(ZoneInfo.exists(line.target_zone) and line.target_zone != id, "%s / %s: goes to another real zone (%s)" % [id, line.name, line.target_zone])
			if ZoneInfo.exists(line.target_zone):
				var there: Node = load(ZoneInfo.scene_for(line.target_zone)).instantiate()
				check(there.has_node("Markers/" + line.target_marker), "%s / %s: %s has the marker '%s'" % [id, line.name, line.target_zone, line.target_marker])
				there.free()
		zone.free()
	check(lines >= 2, "the Outskirts and Dustwind have zone lines to each other")

	# covers(): the server's "was that player really at the line" check
	var zl := ZoneLine.new()
	zl.size = Vector3(60, 30, 6)
	add_child(zl)
	zl.global_position = Vector3(100, 0, 100)
	check(zl.covers(Vector3(110, 2, 101)), "a player at the line")
	check(zl.covers(Vector3(100, 2, 100 + 3 + ZoneLine.SERVER_TOLERANCE - 1)), "a few metres short (lag)")
	check(not zl.covers(Vector3(100, 2, 160)), "60 m away is not at the line")
	zl.queue_free()

	# the server's zone-change check (no body needed for these cases)
	var stored := {"zone": "lumora_outskirts", "bind_zone": "lumora_outskirts", "last_position": [1, 2, 3]}
	var cheat := {"zone": "ashfall_dunes", "last_position": [1, 2, 3]}
	check(Net._check_zone_change(-1, "ztest", stored, cheat, false), "a zone change without a zone line is caught")
	eq(cheat["zone"], "lumora_outskirts", "and the stored zone kept")
	var gm := {"zone": "ashfall_dunes", "last_position": [1, 2, 3]}
	Net._check_zone_change(-1, "ztest", stored, gm, true)
	check(gm["zone"] == "ashfall_dunes" and not gm.has("last_position"), "a game master may go anywhere (arrives at the zone's spawn)")
	var home := {"zone": "lumora_outskirts", "zone_in": "@bind"}
	check(not Net._check_zone_change(-1, "ztest", {"zone": "dustwind_plateaus", "bind_zone": "lumora_outskirts"}, home, false) or home["zone"] == "lumora_outskirts", "going home to the bind zone is allowed")
	eq(home["zone"], "lumora_outskirts", "dying in Dustwind takes you home to the Outskirts")
	var wrong_home := {"zone": "ashfall_dunes", "zone_in": "@bind"}
	Net._check_zone_change(-1, "ztest", {"zone": "dustwind_plateaus", "bind_zone": "lumora_outskirts"}, wrong_home, false)
	eq(wrong_home["zone"], "dustwind_plateaus", "'@bind' to a zone you aren't bound in is refused")
	eq(str(gm.get("last_zone", "")), "Ashfall Dunes", "an accepted zone change shows the new zone on the character list")

	# a save made on the way out through a zone line already names the zone you're going to
	var saved := Global.player_data.duplicate(true)
	Global.player_data = {"player_name": "Ztest", "zone": "dustwind_plateaus"}
	var text := Global.serialize_player_data()
	eq(str(JSON.parse_string(text).get("last_zone", "")), "Dustwind Plateaus", "the character list shows the zone you logged out in")
	Global.player_data = saved

	# EverQuest-style zone-in message
	var said: Array = []
	var listen := func(text: String) -> void: said.append(text)
	GameLog.general_message.connect(listen)
	var walker = await make_player()
	await get_tree().create_timer(0.8).timeout
	GameLog.general_message.disconnect(listen)
	check(said.any(func(t): return str(t).contains("You have entered %s." % WorldAnnouncer.zone_display_name())), "\"You have entered <zone>.\" on entering the world")
	walker.queue_free()

