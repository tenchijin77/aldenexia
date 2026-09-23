# ambient_water_sound.gd — Ocean waves that swell as the local player nears the sea. The distance is measured to the zone's
# water itself (the mesh named "Water" in the zone model), so it works at the docks, along the coast road and up by the cliffs
# without listing places by hand, and follows the water if the map changes. Plays on the "SFX" bus (so the options-menu
# effects volume applies), fades in and out smoothly, and stops playing entirely when you are far from the shore.
# Not created on a dedicated server (no one to hear it).
extends Node

@export var stream: AudioStream
## Within this distance (metres) of the water the waves are at full volume.
@export var full_volume_distance: float = 45.0
## Beyond this distance the waves are silent.
@export var silent_distance: float = 300.0
## Volume at the shore, in dB (the wind loop in the zone is -10).
@export var loudest_db: float = -5.0
## How fast the volume follows changes, in dB per second (so walking away fades rather than cuts).
@export var fade_db_per_second: float = 24.0

const SILENT_DB := -60.0
const MIN_SEA_AREA := 400.0  # m²: a water mesh smaller than this (20 m x 20 m) is part of a model, not the sea

var _sound: AudioStreamPlayer
var _water_rects: Array = []   # Rect2 in the ground plane (x, z) for each water mesh
var _looked_for_water := false
var _current_db := -80.0
var _check_timer := 0.0
var _target_db := -80.0


func _ready() -> void:
	if stream == null or Net.is_dedicated_server:
		set_process(false)
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true  # the import setting is off
	_sound = AudioStreamPlayer.new()
	_sound.name = "OceanLoop"
	_sound.stream = stream
	_sound.bus = &"SFX"
	_sound.volume_db = -80.0
	add_child(_sound)


func _process(delta: float) -> void:
	if not _looked_for_water:
		_find_water()
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.2
		_target_db = _db_for(_distance_to_water())
	_current_db = move_toward(_current_db, _target_db, fade_db_per_second * delta)
	_sound.volume_db = _current_db
	if _current_db > SILENT_DB and not _sound.playing:
		_sound.play(randf() * maxf(stream.get_length() - 1.0, 0.0))  # start somewhere in the loop so every visit is not identical
	elif _current_db <= SILENT_DB and _sound.playing:
		_sound.stop()


func _find_water() -> void:
	_looked_for_water = true
	var scene := get_tree().current_scene
	if scene == null:
		return
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		if String(node.name).to_lower().contains("water"):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var box: AABB = mi.global_transform * mi.get_aabb()
			if box.size.x * box.size.z < MIN_SEA_AREA:
				continue  # a prop's water (the forge's quench trough, a bucket), not the sea
			_water_rects.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))


# Ground-plane distance from the local player to the nearest water (INF when there is none / no player yet).
func _distance_to_water() -> float:
	var player := TargetFrame.local_player()
	if not is_instance_valid(player) or _water_rects.is_empty():
		return INF
	var p := Vector2(player.global_position.x, player.global_position.z)
	var best := INF
	for rect in _water_rects:
		var r: Rect2 = rect
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
		best = minf(best, sqrt(dx * dx + dy * dy))
	return best


func _db_for(distance: float) -> float:
	if distance >= silent_distance:
		return -80.0
	var t := clampf((silent_distance - distance) / maxf(silent_distance - full_volume_distance, 1.0), 0.0, 1.0)
	return loudest_db + linear_to_db(t * t)  # squared: a gentle swell rather than a straight line in loudness
