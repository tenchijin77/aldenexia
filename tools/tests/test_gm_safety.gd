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

	# The Outskirts' north: the land past the mountains is cut away (terrain holes) and walled at x 133
	var outskirts = load("res://Scenes/lumora_outskirts3d.tscn").instantiate()
	add_child(outskirts)
	await frames(6)
	var ob = outskirts.get_node("ZoneBoundary")
	eq(ob.bounds.end.x, 133.0, "the Outskirts' north wall at x 133")
	var t = outskirts.get_node("Terrain3D")
	check(t.data.get_control_hole(Vector3(150, 0, 45)), "north of the ridge is cut away")
	check(not t.data.get_control_hole(Vector3(100, 0, 45)), "the town side is still there")
	check(t.data.get_height(Vector3(104, 0, 300)) > 5.0, "the ridge itself is untouched")
	var spawns: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/lumora_outskirts_spawns.json"))
	check(spawns["spawns"].all(func(sp): return float(sp["position"][0]) < 133.0), "no spawn point north of the wall")
	# The mausoleum (test 33 / 35): in and out through its door, and its walls solid from both sides
	await frames(10)   # building collision is made a moment after the zone loads
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	add_child(body)
	eq(snappedf((await _walk(body, Vector3(20, 0.2, -244.8), Vector3.RIGHT, 3.0)).x, 1.0), 38.0, "walk in through the mausoleum door")
	eq(snappedf((await _walk(body, Vector3(45, 0.2, -244.8), Vector3.LEFT, 3.0)).x, 1.0), 27.0, "and back out")
	check((await _walk(body, Vector3(73, 0.2, -244.8), Vector3.LEFT, 2.0)).x > 69.0, "its back wall is solid from outside")
	check((await _walk(body, Vector3(60, 0.2, -244.8), Vector3.RIGHT, 2.0)).x < 70.0, "and from inside")
	check((await _walk(body, Vector3(40, 0.2, -230.0), Vector3.LEFT, 2.0)).x > 29.0, "the front wall beside the door holds you inside")
	body.queue_free()
	outskirts.queue_free()
	await frames(2)

	# Smooth shading for the Meshy character models (test 35: faceted faces)
	var model: Node = load("res://models/Half-Elf Female/Meshy_AI_female_half_elf_hero__biped_Character_output.fbx").instantiate()
	var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var sm: ArrayMesh = MeshSmoothing.smoothed(mi.mesh)
	check(_flat_share(sm) < 0.05 and _flat_share(mi.mesh) > 0.2, "faceted triangles %.0f%% -> %.0f%%" % [_flat_share(mi.mesh) * 100.0, _flat_share(sm) * 100.0])
	var before: Array = mi.mesh.surface_get_arrays(0)
	var after: Array = sm.surface_get_arrays(0)
	eq(after[Mesh.ARRAY_VERTEX].size(), before[Mesh.ARRAY_VERTEX].size(), "same vertices")
	eq(after[Mesh.ARRAY_BONES], before[Mesh.ARRAY_BONES], "skinning kept (bones)")
	eq(after[Mesh.ARRAY_WEIGHTS], before[Mesh.ARRAY_WEIGHTS], "skinning kept (weights)")
	eq(after[Mesh.ARRAY_TEX_UV], before[Mesh.ARRAY_TEX_UV], "UVs kept")
	check(MeshSmoothing.smoothed(mi.mesh) == sm, "smoothed once per model (cached)")
	model.free()

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


# Share of triangles whose three vertex normals all equal the face normal (flat shading).
func _flat_share(mesh: Mesh) -> float:
	var a := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var flat := 0
	var count := 0
	for t in mini(idx.size() / 3, 3000):
		var f := (v[idx[t * 3 + 1]] - v[idx[t * 3]]).cross(v[idx[t * 3 + 2]] - v[idx[t * 3]]).normalized()
		if f.length() < 0.5:
			continue
		count += 1
		if absf(n[idx[t * 3]].dot(f)) > 0.999 and absf(n[idx[t * 3 + 1]].dot(f)) > 0.999 and absf(n[idx[t * 3 + 2]].dot(f)) > 0.999:
			flat += 1
	return float(flat) / maxf(1.0, count)


func _walk(body: CharacterBody3D, from: Vector3, dir: Vector3, seconds: float) -> Vector3:
	body.global_position = from
	body.velocity = Vector3.ZERO
	for i in int(seconds * 60):
		body.velocity = Vector3(dir.x * 6.0, body.velocity.y - 9.8 / 60.0, dir.z * 6.0)
		body.move_and_slide()
		await get_tree().physics_frame
	return body.global_position

