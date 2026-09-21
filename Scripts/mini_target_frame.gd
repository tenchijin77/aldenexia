# mini_target_frame.gd — two small HUD frames that sit with the target frame:
#   "focus": your FOCUS, the friend your beneficial spells go to while you are targeting an enemy (Player3D.focus_target; set with /focus,
#            Shift-click on a friend or a group row);
#   "tot":   your TARGET'S TARGET, whoever your current target is targeting (who the boss is hitting, what the tank is fighting).
# Built in code like the other HUD windows: draggable, position remembered per character (/resetui puts them back). Click one to target it.
# Shows nothing while there is nothing to show.
extends CanvasLayer   # no class_name on purpose: player3d.gd preloads it (a brand-new class name is unknown to Godot until its class cache is rebuilt)

const SIZE := Vector2(210, 44)
const MIN_SIZE := Vector2(150, 40)
const RESIZE_MARGIN := 14.0
const FOCUS_RANGE_WARN := 15.0   # beyond this, the focus's distance turns red (most spells reach 15 m)

var kind := "focus"          # "focus" | "tot"
var _panel: Panel
var _title: Label
var _name: Label
var _dist: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _player: Node = null
var _shown: Node = null
var _press_pos := Vector2.ZERO
var _dragging := false
var _resizing := false
var _moved := false


func _ready() -> void:
	add_to_group("mini_target_frame")
	visible = false
	var key := "%s_frame" % kind
	_panel = Panel.new()
	# By default: the focus under the target frame, the target's target to its right.
	var origin := Vector2(250, 100) if kind == "focus" else Vector2(470, 10)
	_panel.offset_left = origin.x
	_panel.offset_top = origin.y
	_panel.offset_right = origin.x + SIZE.x
	_panel.offset_bottom = origin.y + SIZE.y
	_panel.add_theme_stylebox_override("panel", Global.window_bg_style())
	WindowPosition.load_full_into(key, _panel)   # position AND size: both are the player's to change
	add_child(_panel)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	_title = Label.new()
	_title.text = "FOCUS" if kind == "focus" else "TARGET'S TARGET"
	_title.add_theme_font_size_override("font_size", 9)
	_title.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7) if kind == "focus" else Color(0.85, 0.7, 0.55))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_title)
	_name = Label.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.add_theme_font_size_override("font_size", 11)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_name)
	_dist = Label.new()
	_dist.add_theme_font_size_override("font_size", 9)
	_dist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_dist)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.custom_minimum_size = Vector2(0, 11)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.7, 0.35) if kind == "focus" else Color(0.8, 0.15, 0.15)
	fill.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.06, 0.09, 0.06) if kind == "focus" else Color(0.12, 0.05, 0.05)
	back.border_color = Color(0, 0, 0, 0.5)
	back.set_border_width_all(1)
	back.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("background", back)
	row.add_child(_hp_bar)
	_hp_text = Label.new()
	_hp_text.add_theme_font_size_override("font_size", 9)
	_hp_text.custom_minimum_size = Vector2(62, 0)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_hp_text)

	_panel.gui_input.connect(_on_gui_input)


# Press and release without moving = target it; press and drag = move the frame; drag the lower-right corner = resize it (both remembered).
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos: Vector2 = event.position
			_resizing = pos.x > _panel.size.x - RESIZE_MARGIN and pos.y > _panel.size.y - RESIZE_MARGIN
			_dragging = not _resizing
			_moved = false
			_press_pos = event.global_position
		else:
			if _moved:
				WindowPosition.save("%s_frame" % kind, _panel)
			elif _dragging and is_instance_valid(_shown) and is_instance_valid(_player):
				_player.current_target = _shown
				if _player.has_method("_announce_target"):
					_player._announce_target(_shown)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion and (_dragging or _resizing):
		if not _moved and event.global_position.distance_to(_press_pos) < 4.0:
			return
		_moved = true
		if _resizing:
			_panel.offset_right = maxf(_panel.offset_left + MIN_SIZE.x, _panel.offset_right + event.relative.x)
			_panel.offset_bottom = maxf(_panel.offset_top + MIN_SIZE.y, _panel.offset_bottom + event.relative.y)
		else:
			_panel.offset_left += event.relative.x
			_panel.offset_top += event.relative.y
			_panel.offset_right += event.relative.x
			_panel.offset_bottom += event.relative.y


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = TargetFrame.local_player()
		if not is_instance_valid(_player):
			visible = false
			return
	var node: Node = null
	if kind == "focus":
		node = _player.get_focus() if _player.has_method("get_focus") else null
	else:
		node = TargetFrame.target_of(_player.get("current_target"))
	if node == null or not is_instance_valid(node):
		_shown = null
		visible = false
		return
	_shown = node
	visible = true
	_name.text = TargetFrame.nameplate_name(node)
	var faction := TargetFrame.faction_status(node)
	_name.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if faction == "Enemy" else Color(0.8, 1.0, 0.85))
	var distance: float = _player.global_position.distance_to(node.global_position) if node != _player else 0.0
	_dist.text = "" if node == _player else "%d m" % int(distance)
	_dist.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if kind == "focus" and distance > FOCUS_RANGE_WARN else Color(0.7, 0.7, 0.7))
	var cn = node.get("combat_node") if "combat_node" in node else null
	if cn is CombatNode:
		_hp_bar.max_value = maxi(cn.max_hp, 1)
		_hp_bar.value = maxi(cn.current_hp, 0)
		_hp_text.text = "%d/%d" % [cn.current_hp, cn.max_hp]
	else:
		_hp_bar.max_value = 1
		_hp_bar.value = 1
		_hp_text.text = ""
