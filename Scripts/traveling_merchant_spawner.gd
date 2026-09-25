# traveling_merchant_spawner.gd — brings Sahren into THIS zone when his timetable (merchant_schedule.gd) says he is here,
# and sends him on (packs him up) when it says he has moved on. Server only (single-player counts as the server); he is
# spawned through a MultiplayerSpawner, so every connected player gets the same replicated merchant.
#
# Every zone has one of these (the Outskirts, Dustwind...). Each works out from the shared clock where he is, so he is only
# ever in one zone: a zone whose server starts halfway through his visit brings him in where he should be by now (partway
# along the road, or at his stop with the rest of his stay left). Once he has walked out of a zone he isn't brought back
# until his next loop reaches it. Real-world time throughout (unix seconds), the same on every server of the machine.
extends Node3D

const MERCHANT_SCENE := "res://Scenes/traveling_merchant.tscn"
const CHECK_SECONDS := 2.0
const OVERSTAY_SECONDS := 180.0   # slower than the timetable (a long path)? he is given this long before being packed up

@onready var spawner: MultiplayerSpawner = $MerchantSpawner
@onready var container: Node3D = $Merchants

var _merchant: Node = null
var _next_id := 0
var _visited := ""     # "<loop>" of the visit already made here (he isn't brought back after walking out)
var _check := 0.0
## Tests set this to run the timetable at another moment (unix seconds); 0 = now.
var clock_override := 0.0


func _ready() -> void:
	spawner.spawn_function = _build_merchant  # on every peer: builds the same node from the same data


# Only the server (or a single-player game) decides; other peers just receive the spawned merchant.
func _is_decider() -> bool:
	return not Net.is_multiplayer_game or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _now() -> float:
	return clock_override if clock_override > 0.0 else Time.get_unix_time_from_system()


func _process(delta: float) -> void:
	if not _is_decider():
		return
	_check += delta
	if _check < CHECK_SECONDS:
		return
	_check = 0.0
	var zone := ZoneInfo.id_for(self)
	var w := MerchantSchedule.where(_now())
	if is_instance_valid(_merchant):
		# The timetable has moved him on (with some slack for a slow walk): he packs up where he is.
		if w.is_empty() or str(w["zone"]) != zone:
			var since := _now() - float(_merchant.get_meta("leg_end", 0.0))
			if since > OVERSTAY_SECONDS:
				_merchant.pack_up()
		return
	_merchant = null
	if w.is_empty() or str(w["zone"]) != zone or _visited == str(w["cycle"]):
		return
	start_visit(w)


# Brings him in where the timetable says he is (`w` from MerchantSchedule.where()); tests may pass their own.
func start_visit(w: Dictionary) -> bool:
	if is_instance_valid(_merchant) or w.is_empty():
		return false
	var leg: Dictionary = w["leg"]
	var stops: Array = []
	for stop in leg.get("stops", []):
		var at: Array = stop.get("at", [0, 0])
		stops.append({"pos": _ground(Vector3(float(at[0]), 0.0, float(at[1]))), "name": str(stop.get("name", "")),
				"stay": float(stop.get("stay_seconds", 300))})
	var ex: Array = leg.get("exit", [0, 0])
	var exit_marker := _marker(str(leg.get("exit_marker", "")))
	if exit_marker != null:   # the zone's own marker wins: move it in the editor and he follows
		ex = [exit_marker.global_position.x, exit_marker.global_position.z]
	# Timeline steps go walk, stay, walk, stay, ..., walk-to-exit: step 2k walks to stop k, step 2k+1 stays at stop k.
	var step := int(w["step"])
	var index := step / 2
	var stay_left := float(w["seconds_left_in_step"]) if step % 2 == 1 else -1.0
	var start: Vector3 = stops[index]["pos"] if stay_left >= 0.0 else _ground(w["position"])
	var enter_marker := _marker(str(leg.get("enter_marker", "")))
	if enter_marker != null and step == 0 and float(w["elapsed"]) < 30.0:
		start = _ground(enter_marker.global_position)   # just arriving: exactly at the zone's marker
	_next_id += 1
	_visited = str(w["cycle"])
	_merchant = spawner.spawn({
		"id": _next_id, "position": [start.x, start.y, start.z], "index": index, "stay_left": stay_left,
		"stops": stops.map(func(st): return [st["pos"].x, st["pos"].y, st["pos"].z, st["name"], st["stay"]]),
		"exit": [float(ex[0]), 0.0, float(ex[1])],
	})
	_merchant.set_meta("leg_end", MerchantSchedule.leg_start(leg, int(w["cycle"])) + MerchantSchedule.leg_seconds(leg, int(w["cycle"])))
	print("🛒 Sahren has come to %s (%s)." % [ZoneInfo.name_for(ZoneInfo.id_for(self)), "trading at " + str(stops[index]["name"]) if stay_left >= 0.0 else "on the road"])
	return true


func _marker(path: String) -> Node3D:
	if path.is_empty():
		return null
	var scene := owner if owner != null else get_parent()
	return scene.get_node_or_null(path) as Node3D


# A point on the walkable ground (the navmesh), or the point itself when there is none there.
func _ground(p: Vector3) -> Vector3:
	var map_rid: RID = get_world_3d().navigation_map
	var on_mesh := NavigationServer3D.map_get_closest_point(map_rid, p)
	return on_mesh if on_mesh != Vector3.ZERO or p.length() < 1.0 else p


func _build_merchant(data: Dictionary) -> Node:
	var merchant: TravelingMerchant = (load(MERCHANT_SCENE) as PackedScene).instantiate()
	merchant.name = "merchant_%d" % int(data.get("id", 0))
	var pos: Array = data.get("position", [0.0, 0.0, 0.0])
	merchant.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	for st in data.get("stops", []):
		merchant.route.append({"pos": Vector3(float(st[0]), float(st[1]), float(st[2])), "name": str(st[3]), "stay": float(st[4])})
	var ex: Array = data.get("exit", [0.0, 0.0, 0.0])
	merchant.route_exit = Vector3(float(ex[0]), float(ex[1]), float(ex[2]))
	merchant.route_index = int(data.get("index", 0))
	merchant.start_stay_left = float(data.get("stay_left", -1.0))
	merchant.set_multiplayer_authority(1)
	return merchant
