# Lumora stand-ins (2026-09-26; tools/make_lumora_standins.gd + tools/place_lumora_standins.py): a building per district
# (its own scene, solid, baked into the navmesh), the 14 class trainers in their guild halls selling their class's scrolls,
# the innkeeper, the Commander, the temple healer, the crier, the notice board; Ralph's Last Round at the Outskirts gate.
extends "res://tools/tests/test_base.gd"

const TRAINERS := ["blademaster", "lightsworn", "aetherfist", "woodstalker", "arcanist", "runecaster", "chaosborn",
		"lightmender", "spiritweaver", "wildspeaker", "voidknight", "gravecaller", "shadowblade", "troubadour"]


func run() -> void:
	var shops = JSON.parse_string(FileAccess.get_file_as_string("res://Data/vendor_shop.json"))
	for cls in TRAINERS:
		var shop: Dictionary = shops.get("trainer_" + cls, {})
		check(shop.get("stock", []).size() >= 10, "the %s trainer sells their scrolls (%d)" % [cls, shop.get("stock", []).size()])
	check(shops.has("lumora_inn") and shops.has("outskirts_tavern"), "the inn and the tavern have their boards")

	var zone: Node3D = load("res://Scenes/zones/lumora.tscn").instantiate()
	add_child(zone)
	await frames(10)
	var stand := zone.get_node_or_null("StandIns")
	check(stand != null and stand.get_child_count() >= 9, "the district buildings and the notice board")
	for n in ["SunlitRest", "OasisheartCitadel", "HallOfArms", "Courthouse", "LycaeumAnnex", "TempleOfTheDawn", "OldTownLodge", "CisternsEntrance"]:
		var b := stand.get_node_or_null(n) if stand else null
		check(b != null and b.find_children("*", "CollisionShape3D", true, false).size() >= 6, "%s stands there, solid" % n)
	var npcs := zone.get_node("NPCs")
	var trainers := 0
	for c in npcs.get_children():
		if str(c.get("shop_id")).begins_with("trainer_"):
			trainers += 1
	check(trainers == 14, "all 14 class trainers are in Lumora (%d)" % trainers)
	check(npcs.has_node("HealerSolenne") and npcs.has_node("CommanderHalvar") and npcs.has_node("InnkeeperDalla") and npcs.has_node("TownCrier"), "the healer, the Commander, the innkeeper, the crier")
	var board := stand.get_node_or_null("NoticeBoard") if stand else null
	check(board != null and str(board.note_text).contains("courthouse"), "a notice board in Citadel Plaza")

	# the navmesh walks round the buildings, and still joins the gate to the plaza
	var region := zone.get_node("NavigationRegion3D") as NavigationRegion3D
	await frames(30)
	var map: RID = region.get_navigation_map()
	# into the Citadel from beside its east wall: round to the door, not through the wall (a straight line is 20 m)
	var into := NavigationServer3D.map_get_path(map, Vector3(20, 0, 158), Vector3(0, 0, 158), true)
	var walked := 0.0
	for i in range(1, into.size()):
		walked += into[i - 1].distance_to(into[i])
	check(into.size() >= 2 and walked > 28.0, "into the Citadel you go round by the door (%.0f m walked)" % walked)
	var path := NavigationServer3D.map_get_path(map, Vector3(0, 0, 420), Vector3(0, 0, 292), true)
	check(path.size() >= 2 and path[path.size() - 1].distance_to(Vector3(0, 0, 292)) < 3.0, "from the south gate to Citadel Plaza")

	# the healer
	var p = await make_player({"player_name": "Zozuur", "player_class": "Voidknight"})
	p.combat_node.current_hp = 5
	p.combat_node.apply_effect("disease", 60.0, {})
	var cured: int = npcs.get_node("HealerSolenne").heal_fully(p)
	check(p.combat_node.current_hp == p.combat_node.max_hp and cured >= 1 and not p.combat_node.active_effects.has("disease"), "the temple heals and cures")
	p.queue_free()
	zone.queue_free()
	await frames(2)

	var out := FileAccess.get_file_as_string("res://Scenes/lumora_outskirts3d.tscn")
	check(out.contains('[node name="RalphsLastRound" parent="StandIns"') and out.contains('npc_name = "Wenna Tuller"'), "Ralph's Last Round and Wenna at the Outskirts gate")
