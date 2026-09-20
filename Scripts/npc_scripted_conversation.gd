# npc_scripted_conversation.gd — Reusable "two NPCs from a group have a short
# scripted back-and-forth" player. Companion to npc_flavor_text.gd: instead of
# one NPC saying one random line, this picks two distinct members of
# npc_group and plays out a random multi-line exchange between them (from a
# JSON file of {"category": [["line1", "line2", ...], ...], ...}), alternating
# speakers and pacing the lines with a short delay so it reads as dialogue
# instead of a wall of text. Put one of these per NPC group that should banter
# (e.g. the outskirts guards) and call play_conversation(category) from
# whatever triggers it (day/night transition, a scheduled idle timer, etc.).
# Each NPC just needs a say(line: String) method.
extends Node
class_name NPCScriptedConversation

@export var npc_group: String = "npc_guard"
@export var conversations_path: String = "res://Data/guard_conversations.json"
@export var line_delay: float = 2.2
@export var auto_play_on_day_night: bool = true  # play "day"/"night" categories off day_night_cycle.gd's phase_changed signal

var _conversations_by_category: Dictionary = {}


func _ready() -> void:
	var file := FileAccess.open(conversations_path, FileAccess.READ)
	if not file:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) == TYPE_DICTIONARY:
		_conversations_by_category = data

	if auto_play_on_day_night:
		var day_night_cycles := get_tree().get_nodes_in_group("day_night_cycle")
		if not day_night_cycles.is_empty():
			day_night_cycles[0].phase_changed.connect(_on_phase_changed)


func _on_phase_changed(is_day: bool) -> void:
	# The server hosts the exchange (its guards are the real ones) and relays each line.
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	play_conversation("day" if is_day else "night")


func play_conversation(category: String) -> void:
	var exchanges: Array = _conversations_by_category.get(category, [])
	if exchanges.is_empty():
		return
	var speakers: Array = get_tree().get_nodes_in_group(npc_group)
	if speakers.is_empty():
		return
	speakers.shuffle()
	var lines: Array = exchanges[randi() % exchanges.size()]
	_play_lines(lines, speakers)


func _play_lines(lines: Array, speakers: Array) -> void:
	for i in lines.size():
		if i > 0:
			await get_tree().create_timer(line_delay).timeout
		var speaker: Node = speakers[i % speakers.size()]
		if is_instance_valid(speaker) and speaker.has_method("say_to_all"):
			speaker.say_to_all(lines[i])
		elif is_instance_valid(speaker) and speaker.has_method("say"):
			speaker.say(lines[i])
