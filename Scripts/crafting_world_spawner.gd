# crafting_world_spawner.gd — places a zone's town crafting stations and gathering nodes from
# Data/crafting_placements.json (keyed by zone_key), using the node types in Data/gathering_nodes.json. Scatter
# positions are seeded from the entry itself, so every client builds the same nodes in the same spots. Heights come
# from a ray dropped onto the ground once physics is running; a node never lands in a keep_clear area (the town) or
# on anything but open floor (walls, buildings, rocks) — those spots are re-rolled.
extends Node3D

const PLACEMENTS_PATH := "res://Data/crafting_placements.json"
const NODES_PATH := "res://Data/gathering_nodes.json"
const RAY_TOP := 300.0
const RAY_BOTTOM := -100.0
const PLACE_ATTEMPTS := 12  # re-rolls for a node whose spot is in a keep_clear area or not on open ground

@export var zone_key: String = "lumora_outskirts"


func _ready() -> void:
	# Wait for the zone's collision to exist before dropping rays onto it.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var placements: Dictionary = _load(PLACEMENTS_PATH).get(zone_key, {})
	var node_defs: Dictionary = _load(NODES_PATH).get("nodes", {})
	for entry in placements.get("stations", []):
		var station := CraftingStation.new()
		station.setup(str(entry.get("station_id", "")), str(entry.get("name", "Crafting Station")))
		add_child(station)
		station.global_position = _ground(entry.get("position", [0, 0]))
	var placed := 0
	for i in range(placements.get("nodes", []).size()):
		var entry: Dictionary = placements["nodes"][i]
		var id: String = str(entry.get("node", ""))
		if not node_defs.has(id):
			push_warning("crafting_placements.json: unknown gathering node '%s'" % id)
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s:%d:%s" % [zone_key, i, id])
		var center: Array = entry.get("center", [0, 0])
		var radius: float = float(entry.get("radius", 10.0))
		for n in range(int(entry.get("count", 1))):
			var spot := Vector3.INF
			for attempt in range(PLACE_ATTEMPTS):
				var angle := rng.randf() * TAU
				var dist := sqrt(rng.randf()) * radius
				var x := float(center[0]) + cos(angle) * dist
				var z := float(center[1]) + sin(angle) * dist
				if _in_keep_clear(x, z, placements.get("keep_clear", [])):
					continue
				var hit := _ground_hit(x, z)
				if hit.is_empty() or _is_open_ground(hit):
					spot = hit["position"] if not hit.is_empty() else Vector3(x, 0.0, z)
					break
			if spot == Vector3.INF:
				push_warning("crafting_placements.json: no open ground for a %s near %s — skipped" % [id, str(center)])
				continue
			var node := GatheringNode.new()
			node.setup(id, node_defs[id])
			add_child(node)
			node.global_position = spot
			node.rotation.y = rng.randf() * TAU
			placed += 1
	print("✅ Crafting world: %d stations, %d gathering nodes in %s" % [placements.get("stations", []).size(), placed, zone_key])


# The ground point under [x, z] (y = 0 if the ray finds nothing).
func _ground(xz: Array) -> Vector3:
	var hit := _ground_hit(float(xz[0]), float(xz[1]))
	return hit["position"] if not hit.is_empty() else Vector3(float(xz[0]), 0.0, float(xz[1]))


# The first thing a ray dropped straight down onto [x, z] hits ({} if nothing).
func _ground_hit(x: float, z: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, RAY_TOP, z), Vector3(x, RAY_BOTTOM, z))
	return get_world_3d().direct_space_state.intersect_ray(query)


# True when a downward ray landed on the zone's floor rather than on a wall, building, rock or creature. The zone's
# collision is one StaticBody3D with a shape per model (Floor_shape, City Wall_shape, Vendor_shape, ...).
func _is_open_ground(hit: Dictionary) -> bool:
	var body: Object = hit.get("collider")
	if not (body is CollisionObject3D):
		return false
	var owner_id: int = body.shape_find_owner(int(hit.get("shape", 0)))
	var shape_node: Object = body.shape_owner_get_owner(owner_id)
	return shape_node is Node and str(shape_node.name).begins_with("Floor")


# True inside any of the zone's keep_clear rectangles ({"min": [x, z], "max": [x, z]}).
func _in_keep_clear(x: float, z: float, rects: Array) -> bool:
	for r in rects:
		var lo: Array = r.get("min", [0, 0])
		var hi: Array = r.get("max", [0, 0])
		if x >= float(lo[0]) and x <= float(hi[0]) and z >= float(lo[1]) and z <= float(hi[1]):
			return true
	return false


func _load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
