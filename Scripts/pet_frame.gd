# pet_frame.gd — Small HUD panel for the active pet: name, HP bar, and command
# buttons (Attack / Stop / Back / Follow / Sit / Guard). Built in code, same
# pattern as action_bar.gd. Instantiated by player3d.gd when a pet is summoned,
# freed when the pet dies.
extends CanvasLayer
class_name PetFrame

const PANEL_WIDTH := 220
const BAR_HEIGHT := 16
const BTN_HEIGHT := 26

var _pet: Node = null
var _player: Node = null
var _panel: Panel = null
var _name_label: Label = null
var _hp_bar: ProgressBar = null
var _hp_label: Label = null
var _dragging := false


func _ready() -> void:
	layer = 4
	_build_ui()


func _build_ui() -> void:
	var panel := Panel.new()
	panel.anchor_left   = 0.0
	panel.anchor_top    = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left   = 16
	panel.offset_top    = 150
	panel.offset_right  = 16 + PANEL_WIDTH
	panel.offset_bottom = 150 + 150
	panel.gui_input.connect(_on_panel_gui_input)
	_panel = panel
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  8
	vbox.offset_top    =  6
	vbox.offset_right  = -8
	vbox.offset_bottom = -6
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_name_label = Label.new()
	_name_label.text = "Spectral Minion"
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))
	vbox.add_child(_name_label)

	var hp_row := HBoxContainer.new()
	vbox.add_child(hp_row)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.show_percentage = false
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.55, 0.35, 0.85)
	_hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_row.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 10)
	_hp_label.custom_minimum_size = Vector2(70, 0)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_row.add_child(_hp_label)

	var btn_grid := GridContainer.new()
	btn_grid.columns = 3
	btn_grid.add_theme_constant_override("h_separation", 4)
	btn_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(btn_grid)

	var commands := [
		["Attack", func(): _on_attack_pressed()],
		["Stop",   func(): _on_simple_command("cmd_stop")],
		["Back",   func(): _on_simple_command("cmd_back")],
		["Follow", func(): _on_simple_command("cmd_follow")],
		["Sit",    func(): _on_simple_command("cmd_sit")],
		["Guard",  func(): _on_simple_command("cmd_guard")],
	]
	for entry in commands:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(0, BTN_HEIGHT)
		btn.pressed.connect(entry[1])
		btn_grid.add_child(btn)

	_load_position()


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not _dragging:
			_save_position()
	elif event is InputEventMouseMotion and _dragging:
		_panel.offset_left   += event.relative.x
		_panel.offset_top    += event.relative.y
		_panel.offset_right  += event.relative.x
		_panel.offset_bottom += event.relative.y


func _save_position() -> void:
	if Global.player_data.is_empty():
		return
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	ui["pet_frame"] = [_panel.offset_left, _panel.offset_top, _panel.offset_right, _panel.offset_bottom]
	Global.player_data["ui_positions"] = ui
	Global.save_player_data_to_file()


func _load_position() -> void:
	var pos: Array = Global.player_data.get("ui_positions", {}).get("pet_frame", [])
	if pos.size() == 4:
		_panel.offset_left   = pos[0]
		_panel.offset_top    = pos[1]
		_panel.offset_right  = pos[2]
		_panel.offset_bottom = pos[3]


func set_pet(pet: Node) -> void:
	_pet = pet
	if is_instance_valid(pet):
		_name_label.text = pet.pet_name


func _get_player() -> Node:
	if not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			_player = players[0]
	return _player


func _on_attack_pressed() -> void:
	if not is_instance_valid(_pet):
		return
	var player := _get_player()
	if player and "current_target" in player:
		_pet.cmd_attack(player.current_target)
	else:
		_pet.cmd_attack(null)


func _on_simple_command(method: String) -> void:
	if is_instance_valid(_pet) and _pet.has_method(method):
		_pet.call(method)


func _process(_delta: float) -> void:
	if not is_instance_valid(_pet):
		queue_free()
		return

	var cn = _pet.combat_node
	_hp_bar.max_value = cn.max_hp
	_hp_bar.value     = cn.current_hp
	_hp_label.text    = "%d / %d" % [cn.current_hp, cn.max_hp]
