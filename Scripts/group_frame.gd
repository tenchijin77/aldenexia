# group_frame.gd — Party frame: your own name/HP/MP, with your active pet
# listed slightly smaller beneath. This is the single-player stand-in for
# what becomes a real multi-member party list once networking exists — same
# row shape (name + HP + MP), so adding other players later means adding more
# rows, not a redesign. Also the healer's practice target for group heals/
# buffs while solo: right-click your own name row or your pet's to target
# yourself/your pet directly (see _on_row_clicked()).
extends CanvasLayer
class_name GroupFrame

const POSITION_KEY := "group_frame"

var _player: Node = null
var _panel: Panel = null
var _dragging := false

var _player_name_label: Label
var _player_hp_bar: ProgressBar
var _player_mp_bar: ProgressBar

var _pet_wrapper: Control
var _pet_name_label: Label
var _pet_hp_bar: ProgressBar
var _pet_mp_bar: ProgressBar


func _ready() -> void:
	layer = 4
	_build_ui()


func _build_ui() -> void:
	var panel := Panel.new()
	panel.anchor_left   = 0.0
	panel.anchor_top    = 0.0
	panel.offset_left   = 10
	panel.offset_top    = 185
	panel.offset_right  = 230
	panel.offset_bottom = 185 + 128
	panel.gui_input.connect(_on_panel_gui_input)
	_panel = panel
	add_child(panel)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.06, 0.92)
	bg.border_color = Color(0.45, 0.38, 0.25)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  6
	vbox.offset_top    =  4
	vbox.offset_right  = -6
	vbox.offset_bottom = -4
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Group"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
	vbox.add_child(title)

	# --- Player row ---
	_player_name_label = Label.new()
	_player_name_label.text = "Player"
	_player_name_label.add_theme_font_size_override("font_size", 11)
	_player_name_label.clip_text = true
	_player_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_player_name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_player_name_label.gui_input.connect(func(e): _on_row_clicked(e, "player"))
	vbox.add_child(_player_name_label)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.custom_minimum_size = Vector2(0, 10)
	_player_hp_bar.show_percentage = false
	_style_bar(_player_hp_bar, Color(0.8, 0.15, 0.15), Color(0.12, 0.05, 0.05))
	vbox.add_child(_player_hp_bar)

	_player_mp_bar = ProgressBar.new()
	_player_mp_bar.custom_minimum_size = Vector2(0, 8)
	_player_mp_bar.show_percentage = false
	_style_bar(_player_mp_bar, Color(0.2, 0.35, 0.9), Color(0.05, 0.06, 0.12))
	vbox.add_child(_player_mp_bar)

	# --- Pet row (smaller, indented, hidden until a pet actually exists) ---
	_pet_wrapper = MarginContainer.new()
	_pet_wrapper.add_theme_constant_override("margin_left", 14)
	_pet_wrapper.visible = false
	vbox.add_child(_pet_wrapper)

	var pet_col := VBoxContainer.new()
	pet_col.add_theme_constant_override("separation", 2)
	_pet_wrapper.add_child(pet_col)

	_pet_name_label = Label.new()
	_pet_name_label.text = "Pet"
	_pet_name_label.add_theme_font_size_override("font_size", 9)
	_pet_name_label.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))
	_pet_name_label.clip_text = true
	_pet_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pet_name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_pet_name_label.gui_input.connect(func(e): _on_row_clicked(e, "pet"))
	pet_col.add_child(_pet_name_label)

	_pet_hp_bar = ProgressBar.new()
	_pet_hp_bar.custom_minimum_size = Vector2(0, 7)
	_pet_hp_bar.show_percentage = false
	_style_bar(_pet_hp_bar, Color(0.65, 0.4, 0.9), Color(0.08, 0.05, 0.12))
	pet_col.add_child(_pet_hp_bar)

	_pet_mp_bar = ProgressBar.new()
	_pet_mp_bar.custom_minimum_size = Vector2(0, 6)
	_pet_mp_bar.show_percentage = false
	_style_bar(_pet_mp_bar, Color(0.2, 0.35, 0.9), Color(0.05, 0.06, 0.12))
	pet_col.add_child(_pet_mp_bar)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	var invite_btn := Button.new()
	invite_btn.text = "Invite"
	invite_btn.custom_minimum_size = Vector2(0, 24)
	invite_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invite_btn.pressed.connect(_on_invite_pressed)
	btn_row.add_child(invite_btn)

	var disband_btn := Button.new()
	disband_btn.text = "Disband"
	disband_btn.custom_minimum_size = Vector2(0, 24)
	disband_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disband_btn.pressed.connect(_on_disband_pressed)
	btn_row.add_child(disband_btn)

	WindowPosition.load_position_into(POSITION_KEY, panel)


# Invite always targets whoever you currently have selected (same as typing
# /invite) — targeting is the whole point of these buttons existing rather
# than, say, a text-entry name field.
func _on_invite_pressed() -> void:
	if is_instance_valid(_player) and _player.has_method("invite_to_group"):
		_player.invite_to_group(_player.current_target)


# Disband with a target selected kicks just that member; with nothing
# selected, disbands the whole group — same rule as /disband.
func _on_disband_pressed() -> void:
	if is_instance_valid(_player) and _player.has_method("disband_or_kick_from_group"):
		_player.disband_or_kick_from_group(_player.current_target)


func _style_bar(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)

	var back := StyleBoxFlat.new()
	back.bg_color = bg_color
	back.border_color = Color(0, 0, 0, 0.5)
	back.set_border_width_all(1)
	back.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", back)


# Left-click a row to target yourself or your pet directly — the healer's way
# to practice single-target heals/buffs on party members before real other
# players exist to click on.
func _on_row_clicked(event: InputEvent, who: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not is_instance_valid(_player):
		return
	if who == "player":
		_player.current_target = _player
	else:
		var pet = _player.get("active_pet")
		if is_instance_valid(pet):
			_player.current_target = pet
	if _player.has_method("_announce_target"):
		_player._announce_target(_player.current_target)


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
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		_player = players[0]

	if not ("combat_node" in _player):
		return
	_player_name_label.text = _player.player_name if "player_name" in _player else "Player"

	var cn = _player.combat_node
	_player_hp_bar.max_value = cn.max_hp
	_player_hp_bar.value     = cn.current_hp
	_player_mp_bar.max_value = cn.max_mana
	_player_mp_bar.value     = cn.current_mana

	var pet = _player.get("active_pet")
	if is_instance_valid(pet):
		_pet_wrapper.visible = true
		_pet_name_label.text = pet.pet_name
		var pcn = pet.combat_node
		_pet_hp_bar.max_value = pcn.max_hp
		_pet_hp_bar.value     = pcn.current_hp
		_pet_mp_bar.max_value = pcn.max_mana
		_pet_mp_bar.value     = pcn.current_mana
	else:
		_pet_wrapper.visible = false
