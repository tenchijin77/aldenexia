#slot_button.gd - creates the drag and drop bag slots
extends TextureButton

var slot_type: String = ""
var slot_index: int = -1
var bag_slot: int = -1
var item_index: int = -1
var item_data: Dictionary = {}

var _rclick_active: bool = false
var _rclick_timer: float = 0.0
const INSPECT_HOLD_TIME: float = 1.0

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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and not item_data.is_empty():
			_rclick_active = true
			_rclick_timer = 0.0
		else:
			_rclick_active = false
			_rclick_timer = 0.0

func _process(delta: float) -> void:
	if _rclick_active:
		_rclick_timer += delta
		if _rclick_timer >= INSPECT_HOLD_TIME:
			_rclick_active = false
			_rclick_timer = 0.0
			_show_inspect_popup()

func _show_inspect_popup() -> void:
	var existing = get_tree().root.get_node_or_null("ItemInspectPopup")
	if existing:
		existing.queue_free()

	var popup = Panel.new()
	popup.name = "ItemInspectPopup"
	popup.custom_minimum_size = Vector2(300, 100)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)

	var title = Label.new()
	title.text = item_data.get("name", "Unknown Item")
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(title)

	var desc = Label.new()
	desc.text = item_data.get("description", "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	if item_data.has("lore") and item_data["lore"] != "":
		var lore = Label.new()
		lore.text = "\n" + item_data["lore"]
		lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lore.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		vbox.add_child(lore)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): popup.queue_free())
	vbox.add_child(close_btn)

	popup.add_child(vbox)
	popup.position = get_global_mouse_position() + Vector2(10, 10)
	get_tree().root.add_child(popup)

func get_drag_data(position):
	if item_data.is_empty():
		return null
	var payload := {
		"item_data": item_data,
		"slot_type": slot_type,
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

func can_drop_data(position, data):
	return typeof(data) == TYPE_DICTIONARY and data.has("item_data")

func drop_data(position, data):
	Inventory.move_item_between_slots(self, data)
