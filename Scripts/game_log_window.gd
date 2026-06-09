# game_log_window.gd — Tabbed General / Combat message log
extends CanvasLayer
class_name GameLogWindow

@onready var general_log: RichTextLabel = $Panel/VBox/Tabs/General/GeneralLog
@onready var combat_log:  RichTextLabel = $Panel/VBox/Tabs/Combat/CombatLog

const MAX_LINES    := 200
const DRAG_BAR_H   := 22.0

var _autoattack_dot: Label
var _dot_tween: Tween
var _dragging := false


func _ready() -> void:
	GameLog.general_message.connect(_on_general)
	GameLog.combat_message.connect(_on_combat)
	GameLog.autoattack_changed.connect(_on_autoattack_changed)
	_append(general_log, "[color=#888888]— Welcome to Aldenexia —[/color]")
	_setup_autoattack_dot()
	_setup_drag_bar()
	# Prevent the chat window from consuming player movement keys
	$Panel/VBox/Tabs.focus_mode = Control.FOCUS_NONE
	general_log.focus_mode = Control.FOCUS_NONE
	combat_log.focus_mode  = Control.FOCUS_NONE


func _setup_drag_bar() -> void:
	# Thin title bar sits above the VBox and is the only drag handle
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
	# Push the VBox down so it doesn't overlap the bar
	$Panel/VBox.offset_top = DRAG_BAR_H
	_load_position()


func _on_drag_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not _dragging:
			_save_position()
	elif event is InputEventMouseMotion and _dragging:
		var panel: Panel = $Panel
		panel.offset_left   += event.relative.x
		panel.offset_top    += event.relative.y
		panel.offset_right  += event.relative.x
		panel.offset_bottom += event.relative.y


func _save_position() -> void:
	if Global.player_data.is_empty():
		return
	var p: Panel = $Panel
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	ui["chat"] = [p.offset_left, p.offset_top, p.offset_right, p.offset_bottom]
	Global.player_data["ui_positions"] = ui
	Global.save_player_data_to_file()


func _load_position() -> void:
	var pos: Array = Global.player_data.get("ui_positions", {}).get("chat", [])
	if pos.size() == 4:
		var p: Panel = $Panel
		p.offset_left   = pos[0]
		p.offset_top    = pos[1]
		p.offset_right  = pos[2]
		p.offset_bottom = pos[3]


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


func _on_general(text: String) -> void:
	_append(general_log, text)


func _on_combat(text: String) -> void:
	_append(combat_log, text)


func _append(log: RichTextLabel, text: String) -> void:
	if log.get_paragraph_count() > MAX_LINES:
		log.clear()
	log.append_text(text + "\n")
