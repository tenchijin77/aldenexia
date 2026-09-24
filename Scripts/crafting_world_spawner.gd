# crafting_world_spawner.gd — places a zone's town crafting stations and gathering nodes from
# Data/crafting_placements.json (keyed by zone_key), using the node types in Data/gathering_nodes.json. Scatter
# positions are random inside each cluster and change every in-game day; they're seeded from the entry and the day, so
# every client builds the same nodes in the same spots. Heights come
# from a ray dropped onto the ground once physics is running; a node never lands in a keep_clear area (the town) or
# on anything but open floor (walls, buildings, rocks) — those spots are re-rolled.
extends Node3D

const PLACEMENTS_PATH := "res://Data/crafting_placements.json"
const NODES_PATH := "res://Data/gathering_nodes.json"
const MODELS_PATH := "res://Data/crafting_models.json"  # which model each node / station uses
const RAY_TOP := 300.0
const RAY_BOTTOM := -100.0
const PLACE_ATTEMPTS := 12  # re-rolls for a node whose spot is in a keep_clear area or not on open ground

@export var zone_key: String = "lumora_outskirts"

var _placements: Dictionary = {}
var _clusters := {}        # placements "nodes" index -> [GatheringNode] of that cluster
var _layout_key := ""      # the in-game day the nodes are laid out for
var _day_check := 0.0


func _ready() -> void:
	# Wait for the zone's collision to exist before dropping rays onto it.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var placements: Dictionary = _load(PLACEMENTS_PATH).get(zone_key, {})
	var node_defs: Dictionary = _load(NODES_PATH).get("nodes", {})
	var models: Dictionary = _load(MODELS_PATH)
	# Stations placed by hand in the zone scene win: the data's stations are only used for a zone that has none.
	var scene_has_stations := not get_tree().get_nodes_in_group("crafting_station").is_empty()
	for entry in ([] if scene_has_stations else placements.get("stations", [])):
		var station := CraftingStation.new()
		var station_id := str(entry.get("station_id", ""))
		station.setup(station_id, str(entry.get("name", "Crafting Station")), models.get("stations", {}).get(station_id, {}))
		add_child(station)
		station.global_position = _ground(entry.get("position", [0, 0]))
	_placements = placements
	for i in range(placements.get("nodes", []).size()):
		var entry: Dictionary = placements["nodes"][i]
		var id: String = str(entry.get("node", ""))
		if not node_defs.has(id):
			push_warning("crafting_placements.json: unknown gathering node '%s'" % id)
			continue
		var cluster: Array = []
		for n in range(int(entry.get("count", 1))):
			var node := GatheringNode.new()
			node.setup(id, node_defs[id], models.get("nodes", {}).get(id, {}))
			add_child(node)
			cluster.append(node)
		_clusters[i] = cluster
	_layout_key = _day_key()
	var placed := _lay_out()
	print("✅ Crafting world: %d stations, %d gathering nodes in %s" % [placements.get("stations", []).size(), placed, zone_key])


# Every in-game day (24 real minutes) the gathering nodes move to new random spots inside their clusters. The layout is
# seeded by the day, so every player (the day comes from the server's clock) sees the same nodes in the same spots.
# A joining client builds the zone before the server's clock arrives, so a change of day key re-lays the nodes too.
func _process(delta: float) -> void:
	_day_check -= delta
	if _day_check > 0.0 or _clusters.is_empty():
		return
	_day_check = 2.0
	var key := _day_key()
	if key != _layout_key:
		_layout_key = key
		_lay_out()


func _day_key() -> String:
	var t: Dictionary = Global.game_time
	return "%d-%d-%d" % [int(t.get("year", 0)), int(t.get("month", 0)), int(t.get("day", 0))]


# Puts every node of every cluster at its spot for the current day. A node someone is gathering right now stays put until
# the next change. Returns how many nodes found a spot (a node with no open ground is hidden for the day).
func _lay_out() -> int:
	var placed := 0
	for i in _clusters:
		var entry: Dictionary = _placements["nodes"][i]
		var id: String = str(entry.get("node", ""))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s:%d:%s:%s" % [zone_key, i, id, _layout_key])
		var center: Array = entry.get("center", [0, 0])
		var radius: float = float(entry.get("radius", 10.0))
		for node in _clusters[i]:
			var spot := Vector3.INF
			for attempt in range(PLACE_ATTEMPTS):
				var angle := rng.randf() * TAU
				var dist := sqrt(rng.randf()) * radius
				var x := float(center[0]) + cos(angle) * dist
				var z := float(center[1]) + sin(angle) * dist
				if _in_keep_clear(x, z, _placements.get("keep_clear", [])):
					continue
				var hit := _ground_hit(x, z)
				if hit.is_empty() or _is_open_ground(hit):
					spot = hit["position"] if not hit.is_empty() else Vector3(x, 0.0, z)
					break
			var turn := rng.randf() * TAU
			if (node as GatheringNode).is_being_gathered():
				placed += 1
				continue
			if spot == Vector3.INF:
				push_warning("crafting_placements.json: no open ground for a %s near %s today — hidden" % [id, str(center)])
				node.visible = false
				continue
			node.visible = true
			node.global_position = spot
			node.rotation.y = turn
			placed += 1
	return placed


# The ground point under [x, z] (y = 0 if the ray finds nothing).
func _ground(xz: Array) -> Vector3:
	var hit := _ground_hit(float(xz[0]), float(xz[1]))
	return hit["position"] if not hit.is_empty() else Vector3(float(xz[0]), 0.0, float(xz[1]))


# The first thing a ray dropped straight down onto [x, z] hits ({} if nothing).
func _ground_hit(x: float, z: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, RAY_TOP, z), Vector3(x, RAY_BOTTOM, z))
	return Global.ground_ray(get_world_3d().direct_space_state, query)


# True when a downward ray landed on open ground rather than on a wall, building, rock or creature: a Terrain3D surface
# (the Terrain3D rebuild of the zone), or the old flat zone's floor — its collision is one StaticBody3D with a shape per
# model (Floor_shape, City Wall_shape, Vendor_shape, ...), and only the Floor shape counts.
func _is_open_ground(hit: Dictionary) -> bool:
	var body: Object = hit.get("collider")
	if body != null and body.is_class("Terrain3D"):
		return true
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
