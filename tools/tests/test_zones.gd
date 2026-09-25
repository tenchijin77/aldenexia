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
