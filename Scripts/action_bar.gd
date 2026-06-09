# action_bar.gd — Bottom-center HUD bar showing ability slots (spells + skills)
extends CanvasLayer
class_name ActionBar

const SLOT_COUNT  := 12
const SLOT_SIZE   := 62
const SLOT_GAP    := 4

var _slots: Array[Dictionary] = []
var _player: Node = null
var _slot_panels: Array[Control] = []
var _panel: Panel = null
var _dragging := false


func _ready() -> void:
	layer = 4
	_build_ui()


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
	ui["action_bar"] = [_panel.offset_left, _panel.offset_top, _panel.offset_right, _panel.offset_bottom]
	Global.player_data["ui_positions"] = ui
	Global.save_player_data_to_file()


func _load_position() -> void:
	var pos: Array = Global.player_data.get("ui_positions", {}).get("action_bar", [])
	if pos.size() == 4:
		_panel.offset_left   = pos[0]
		_panel.offset_top    = pos[1]
		_panel.offset_right  = pos[2]
		_panel.offset_bottom = pos[3]


func _build_ui() -> void:
	var total_w := SLOT_SIZE * SLOT_COUNT + SLOT_GAP * (SLOT_COUNT - 1) + 12

	var panel := Panel.new()
	panel.anchor_left   = 0.5
	panel.anchor_top    = 1.0
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 1.0
	panel.offset_left   = -total_w / 2.0
	panel.offset_top    = -(SLOT_SIZE + 16)
	panel.offset_right  =  total_w / 2.0
	panel.offset_bottom = -4.0
	panel.gui_input.connect(_on_panel_gui_input)
	_panel = panel
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left   =  6
	hbox.offset_top    =  4
	hbox.offset_right  = -6
	hbox.offset_bottom = -4
	hbox.add_theme_constant_override("separation", SLOT_GAP)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(hbox)

	const KEY_LABELS: Array[String] = ["1","2","3","4","5","6","7","8","9","0","-","="]

	for i in range(SLOT_COUNT):
		var key_text: String = KEY_LABELS[i]

		var slot_panel := Panel.new()
		slot_panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot_panel.mouse_filter = Control.MOUSE_FILTER_PASS

		var bg := StyleBoxFlat.new()
		bg.bg_color      = Color(0.08, 0.08, 0.12, 0.92)
		bg.border_color  = Color(0.35, 0.35, 0.45)
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(3)
		slot_panel.add_theme_stylebox_override("panel", bg)

		# Key number label (top-left)
		var key_lbl := Label.new()
		key_lbl.text = key_text
		key_lbl.add_theme_font_size_override("font_size", 10)
		key_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
		key_lbl.position = Vector2(3, 2)
		key_lbl.size     = Vector2(14, 14)
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(key_lbl)

		# Type badge (top-right: "S" spell, "K" skill)
		var type_lbl := Label.new()
		type_lbl.add_theme_font_size_override("font_size", 9)
		type_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
		type_lbl.anchor_right  = 1.0
		type_lbl.offset_right  = -3.0
		type_lbl.offset_top    = 2.0
		type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(type_lbl)

		# Ability name label (centered)
		var name_lbl := Label.new()
		name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		name_lbl.offset_top    =  14
		name_lbl.offset_bottom = -14
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode         = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(name_lbl)

		# Cooldown overlay
		var cd_overlay := ColorRect.new()
		cd_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd_overlay.color        = Color(0, 0, 0, 0.65)
		cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_overlay.visible      = false
		slot_panel.add_child(cd_overlay)

		# Cooldown timer label
		var cd_lbl := Label.new()
		cd_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd_lbl.add_theme_font_size_override("font_size", 13)
		cd_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.15))
		cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		cd_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		cd_lbl.visible              = false
		slot_panel.add_child(cd_lbl)

		# Wire drop target
		var slot_idx := i
		slot_panel.set_drag_forwarding(
			Callable(),
			func(_pos, data): return typeof(data) == TYPE_DICTIONARY and data.has("type") and data.has("name"),
			func(_pos, data): _on_slot_drop(slot_idx, data)
		)

		hbox.add_child(slot_panel)
		_slot_panels.append(slot_panel)

		_slots.append({
			"name_lbl":   name_lbl,
			"type_lbl":   type_lbl,
			"cd_overlay": cd_overlay,
			"cd_lbl":     cd_lbl,
			"bg":         bg,
			"type":       "",
			"ability":    "",
		})

	_load_position()


func _on_slot_drop(idx: int, data: Dictionary) -> void:
	var atype: String = data.get("type", "")
	var aname: String = data.get("name", "")
	_slots[idx]["type"]    = atype
	_slots[idx]["ability"] = aname
	_update_slot_display(idx)

	# Persist to player's action_bar_slots
	if is_instance_valid(_player) and "action_bar_slots" in _player:
		_player.action_bar_slots[idx] = {"type": atype, "name": aname}


func _update_slot_display(i: int) -> void:
	var atype: String   = _slots[i]["type"]
	var aname: String   = _slots[i]["ability"]
	var name_lbl: Label = _slots[i]["name_lbl"]
	var type_lbl: Label = _slots[i]["type_lbl"]
	var bg: StyleBoxFlat = _slots[i]["bg"]

	if aname.is_empty():
		name_lbl.text     = ""
		type_lbl.text     = ""
		bg.border_color   = Color(0.35, 0.35, 0.45)
		return

	var display := aname.replace("_", " ").capitalize()
	if display.length() > 12:
		var parts := display.split(" ", true, 1)
		display = "\n".join(parts)
	name_lbl.text = display

	match atype:
		"spell":
			type_lbl.text   = "S"
			bg.border_color = Color(0.55, 0.45, 0.25)   # gold — spell
		"skill":
			type_lbl.text   = "K"
			bg.border_color = Color(0.3, 0.55, 0.3)     # green — skill
		_:
			type_lbl.text   = ""
			bg.border_color = Color(0.35, 0.35, 0.45)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		_player = players[0]
		_refresh_slots()
		return

	var spell_cds: Dictionary = _player.get("_spell_cooldowns") if "_spell_cooldowns" in _player else {}
	var skill_cds: Dictionary = _player.get("_skill_cooldowns") if "_skill_cooldowns" in _player else {}

	for i in range(SLOT_COUNT):
		var atype: String  = _slots[i]["type"]
		var aname: String  = _slots[i]["ability"]
		if aname.is_empty():
			continue
		var cd: float = spell_cds.get(aname, 0.0) if atype == "spell" else skill_cds.get(aname, 0.0)
		var on_cd := cd > 0.01
		_slots[i]["cd_overlay"].visible = on_cd
		_slots[i]["cd_lbl"].visible     = on_cd
		if on_cd:
			_slots[i]["cd_lbl"].text = "%.1f" % cd


func _refresh_slots() -> void:
	var bar: Array = _player.get("action_bar_slots") if "action_bar_slots" in _player else []
	for i in range(SLOT_COUNT):
		if i < bar.size():
			var slot: Dictionary = bar[i]
			_slots[i]["type"]    = slot.get("type", "")
			_slots[i]["ability"] = slot.get("name", "")
		else:
			_slots[i]["type"]    = ""
			_slots[i]["ability"] = ""
		_update_slot_display(i)
