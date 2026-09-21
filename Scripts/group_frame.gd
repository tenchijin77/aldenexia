# group_frame.gd — Party frame: one row per group member (name + HP + MP),
# each with their own pet listed slightly smaller beneath if they have one
# out. Built as a fixed pool of MAX_ROWS row widgets, shown/hidden each frame
# to match the player's live group_members — cheap and avoids rebuilding the
# UI every time someone joins/leaves. Click any row (player or pet) to target
# it directly — the healer's way to heal/buff a specific group member.
extends CanvasLayer
class_name GroupFrame

const POSITION_KEY := "group_frame"
const MAX_ROWS := 6  # matches player3d.gd's MAX_GROUP_SIZE
const RESIZE_MARGIN := 16.0
const MIN_WIDTH := 180.0
const MIN_HEIGHT := 150.0

var _player: Node = null
var _panel: Panel = null
var _dragging := false
var _resizing := false

# One entry per row: {wrapper, name_label, hp_bar, mp_bar, pet_wrapper,
# pet_name_label, pet_hp_bar, pet_mp_bar}
var _member_rows: Array = []


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
	# Tall enough for a full 6-member group each with a pet out; empty/hidden
	# rows just leave blank space at the bottom rather than the panel
	# resizing dynamically (Panel doesn't auto-fit VBoxContainer content).
	panel.offset_bottom = 185 + 400
	panel.gui_input.connect(_on_panel_gui_input)
	_panel = panel
	add_child(panel)

	panel.add_theme_stylebox_override("panel", Global.window_bg_style())

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  6
	vbox.offset_top    =  4
	vbox.offset_right  = -6
	vbox.offset_bottom = -4
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Group"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
	vbox.add_child(title)

	for i in range(MAX_ROWS):
		_member_rows.append(_build_member_row(vbox))

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

	WindowPosition.load_full_into(POSITION_KEY, panel)


# Builds one member row (name/hp/mp + a nested, initially-hidden pet
# sub-row) and appends it to `parent`. Returns the dictionary of refs
# _process() needs to keep it updated.
func _build_member_row(parent: VBoxContainer) -> Dictionary:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	parent.add_child(wrapper)

	var name_label := Label.new()
	name_label.text = "Player"
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	wrapper.add_child(name_label)

	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 10)
	hp_bar.show_percentage = false
	_style_bar(hp_bar, Color(0.8, 0.15, 0.15), Color(0.12, 0.05, 0.05))
	wrapper.add_child(hp_bar)

	var mp_bar := ProgressBar.new()
	mp_bar.custom_minimum_size = Vector2(0, 8)
	mp_bar.show_percentage = false
	_style_bar(mp_bar, Color(0.2, 0.35, 0.9), Color(0.05, 0.06, 0.12))
	wrapper.add_child(mp_bar)

	var pet_wrapper := MarginContainer.new()
	pet_wrapper.add_theme_constant_override("margin_left", 14)
	pet_wrapper.visible = false
	wrapper.add_child(pet_wrapper)

	var pet_col := VBoxContainer.new()
	pet_col.add_theme_constant_override("separation", 2)
	pet_wrapper.add_child(pet_col)

	var pet_name_label := Label.new()
	pet_name_label.text = "Pet"
	pet_name_label.add_theme_font_size_override("font_size", 9)
	pet_name_label.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))
	pet_name_label.clip_text = true
	pet_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pet_name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	pet_col.add_child(pet_name_label)

	var pet_hp_bar := ProgressBar.new()
	pet_hp_bar.custom_minimum_size = Vector2(0, 7)
	pet_hp_bar.show_percentage = false
	_style_bar(pet_hp_bar, Color(0.8, 0.15, 0.15), Color(0.12, 0.05, 0.05))
	pet_col.add_child(pet_hp_bar)

	var pet_mp_bar := ProgressBar.new()
	pet_mp_bar.custom_minimum_size = Vector2(0, 6)
	pet_mp_bar.show_percentage = false
	_style_bar(pet_mp_bar, Color(0.2, 0.35, 0.9), Color(0.05, 0.06, 0.12))
	pet_col.add_child(pet_mp_bar)

	var row := {
		"wrapper": wrapper,
		"name_label": name_label,
		"hp_bar": hp_bar,
		"mp_bar": mp_bar,
		"pet_wrapper": pet_wrapper,
		"pet_name_label": pet_name_label,
		"pet_hp_bar": pet_hp_bar,
		"pet_mp_bar": pet_mp_bar,
		"member": null,
		"pet": null,
	}
	name_label.gui_input.connect(func(e): _on_row_clicked(e, row, "member"))
	pet_name_label.gui_input.connect(func(e): _on_row_clicked(e, row, "pet"))
	return row


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


# Left-click a row to target that member or their pet directly — the
# healer's way to heal/buff a specific group member without needing to find
# and click their character in the world.
func _on_row_clicked(event: InputEvent, row: Dictionary, part: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not is_instance_valid(_player):
		return
	var target: Node = row["member"] if part == "member" else row["pet"]
	if not is_instance_valid(target):
		return
	if Input.is_key_pressed(KEY_SHIFT) and _player.has_method("set_focus"):
		_player.set_focus(target)   # Shift-click a group row: make them your focus
		return
	_player.current_target = target
	if _player.has_method("_announce_target"):
		_player._announce_target(target)


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos: Vector2 = event.position
			if pos.x > _panel.size.x - RESIZE_MARGIN and pos.y > _panel.size.y - RESIZE_MARGIN:
				_resizing = true
			else:
				_dragging = true
		else:
			if _dragging or _resizing:
				WindowPosition.save(POSITION_KEY, _panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _resizing:
			_panel.offset_right  = max(_panel.offset_left + MIN_WIDTH, _panel.offset_right + event.relative.x)
			_panel.offset_bottom = max(_panel.offset_top + MIN_HEIGHT, _panel.offset_bottom + event.relative.y)
		elif _dragging:
			_panel.offset_left   += event.relative.x
			_panel.offset_top    += event.relative.y
			_panel.offset_right  += event.relative.x
			_panel.offset_bottom += event.relative.y


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = TargetFrame.local_player()
		if not is_instance_valid(_player):
			return

	if not ("group_members" in _player):
		return

	var group_members: Array = _player.group_members

	for i in range(MAX_ROWS):
		var row: Dictionary = _member_rows[i]
		if i >= group_members.size():
			row["wrapper"].visible = false
			row["member"] = null
			row["pet"] = null
			continue

		var member: Node = _player._peer_id_to_player_node(group_members[i]) if _player.has_method("_peer_id_to_player_node") else null
		if not is_instance_valid(member):
			# Grouped but not currently resolvable here (different zone,
			# not yet connected, etc.) — keep the slot hidden rather than
			# showing stale/empty bars.
			row["wrapper"].visible = false
			row["member"] = null
			row["pet"] = null
			continue

		row["wrapper"].visible = true
		row["member"] = member

		row["name_label"].text = member.player_name if "player_name" in member else "Player"
		# current_hp/max_hp/current_mana/max_mana now replicate for every
		# player (see player3d.tscn's SceneReplicationConfig) — cn should
		# never actually be null for a real player anymore, but the empty-bars
		# fallback stays as a harmless guard (e.g. a frame before a freshly
		# spawned puppet's _ready() has run).
		var cn = member.get("combat_node") if "combat_node" in member else null
		if cn != null:
			row["hp_bar"].max_value = cn.max_hp
			row["hp_bar"].value     = cn.current_hp
			row["mp_bar"].max_value = cn.max_mana
			row["mp_bar"].value     = cn.current_mana
		else:
			row["hp_bar"].max_value = 1
			row["hp_bar"].value     = 0
			row["mp_bar"].max_value = 1
			row["mp_bar"].value     = 0

		var pet = member.get("active_pet") if "active_pet" in member else null
		if is_instance_valid(pet):
			row["pet"] = pet
			row["pet_wrapper"].visible = true
			row["pet_name_label"].text = pet.pet_name
			var pcn = pet.combat_node
			row["pet_hp_bar"].max_value = pcn.max_hp
			row["pet_hp_bar"].value     = pcn.current_hp
			row["pet_mp_bar"].max_value = pcn.max_mana
			row["pet_mp_bar"].value     = pcn.current_mana
		else:
			row["pet"] = null
			row["pet_wrapper"].visible = false
