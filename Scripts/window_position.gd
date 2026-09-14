# window_position.gd — shared save/restore for a draggable window's position,
# keyed under Global.player_data["ui_positions"][key] as [left, top, right,
# bottom] (matching the format action_bar.gd/game_log_window.gd already used
# individually before this existed). Call save() from a panel's drag-end,
# call load_into() once in _ready() before the panel is first shown.
class_name WindowPosition
extends RefCounted


static func save(key: String, panel: Control) -> void:
	if Global.player_data.is_empty():
		return
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	ui[key] = [panel.offset_left, panel.offset_top, panel.offset_right, panel.offset_bottom]
	Global.player_data["ui_positions"] = ui
	Global.save_player_data_to_file()


# Only restores the top-left origin, leaving offset_right/offset_bottom (size)
# untouched — for windows whose size is fixed by their scene layout that's a
# no-op either way, and for ones that auto-resize to their own content (the
# loot window) it avoids fighting that with a stale saved size.
static func load_position_into(key: String, panel: Control) -> void:
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	var pos: Array = ui.get(key, [])
	if pos.size() != 4:
		return
	var width: float = panel.offset_right - panel.offset_left
	var height: float = panel.offset_bottom - panel.offset_top
	panel.offset_left = pos[0]
	panel.offset_top = pos[1]
	panel.offset_right = pos[0] + width
	panel.offset_bottom = pos[1] + height


# Restores the full saved rect, including size — for windows whose size is
# meant to be user-resizable and persisted as such (character sheet, backpack).
static func load_full_into(key: String, panel: Control) -> void:
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	var pos: Array = ui.get(key, [])
	if pos.size() != 4:
		return
	panel.offset_left = pos[0]
	panel.offset_top = pos[1]
	panel.offset_right = pos[2]
	panel.offset_bottom = pos[3]
