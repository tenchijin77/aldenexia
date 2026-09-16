# game_log_window.gd — Tabbed General / Combat message log
extends CanvasLayer
class_name GameLogWindow

@onready var general_log: RichTextLabel = $Panel/VBox/Tabs/General/GeneralLog
@onready var combat_log:  RichTextLabel = $Panel/VBox/Tabs/Combat/CombatLog
@onready var combat_tab:  Control = $Panel/VBox/Tabs/Combat
@onready var tabs: TabContainer = $Panel/VBox/Tabs
@onready var chat_input:  LineEdit = $Panel/VBox/ChatInput
@onready var player := get_tree().get_nodes_in_group("player")[0]

const MAX_LINES  := 200
const DRAG_BAR_H := 22.0
const MIN_WIDTH  := 180.0
const MIN_HEIGHT := 80.0
const FONT_SIZES := [10, 11, 12, 13, 14, 16, 18]

var _autoattack_dot: Label
var _dot_tween:  Tween
var _dragging  := false
var _resizing  := false
var _font_size: int = 12
var _font_menu: PopupMenu

# Detached Combat window (Panel lives outside the main Tabs while detached)
var _combat_window: CanvasLayer = null
var _combat_window_panel: Panel = null
var _combat_detached := false
var _combat_window_dragging := false
var _combat_window_resizing := false


func _ready() -> void:
	GameLog.general_message.connect(_on_general)
	GameLog.combat_message.connect(_on_combat)
	GameLog.autoattack_changed.connect(_on_autoattack_changed)
	_append(general_log, "[color=#888888]— Welcome to Aldenexia —[/color]")
	_setup_font_menu()
	_setup_autoattack_dot()
	_setup_drag_bar()
	_setup_resize_handle()
	_setup_detach_button()
	tabs.focus_mode = Control.FOCUS_NONE
	general_log.focus_mode = Control.FOCUS_NONE
	combat_log.focus_mode  = Control.FOCUS_NONE
	# Up/Down aren't meaningful to a single-line field, so without this Godot's
	# default focus-traversal grabs them instead and hands focus off to some
	# other focusable control while the chat box is active.
	chat_input.focus_neighbor_top    = chat_input.get_path()
	chat_input.focus_neighbor_bottom = chat_input.get_path()
	chat_input.text_submitted.connect(_on_chat_input_submitted)
	chat_input.gui_input.connect(_on_chat_input_gui_input)
	set_process_unhandled_input(true)

	if Global.player_data.get("ui_positions", {}).get("chat_combat_detached", false):
		call_deferred("_detach_combat")


# ── Font size menu ────────────────────────────────────────────────────────────

func _setup_font_menu() -> void:
	_font_menu = PopupMenu.new()
	for i in FONT_SIZES.size():
		_font_menu.add_item("Font size %d" % FONT_SIZES[i], i)
	_font_menu.id_pressed.connect(_on_font_size_chosen)
	add_child(_font_menu)


func _on_font_size_chosen(id: int) -> void:
	for i in FONT_SIZES.size():
		_font_menu.set_item_checked(i, i == id)
	_font_size = FONT_SIZES[id]
	_apply_font_size()
	_save_position()


func _apply_font_size() -> void:
	general_log.add_theme_font_size_override("normal_font_size", _font_size)
	combat_log.add_theme_font_size_override("normal_font_size", _font_size)


# ── Drag bar (title + drag handle + right-click menu trigger) ─────────────────

func _setup_drag_bar() -> void:
	var bar := Label.new()
	bar.text = "Chat"
	bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	bar.add_theme_font_size_override("font_size", 10)
	bar.add_theme_color_override("font_color", Color(0.75, 0.70, 0.55))
	bar.anchor_right  = 1.0
	bar.anchor_bottom = 0.0
	bar.offset_top    = 0.0
	bar.offset_bottom = DRAG_BAR_H
	bar.mouse_filter  = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_drag_bar_input)
	$Panel.add_child(bar)
	$Panel/VBox.offset_top = DRAG_BAR_H
	_load_position()


func _on_drag_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if not _dragging:
				_save_position()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_font_menu(event.global_position)
	elif event is InputEventMouseMotion and _dragging:
		var panel: Panel = $Panel
		panel.offset_left   += event.relative.x
		panel.offset_top    += event.relative.y
		panel.offset_right  += event.relative.x
		panel.offset_bottom += event.relative.y


func _show_font_menu(at: Vector2) -> void:
	# Mark currently active size
	for i in FONT_SIZES.size():
		_font_menu.set_item_checked(i, FONT_SIZES[i] == _font_size)
	_font_menu.position = Vector2i(at)
	_font_menu.reset_size()
	_font_menu.popup()


# ── Resize handle (bottom-right corner) ──────────────────────────────────────

func _setup_resize_handle() -> void:
	var handle := Label.new()
	handle.text = "◢"
	handle.add_theme_font_size_override("font_size", 14)
	handle.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50, 0.70))
	handle.anchor_left   = 1.0
	handle.anchor_top    = 1.0
	handle.anchor_right  = 1.0
	handle.anchor_bottom = 1.0
	handle.offset_left   = -18.0
	handle.offset_top    = -18.0
	handle.offset_right  = 0.0
	handle.offset_bottom = 0.0
	handle.mouse_filter  = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	handle.gui_input.connect(_on_resize_input)
	$Panel.add_child(handle)


func _on_resize_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		if not _resizing:
			_save_position()
	elif event is InputEventMouseMotion and _resizing:
		var panel: Panel = $Panel
		var motion := event as InputEventMouseMotion
		var new_right:  float = panel.offset_right  + motion.relative.x
		var new_bottom: float = panel.offset_bottom + motion.relative.y
		if new_right - panel.offset_left >= MIN_WIDTH:
			panel.offset_right = new_right
		if new_bottom - panel.offset_top >= MIN_HEIGHT:
			panel.offset_bottom = new_bottom


# ── Detachable Combat window ──────────────────────────────────────────────────

func _setup_detach_button() -> void:
	var btn := Button.new()
	btn.text = "Detach"
	btn.tooltip_text = "Pop the Combat log out into its own window"
	btn.add_theme_font_size_override("font_size", 11)
	btn.anchor_left   = 1.0
	btn.anchor_right  = 1.0
	btn.offset_left   = -64.0
	btn.offset_top    = 3.0
	btn.offset_right  = -4.0
	btn.offset_bottom = 25.0
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_detach_combat)
	combat_tab.add_child(btn)


func _detach_combat() -> void:
	if _combat_detached:
		return
	_combat_detached = true

	tabs.remove_child(combat_tab)
	combat_log.reparent(_build_combat_window(), false)
	_load_combat_window_position()
	_save_position()


func _reattach_combat() -> void:
	if not _combat_detached:
		return
	_combat_detached = false

	combat_log.reparent(combat_tab, false)
	tabs.add_child(combat_tab)
	if is_instance_valid(_combat_window):
		_combat_window.queue_free()
	_combat_window = null
	_combat_window_panel = null
	_save_position()


func _build_combat_window() -> Control:
	var window := CanvasLayer.new()
	window.layer = 5
	# Persistent HUD, same as the main chat window it detached from — without
	# this, player3d.gd's Escape handler (which closes every CanvasLayer NOT
	# in this group) was treating the detached combat log as just another
	# modal window and closing it.
	window.add_to_group("game_hud")
	get_tree().root.add_child(window)
	_combat_window = window

	var panel := Panel.new()
	panel.offset_left   = 500.0
	panel.offset_top    = -210.0
	panel.offset_right  = 780.0
	panel.offset_bottom = -10.0
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	window.add_child(panel)
	_combat_window_panel = panel

	# Plain Control (not a container) so the reparented RichTextLabel's own
	# manual anchors (anchors_preset=15, full rect) behave exactly as they
	# did inside the original Tabs/Combat Control.
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left   = 4.0
	content.offset_top    = DRAG_BAR_H + 4.0
	content.offset_right  = -4.0
	content.offset_bottom = -4.0
	panel.add_child(content)

	var bar := Label.new()
	bar.text = "Combat"
	bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	bar.add_theme_font_size_override("font_size", 10)
	bar.add_theme_color_override("font_color", Color(0.75, 0.70, 0.55))
	bar.anchor_right  = 1.0
	bar.anchor_bottom = 0.0
	bar.offset_top    = 0.0
	bar.offset_bottom = DRAG_BAR_H
	bar.mouse_filter  = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_combat_window_drag_bar_input)
	panel.add_child(bar)

	var reattach_btn := Button.new()
	reattach_btn.text = "Reattach"
	reattach_btn.tooltip_text = "Reattach to the main log window"
	reattach_btn.add_theme_font_size_override("font_size", 10)
	reattach_btn.anchor_left   = 1.0
	reattach_btn.anchor_right  = 1.0
	reattach_btn.offset_left   = -68.0
	reattach_btn.offset_top    = 1.0
	reattach_btn.offset_right  = -2.0
	reattach_btn.offset_bottom = DRAG_BAR_H - 1.0
	reattach_btn.focus_mode = Control.FOCUS_NONE
	reattach_btn.pressed.connect(_reattach_combat)
	panel.add_child(reattach_btn)

	var handle := Label.new()
	handle.text = "◢"
	handle.add_theme_font_size_override("font_size", 14)
	handle.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50, 0.70))
	handle.anchor_left   = 1.0
	handle.anchor_top    = 1.0
	handle.anchor_right  = 1.0
	handle.anchor_bottom = 1.0
	handle.offset_left   = -18.0
	handle.offset_top    = -18.0
	handle.offset_right  = 0.0
	handle.offset_bottom = 0.0
	handle.mouse_filter  = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	handle.gui_input.connect(_on_combat_window_resize_input)
	panel.add_child(handle)

	combat_tab.focus_mode = Control.FOCUS_NONE
	return content


func _on_combat_window_drag_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_combat_window_dragging = event.pressed
			if not _combat_window_dragging:
				_save_position()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_font_menu(event.global_position)
	elif event is InputEventMouseMotion and _combat_window_dragging:
		_combat_window_panel.offset_left   += event.relative.x
		_combat_window_panel.offset_top    += event.relative.y
		_combat_window_panel.offset_right  += event.relative.x
		_combat_window_panel.offset_bottom += event.relative.y


func _on_combat_window_resize_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_combat_window_resizing = event.pressed
		if not _combat_window_resizing:
			_save_position()
	elif event is InputEventMouseMotion and _combat_window_resizing:
		var panel := _combat_window_panel
		var motion := event as InputEventMouseMotion
		var new_right:  float = panel.offset_right  + motion.relative.x
		var new_bottom: float = panel.offset_bottom + motion.relative.y
		if new_right - panel.offset_left >= MIN_WIDTH:
			panel.offset_right = new_right
		if new_bottom - panel.offset_top >= MIN_HEIGHT:
			panel.offset_bottom = new_bottom


func _load_combat_window_position() -> void:
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	var pos: Array = ui.get("chat_combat", [])
	if pos.size() == 4 and is_instance_valid(_combat_window_panel):
		_combat_window_panel.offset_left   = pos[0]
		_combat_window_panel.offset_top    = pos[1]
		_combat_window_panel.offset_right  = pos[2]
		_combat_window_panel.offset_bottom = pos[3]


# ── Persistence ───────────────────────────────────────────────────────────────

func _save_position() -> void:
	if Global.player_data.is_empty():
		return
	var p: Panel = $Panel
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	ui["chat"]           = [p.offset_left, p.offset_top, p.offset_right, p.offset_bottom]
	ui["chat_font_size"] = _font_size
	ui["chat_combat_detached"] = _combat_detached
	if _combat_detached and is_instance_valid(_combat_window_panel):
		var cp: Panel = _combat_window_panel
		ui["chat_combat"] = [cp.offset_left, cp.offset_top, cp.offset_right, cp.offset_bottom]
	Global.player_data["ui_positions"] = ui
	Global.save_player_data_to_file()


func _load_position() -> void:
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	var pos: Array = ui.get("chat", [])
	if pos.size() == 4:
		var p: Panel = $Panel
		p.offset_left   = pos[0]
		p.offset_top    = pos[1]
		p.offset_right  = pos[2]
		p.offset_bottom = pos[3]
	_font_size = ui.get("chat_font_size", 12)
	_apply_font_size()


# ── Autoattack indicator ──────────────────────────────────────────────────────

func _setup_autoattack_dot() -> void:
	_autoattack_dot = Label.new()
	_autoattack_dot.text = "⬤"
	_autoattack_dot.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1))
	_autoattack_dot.add_theme_font_size_override("font_size", 10)
	_autoattack_dot.anchor_left   = 1.0
	_autoattack_dot.anchor_top    = 0.0
	_autoattack_dot.anchor_right  = 1.0
	_autoattack_dot.anchor_bottom = 0.0
	_autoattack_dot.offset_left   = -22.0
	_autoattack_dot.offset_top    = 5.0
	_autoattack_dot.offset_right  = -6.0
	_autoattack_dot.offset_bottom = 20.0
	_autoattack_dot.visible = false
	$Panel.add_child(_autoattack_dot)


func _on_autoattack_changed(active: bool) -> void:
	if _dot_tween:
		_dot_tween.kill()
	_autoattack_dot.modulate.a = 1.0
	_autoattack_dot.visible = active
	if active:
		_dot_tween = create_tween().set_loops()
		_dot_tween.tween_property(_autoattack_dot, "modulate:a", 0.15, 0.45)
		_dot_tween.tween_property(_autoattack_dot, "modulate:a", 1.0,  0.45)


# ── Chat input ────────────────────────────────────────────────────────────────

# Enter opens the chat box for typing when nothing else has focus. If chat_input
# (or any other Control) is already focused, it consumes Enter itself during
# GUI input processing, so this never even sees the event in that case.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		chat_input.grab_focus()
		get_viewport().set_input_as_handled()


func _on_chat_input_submitted(text: String) -> void:
	chat_input.text = ""
	# Sending a message (or just pressing Enter on an empty box) hands focus
	# back to the game — otherwise the player stays locked out of movement
	# (see player3d.gd's chat_focused check) until they click the box again.
	chat_input.release_focus()
	text = text.strip_edges()
	if text == "":
		return
	if text.begins_with("/"):
		_handle_slash_command(text)
	else:
		GameLog.log_general("[color=yellow]You say, '%s'[/color]" % text)


# Lets Escape back out of an accidental click into the chat box without
# sending anything — same "give movement back" reasoning as submitting.
func _on_chat_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		chat_input.text = ""
		chat_input.release_focus()


# Canonical / commands. Typing any unambiguous prefix of one of these works
# too (Linux-style abbreviation) — see _resolve_command() below. e.g. "/loc"
# and "/location" both resolve to "/location" since no other command starts
# with "loc"; "/f" would be ambiguous if two commands both started with "f".
const COMMANDS := ["/location", "/hail", "/appraise", "/time", "/follow", "/camp", "/exit", "/log", "/invite", "/disband", "/tell", "/party"]


func _handle_slash_command(text: String) -> void:
	var parts := text.split(" ", false)
	var typed_cmd := parts[0].to_lower()
	var arg := text.substr(parts[0].length()).strip_edges()

	var cmd := _resolve_command(typed_cmd)
	if cmd.is_empty():
		return  # _resolve_command already logged unknown/ambiguous

	match cmd:
		"/location":
			var pos: Vector3 = player.global_position
			GameLog.log_general("[color=green]Your location: X=%.2f Y=%.2f Z=%.2f[/color]" % [pos.x, pos.y, pos.z])
		"/hail":
			player.try_hail_nearby_npc()
		"/appraise":
			player.try_appraise_target()
		"/follow":
			player.try_follow(arg)
		"/camp":
			_start_camp_sequence()
		"/exit":
			_save_and_quit()
		"/log":
			_toggle_file_logging()
		"/invite":
			if arg.is_empty():
				player.invite_to_group(player.current_target)
			else:
				player.invite_to_group_by_name(arg)
		"/disband":
			if arg.is_empty():
				player.disband_or_kick_from_group(player.current_target)
			else:
				player.disband_from_group_by_name(arg)
		"/tell":
			var tell_parts := arg.split(" ", false, 1)
			if tell_parts.size() < 2:
				GameLog.log_general("[color=red]Usage: /tell <name> <message>[/color]")
			else:
				player.send_tell(tell_parts[0], tell_parts[1])
		"/party":
			if arg.is_empty():
				GameLog.log_general("[color=red]Usage: /party <message>[/color]")
			else:
				player.send_party_message(arg)
		"/time":
			GameLog.log_general("[color=green]%s[/color]" % Global.format_full_date())
			var day_night_nodes := get_tree().get_nodes_in_group("day_night_cycle")
			var day_night = day_night_nodes[0] if day_night_nodes.size() > 0 else null
			if day_night:
				var next_label := "sunset" if day_night.is_day() else "sunrise"
				var remaining := int(day_night.seconds_until_next_phase())
				GameLog.log_general("[color=green]Sky: %s (%s in %dm %ds)[/color]" % [
					"Daytime" if day_night.is_day() else "Nighttime", next_label, remaining / 60, remaining % 60])
			var d := Time.get_datetime_dict_from_system(false)
			var hour12: int = d.hour % 12
			if hour12 == 0:
				hour12 = 12
			var ampm := "AM" if d.hour < 12 else "PM"
			GameLog.log_general("[color=green]Real time: %d:%02d %s[/color]" % [hour12, d.minute, ampm])


# 15-second channel before /camp actually saves and exits to the main menu —
# without this, /camp is a free instant escape from a bad pull or a fight
# gone wrong. Interrupted (not just delayed) by taking any damage during the
# channel, same idea as EQ's camp timer resetting on a hit.
var _camping := false
const CAMP_CHANNEL_MS := 15000

func _start_camp_sequence() -> void:
	if _camping:
		GameLog.log_general("[color=#ffaa66]You are already trying to camp.[/color]")
		return
	if not is_instance_valid(player):
		return
	_camping = true
	var start_ms := Time.get_ticks_msec()
	var start_damage_ms: int = player.last_damage_time_ms
	var was_sitting: bool = player.is_sitting
	player.is_sitting = true
	GameLog.log_general("[color=#ffdd88]You sit down and prepare to break camp. Remain undisturbed for 15 seconds...[/color]")

	while Time.get_ticks_msec() - start_ms < CAMP_CHANNEL_MS:
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(player):
			_camping = false
			return
		if player.last_damage_time_ms > start_damage_ms:
			GameLog.log_general("[color=#ff6666]Your camping attempt is interrupted — you've taken damage![/color]")
			player.is_sitting = was_sitting
			_camping = false
			return

	_camping = false
	GameLog.log_general("[color=#88cc88]You finish breaking camp.[/color]")
	_save_and_return_to_menu()


# Same save-and-tear-down sequence as pause_menu.gd's "Save and Exit" button —
# frees every CanvasLayer on root (HUD, character sheet, backpack, pet frame,
# etc.) before switching scenes, since none of those free themselves on their
# own when the zone scene changes out from under them.
func _save_and_return_to_menu() -> void:
	Global.save_player_data_to_file()
	for node in get_tree().root.get_children():
		if node is CanvasLayer:
			node.queue_free()
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")


func _save_and_quit() -> void:
	Global.save_player_data_to_file()
	get_tree().quit()


# Resolves a typed command to a canonical one from COMMANDS, allowing any
# unambiguous prefix (e.g. "/fol" -> "/follow") the same way Linux shells
# tab-complete unique abbreviations. Logs "Unknown"/"Ambiguous" itself and
# returns "" in either failure case, so callers can just bail on empty.
func _resolve_command(typed: String) -> String:
	if COMMANDS.has(typed):
		return typed
	var matches: Array = []
	for c in COMMANDS:
		if c.begins_with(typed):
			matches.append(c)
	if matches.size() == 1:
		return matches[0]
	if matches.size() > 1:
		GameLog.log_general("[color=red]Ambiguous command '%s' — did you mean: %s?[/color]" % [typed, ", ".join(matches)])
		return ""
	GameLog.log_general("[color=red]Unknown command: %s[/color]" % typed)
	return ""


# ── Log output ────────────────────────────────────────────────────────────────

func _on_general(text: String) -> void:
	_append(general_log, text)
	_write_to_log_file("GENERAL", text)


const COMBAT_VISIBILITY_RANGE := 10.0

func _on_combat(text: String, has_position: bool, position: Vector3) -> void:
	# The file log is for balance/metrics review, so it captures every combat
	# message unconditionally (e.g. a distant guard fight) — the 10m range
	# above only gates what's actually shown on screen.
	_write_to_log_file("COMBAT", text)
	if has_position and is_instance_valid(player) \
			and player.global_position.distance_to(position) > COMBAT_VISIBILITY_RANGE:
		return
	_append(combat_log, text)


# ===== /log — dumps chat + combat to a plain-text file for balance review =====

var _log_file: FileAccess = null
const LOG_DIR := "user://logs"

func _toggle_file_logging() -> void:
	if _log_file != null:
		_log_file.close()
		_log_file = null
		GameLog.log_general("[color=#88cc88]Logging stopped.[/color]")
		return

	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var d := Time.get_datetime_dict_from_system(false)
	var stamp := "%04d-%02d-%02d_%02d-%02d-%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
	var file_path := "%s/session_%s.txt" % [LOG_DIR, stamp]
	_log_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _log_file:
		var real_path := ProjectSettings.globalize_path(file_path)
		GameLog.log_general("[color=#88cc88]Logging chat and combat to:[/color] %s" % real_path)
	else:
		GameLog.log_general("[color=#ff6666]Couldn't open a log file to write to.[/color]")


func _write_to_log_file(channel: String, text: String) -> void:
	if _log_file == null:
		return
	var d := Time.get_datetime_dict_from_system(false)
	_log_file.store_line("[%02d:%02d:%02d] [%s] %s" % [d.hour, d.minute, d.second, channel, _strip_bbcode(text)])
	_log_file.flush()  # write-through so a crash or force-quit doesn't lose a buffered tail


func _exit_tree() -> void:
	if _log_file != null:
		_log_file.close()
		_log_file = null


func _strip_bbcode(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[[^\\]]*\\]")
	return regex.sub(text, "", true)


func _append(log: RichTextLabel, text: String) -> void:
	if log.get_paragraph_count() > MAX_LINES:
		log.clear()
	log.append_text(_timestamp() + text + "\n")


func _timestamp() -> String:
	var d := Time.get_datetime_dict_from_system(false)
	var hour12: int = d.hour % 12
	if hour12 == 0:
		hour12 = 12
	var ampm := "AM" if d.hour < 12 else "PM"
	return "[color=#666666][%02d:%02d %s][/color] " % [hour12, d.minute, ampm]
