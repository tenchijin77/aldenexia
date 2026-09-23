# ambient_nature.gd — the zone's background life: birds while it's day, crickets at night (Data/sounds.json
# "ambient_birds" / "ambient_crickets", faded across at dawn and dusk). Made at runtime by ambient_water_sound.gd (the
# zone's AmbientOcean node), so the zone scene needs no extra node. Nothing on a dedicated server.
extends Node

var _loop: Node = null
var _playing := ""
var _check := 0.0


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 2.0
	var cycles := get_tree().get_nodes_in_group("day_night_cycle")
	var day: bool = cycles.is_empty() or not cycles[0].has_method("is_day") or cycles[0].is_day()
	var want := "ambient_birds" if day else "ambient_crickets"
	if want != _playing:
		Sfx.stop(_loop)
		_loop = Sfx.start_loop(want, self)
		_playing = want
