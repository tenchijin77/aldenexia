# traveling_merchant_spawner.gd — Decides WHEN the traveling merchant comes to the zone and brings him in. Server only
# (single-player counts as the server); the merchant is spawned through a MultiplayerSpawner, so every connected player
# gets the same replicated merchant and one who joins mid-visit sees him too — same pattern as mob_spawner3d.gd.
#
# Random, not a schedule: after the server starts he first appears after a random number of minutes, and after each visit
# he stays away for another random number of minutes (Data/traveling_merchant.json). Only one exists at a time. The visit
# itself (walk to the dock, trade, walk to the gate, trade, leave) is traveling_merchant.gd.
# Real-world time throughout (Time.get_ticks_msec), so engine time scale or a slow frame never stretches a visit.
extends Node3D

const CONFIG_PATH := "res://Data/traveling_merchant.json"
const MERCHANT_SCENE := "res://Scenes/traveling_merchant.tscn"

@onready var spawner: MultiplayerSpawner = $MerchantSpawner
@onready var container: Node3D = $Merchants

var _config: Dictionary = {}
var _next_visit_msec := 0
var _merchant: Node = null
var _next_id := 0


func _ready() -> void:
	spawner.spawn_function = _build_merchant  # on every peer: builds the same node from the same data
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
	_config = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	if _is_decider():
		_schedule_next(true)


# Only the server (or a single-player game) decides; other peers just receive the spawned merchant.
func _is_decider() -> bool:
	return not Net.is_multiplayer_game or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _process(_delta: float) -> void:
	if not _is_decider() or is_instance_valid(_merchant):
		return
	if _merchant != null:  # he has just left: plan the next visit
		_merchant = null
		_schedule_next(false)
	if Time.get_ticks_msec() >= _next_visit_msec:
		start_visit()


func _schedule_next(first: bool) -> void:
	var range_minutes: Array = _config.get("first_visit_delay_minutes" if first else "visit_gap_minutes", [20, 50])
	var minutes := randf_range(float(range_minutes[0]), float(range_minutes[1]))
	_next_visit_msec = Time.get_ticks_msec() + int(minutes * 60000.0)
	print("🛒 Traveling merchant: next visit in %.1f minutes." % minutes)


# Brings him in now (also handy for testing). Does nothing if he is already here or a marker is missing.
func start_visit() -> bool:
	if is_instance_valid(_merchant):
		return false
	var markers: Dictionary = _config.get("markers", {})
	var spawn_marker := get_parent().get_node_or_null(str(markers.get("spawn", ""))) as Node3D
	var dock_marker := get_parent().get_node_or_null(str(markers.get("dock", ""))) as Node3D
	var gate_marker := get_parent().get_node_or_null(str(markers.get("gate", ""))) as Node3D
	if spawn_marker == null or dock_marker == null or gate_marker == null:
		push_warning("Traveling merchant: a marker from %s is missing in the zone — no visit." % CONFIG_PATH)
		_schedule_next(false)
		return false
	var map_rid: RID = get_world_3d().navigation_map
	var start := NavigationServer3D.map_get_closest_point(map_rid, spawn_marker.global_position)
	_next_id += 1
	_merchant = spawner.spawn({
		"id": _next_id,
		"position": [start.x, start.y, start.z],
		"dock": [dock_marker.global_position.x, dock_marker.global_position.y, dock_marker.global_position.z],
		"gate": [gate_marker.global_position.x, gate_marker.global_position.y, gate_marker.global_position.z],
	})
	print("🛒 Traveling merchant has come to the zone.")
	return true


func _build_merchant(data: Dictionary) -> Node:
	var merchant: TravelingMerchant = (load(MERCHANT_SCENE) as PackedScene).instantiate()
	merchant.name = "merchant_%d" % int(data.get("id", 0))
	var pos: Array = data.get("position", [0.0, 0.0, 0.0])
	merchant.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var dock: Array = data.get("dock", [0.0, 0.0, 0.0])
	var gate: Array = data.get("gate", [0.0, 0.0, 0.0])
	merchant.route_dock = Vector3(float(dock[0]), float(dock[1]), float(dock[2]))
	merchant.route_gate = Vector3(float(gate[0]), float(gate[1]), float(gate[2]))
	merchant.set_multiplayer_authority(1)
	return merchant
