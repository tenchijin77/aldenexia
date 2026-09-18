# cast_bar.gd — Shows the local player's own spell cast: name on the left,
# a fill bar that completes when the spell resolves, and time remaining on
# the right. Hidden entirely except while combat_node.is_casting is true.
# Built in code, same pattern as stance_bar.gd/action_bar.gd. Polls the
# player's combat_node every frame rather than using a signal, same reasoning
# as player_frame.gd's HP/MP bars — casting state changes too often (every
# frame while a cast is running) for signals to be worth the wiring.
extends CanvasLayer
class_name CastBar

const BAR_WIDTH := 260
const BAR_HEIGHT := 18
# Clears the action bar and, whether or not this class actually has one, the
# stance bar row above it too — cheaper than asking StanceBar if it built
# itself for this class.
const GAP_ABOVE_ACTION_BAR := 74
const POSITION_KEY := "cast_bar"

var _player: Node = null
var _panel: Panel = null
var _name_label: Label = null
var _time_label: Label = null
var _bar: ProgressBar = null
var _dragging := false


func _ready() -> void:
	layer = 4
	_build_ui()
	WindowPosition.load_position_into(POSITION_KEY, _panel)
	visible = false


func _build_ui() -> void:
	var action_bar_height: float = ActionBar.SLOT_SIZE + 16

	_panel = Panel.new()
	_panel.anchor_left   = 0.5
	_panel.anchor_top    = 1.0
	_panel.anchor_right  = 0.5
	_panel.anchor_bottom = 1.0
	_panel.offset_left   = -BAR_WIDTH / 2.0
	_panel.offset_right  = BAR_WIDTH / 2.0
	_panel.offset_bottom = -(action_bar_height + GAP_ABOVE_ACTION_BAR)
	_panel.offset_top    = _panel.offset_bottom - (BAR_HEIGHT + 22)
	add_child(_panel)
	_panel.gui_input.connect(_on_panel_gui_input)

	_panel.add_theme_stylebox_override("panel", Global.window_bg_style())

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 6
	vbox.offset_top    = 3
	vbox.offset_right  = -6
	vbox.offset_bottom = -3
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	header.add_child(_name_label)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 12)
	_time_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_time_label)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.7, 0.15)
	fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)

	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.06, 0.05, 0.09)
	back.border_color = Color(0, 0, 0, 0.5)
	back.set_border_width_all(1)
	back.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("background", back)

	vbox.add_child(_bar)


# Same drag pattern as player_frame.gd/stance_bar.gd's panels — only draggable
# while actually visible (i.e. mid-cast), same as every other frame is only
# draggable while shown.
func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not _dragging:
			WindowPosition.save(POSITION_KEY, _panel)
	elif event is InputEventMouseMotion and _dragging:
		_panel.offset_left   += event.relative.x
		_panel.offset_top    += event.relative.y
		_panel.offset_right  += event.relative.x
		_panel.offset_bottom += event.relative.y


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = TargetFrame.local_player()
		if not is_instance_valid(_player):
			visible = false
			return

	var cn = _player.get("combat_node")
	if not (cn is CombatNode) or not cn.is_casting:
		visible = false
		return

	visible = true
	var total: float = maxf(cn.total_cast_time, 0.01)
	var progress: float = clampf(cn.current_cast_time / total, 0.0, 1.0)
	_bar.value = progress
	_name_label.text = _player.get("casting_spell_name") if "casting_spell_name" in _player else ""
	_time_label.text = "%.1fs" % maxf(total - cn.current_cast_time, 0.0)
