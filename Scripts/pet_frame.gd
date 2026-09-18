# pet_frame.gd — Small HUD panel for the active pet: name, HP bar, and command
# buttons (Attack / Assist / Back / Follow / Sit / Guard / Gear / Dismiss).
# Built in code, same pattern as action_bar.gd. Instantiated by player3d.gd
# when a pet is summoned, freed when the pet dies.
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
var _mp_bar: ProgressBar = null
var _mp_label: Label = null
var _dragging := false

# Follow/Guard/Assist/Sit are persistent modes (not one-shot actions like
# Attack/Back/Gear/Dismiss) — keyed by PetState.PetState value so _process()
# can ring-highlight whichever one is actually active, both to answer "is
# this pet actually in Guard mode or not" at a glance and to make it obvious
# a mode change really took (e.g. leaving Sit for Follow).
var _mode_buttons: Dictionary = {}
var _mode_style_off: StyleBoxFlat
var _mode_style_on: StyleBoxFlat


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
	panel.offset_bottom = 150 + 200  # +20 over the old height for the new MP row
	panel.gui_input.connect(_on_panel_gui_input)
	_panel = panel
	add_child(panel)

	panel.add_theme_stylebox_override("panel", Global.window_bg_style())

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
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(_name_label)

	var hp_row := HBoxContainer.new()
	vbox.add_child(hp_row)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.show_percentage = false
	_style_bar(_hp_bar, Color(0.8, 0.15, 0.15), Color(0.12, 0.05, 0.05))
	hp_row.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 10)
	_hp_label.custom_minimum_size = Vector2(70, 0)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_row.add_child(_hp_label)

	# Pets don't spend mana on anything yet, but the bar's wired up now so it's
	# ready the moment they get spells that do.
	var mp_row := HBoxContainer.new()
	vbox.add_child(mp_row)

	_mp_bar = ProgressBar.new()
	_mp_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_mp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mp_bar.show_percentage = false
	_style_bar(_mp_bar, Color(0.2, 0.35, 0.9), Color(0.05, 0.06, 0.12))
	mp_row.add_child(_mp_bar)

	_mp_label = Label.new()
	_mp_label.add_theme_font_size_override("font_size", 10)
	_mp_label.custom_minimum_size = Vector2(70, 0)
	_mp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mp_row.add_child(_mp_label)

	_mode_style_off = StyleBoxFlat.new()
	_mode_style_off.bg_color = Color(0.16, 0.16, 0.18)
	_mode_style_off.border_color = Color(0.4, 0.4, 0.45)
	_mode_style_off.set_border_width_all(1)
	_mode_style_off.set_corner_radius_all(3)

	_mode_style_on = StyleBoxFlat.new()
	_mode_style_on.bg_color = Color(0.32, 0.22, 0.5)
	_mode_style_on.border_color = Color(0.75, 0.55, 1.0)
	_mode_style_on.set_border_width_all(2)
	_mode_style_on.set_corner_radius_all(3)

	var btn_grid := GridContainer.new()
	btn_grid.columns = 3
	btn_grid.add_theme_constant_override("h_separation", 4)
	btn_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(btn_grid)

	# PetMinion.PetState: FOLLOW=0, ATTACK=1, SIT=2, GUARD=3, ASSIST=4 — the
	# four persistent-mode entries below record their state value so
	# _process() can look up which button to ring-highlight.
	var commands := [
		["Attack", func(): _on_attack_pressed(), -1],
		["Assist", func(): _on_simple_command("cmd_assist"), 4],
		["Back",   func(): _on_simple_command("cmd_back"), -1],
		["Follow", func(): _on_simple_command("cmd_follow"), 0],
		["Sit",    func(): _on_simple_command("cmd_sit"), 2],
		["Guard",  func(): _on_simple_command("cmd_guard"), 3],
		["Gear",   func(): _on_gear_pressed(), -1],
		["Dismiss", func(): _on_simple_command("cmd_dismiss"), -1],
	]
	for entry in commands:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(0, BTN_HEIGHT)
		btn.pressed.connect(entry[1])
		var state_value: int = entry[2]
		if state_value >= 0:
			btn.add_theme_stylebox_override("normal", _mode_style_off)
			btn.add_theme_stylebox_override("hover", _mode_style_off)
			_mode_buttons[state_value] = btn
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


# Same helper as player_frame.gd/target_frame.gd — see those for why it isn't shared.
func _style_bar(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)

	var back := StyleBoxFlat.new()
	back.bg_color = bg_color
	back.border_color = Color(0, 0, 0, 0.5)
	back.set_border_width_all(1)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)


func _get_player() -> Node:
	if not is_instance_valid(_player):
		_player = TargetFrame.local_player()
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


func _on_gear_pressed() -> void:
	var player := _get_player()
	if player and player.has_method("toggle_pet_gear_window"):
		player.toggle_pet_gear_window()


func _process(_delta: float) -> void:
	# A charmed monster (monster3d.gd's apply_charm()) reverts is_charmed to
	# false on its own when the spell ends or is dismissed, rather than
	# freeing itself — a real PetMinion has no such property, so this is a
	# no-op for every normal pet.
	if not is_instance_valid(_pet) or ("is_charmed" in _pet and not _pet.is_charmed):
		queue_free()
		return

	var cn = _pet.combat_node
	_hp_bar.max_value = cn.max_hp
	_hp_bar.value     = cn.current_hp
	_hp_label.text    = "%d / %d" % [cn.current_hp, cn.max_hp]

	_mp_bar.max_value = cn.max_mana
	_mp_bar.value     = cn.current_mana
	_mp_label.text    = "%d / %d" % [cn.current_mana, cn.max_mana]

	var active_state: int = _pet.command
	for state_value in _mode_buttons:
		var btn: Button = _mode_buttons[state_value]
		btn.add_theme_stylebox_override("normal", _mode_style_on if state_value == active_state else _mode_style_off)
		btn.add_theme_stylebox_override("hover", _mode_style_on if state_value == active_state else _mode_style_off)
