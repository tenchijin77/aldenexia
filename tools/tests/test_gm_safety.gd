# Test 34.5: walking off Dustwind's edge fell forever. Zone edges are walled, a fall out of the world is rescued, and game
# masters have /kill, /give and /teleport.
extends "res://tools/tests/test_base.gd"

const GM := preload("res://Scripts/gm_commands.gd")


func run() -> void:
	# Invisible walls round Dustwind's terrain
	var zone = load("res://Scenes/zones/dustwind_plateaus.tscn").instantiate()
	add_child(zone)
	await frames(4)
	var boundary = zone.get_node("ZoneBoundary")
	eq(boundary.get_child_count(), 4, "four edge walls")
	eq(boundary.bounds, Rect2(-512, -512, 1024, 1024), "round the whole terrain")
	var line = zone.get_node("ZoneLines/To Lumora Outskirts")
	check(line.size.x >= 1024.0, "Dustwind's line back covers the whole north edge")
	check(line.covers(Vector3(46, 1, -505)) and line.covers(Vector3(-500, 1, -505)), "including where Tenchijin walked past it (x 46)")
	zone.queue_free()
	await frames(2)

	# Falling out of the world puts you back on the ground
	make_floor(100.0)
	var p = await make_player()
	p.global_position = Vector3(10, -400, 10)
	await get_tree().create_timer(0.5).timeout
	check(p.global_position.y > -10.0, "rescued from the void (y %.1f)" % p.global_position.y)

	# /give: names, starts of names, counts
	eq(GM.find_item("tin shi"), ["tin_shield"], "/give tin shi = the Tin Shield")
	eq(GM.find_item("tin sh").size(), 2, "tin sh could be the shield or the shortsword: both are listed")
	eq(GM.find_item("A Small Bag"), ["small_bag"], "a name with its article")
	eq(GM.find_item("dagger"), ["dagger"], "an exact name wins over longer ones")
	check(GM.find_item("zzzz").is_empty(), "nothing called that")
	Inventory.reset_for_new_character()
	var reply := GM.run(p, "give", "iron rations 5", get_tree(), true)
	check(reply.contains("Given"), "give answers: %s" % reply)
	var rations := 0
	for slot in Inventory.basic_inventory:
		if slot != null and str(slot.get("item_id", "")) == "iron_rations":
			rations += int(slot.get("quantity", 1))
	eq(rations, 5, "5 iron rations arrived")
	check(GM.run(p, "give", "dagger", get_tree(), false) == GM.DENIED, "only a game master may /give")

	# /kill: a monster (no experience) and yourself
	var rat = load("res://Scenes/monster_template.tscn").instantiate()
	rat.monster_name = "rat"
	add_child(rat)
	rat.global_position = Vector3(3, 1, 3)
	await frames(3)
	var xp_before := int(Global.player_data.get("xp", 0))
	GM.run(p, "kill", TargetFrame.target_key_of(rat), get_tree(), true)
	eq(rat.current_state, rat.State.DEAD, "/kill on a monster kills it")
	eq(int(Global.player_data.get("xp", 0)), xp_before, "no experience for a GM kill")
	GM.run(p, "kill", TargetFrame.target_key_of(p), get_tree(), true)
	check(p.dying, "/kill me")
	check(GM.run(p, "kill", "m:nobody", get_tree(), true).contains("Target something"), "nothing to kill")
