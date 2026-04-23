# backpack_ui.gd
extends CanvasLayer

#region UI References
@onready var search_bar = $Panel/MarginContainer/VBoxContainer/SearchBar
@onready var slot_container = $Panel/MarginContainer/VBoxContainer/ScrollContainer/SlotGrid
@onready var slot_count_label = $Panel/MarginContainer/VBoxContainer/SlotCountLabel
#endregion

#region Slot Management
var slot_buttons: Array = []  # All created slot buttons
var visible_slots: Array = []  # Currently visible slots (after filtering)
const SLOT_SIZE = Vector2(48, 48)  # Size of each inventory slot
#endregion

#region Search State
var current_search: String = ""
#endregion

func _ready():
	print("✅ Backpack UI _ready()")

	# Connect search bar
	if search_bar:
		search_bar.text_changed.connect(_on_search_text_changed)

		# Initial refresh
		refresh_backpack()

		func refresh_backpack():
			"""Rebuilds the entire backpack UI based on equipped bags"""
			clear_slots()

			# Calculate total bag slots from Inventory autoload
			var total_slots = Inventory.calculate_total_bag_slots()

			# Update slot count label
			if slot_count_label:
				slot_count_label.text = "Bag Slots: %d" % total_slots

			# Create slot buttons
			create_slots(total_slots)

			# Populate with items
			populate_slots()

			# Apply search filter if active
			if current_search.length() > 0:
				apply_search_filter(current_search)

				func clear_slots():
	"""Removes all existing slot buttons"""
			for slot in slot_buttons:
				slot.queue_free()
				slot_buttons.clear()
				visible_slots.clear()

				func create_slots(count: int):
	"""Creates the specified number of slot buttons"""
	for i in range(count):
		var slot_button = TextureButton.new()
		slot_button.custom_minimum_size = SLOT_SIZE
		slot_button.expand_mode = TextureButton.EXPAND_IGNORE_SIZE
		slot_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED

		# Style the button (you can customize this)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.2, 0.8)  # Semi-transparent dark
		style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		style.set_border_width_all(1)
		slot_button.add_theme_stylebox_override("normal", style)

		# Store slot index as metadata
		slot_button.set_meta("slot_index", i)

		# Connect click event
		slot_button.pressed.connect(_on_slot_clicked.bind(i))

		# Add to container
		slot_container.add_child(slot_button)
		slot_buttons.append(slot_button)
		visible_slots.append(slot_button)

		func populate_slots():
	"""Fills slots with items from bag contents"""
	var slot_index = 0

	# Iterate through all bags in basic inventory
	for bag_slot in range(Inventory.BASIC_INVENTORY_SIZE):
		var bag = Inventory.basic_inventory[bag_slot]

		# Skip if not a bag
		if bag == null or not Inventory.is_bag(bag):
			continue

		# Get items in this bag
		var bag_items = Inventory.get_bag_contents(bag_slot)

		# Fill slots with items from this bag
		for item in bag_items:
			if slot_index >= slot_buttons.size():
				break

				var slot = slot_buttons[slot_index]

			# Set item icon
			if item.has("icon") and item.icon.length() > 0:
				if FileAccess.file_exists(item.icon):
					slot.texture_normal = load(item.icon)

			# Store item data in metadata
			slot.set_meta("item_data", item)
			slot.set_meta("bag_slot", bag_slot)
			slot.set_meta("item_index", bag_items.find(item))

			# Add quantity label if stackable
			if item.get("stackable", false):
				add_quantity_label(slot, item.get("quantity", 1))

			# Add tooltip (item name)
			slot.tooltip_text = item.get("name", "Unknown Item")

			slot_index += 1

			func add_quantity_label(slot_button: TextureButton, quantity: int):
	"""Adds a quantity label overlay to a slot"""
	# Remove existing quantity label if any
	var existing = slot_button.get_node_or_null("QuantityLabel")
	if existing:
		existing.queue_free()

	# Create new quantity label
	var qty_label = Label.new()
	qty_label.name = "QuantityLabel"
	qty_label.text = str(quantity)

	# Style the label
	qty_label.add_theme_color_override("font_color", Color.WHITE)
	qty_label.add_theme_color_override("font_outline_color", Color.BLACK)
	qty_label.add_theme_constant_override("outline_size", 2)

	# Position in upper-right corner
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	qty_label.anchor_right = 1.0
	qty_label.anchor_bottom = 1.0
	qty_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	qty_label.grow_vertical = Control.GROW_DIRECTION_END

	slot_button.add_child(qty_label)

	func _on_search_text_changed(new_text: String):
	"""Handles search bar text changes"""
	current_search = new_text.to_lower().strip_edges()

	if current_search.length() == 0:
		# Show all slots
		show_all_slots()
		else:
		# Filter slots
		apply_search_filter(current_search)

		func show_all_slots():
	"""Makes all slots visible"""
	for slot in slot_buttons:
		slot.visible = true

		func apply_search_filter(search_term: String):
	"""Hides slots that don't match search term"""
	for slot in slot_buttons:
		var item_data = slot.get_meta("item_data", null)

		if item_data == null:
			# Empty slot - hide it during search
			slot.visible = false
			continue

		# Check if item name contains search term
		var item_name = item_data.get("name", "").to_lower()
		if search_term in item_name:
			slot.visible = true
			else:
			slot.visible = false

			func _on_slot_clicked(slot_index: int):
	"""Handles slot click events"""
	if slot_index >= slot_buttons.size():
		return

		var slot = slot_buttons[slot_index]
		var item_data = slot.get_meta("item_data", null)

		if item_data == null:
		print("🎒 Empty slot clicked")
		return

		var item_name = item_data.get("name", "Unknown")
		print("🎒 Clicked: %s" % item_name)

		# TODO: Implement item actions (use, equip, drop, etc.)
	# For now, just print info
	print("   Type: %s" % item_data.get("type", "unknown"))
	if item_data.get("stackable", false):
		print("   Quantity: %d" % item_data.get("quantity", 1))

		func _input(event: InputEvent):
	"""Handles closing the backpack"""
	if Input.is_action_just_pressed("toggle_backpack"):
		queue_free()
		get_viewport().set_input_as_handled()
