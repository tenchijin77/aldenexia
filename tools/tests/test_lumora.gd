# Lumora, the city (first pass, 2026-09-25): the town's vendors, bank, archive, crafting stations and mirror moved in from
# the Outskirts (Aldric stays at the gate), district markers, static and patrolling guards, and its own music.
extends "res://tools/tests/test_base.gd"

const MOVED := ["Lira Solarpetal", "Ilsabet Thornmere", "Oswin Coinwright", "Xalvyr Tenn", "Borgrim Emberforge"]


func run() -> void:
	var city: Node = load("res://Scenes/zones/lumora.tscn").instantiate()
	var names := _npc_names(city)
	for n in MOVED:
		check(names.has(n), "%s is in Lumora" % n)
	check(city.get_node_or_null("NPCs/TobbleTinkerer") != null, "Tobble is in Lumora")
	eq(city.get_node("CraftingStations").get_child_count(), 10, "all ten crafting stations are on Crafters' Row")
	var row: Vector3 = city.get_node("Markers/Crafters' Row").position
	for s in city.get_node("CraftingStations").get_children():
		check(Vector2(s.position.x, s.position.z).distance_to(Vector2(row.x, row.z)) < 40.0, "%s stands on Crafters' Row" % s.name)
	check(city.get_node_or_null("SilveredMirror") != null, "the mirror is at the barber's")
	for m in ["South Gate", "Citadel Plaza", "Oasisheart Citadel", "Solaris Vault", "The Oasis", "Sandveil Bazaar", "Crafters' Row",
			"Dawnspire Altar", "The Sunlit Rest", "Treasury Office", "Old Town", "Caravanserai"]:
		check(city.get_node_or_null("Markers/" + m) != null, "district marker: " + m)
	# inside the walls: the main block x -420..425, z 45..440, or the eastern annex x 425..795, z 60..300
	for m in city.get_node("Markers").get_children():
		if m.name == "lumora_outskirts_zone":
			continue
		var p: Vector3 = m.position
		var inside: bool = (p.x > -420 and p.x < 425 and p.z > 45 and p.z < 440) or (p.x >= 425 and p.x < 795 and p.z > 60 and p.z < 300)
		check(inside, "%s is inside the city wall (%s)" % [m.name, str(p)])
	var guards: Node = city.get_node("Guards")
	check(guards.get_child_count() >= 8, "Oasis Wardens at the gate, the Citadel and the Vault, and on patrol")
	var patrols := 0
	for g in guards.get_children():
		var wps: Array = g.get("patrol_waypoints")
		if wps.is_empty():
			continue
		patrols += 1
		for p in wps:
			check(g.get_node_or_null(p) != null, "%s: waypoint %s exists" % [g.name, str(p)])
	check(patrols >= 2, "two patrol routes")
	city.free()

	# the Outskirts keeps Aldric at the gate; the rest moved
	var outs: Node = load("res://Scenes/lumora_outskirts3d.tscn").instantiate()
	var out_names := _npc_names(outs)
	check(out_names.has("Aldric the Provisioner"), "Aldric stays at the Outskirts gate")
	for n in MOVED:
		check(not out_names.has(n), "%s is no longer in the Outskirts" % n)
	check(outs.get_node_or_null("CraftingStations") == null and outs.get_node_or_null("SilveredMirror") == null, "no stations or mirror left behind")
	outs.free()
	var placements = JSON.parse_string(FileAccess.get_file_as_string("res://Data/crafting_placements.json"))
	eq(placements["lumora_outskirts"]["stations"].size(), 0, "the data's stations don't reappear in the Outskirts")

	# music: the user's own theme, balanced like every other track
	check(FileAccess.get_file_as_string("res://Scripts/global_background_music.gd").contains('"res://Scenes/zones/lumora.tscn": "res://Assets/music/Welcome to Lumora.ogg"'), "Lumora plays Welcome to Lumora")
	var sounds = JSON.parse_string(FileAccess.get_file_as_string("res://Data/sounds.json"))
	check(sounds["music"].has("res://Assets/music/Welcome to Lumora.ogg") and sounds["music"]["res://Assets/music/Welcome to Lumora.ogg"].has("volume_db"), "and it's volume-balanced")


func _npc_names(zone: Node) -> Array:
	var out := []
	for n in zone.get_node("NPCs").get_children():
		out.append(str(n.get("npc_name")))
	return out
