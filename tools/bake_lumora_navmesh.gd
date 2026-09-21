# bake_lumora_navmesh.gd
# Re-bakes the navmesh for the LumoraOutskirts zone from the zone's collision shapes and saves it to
# Data/lumora_outskirts_navmesh.tres (wired into the scene as an ExtResource). Run it after
# tools/regen_lumora_collision.gd (the bake reads the collision, so stale collision = stale navmesh);
# tools/regen_lumora_collision.sh does both.
#   godot --headless --path . --script res://tools/bake_lumora_navmesh.gd
# Takes about 6 seconds. The "Parameter material is null" errors it prints are headless debug-draw noise.
# (Cell size, agent size and the STATIC_COLLIDERS source type are the settings stored in the .tres itself.)
extends SceneTree

const SCENE_PATH := "res://Scenes/lumora_outskirts3d.tscn"
const NAVMESH_PATH := "res://Data/lumora_outskirts_navmesh.tres"
const TIMEOUT_MSEC := 120000


func _initialize() -> void:
	await process_frame
	var zone: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(zone)
	await create_timer(1.0).timeout
	var region := zone.get_node("NavigationRegion3D") as NavigationRegion3D
	print("Navmesh before: %d polygons" % region.navigation_mesh.get_polygon_count())
	# A dictionary, not a bool: a lambda captures plain variables by value, so it could never set a local flag.
	var state := {"done": false}
	region.bake_finished.connect(func(): state["done"] = true)
	var started := Time.get_ticks_msec()
	region.bake_navigation_mesh(true)
	while not state["done"] and Time.get_ticks_msec() - started < TIMEOUT_MSEC:
		await create_timer(0.25).timeout
	var baked := region.navigation_mesh
	if not state["done"] or baked.get_polygon_count() == 0:
		printerr("Navmesh bake did not finish (or came out empty) — nothing saved.")
		quit(1)
		return
	var err := ResourceSaver.save(baked, NAVMESH_PATH)
	print("Navmesh baked in %.1f s: %d vertices, %d polygons. Saved: %s" % [(Time.get_ticks_msec() - started) / 1000.0, baked.get_vertices().size(), baked.get_polygon_count(), str(err == OK)])
	quit(0 if err == OK else 1)
