# game_window.gd — the frame shared by windows built entirely in code (quest_journal.gd, recipe_book.gd): the game's
# window background, a title bar with a close button, drag anywhere on the frame, resize from the bottom-right corner,
# and position/size remembered per window (WindowPosition), the same behaviour as tracking_window.gd. A subclass calls
# build_frame(title, key, default_size) in _ready() and fills `body` (a VBoxContainer under the title bar).
extends CanvasLayer
class_name GameWindow

const RESIZE_MARGIN := 16.0

var panel: Panel
var body: VBoxContainer
var _position_key := ""
var _min_size := Vector2(320, 240)
var _dragging := false
var _resizing := false


func build_frame(title: String, position_key: String, default_size: Vector2, min_size: Vector2 = Vector2(320, 240)) -> void:
	layer = 5
	_position_key = position_key
	_min_size = min_size
	panel = Panel.new()
	panel.add_theme_stylebox_override("panel", Global.window_bg_style())
	panel.position = Vector2(120, 120)
	panel.size = default_size
	add_child(panel)
	panel.gui_input.connect(_on_panel_gui_input)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)

	var title_bar := HBoxContainer.new()
	title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(title_bar)
	var title_label := Label.new()
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.6))
	title_label.add_theme_font_size_override("font_size", 15)
	title_bar.add_child(title_label)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.pressed.connect(queue_free)
	title_bar.add_child(close_btn)

	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	outer.add_child(body)
	WindowPosition.load_full_into(_position_key, panel)


# Drag from anywhere on the frame; resize from the bottom-right corner. Saved when the mouse is released.
func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos: Vector2 = event.position
			_resizing = pos.x > panel.size.x - RESIZE_MARGIN and pos.y > panel.size.y - RESIZE_MARGIN
			_dragging = not _resizing
		else:
			if _dragging or _resizing:
				WindowPosition.save(_position_key, panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _resizing:
			panel.size = Vector2(maxf(_min_size.x, panel.size.x + event.relative.x), maxf(_min_size.y, panel.size.y + event.relative.y))
		elif _dragging:
			panel.position += event.relative


# A small header label in the window's colours.
func header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	label.add_theme_font_size_override("font_size", 12)
	return label
