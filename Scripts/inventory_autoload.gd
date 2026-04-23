# inventory_autoload.gd (Autoload Singleton)
# Manages player inventory, bags, and item data
# ADD TO PROJECT SETTINGS → AUTOLOAD as "Inventory"
extends Node

#region Item Data
var item_data: Dictionary = {}  # Loaded from items.json
#endregion

#region Basic Inventory (12 slots on character sheet)
var basic_inventory: Array = []  # 12 slots, can hold items OR bags
const BASIC_INVENTORY_SIZE = 12
#endregion

#region Bag Contents
# Dictionary where key = basic_inventory slot index (0-11)
# Value = Array of items in that bag
var bag_contents: Dictionary = {}
#endregion

#region Bank Storage
var bank_storage: Dictionary = {}  # Same structure as bag_contents (for later)
#endregion

#region Initialization
func _ready():
	load_item_data()
	initialize_basic_inventory()
	print("✅ Inventory system initialized")

func load_item_data():
	"""Loads item definitions from items.json"""
	var file = FileAccess.open("res://Data/items.json", FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			item_data = parsed
			print("✅ Loaded %d item definitions" % item_data.size())
		else:
			push_error("❌ items.json parsing failed")
	else:
		push_error("❌ items.json not found - creating empty inventory")

func initialize_basic_inventory():
	"""Creates empty basic inventory slots"""
	basic_inventory.clear()
	for i in range(BASIC_INVENTORY_SIZE):
		basic_inventory.append(null)
#endregion

#region Item Instance Creation
func create_item_instance(item_id: String, quantity: int = 1) -> Dictionary:
	"""Creates an instance of an item from its definition"""
	if not item_data.has(item_id):
		push_error("❌ Item definition not found: %s" % item_id)
		return {}

	var definition = item_data[item_id]
	var instance = definition.duplicate()
	instance["item_id"] = item_id

	if instance.get("stackable", false):
		instance["quantity"] = quantity

	return instance

func get_item_definition(item_id: String) -> Dictionary:
	"""Returns item definition from items.json"""
	return item_data.get(item_id, {})
#endregion

#region Bag Utilities
func is_bag(item: Dictionary) -> bool:
	"""Checks if an item is a bag"""
	return item.get("type") == "bag"

func get_bag_size(item: Dictionary) -> int:
	"""Returns bag's slot capacity"""
	return item.get("bag_size", 0) if is_bag(item) else 0

func calculate_total_bag_slots() -> int:
	"""Calculates total available backpack slots from equipped bags"""
	var total = 0
	for item in basic_inventory:
		if item != null and is_bag(item):
			total += get_bag_size(item)
	return total

func can_place_bag_in_bag(bag_item: Dictionary, target_bag_slot: int) -> bool:
	"""Validates nested bag rule: inner bag must be empty"""
	if not is_bag(bag_item):
		return true  # Not a bag, always OK

	# Check if this bag has any contents
	var bag_key = str(target_bag_slot)
	if bag_contents.has(bag_key):
		var contents = bag_contents[bag_key]
		if contents.size() > 0:
			return false  # Bag has items, can't nest it

	return true
#endregion

#region Basic Inventory Management
func add_to_basic_inventory(item_id: String, slot_index: int = -1) -> bool:
	"""Adds item to basic inventory (character sheet slots)"""
	if not item_data.has(item_id):
		push_error("❌ Item not found: %s" % item_id)
		return false

	var item = create_item_instance(item_id)

	# If slot specified, try to place there
	if slot_index >= 0 and slot_index < BASIC_INVENTORY_SIZE:
		if basic_inventory[slot_index] == null:
			basic_inventory[slot_index] = item
			print("✅ Added %s to basic inventory slot %d" % [item.name, slot_index])
			return true
		else:
			print("⚠️ Slot %d already occupied" % slot_index)
			return false

	# Find first empty slot
	for i in range(BASIC_INVENTORY_SIZE):
		if basic_inventory[i] == null:
			basic_inventory[i] = item
			print("✅ Added %s to basic inventory slot %d" % [item.name, i])
			return true

	print("❌ Basic inventory full!")
	return false

func remove_from_basic_inventory(slot_index: int) -> Dictionary:
	"""Removes and returns item from basic inventory slot"""
	if slot_index < 0 or slot_index >= BASIC_INVENTORY_SIZE:
		return {}

	var item = basic_inventory[slot_index]
	basic_inventory[slot_index] = null

	# If it was a bag, also clear bag contents
	if item != null and is_bag(item):
		bag_contents.erase(str(slot_index))

	return item if item != null else {}

func get_basic_inventory_slot(slot_index: int) -> Dictionary:
	"""Returns item in basic inventory slot (or empty dict)"""
	if slot_index < 0 or slot_index >= BASIC_INVENTORY_SIZE:
		return {}
	var item = basic_inventory[slot_index]
	return item if item != null else {}
#endregion

#region Bag Content Management
func add_to_bag(bag_slot_index: int, item_id: String) -> bool:
	"""Adds item to a bag in basic inventory"""
	# Verify bag exists
	var bag = get_basic_inventory_slot(bag_slot_index)
	if not is_bag(bag):
		push_error("❌ Slot %d does not contain a bag" % bag_slot_index)
		return false

	# Get or create bag contents array
	var bag_key = str(bag_slot_index)
	if not bag_contents.has(bag_key):
		bag_contents[bag_key] = []

	var bag_items = bag_contents[bag_key]
	var bag_capacity = get_bag_size(bag)

	# Check if bag is full
	if bag_items.size() >= bag_capacity:
		print("❌ Bag is full (%d/%d)" % [bag_items.size(), bag_capacity])
		return false

	var item = create_item_instance(item_id)

	# If item is a bag, verify it's empty (nested bag rule)
	if is_bag(item):
		if not can_place_bag_in_bag(item, bag_slot_index):
			print("❌ Cannot place bag inside another unless it's empty!")
			return false

	# Try to stack if item is stackable
	if item.get("stackable", false):
		for existing in bag_items:
			if existing.item_id == item_id:
				existing.quantity += item.get("quantity", 1)
				print("✅ Stacked %s (now %d)" % [item.name, existing.quantity])
				return true

	# Add as new item
	bag_items.append(item)
	print("✅ Added %s to bag slot %d" % [item.name, bag_slot_index])
	return true

func remove_from_bag(bag_slot_index: int, item_index: int) -> Dictionary:
	"""Removes item from bag and returns it"""
	var bag_key = str(bag_slot_index)
	if not bag_contents.has(bag_key):
		return {}

	var bag_items = bag_contents[bag_key]
	if item_index < 0 or item_index >= bag_items.size():
		return {}

	var item = bag_items[item_index]
	bag_items.remove_at(item_index)
	return item

func get_bag_contents(bag_slot_index: int) -> Array:
	"""Returns array of items in a bag"""
	var bag_key = str(bag_slot_index)
	return bag_contents.get(bag_key, [])
#endregion

#region Search & Filter
func search_all_items(search_term: String) -> Array:
	"""Searches all inventory for items matching search term"""
	var results = []
	search_term = search_term.to_lower()

	# Search basic inventory
	for i in range(BASIC_INVENTORY_SIZE):
		var item = basic_inventory[i]
		if item != null:
			var name = item.get("name", "").to_lower()
			if search_term in name:
				results.append({
					"item": item,
					"location": "basic",
					"slot": i
				})

	# Search bags
	for bag_key in bag_contents.keys():
		var bag_items = bag_contents[bag_key]
		for j in range(bag_items.size()):
			var item = bag_items[j]
			var name = item.get("name", "").to_lower()
			if search_term in name:
				results.append({
					"item": item,
					"location": "bag",
					"bag_slot": int(bag_key),
					"item_slot": j
				})

	return results
#endregion

#region Save/Load
func save_inventory_data() -> Dictionary:
	"""Exports inventory to dictionary for saving"""
	return {
		"basic_inventory": basic_inventory,
		"bag_contents": bag_contents,
		"bank_storage": bank_storage
	}

func load_inventory_data(data: Dictionary):
	"""Imports inventory from saved data"""
	basic_inventory = data.get("basic_inventory", [])
	bag_contents = data.get("bag_contents", {})
	bank_storage = data.get("bank_storage", {})

	# Ensure basic_inventory is correct size
	while basic_inventory.size() < BASIC_INVENTORY_SIZE:
		basic_inventory.append(null)

	print("✅ Inventory data loaded")
#endregion
