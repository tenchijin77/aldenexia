# stance_bar.gd — Small bar of stance slots, shown above the action bar and
# indented right ("tabbed in" from its left edge). Hidden entirely for classes
# with no stances. Built in code, same pattern as action_bar.gd.
extends CanvasLayer
class_name StanceBar

const SLOT_SIZE := 40
const SLOT_GAP  := 4
const INDENT    := 60   # how far right of the action bar's left edge this bar starts
const GAP_ABOVE_ACTION_BAR := 4

var _player: Node = null
var _stances: Array = []
var _slot_panels: Array[Control] = []
var _panel: Panel = null


func _ready() -> void:
	layer = 4


func _process(_delta: float) -> void:
	if _panel != null:
		return  # already built (or determined not to build)

	if not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		_player = players[0]

	_stances = _load_stances_for_class(_player.get("player_class") if "player_class" in _player else "")
	if _stances.is_empty():
		queue_free()
		return

	_build_ui()


func _load_stances_for_class(class_name_str: String) -> Array:
	if class_name_str.is_empty():
		return []
	var file := FileAccess.open("res://Data/class_stances.json", FileAccess.READ)
	if not file:
		return []
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		return []
	return data.get(class_name_str, [])


func _build_ui() -> void:
	var count: int = _stances.size()
	var total_w: int = SLOT_SIZE * count + SLOT_GAP * maxi(count - 1, 0) + 12

	var action_bar_total_w: float = ActionBar.SLOT_SIZE * ActionBar.SLOT_COUNT \
		+ ActionBar.SLOT_GAP * (ActionBar.SLOT_COUNT - 1) + 12
	var action_bar_height: float = ActionBar.SLOT_SIZE + 16

	var panel := Panel.new()
	panel.anchor_left   = 0.5
	panel.anchor_top    = 1.0
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 1.0
	panel.offset_left   = -action_bar_total_w / 2.0 + INDENT
	panel.offset_right  = panel.offset_left + total_w
	panel.offset_bottom = -(action_bar_height + GAP_ABOVE_ACTION_BAR)
	panel.offset_top    = panel.offset_bottom - (SLOT_SIZE + 16)
	_panel = panel
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left   =  6
	hbox.offset_top    =  4
	hbox.offset_right  = -6
	hbox.offset_bottom = -4
	hbox.add_theme_constant_override("separation", SLOT_GAP)
	panel.add_child(hbox)

	for i in range(count):
		var stance: Dictionary = _stances[i]
		var slot_panel := Panel.new()
		slot_panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

		var bg := StyleBoxFlat.new()
		bg.bg_color     = Color(0.08, 0.08, 0.12, 0.92)
		bg.border_color = Color(0.35, 0.35, 0.45)
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(3)
		slot_panel.add_theme_stylebox_override("panel", bg)

		var name_lbl := Label.new()
		name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		name_lbl.text = stance.get("name", "").replace(" Stance", "")
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(name_lbl)

		slot_panel.tooltip_text = stance.get("description", "")
		slot_panel.mouse_filter = Control.MOUSE_FILTER_STOP

		var stance_id: String = stance.get("stance_id", "")
		slot_panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton \
					and event.button_index == MOUSE_BUTTON_LEFT \
					and event.pressed:
				_on_slot_clicked(stance_id, bg)
		)

		hbox.add_child(slot_panel)
		_slot_panels.append(slot_panel)


func _on_slot_clicked(stance_id: String, bg: StyleBoxFlat) -> void:
	if not ("current_stance" in _player) or not ("combat_node" in _player):
		return

	var combat_node = _player.combat_node

	if _player.current_stance == stance_id:
		# Toggle off
		combat_node.remove_effect("stance_" + stance_id)
		_player.current_stance = ""
		GameLog.log_general("You drop your stance.")
	else:
		if not _player.current_stance.is_empty():
			combat_node.remove_effect("stance_" + _player.current_stance)

		var stance: Dictionary = {}
		for s in _stances:
			if s.get("stance_id", "") == stance_id:
				stance = s
				break
		if stance.is_empty():
			return

		combat_node.apply_effect("stance_" + stance_id, INF, stance.get("modifiers", {}))
		_player.current_stance = stance_id
		GameLog.log_general("[color=#ffcc66]You assume the %s.[/color]" % stance.get("name", ""))

	_refresh_highlight()


func _refresh_highlight() -> void:
	for i in range(_stances.size()):
		var stance: Dictionary = _stances[i]
		var slot_panel: Control = _slot_panels[i]
		var bg: StyleBoxFlat = slot_panel.get_theme_stylebox("panel")
		if stance.get("stance_id", "") == _player.current_stance:
			bg.border_color = Color(0.55, 0.45, 0.25)
		else:
			bg.border_color = Color(0.35, 0.35, 0.45)
