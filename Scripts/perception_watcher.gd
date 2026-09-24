# perception_watcher.gd — D&D-style Perception (Data/perception_spots.json). A child node "Perception" of every player
# (player3d.gd _ready()) that only acts for the local player. Once a second: for every spot you are standing in, the next
# notice you haven't seen rolls d20 + Wisdom modifier + Perception skill / 10 against its DC. A success prints it in the
# chat and is remembered for this character (Global.player_data["perception_noticed"]); a failure may be tried again after
# retry_seconds. Every roll trains Perception, so the more you look, the more you see.
extends Node
class_name PerceptionWatcher

const SPOTS_PATH := "res://Data/perception_spots.json"
const ZONE_KEY := "lumora_outskirts"
const SAVE_KEY := "perception_noticed"
const CHECK_SECONDS := 1.0
const COLOUR := "#a8d8c0"

static var _data: Dictionary = {}

var _timer := 0.0
var _retry_at := {}   # "spot:index" -> Time.get_ticks_msec() when it may be rolled again


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SPOTS_PATH)) if FileAccess.file_exists(SPOTS_PATH) else null
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {"_": ""}
	return _data


static func noticed() -> Dictionary:
	if typeof(Global.player_data.get(SAVE_KEY)) != TYPE_DICTIONARY:
		Global.player_data[SAVE_KEY] = {}
	return Global.player_data[SAVE_KEY]


# d20 + Wisdom modifier + a tenth of the Perception skill (racial bonuses included) — the same bonus appraising uses.
static func bonus(player: Node) -> int:
	var wis := int(player.combat_node.wisdom) if player.combat_node else 10
	return int(floor((wis - 10) / 2.0)) + int(player.effective_skill("perception")) / 10


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_SECONDS:
		return
	_timer = 0.0
	var player := get_parent()
	if player != TargetFrame.local_player() or player.get("dying"):
		return
	for spot in data().get(ZONE_KEY, []):
		var p: Array = spot.get("position", [0, 0])
		var flat := Vector2(player.global_position.x - float(p[0]), player.global_position.z - float(p[1]))
		if flat.length() > float(spot.get("radius", 10.0)):
			continue
		if _roll_next(player, spot):
			return   # at most one new notice a second, so arriving somewhere doesn't flood the chat


# Rolls the easiest notice at this spot that hasn't been seen and isn't waiting to be retried. True if one was noticed.
func _roll_next(player: Node, spot: Dictionary) -> bool:
	var notices: Array = spot.get("notices", [])
	var is_night := NPCConversation.is_night(get_tree())
	for i in range(notices.size()):
		var key := "%s:%d" % [spot.get("id", ""), i]
		var notice: Dictionary = notices[i]
		if noticed().has(key) or Time.get_ticks_msec() < int(_retry_at.get(key, 0)):
			continue
		if notice.has("night") and bool(notice["night"]) != is_night:
			continue
		var roll := randi_range(1, 20)
		var total := roll + bonus(player)
		if player.has_method("_tick_skill"):
			player._tick_skill("perception", 0.5)
		if total >= int(notice.get("dc", 10)):
			noticed()[key] = true
			Global.save_player_data_to_file()
			GameLog.log_general("[color=%s][i]You notice something.[/i] %s[/color]" % [COLOUR, notice.get("text", "")])
			return true
		_retry_at[key] = Time.get_ticks_msec() + int(float(data().get("retry_seconds", 300)) * 1000.0)
		return false   # one roll per spot per check
	return false
