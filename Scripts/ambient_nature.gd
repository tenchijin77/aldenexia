# ambient_nature.gd — the zone's background life: now and then (every GAP_MIN..GAP_MAX seconds) a burst of birdsong by
# day or crickets at night, CLIP_MIN..CLIP_MAX seconds long from a random part of the recording, faded in and out and
# coming from a random direction a little way off (Data/sounds.json "ambient_birds" / "ambient_crickets"). A constant
# loop all day or all night wore thin fast (test 23). Also the zone's sounds tied to places (Data/sounds.json
# "emitters": the town crowd, the forge's fire, the harbour bell now and then). Made at runtime by
# ambient_water_sound.gd (the zone's AmbientOcean node), so the zone scene needs no extra node. Nothing on a dedicated server.
extends Node

const GAP_MIN := 25.0
const GAP_MAX := 70.0
const CLIP_MIN := 8.0
const CLIP_MAX := 12.0
const DISTANCE_MIN := 10.0
const DISTANCE_MAX := 22.0

var _next := 0.0
var _timed: Array = []   # emitters with "every": [{"cfg": emitter, "in": seconds until the next}]


func _ready() -> void:
	_next = randf_range(5.0, 20.0)  # the first one soon after arriving
	_start_emitters.call_deferred()


# The zone's place-bound sounds: loops start now; "every" ones play at random intervals (_process).
func _start_emitters() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://Data/sounds.json"))
	var list: Variant = parsed.get("emitters", {}).get(scene.scene_file_path, []) if typeof(parsed) == TYPE_DICTIONARY else []
	for emitter in list:
		var pos: Array = emitter.get("position", [0, 0, 0])
		var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if emitter.has("every"):
			_timed.append({"cfg": emitter, "at": at, "in": randf_range(float(emitter["every"][0]), float(emitter["every"][1]))})
		else:
			Sfx.start_loop_at(str(emitter["sound"]), at, float(emitter.get("max_distance", 30.0)), float(emitter.get("unit_size", 8.0)))


func _process(delta: float) -> void:
	for timed in _timed:
		timed["in"] = float(timed["in"]) - delta
		if float(timed["in"]) <= 0.0:
			var cfg: Dictionary = timed["cfg"]
			timed["in"] = randf_range(float(cfg["every"][0]), float(cfg["every"][1]))
			var sound := Sfx.play(str(cfg["sound"]), timed["at"]) as AudioStreamPlayer3D
			if sound:
				sound.max_distance = float(cfg.get("max_distance", 40.0))
				sound.unit_size = float(cfg.get("unit_size", 8.0))
	_next -= delta
	if _next > 0.0:
		return
	_next = randf_range(GAP_MIN, GAP_MAX)
	var player := TargetFrame.local_player() as Node3D
	if not is_instance_valid(player):
		return
	var cycles := get_tree().get_nodes_in_group("day_night_cycle")
	var day: bool = cycles.is_empty() or not cycles[0].has_method("is_day") or cycles[0].is_day()
	var angle := randf() * TAU
	var spot := player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(DISTANCE_MIN, DISTANCE_MAX) + Vector3(0, 3.0, 0)
	Sfx.play_clip("ambient_birds" if day else "ambient_crickets", spot, randf_range(CLIP_MIN, CLIP_MAX))
