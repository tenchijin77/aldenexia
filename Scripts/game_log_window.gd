# game_log_window.gd — Tabbed General / Combat message log
extends CanvasLayer
class_name GameLogWindow

@onready var general_log: RichTextLabel = $Panel/VBox/Tabs/General/GeneralLog
@onready var combat_log:  RichTextLabel = $Panel/VBox/Tabs/Combat/CombatLog
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


func _ready() -> void:
	GameLog.general_message.connect(_on_general)
	GameLog.combat_message.connect(_on_combat)
	GameLog.autoattack_changed.connect(_on_autoattack_changed)
	_append(general_log, "[color=#888888]— Welcome to Aldenexia —[/color]")
	_setup_font_menu()
	_setup_autoattack_dot()
	_setup_drag_bar()
	_setup_resize_handle()
	$Panel/VBox/Tabs.focus_mode = Control.FOCUS_NONE
	general_log.focus_mode = Control.FOCUS_NONE
	combat_log.focus_mode  = Control.FOCUS_NONE
	chat_input.text_submitted.connect(_on_chat_input_submitted)


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


# ── Persistence ───────────────────────────────────────────────────────────────

func _save_position() -> void:
	if Global.player_data.is_empty():
		return
	var p: Panel = $Panel
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	ui["chat"]           = [p.offset_left, p.offset_top, p.offset_right, p.offset_bottom]
	ui["chat_font_size"] = _font_size
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

func _on_chat_input_submitted(text: String) -> void:
	chat_input.text = ""
	text = text.strip_edges()
	if text == "":
		return
	if text.begins_with("/"):
		_handle_slash_command(text)
	else:
		GameLog.log_general("[color=yellow]You say, '%s'[/color]" % text)


func _handle_slash_command(text: String) -> void:
	var cmd := text.split(" ", false)[0].to_lower()
	match cmd:
		"/loc":
			var pos: Vector3 = player.global_position
			GameLog.log_general("[color=green]Your location: X=%.2f Y=%.2f Z=%.2f[/color]" % [pos.x, pos.y, pos.z])
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
		_:
			GameLog.log_general("[color=red]Unknown command: %s[/color]" % cmd)


# ── Log output ────────────────────────────────────────────────────────────────

func _on_general(text: String) -> void:
	_append(general_log, text)


func _on_combat(text: String) -> void:
	_append(combat_log, text)


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
