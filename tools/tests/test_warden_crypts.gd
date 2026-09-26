# The Warden Crypts (2026-09-26): the first indoor dungeon, a placeholder under the Outskirts mausoleum ("a small zone...
# zone into via steps inside the mausoleum building... add halvek and some harder undead there"). Built from a text layout
# (Data/warden_crypts_layout.txt, Scripts/dungeon_builder.gd); underground lighting (DayNightCycle outdoors off: no sun,
# no rain, no Elf outdoor speed); the camera stops at walls and ceilings.
extends "res://tools/tests/test_base.gd"

const CRYPT := "res://Scenes/zones/warden_crypts.tscn"


func run() -> void:
	check(ZoneInfo.exists("warden_crypts") and not ZoneInfo.always_on("warden_crypts"), "zones.json: the crypts, started on demand")
	eq(ZoneInfo.name_for("warden_crypts"), "The Warden Crypts", "its name")
	var rows := preload("res://Scripts/dungeon_builder.gd").load_rows("res://Data/warden_crypts_layout.txt")
	check(rows.size() > 10, "the layout reads (%d rows)" % rows.size())

	# the spawns: Halvek moved down from the mausoleum floor, harder undead deeper in, every spawn point on an open cell
	var outskirts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/lumora_outskirts_spawns.json"))
	var crypt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/warden_crypts_spawns.json"))
	check(not outskirts["spawns"].any(func(s): return s["mob_type"] == "sergeant_halvek"), "Halvek no longer stands on the mausoleum floor")
	check(crypt["spawns"].any(func(s): return s["mob_type"] == "sergeant_halvek"), "he's in the crypts")
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/monsters.json"))
	monsters = monsters.get("monsters", monsters)
	var top := 0
	for s in crypt["spawns"]:
		check(monsters.has(s["mob_type"]), "%s is a real monster" % s["mob_type"])
		top = maxi(top, int(monsters.get(s["mob_type"], {}).get("level", 0)))
		var c := int(floor(float(s["position"][0]) / 3.0))
		var r := int(floor(float(s["position"][2]) / 3.0))
		check(r < rows.size() and c < rows[r].length() and rows[r][c] != "#", "%s spawns on an open cell (%d, %d)" % [s["mob_type"], c, r])
	check(top >= 9, "harder undead than the mausoleum's (up to level %d)" % top)

	# the zone itself
	var zone: Node = load(CRYPT).instantiate()
	add_child(zone)
	await frames(4)
	var dungeon := zone.get_node("Structures/Dungeon")
	check(dungeon.get_node_or_null("DungeonCollision") != null, "rooms built with collision")
	check(dungeon.get_node("DungeonCollision").owner == null, "(built at load, never saved into the scene)")
	var torches := dungeon.get_children().filter(func(n): return n.name.begins_with("WallTorch"))
	check(torches.size() >= 10, "wall torches light it (%d)" % torches.size())
	check(torches.all(func(t): return t.find_children("*", "OmniLight3D", true, false).size() == 1 and t.find_children("*", "MeshInstance3D", true, false).size() >= 2), "each one the hand torch model in a bracket, with its light")
	check(not zone.get_node("DirectionalLight3D").visible, "no sun underground")
	check(zone.get_node("DayNightCycle").outdoors == false, "the day/night cycle knows it's underground")
	for i in 5:
		await get_tree().physics_frame
	var space := (zone as Node3D).get_world_3d().direct_space_state
	var arrive: Vector3 = zone.get_node("Markers/lumora_outskirts_zone").global_position
	var down := PhysicsRayQueryParameters3D.create(arrive + Vector3(0, 1, 0), arrive + Vector3(0, -3, 0), 64)
	var floor_hit := space.intersect_ray(down)
	check(not floor_hit.is_empty() and absf(floor_hit["position"].y) < 0.05, "there's a floor where you arrive")
	var up := PhysicsRayQueryParameters3D.create(arrive + Vector3(0, 1, 0), arrive + Vector3(0, 10, 0), 64)
	check(not space.intersect_ray(up).is_empty(), "and a ceiling over you")
	var west := PhysicsRayQueryParameters3D.create(arrive + Vector3(0, 1, 0), arrive + Vector3(-30, 1, 0), 64)
	var wall := space.intersect_ray(west)
	check(not wall.is_empty() and arrive.x - wall["position"].x < 12.0, "and walls (the entry hall is %.1f m to its west wall)" % (arrive.x - float(wall.get("position", Vector3.ZERO).x)))
	var line: ZoneLine = zone.get_node("ZoneLines/Up to the Mausoleum")
	check(not _in_box(line, arrive), "you don't arrive on the way back up")
	check(_in_box(line, arrive + Vector3(0, 1, -7)), "the top of the stairs takes you back up")

	# the camera: pulled in by the west wall instead of looking through it
	var p = await make_player({"player_race": "elf"})
	p.global_position = arrive
	var rig = p.get_node("CameraRig")
	rig.rotation.y = -PI / 2.0   # looking east: the camera sits behind, to the west, through the wall at 12 m zoom
	rig.current_zoom = 12.0
	rig.camera.current = true
	for i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
	var cam_x: float = rig.camera.global_position.x
	check(cam_x > float(wall.get("position", Vector3.ZERO).x), "the camera stops in front of the wall (x %.1f, wall %.1f)" % [cam_x, float(wall.get("position", Vector3.ZERO).x)])
	check(not p.zone_is_outdoors(), "the player knows it's underground")
	p.combat_node.race_movement_speed_mult = 0.0
	p.apply_racial_traits("elf")
	eq(p.combat_node.race_movement_speed_mult, 0.0, "an Elf's outdoor speed doesn't apply underground")
	var weather = zone.get_node("WeatherManager")
	weather._time_to_next_change = 0.0
	await frames(3)
	check(not weather.raining, "it never rains underground")
	p.queue_free()
	zone.queue_free()
	await frames(2)

	# the Outskirts side: steps down inside the mausoleum
	var out: Node = load("res://Scenes/lumora_outskirts3d.tscn").instantiate()
	var down_line: ZoneLine = out.get_node("ZoneLines/Down to the Warden Crypts")
	eq(down_line.target_zone, "warden_crypts", "the mausoleum's stairwell leads to the crypts")
	var inside := Vector3(49.5, 0, -244.6)   # the mausoleum's hollow middle (x 29.6-69.5, z -263.6 to -225.6)
	check(absf(down_line.position.x - inside.x) < 20.0 and absf(down_line.position.z - inside.z) < 19.0, "inside the mausoleum")
	check(out.has_node("StandIns/CryptStairwell"), "with a stand-in stairwell")
	var back: Vector3 = out.get_node("Markers/warden_crypts_zone").position
	check(not _in_box(down_line, back), "coming back up you arrive beside it, not on it")
	out.free()


# inside the zone line's own box (what walking into it does; covers() adds the server's lag slack)
func _in_box(line: ZoneLine, point: Vector3) -> bool:
	var local := line.transform.affine_inverse() * point if not line.is_inside_tree() else line.to_local(point)
	return absf(local.x) <= line.size.x / 2.0 and absf(local.y) <= line.size.y / 2.0 and absf(local.z) <= line.size.z / 2.0
