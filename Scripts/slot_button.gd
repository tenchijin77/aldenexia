#slot_button.gd - creates the drag and drop bag slots
extends TextureButton

var slot_type: String = ""
var slot_name: String = ""
var slot_index: int = -1
var bag_slot: int = -1
var item_index: int = -1
var item_data: Dictionary = {}

func _ready():
	custom_minimum_size = Vector2(48, 48)
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.15, 0.15, 0.9))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.5, 0.5, 1.0), false, 1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed and not item_data.is_empty():
		var equip_slot: String = Inventory.ITEM_SLOT_MAP.get(item_data.get("slot", ""), "")
		if not equip_slot.is_empty():
			Inventory.equip_item(item_data, slot_type, slot_index, bag_slot, item_index)
		else:
			_show_inspect_popup()

func _show_inspect_popup() -> void:
	var root = get_tree().root
	var existing = root.get_node_or_null("ItemInspectLayer")
	if existing:
		existing.queue_free()

	var layer := CanvasLayer.new()
	layer.name = "ItemInspectLayer"
	layer.layer = 10

	var popup := Panel.new()
	popup.custom_minimum_size = Vector2(300, 100)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)

	var title := Label.new()
	title.text = item_data.get("name", "Unknown Item")
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = item_data.get("description", "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	if item_data.has("lore") and item_data["lore"] != "":
		var lore := Label.new()
		lore.text = "\n" + item_data["lore"]
		lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lore.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		vbox.add_child(lore)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): layer.queue_free())
	vbox.add_child(close_btn)

	popup.add_child(vbox)
	popup.position = get_global_mouse_position() + Vector2(10, 10)
	layer.add_child(popup)
	root.add_child(layer)

func _get_drag_data(at_position: Vector2) -> Variant:
	if item_data.is_empty():
		return null
	var payload := {
		"item_data": item_data,
		"slot_type": slot_type,
		"slot_name": slot_name,
		"slot_index": slot_index,
		"bag_slot": bag_slot,
		"item_index": item_index
	}
	var preview := TextureRect.new()
	if item_data.has("icon") and item_data.get("icon") is String and FileAccess.file_exists(item_data.get("icon", "")):
		preview.texture = load(item_data.get("icon"))
	preview.custom_minimum_size = Vector2(48, 48)
	preview.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(preview)
	return payload

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.get("slot_type") == "loot":
		return not data.get("item_id", "").is_empty()
	if slot_type == "equipment":
		var item: Dictionary = data.get("item_data", {})
		var target: String = Inventory.ITEM_SLOT_MAP.get(item.get("slot", "none"), "")
		return target == slot_name
	return data.has("item_data")

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if data.get("slot_type") == "loot":
		var item_id: String = data.get("item_id", "")
		if item_id.is_empty():
			return
		if Inventory.add_to_basic_inventory(item_id):
			var window = data.get("loot_window")
			if is_instance_valid(window):
				window.consume_loot(data.get("loot_drop"))
	elif slot_type == "equipment":
		Inventory.equip_item(
			data.get("item_data", {}),
			data.get("slot_type", ""),
			data.get("slot_index", -1),
			data.get("bag_slot", -1),
			data.get("item_index", -1)
		)
	elif data.get("slot_type") == "equipment":
		Inventory.unequip_item(data.get("slot_name", ""))
	else:
		Inventory.move_item_between_slots(self, data)
