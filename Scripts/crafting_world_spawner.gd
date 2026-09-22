# crafting_world_spawner.gd — places a zone's town crafting stations and gathering nodes from
# Data/crafting_placements.json (keyed by zone_key), using the node types in Data/gathering_nodes.json. Scatter
# positions are seeded from the entry itself, so every client builds the same nodes in the same spots. Heights come
# from a ray dropped onto the ground once physics is running.
extends Node3D

const PLACEMENTS_PATH := "res://Data/crafting_placements.json"
const NODES_PATH := "res://Data/gathering_nodes.json"
const RAY_TOP := 300.0
const RAY_BOTTOM := -100.0

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
			var angle := rng.randf() * TAU
			var dist := sqrt(rng.randf()) * radius
			var node := GatheringNode.new()
			node.setup(id, node_defs[id])
			add_child(node)
			node.global_position = _ground([float(center[0]) + cos(angle) * dist, float(center[1]) + sin(angle) * dist])
			node.rotation.y = rng.randf() * TAU
			placed += 1
	print("✅ Crafting world: %d stations, %d gathering nodes in %s" % [placements.get("stations", []).size(), placed, zone_key])


# The ground point under [x, z] (y = 0 if the ray finds nothing).
func _ground(xz: Array) -> Vector3:
	var x := float(xz[0])
	var z := float(xz[1])
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, RAY_TOP, z), Vector3(x, RAY_BOTTOM, z))
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else Vector3(x, 0.0, z)


func _load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
