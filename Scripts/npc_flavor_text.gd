# npc_flavor_text.gd — Reusable random-line picker for NPC chatter, loaded from
# a JSON file of {"category": ["line", ...], ...} (e.g. Data/guard_flavor_text.json).
# Any NPC script can own one of these per its own flavor-text file and pull
# random lines by category ("hail", "engage", "day", "night", or whatever
# categories that NPC's file defines) instead of hand-rolling its own JSON
# loading/random-pick logic.
class_name NPCFlavorText
extends RefCounted

var _lines_by_category: Dictionary = {}


func _init(json_path: String) -> void:
	var file := FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) == TYPE_DICTIONARY:
		_lines_by_category = data


func get_line(category: String) -> String:
	var lines: Array = _lines_by_category.get(category, [])
	if lines.is_empty():
		return ""
	return lines[randi() % lines.size()]
