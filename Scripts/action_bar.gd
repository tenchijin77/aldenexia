# action_bar.gd — Bottom-center HUD bar showing ability slots (spells + skills)
# Arranging: drag an ability from the Abilities Book onto a slot to place it; drag a slot onto another slot to MOVE it (if the other slot
# has something, the two swap); drag a slot off the bar (drop it anywhere that is not a slot) to REMOVE it. A slot fires on mouse-RELEASE,
# so picking one up to drag it does not cast it.
extends CanvasLayer
class_name ActionBar


# One slot of the bar. A plain Panel cannot receive the "drag ended" notification, so the slot is its own small class.
class ActionSlot extends Panel:
	var bar: ActionBar = null
	var index := 0

	func _get_drag_data(_at: Vector2) -> Variant:
		return bar._begin_slot_drag(index, self)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("type") and data.has("name")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		bar._on_slot_drop(index, data)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END and bar != null:
			bar._on_any_drag_end(get_viewport().gui_is_drag_successful())


const SLOT_COUNT  := 12
const SLOT_SIZE   := 62
const SLOT_GAP    := 4

var _slots: Array[Dictionary] = []
var _player: Node = null
var _slot_panels: Array[Control] = []
var _panel: Panel = null
var _dragging := false
var _drag_from := -1   # the slot being dragged right now (-1: none, or the drag came from the Abilities Book)


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

		var slot_panel := ActionSlot.new()
		slot_panel.bar = self
		slot_panel.index = i
		slot_panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot_panel.mouse_filter = Control.MOUSE_FILTER_PASS

		var bg := StyleBoxFlat.new()
		bg.bg_color      = Color(0.08, 0.08, 0.12, 0.92)
		bg.border_color  = Color(0.35, 0.35, 0.45)
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(3)
		slot_panel.add_theme_stylebox_override("panel", bg)

		# Spell icon (added first so every label/overlay below draws on top)
		var icon_rect := TextureRect.new()
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.offset_left   = 2
		icon_rect.offset_top    = 2
		icon_rect.offset_right  = -2
		icon_rect.offset_bottom = -2
		icon_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.visible = false
		slot_panel.add_child(icon_rect)

		# Key number label (top-left)
		var key_lbl := Label.new()
		key_lbl.text = key_text
		key_lbl.add_theme_font_size_override("font_size", 10)
		key_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
		key_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		key_lbl.add_theme_constant_override("outline_size", 3)
		key_lbl.position = Vector2(3, 2)
		key_lbl.size     = Vector2(14, 14)
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(key_lbl)

		# Type badge (top-right: "S" spell, "K" skill)
		var type_lbl := Label.new()
		type_lbl.add_theme_font_size_override("font_size", 9)
		type_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
		type_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		type_lbl.add_theme_constant_override("outline_size", 3)
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

		# Stop clicks here so they don't bubble up and drag the whole bar
		slot_panel.mouse_filter = Control.MOUSE_FILTER_STOP

		# Left-click fires the slotted ability — on RELEASE, so that pressing and dragging (to move or remove it) does not cast it
		var slot_idx := i
		slot_panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton \
					and event.button_index == MOUSE_BUTTON_LEFT \
					and not event.pressed:
				_activate_slot(slot_idx)
		)

		hbox.add_child(slot_panel)
		_slot_panels.append(slot_panel)

		_slots.append({
			"icon_rect":  icon_rect,
			"name_lbl":   name_lbl,
			"type_lbl":   type_lbl,
			"cd_overlay": cd_overlay,
			"cd_lbl":     cd_lbl,
			"bg":         bg,
			"type":       "",
			"ability":    "",
		})

	_load_position()


func _activate_slot(idx: int) -> void:
	var atype: String = _slots[idx]["type"]
	var aname: String = _slots[idx]["ability"]
	if aname.is_empty() or not is_instance_valid(_player):
		return

	# Brief highlight flash
	var bg: StyleBoxFlat = _slots[idx]["bg"]
	var orig_color := bg.bg_color
	bg.bg_color = Color(0.35, 0.35, 0.55, 0.95)
	get_tree().create_timer(0.08).timeout.connect(func(): bg.bg_color = orig_color)

	match atype:
		"spell": _player.cast_spell(aname)
		"skill": _player.use_skill(aname)


func _on_slot_drop(idx: int, data: Dictionary) -> void:
	var atype: String = data.get("type", "")
	var aname: String = data.get("name", "")
	var from_slot := int(data.get("from_slot", -1))
	if from_slot >= 0 and from_slot < SLOT_COUNT:
		if from_slot == idx:
			return
		# a slot dragged onto another one: they trade places (an empty target simply receives it)
		_set_slot(from_slot, _slots[idx]["type"], _slots[idx]["ability"])
	_set_slot(idx, atype, aname)


func _set_slot(idx: int, atype: String, aname: String) -> void:
	_slots[idx]["type"]    = atype
	_slots[idx]["ability"] = aname
	_slots[idx]["cd_overlay"].visible = false
	_slots[idx]["cd_lbl"].visible     = false
	_update_slot_display(idx)
	# Persist to player's action_bar_slots
	if is_instance_valid(_player) and "action_bar_slots" in _player:
		while _player.action_bar_slots.size() <= idx:
			_player.action_bar_slots.append({"type": "", "name": ""})
		_player.action_bar_slots[idx] = {"type": atype, "name": aname}


# Picking a slot up: the payload is what the Abilities Book gives (type + name) plus where it came from.
func _begin_slot_drag(idx: int, slot: Control) -> Variant:
	var atype: String = _slots[idx]["type"]
	var aname: String = _slots[idx]["ability"]
	if aname.is_empty():
		return null
	_drag_from = idx
	var icon_rect: TextureRect = _slots[idx]["icon_rect"]
	if icon_rect.texture != null:
		var preview := TextureRect.new()
		preview.texture = icon_rect.texture
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.custom_minimum_size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 8)
		preview.size = preview.custom_minimum_size
		preview.modulate = Color(1, 1, 1, 0.85)
		slot.set_drag_preview(preview)
	else:
		var label := Label.new()
		label.text = Player3D.spell_display_name(aname)
		label.add_theme_font_size_override("font_size", 12)
		slot.set_drag_preview(label)
	return {"type": atype, "name": aname, "from_slot": idx}


# Every slot hears "a drag ended". If it was one of OUR slots being dragged and nothing accepted it (it was let go off the bar), the
# ability is taken off the bar.
func _on_any_drag_end(accepted: bool) -> void:
	if _drag_from < 0:
		return
	var idx := _drag_from
	_drag_from = -1
	if not accepted:
		_set_slot(idx, "", "")


func _update_slot_display(i: int) -> void:
	var atype: String   = _slots[i]["type"]
	var aname: String   = _slots[i]["ability"]
	var name_lbl: Label = _slots[i]["name_lbl"]
	var type_lbl: Label = _slots[i]["type_lbl"]
	var bg: StyleBoxFlat = _slots[i]["bg"]
	var icon_rect: TextureRect = _slots[i]["icon_rect"]
	var slot_panel: Control = _slot_panels[i]

	# Reset the icon/tooltip each time — refilled below for spells that have them.
	icon_rect.texture = null
	icon_rect.visible = false
	slot_panel.tooltip_text = ""

	if aname.is_empty():
		name_lbl.text     = ""
		type_lbl.text     = ""
		bg.border_color   = Color(0.35, 0.35, 0.45)
		return

	var display := Player3D.spell_display_name(aname)
	if display.length() > 12:
		var parts := display.split(" ", true, 1)
		display = "\n".join(parts)
	name_lbl.text = display

	# Spells show their icon (name label hidden — the tooltip carries the name
	# and description). Spells with no icon in player_spells.json, and skills,
	# keep the text label.
	if atype == "spell":
		var spell_db: Dictionary = _player.get("_spell_by_name") if is_instance_valid(_player) and "_spell_by_name" in _player else {}
		var info: Dictionary = spell_db.get(aname, {})
		slot_panel.tooltip_text = SpellInfo.tooltip(aname, info)
		var tex := SpellInfo.icon_texture(info)
		if tex != null:
			icon_rect.texture = tex
			icon_rect.visible = true
			name_lbl.text = ""

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
		_player = TargetFrame.local_player()
		if not is_instance_valid(_player):
			return
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
