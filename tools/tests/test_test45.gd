# Test 45 (Leeia, Jaessa; build 83a5623). Stealth [Name] / invisible (Name), appraisal sight and moving at 70% in Stealth
# are in test_test44.gd; the NPCs facing out from their doors in test_lumora_standins.gd.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	# "there are two buildings in lumora to the east that i can't get to... there is an invisible wall": every stand-in
	# building stands inside the zone's walls (the terrain's edge)
	var zone: Node = load("res://Scenes/zones/lumora.tscn").instantiate()
	add_child(zone)
	await frames(4)
	var bounds: Rect2 = zone.get_node("ZoneBoundary").bounds
	check(bounds.size.x > 100.0, "Lumora is walled (%s)" % bounds)
	for building in zone.get_node("StandIns").get_children():
		if not (building is Node3D):
			continue
		var at: Vector3 = (building as Node3D).global_position
		check(bounds.grow(-5.0).has_point(Vector2(at.x, at.z)), "%s is inside the walls (%.0f, %.0f)" % [building.name, at.x, at.z])

	# "the notice board is using the note model from the wagon quest. medieval signpost would be better"
	var board: Node = zone.get_node("StandIns/NoticeBoard")
	check(board.get("show_paper") == false, "the notice board isn't a scrap of paper")
	check(board.has_node("Signpost") and board.get_node("Signpost").scene_file_path.ends_with("medieval_signpost.tscn"), "it's the medieval signpost")
	zone.queue_free()
	await frames(2)

	# "old foundation stone model is in the models folder": the Guildmaster's Note cache uses it
	var stone := WorldNote.new()
	stone.show_stone = true
	add_child(stone)
	await frames(1)
	check(stone.has_node("Stone") and stone.get_node("Stone").scene_file_path.ends_with("old_foundation_stone.tscn"), "the foundation stone is the model, not a box")
	stone.queue_free()
