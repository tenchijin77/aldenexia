extends CanvasLayer

const SLOT_SIZE := Vector2(48, 48)

var slot_buttons: Array = []
var visible_slots: Array = []

@onready var search_bar = $Panel/MarginContainer/VBoxContainer/SearchBar
@onready var slot_count_label = $Panel/MarginContainer/VBoxContainer/SlotCountLabel
@onready var slot_container = $Panel/MarginContainer/VBoxContainer/ScrollContainer/SlotGrid

func _ready():
	if search_bar:
		search_bar.text_changed.connect(_on_search_text_changed)
	if Inventory.inventory_changed.is_connected(_on_inventory_changed) == false:
		Inventory.inventory_changed.connect(_on_inventory_changed)
	refresh_backpack()

func refresh_backpack():
	clear_slots()
	var total_slots = Inventory.calculate_total_bag_slots()
	slot_count_label.text = "Bag Slots: %d" % total_slots
	create_slots(total_slots)
	populate_slots()

func clear_slots():
	for s in slot_buttons:
		if is_instance_valid(s):
			s.queue_free()
	slot_buttons.clear()
	visible_slots.clear()

func create_slots(count: int):
	for i in range(count):
		var slot_button = load("res://Scripts/slot_button.gd").new()
		slot_button.custom_minimum_size = SLOT_SIZE
		slot_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		slot_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		style.set_border_width_all(1)
		slot_button.add_theme_stylebox_override("normal", style)

		slot_button.slot_type = "bag"
		slot_button.slot_index = i
		slot_button.bag_slot = -1
		slot_button.item_index = -1
		slot_button.item_data = {}

		slot_container.add_child(slot_button)
		slot_buttons.append(slot_button)
		visible_slots.append(slot_button)

func populate_slots():
	var slot_index = 0

	for bag_slot in range(Inventory.BASIC_INVENTORY_SIZE):
		var bag = Inventory.basic_inventory[bag_slot]
		if bag == null or not Inventory.is_bag(bag):
			continue

		var bag_items = Inventory.get_bag_contents(bag_slot)

		for item_i in range(bag_items.size()):
			if slot_index >= slot_buttons.size():
				return

			var item = bag_items[item_i]
			var slot = slot_buttons[slot_index]

			slot.slot_type = "bag"
			slot.bag_slot = bag_slot
			slot.slot_index = slot_index
			slot.item_index = item_i
			slot.item_data = item

			if item.has("icon") and item.icon is String and FileAccess.file_exists(item.icon):
				slot.texture_normal = load(item.icon)
			else:
				slot.texture_normal = null

			slot.tooltip_text = item.get("name", "Unknown Item")

			if item.get("stackable", false):
				_add_quantity_label(slot, item.get("quantity", 1))

			slot_index += 1

func _add_quantity_label(slot: TextureButton, qty: int):
	var label = Label.new()
	label.text = str(qty)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.position = Vector2(2, 2)
	slot.add_child(label)

func _on_search_text_changed(new_text: String):
	var term = new_text.to_lower()

	for slot in visible_slots:
		if slot.item_data == {}:
			slot.visible = true
			continue

		var name = slot.item_data.get("name", "").to_lower()
		slot.visible = term in name

func _on_inventory_changed():
	refresh_backpack()
