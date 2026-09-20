# give_window.gd — Small EQ-style "hand something to an NPC" window. Drag an
# item from your bags into the slot, press Give. The NPC decides what to do
# with it (see KenjiNPC.try_give()); this window only shows what's offered and
# never moves anything out of your inventory itself. Closes on its own if you
# walk away from the NPC. Built in code, same pattern as the other HUD windows.
extends CanvasLayer
class_name GiveWindow

const CLOSE_DISTANCE := 8.0

var _npc: Node3D = null
var _player: Node3D = null
var _offered_id := ""
var _offered_item: Dictionary = {}
var _progress_label: Label

var _slot_icon: TextureRect
var _slot_label: Label
var _status_label: Label


func setup(npc: Node3D, player: Node3D) -> void:
	_npc = npc
	_player = player
	layer = 12

	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -170
	panel.offset_right = 170
	panel.offset_top = -140
	panel.offset_bottom = 140
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.06, 0.97)
	bg.border_color = Color(0.45, 0.38, 0.25)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Give to %s" % str(_npc.get("npc_name"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Drag an item from your bags into the slot, then press Give."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vbox.add_child(hint)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 11)
	_progress_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	vbox.add_child(_progress_label)
	_refresh_progress()

	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(72, 72)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var slot_bg := StyleBoxFlat.new()
	slot_bg.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	slot_bg.border_color = Color(0.55, 0.5, 0.35)
	slot_bg.set_border_width_all(2)
	slot_bg.set_corner_radius_all(3)
	slot.add_theme_stylebox_override("panel", slot_bg)
	slot.set_drag_forwarding(Callable(), _can_drop, _on_drop)
	vbox.add_child(slot)

	_slot_icon = TextureRect.new()
	_slot_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_icon.offset_left = 4
	_slot_icon.offset_top = 4
	_slot_icon.offset_right = -4
	_slot_icon.offset_bottom = -4
	_slot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_slot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(_slot_icon)

	_slot_label = Label.new()
	_slot_label.text = "(empty)"
	_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_slot_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	vbox.add_child(_status_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons)
	var give_btn := Button.new()
	give_btn.text = "Give"
	give_btn.custom_minimum_size = Vector2(90, 28)
	give_btn.pressed.connect(_on_give_pressed)
	buttons.add_child(give_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(90, 28)
	close_btn.pressed.connect(queue_free)
	buttons.add_child(close_btn)


func _process(_delta: float) -> void:
	if not is_instance_valid(_npc) or not is_instance_valid(_player) \
			or _player.global_position.distance_to(_npc.global_position) > CLOSE_DISTANCE:
		queue_free()


func _can_drop(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("item_data") \
			and data.get("slot_type", "") in ["basic", "bag"]


func _on_drop(_at_position: Vector2, data: Variant) -> void:
	var item: Dictionary = data["item_data"]
	_offered_item = item
	_offered_id = str(item.get("item_id", ""))
	var icon_path: String = str(item.get("icon", ""))
	_slot_icon.texture = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
	_status_label.text = ""
	_refresh_label(item)


func _refresh_label(item: Dictionary) -> void:
	var have: int = KenjiNPC.count_item(_offered_id)
	_slot_label.text = "%s  (you have %d)" % [str(item.get("name", _offered_id)), have]


func _on_give_pressed() -> void:
	if _offered_id.is_empty():
		_status_label.text = "Drag an item into the slot first."
		return
	if _npc.has_method("try_give") and _npc.try_give(_offered_id, _player):
		queue_free()
		return
	# Partial hand-in (or refused): stay open with fresh counts.
	_refresh_progress()
	if not _offered_item.is_empty():
		_refresh_label(_offered_item)


# Shows the NPC's running tally, if it keeps one (Kenji does).
func _refresh_progress() -> void:
	if _npc.has_method("progress_summary"):
		_progress_label.text = _npc.progress_summary()
