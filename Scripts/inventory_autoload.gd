# inventory_autoload.gd (Autoload Singleton)
# Manages player inventory, bags, and item data
# ADD TO PROJECT SETTINGS → AUTOLOAD as "Inventory"
extends Node

signal inventory_changed
signal equipment_changed

#region Item Data
var item_data: Dictionary = {}  # Loaded from items.json
#endregion

#region Basic Inventory (12 slots on character sheet)
var basic_inventory: Array = [] # 12 slots, can hold items OR bags
const BASIC_INVENTORY_SIZE = 12
const CRAFTING_ITEMS_PATH := "res://Data/crafting_items.json"
#endregion

#region Equipment
const EQUIPMENT_SLOTS: Array = [
	"ear1", "neck", "face", "head", "ear2",
	"finger1", "wrist1", "arms", "hands", "wrist2", "finger2",
	"shoulders", "chest", "back", "waist", "legs", "feet",
	"trinket1", "trinket2",
	"primary", "offhand", "ranged", "ammo", "charm", "focus",
	"light"  # torches now; lanterns / magic lights later (items with a "light_source")
]

# Maps item "slot" field → equipment slot name
const ITEM_SLOT_MAP: Dictionary = {
	"primary": "primary", "offhand": "offhand", "secondary": "offhand",
	"head": "head", "face": "face", "ear": "ear1",
	"neck": "neck", "shoulders": "shoulders", "chest": "chest",
	"arms": "arms", "wrist": "wrist1", "hands": "hands",
	"back": "back", "waist": "waist", "legs": "legs", "feet": "feet",
	"finger": "finger1", "ring": "finger1",
	"ranged": "ranged", "ammo": "ammo",
	"trinket": "trinket1", "charm": "charm", "focus": "focus",
	"light": "light",
}

var equipped: Dictionary = {}
#endregion

#region Bag Contents
var bag_contents: Dictionary = {}
#endregion

#region Bank Storage
var bank_storage: Dictionary = {}
#endregion

#region Initialization
func _ready():
	load_item_data()
	initialize_basic_inventory()
	_initialize_equipment()
	print("✅ Inventory system initialized")

func load_item_data():
	# Loads item definitions from items.json
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
	_merge_crafting_items()


# Adds Data/crafting_items.json (generated from the crafting workbook by tools/export_crafting.py: materials, crafted
# gear, kits, tools, recipe scrolls) to the item database. A hand-made items.json entry with the same id always wins.
func _merge_crafting_items() -> void:
	var file := FileAccess.open(CRAFTING_ITEMS_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("items")) != TYPE_DICTIONARY:
		push_error("❌ crafting_items.json parsing failed")
		return
	var added := 0
	for item_id in parsed["items"]:
		if not item_data.has(item_id):
			item_data[item_id] = parsed["items"][item_id]
			added += 1
	print("✅ Merged %d crafting item definitions" % added)

func initialize_basic_inventory():
	basic_inventory.clear()
	for i in range(BASIC_INVENTORY_SIZE):
		basic_inventory.append(null)

func _initialize_equipment():
	equipped.clear()
	for slot in EQUIPMENT_SLOTS:
		equipped[slot] = null
#endregion

#region Item Instance Creation
func create_item_instance(item_id: String, quantity: int = 1) -> Dictionary:
	# Creates an instance of an item from its definition
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
	# Returns item definition from items.json
	return item_data.get(item_id, {})
#endregion

#region Bag Utilities
func is_bag(item: Dictionary) -> bool:
	# Checks if an item is a bag
	return item.get("type") == "bag"

func get_bag_size(item: Dictionary) -> int:
	# Returns bag's slot capacity
	return item.get("bag_size", 0) if is_bag(item) else 0

func calculate_total_bag_slots() -> int:
	# Calculates total available backpack slots from equipped bags
	var total = 0
	for item in basic_inventory:
		if item != null and is_bag(item):
			total += get_bag_size(item)
	return total

func can_place_bag_in_bag(bag_item: Dictionary, target_bag_slot: int) -> bool:
	# Validates nested bag rule: inner bag must be empty
	if not is_bag(bag_item):
		return true

	var bag_key = str(target_bag_slot)
	if bag_contents.has(bag_key):
		var contents = bag_contents[bag_key]
		if contents.size() > 0:
			return false

	return true
#endregion

#region Basic Inventory Management
func add_to_basic_inventory(item_id: String, slot_index: int = -1, quantity: int = 1) -> bool:
	# Adds item to basic inventory (character sheet slots)
	if not item_data.has(item_id):
		push_error("❌ Item not found: %s" % item_id)
		return false

	var item = create_item_instance(item_id, quantity)

	if slot_index >= 0 and slot_index < BASIC_INVENTORY_SIZE:
		if basic_inventory[slot_index] == null:
			basic_inventory[slot_index] = item
			print("✅ Added %s to basic inventory slot %d" % [item.name, slot_index])
			sync_to_global()
			return true
		else:
			print("⚠️ Slot %d already occupied" % slot_index)
			return false

	for i in range(BASIC_INVENTORY_SIZE):
		if basic_inventory[i] == null:
			basic_inventory[i] = item
			print("✅ Added %s to basic inventory slot %d" % [item.name, i])
			sync_to_global()
			return true

	print("❌ Basic inventory full!")
	return false

func remove_from_basic_inventory(slot_index: int) -> Dictionary:
	# Removes and returns item from basic inventory slot
	if slot_index < 0 or slot_index >= BASIC_INVENTORY_SIZE:
		return {}

	var item = basic_inventory[slot_index]
	basic_inventory[slot_index] = null

	if item != null and is_bag(item):
		bag_contents.erase(str(slot_index))

	sync_to_global()
	inventory_changed.emit()
	return item if item != null else {}

func get_basic_inventory_slot(slot_index: int) -> Dictionary:
	# Returns item in basic inventory slot (or empty dict)
	if slot_index < 0 or slot_index >= BASIC_INVENTORY_SIZE:
		return {}
	var item = basic_inventory[slot_index]
	return item if item != null else {}


# Smart "give the player an item" entrypoint — every loot/purchase call site
# should go through this instead of add_to_basic_inventory() directly. Prefers
# merging onto an existing stack in any bag (correctly applying `quantity` —
# every prior call site called add_to_basic_inventory()/add_to_bag() with no
# quantity arg at all, so a "3x spider silk" drop only ever added 1), then
# any bag with room (keeps the scarce 12 basic_inventory slots free for
# equipment/bags rather than 1-per-item loot), and only falls back to a bare
# basic_inventory slot if every bag is full. Returns false only when there's
# truly no room anywhere — callers MUST check this before claiming success
# (add_to_basic_inventory's return value being ignored at several call sites
# was why "You receive X" could log while the item silently failed to fit).
func add_item(item_id: String, quantity: int = 1) -> bool:
	if not item_data.has(item_id):
		push_error("❌ Item not found: %s" % item_id)
		return false

	var def: Dictionary = item_data[item_id]

	if def.get("stackable", false):
		for slot in basic_inventory:
			if slot != null and not is_bag(slot) and slot.get("item_id") == item_id:
				slot.quantity += quantity
				sync_to_global()
				inventory_changed.emit()
				return true
		for bag_slot in range(BASIC_INVENTORY_SIZE):
			for existing in bag_contents.get(str(bag_slot), []):
				if existing.get("item_id") == item_id:
					existing.quantity += quantity
					sync_to_global()
					inventory_changed.emit()
					return true

	# Per user feedback (2026-09-17): free basic-inventory slots (not bags)
	# fill first, THEN bags in order — previously bags were filled first and
	# basic slots were only a last resort, the opposite of what's expected.
	if add_to_basic_inventory(item_id, -1, quantity):
		inventory_changed.emit()
		return true

	for bag_slot in range(BASIC_INVENTORY_SIZE):
		var bag = basic_inventory[bag_slot]
		if bag == null or not is_bag(bag):
			continue
		if bag_contents.get(str(bag_slot), []).size() >= get_bag_size(bag):
			continue
		if add_to_bag(bag_slot, item_id, quantity):
			inventory_changed.emit()
			return true

	return false
#endregion

#region Bag Content Management
func add_to_bag(bag_slot_index: int, item_id: String, quantity: int = 1) -> bool:
	# Adds item to a bag in basic inventory
	var bag = get_basic_inventory_slot(bag_slot_index)
	if not is_bag(bag):
		push_error("❌ Slot %d does not contain a bag" % bag_slot_index)
		return false

	var bag_key = str(bag_slot_index)
	if not bag_contents.has(bag_key):
		bag_contents[bag_key] = []

	var bag_items = bag_contents[bag_key]
	var bag_capacity = get_bag_size(bag)

	if bag_items.size() >= bag_capacity:
		print("❌ Bag is full (%d/%d)" % [bag_items.size(), bag_capacity])
		return false

	var item = create_item_instance(item_id, quantity)

	if is_bag(item) and not can_place_bag_in_bag(item, bag_slot_index):
		print("❌ Cannot place bag inside another unless it's empty!")
		return false

	if item.get("stackable", false):
		for existing in bag_items:
			if existing.item_id == item_id:
				existing.quantity += quantity
				print("✅ Stacked %s (now %d)" % [item.name, existing.quantity])
				sync_to_global()
				return true

	bag_items.append(item)
	print("✅ Added %s to bag slot %d" % [item.name, bag_slot_index])

	sync_to_global()
	return true

func remove_from_bag(bag_slot_index: int, item_index: int) -> Dictionary:
	# Removes item from bag and returns it
	var bag_key = str(bag_slot_index)
	if not bag_contents.has(bag_key):
		return {}

	var bag_items = bag_contents[bag_key]
	if item_index < 0 or item_index >= bag_items.size():
		return {}

	var item = bag_items[item_index]
	bag_items.remove_at(item_index)

	sync_to_global()
	inventory_changed.emit()
	return item

# Removes ONE unit of an item (eating food, drinking water, selling a single
# item off a stack) instead of the whole stack entry — decrements quantity if
# stackable and more than one remains, otherwise removes the slot/entry
# entirely. slot_type is "basic" (character-sheet slots, addressed by
# slot_index) or "bag" (addressed by bag_slot + item_index), matching the
# addressing already used throughout (slot_button.gd's drag payload, etc.).
func consume_one(slot_type: String, slot_index: int, bag_slot: int, item_index: int) -> void:
	consume_amount(slot_type, slot_index, bag_slot, item_index, 1)


# Same as consume_one() but removes `amount` units in a single operation
# (one sync/signal instead of `amount` repeated ones) — needed for the vendor
# window's sell-a-stack-at-once option.
func consume_amount(slot_type: String, slot_index: int, bag_slot: int, item_index: int, amount: int) -> void:
	if amount <= 0:
		return
	if slot_type == "bag":
		var bag_key = str(bag_slot)
		if not bag_contents.has(bag_key):
			return
		var bag_items = bag_contents[bag_key]
		if item_index < 0 or item_index >= bag_items.size():
			return
		var item = bag_items[item_index]
		var current_qty: int = item.get("quantity", 1) if item.get("stackable", false) else 1
		if amount >= current_qty:
			remove_from_bag(bag_slot, item_index)
		else:
			item.quantity -= amount
			sync_to_global()
			inventory_changed.emit()
	else:
		var item = get_basic_inventory_slot(slot_index)
		var current_qty: int = item.get("quantity", 1) if item.get("stackable", false) else 1
		if amount >= current_qty:
			remove_from_basic_inventory(slot_index)
		else:
			item.quantity -= amount
			sync_to_global()
			inventory_changed.emit()

func get_bag_contents(bag_slot_index: int) -> Array:
	# Returns array of items in a bag
	var bag_key = str(bag_slot_index)
	return bag_contents.get(bag_key, [])


# Finds the first item anywhere in the player's inventory (basic slots, then
# bags) whose item definition restores the given vital ("satiety"/"thirst") —
# used by player3d.gd's auto-eat/auto-drink so it doesn't need to know about
# basic_inventory vs. bag_contents storage. Returns the same
# (slot_type, slot_index, bag_slot, item_index) addressing consume_one()
# expects, or an empty dict if nothing matches.
func find_first_by_restores(restores: String) -> Dictionary:
	for i in range(BASIC_INVENTORY_SIZE):
		var item = basic_inventory[i]
		if item != null and item.get("restores", "") == restores:
			return {"item": item, "slot_type": "basic", "slot_index": i, "bag_slot": -1, "item_index": -1}

	for bag_key in bag_contents.keys():
		var bag_items = bag_contents[bag_key]
		for j in range(bag_items.size()):
			var item = bag_items[j]
			if item.get("restores", "") == restores:
				return {"item": item, "slot_type": "bag", "slot_index": -1, "bag_slot": int(bag_key), "item_index": j}

	return {}
#endregion

#region Search & Filter
func search_all_items(search_term: String) -> Array:
	# Searches all inventory for items matching search term
	var results = []
	search_term = search_term.to_lower()

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
	return {
		"basic_inventory": basic_inventory,
		"bag_contents": bag_contents,
		"bank_storage": bank_storage,
		"equipped": equipped,
	}

func load_inventory_data(data: Dictionary):
	basic_inventory = data.get("basic_inventory", [])
	bag_contents = data.get("bag_contents", {})
	bank_storage = data.get("bank_storage", {})
	equipped = data.get("equipped", {})
	for slot in EQUIPMENT_SLOTS:
		if not equipped.has(slot):
			equipped[slot] = null
	while basic_inventory.size() < BASIC_INVENTORY_SIZE:
		basic_inventory.append(null)
	refresh_item_icons(basic_inventory)
	refresh_item_icons(bag_contents)
	refresh_item_icons(bank_storage)
	refresh_item_icons(equipped)
	_rescue_orphaned_items()
	print("✅ Inventory data loaded")


# A saved item is a full COPY of its definition taken when it was created
# (create_item_instance()), so it also carries the icon path from that day. When
# items.json's icons were re-pathed (Session 49) every older character kept the dead
# path — flat white placeholder silhouettes for the old Lorc art, blank slots for files
# that no longer exist. The icon is purely presentational, so re-read it from the
# current definition on every load; nothing else on the saved item is touched. Walks
# any mix of arrays/dictionaries so it covers bags, bank, equipment and pet gear alike.
func refresh_item_icons(node: Variant) -> void:
	if node is Array:
		for entry in node:
			refresh_item_icons(entry)
	elif node is Dictionary:
		var item_id: String = str(node.get("item_id", ""))
		if not item_id.is_empty() and item_data.has(item_id):
			var icon: String = str(item_data[item_id].get("icon", ""))
			if not icon.is_empty():
				node["icon"] = icon
		else:
			for key in node:
				var value: Variant = node[key]
				if value is Array or value is Dictionary:
					refresh_item_icons(value)
#endregion

#region Drag & Drop Movement
func move_item_between_slots(target_slot: Node, data: Dictionary) -> void:
	var src_type: String = data.get("slot_type", "")
	var dst_type: String = target_slot.slot_type

	var src_basic_index: int = data.get("slot_index", -1)
	var src_bag_slot: int = data.get("bag_slot", -1)
	var src_item_index: int = data.get("item_index", -1)

	var dst_basic_index: int = target_slot.slot_index
	var dst_bag_slot: int = target_slot.bag_slot
	var dst_item_index: int = target_slot.item_index

	if src_type == "basic" and dst_type == "basic":
		_swap_basic_slots(src_basic_index, dst_basic_index)
	elif src_type == "basic" and dst_type == "bag":
		_move_basic_to_bag(src_basic_index, dst_bag_slot)
	elif src_type == "bag" and dst_type == "basic":
		_move_bag_to_basic(src_bag_slot, src_item_index, dst_basic_index)
	elif src_type == "bag" and dst_type == "bag":
		_swap_bag_items(src_bag_slot, src_item_index, dst_bag_slot, dst_item_index)

	sync_to_global()
	inventory_changed.emit()

func _swap_basic_slots(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= BASIC_INVENTORY_SIZE or b >= BASIC_INVENTORY_SIZE:
		return
	var tmp = basic_inventory[a]
	basic_inventory[a] = basic_inventory[b]
	basic_inventory[b] = tmp

# Drag from a character-sheet slot into the backpack. `target_bag` is the bag of the backpack slot it was dropped on, or -1 when that
# slot was EMPTY (an empty backpack tile belongs to no particular bag). It used to file the item under bag "-1" — a bag that does not
# exist — so the dagger vanished from every window (its data sat in bag_contents["-1"]). Now: the bag it was dropped on if that bag has
# room, otherwise the first bag that does; a bag may only go into another bag when it is empty; when nothing fits the item stays put.
func _move_basic_to_bag(src_slot: int, target_bag: int) -> void:
	if src_slot < 0 or src_slot >= BASIC_INVENTORY_SIZE:
		return
	var item = basic_inventory[src_slot]
	if item == null:
		return
	if is_bag(item) and not bag_contents.get(str(src_slot), []).is_empty():
		GameLog.log_general("[color=#ff8866]Empty that bag before putting it inside another.[/color]")
		return
	var dest := _bag_with_room_for(item, src_slot, target_bag)
	if dest < 0:
		GameLog.log_general("[color=#ff8866]There is no room in your bags for that.[/color]")
		return
	basic_inventory[src_slot] = null
	if is_bag(item):
		bag_contents.erase(str(src_slot))
	var key := str(dest)
	if not bag_contents.has(key):
		bag_contents[key] = []
	if item.get("stackable", false):
		for existing in bag_contents[key]:
			if existing.get("item_id") == item.get("item_id"):
				existing["quantity"] = int(existing.get("quantity", 1)) + int(item.get("quantity", 1))
				return
	bag_contents[key].append(item)


# The bag (a basic_inventory slot number) this item can go into: `preferred` first, then every other bag in order. -1 when none can
# take it. A stackable item also fits a full bag if the stack it joins is there.
func _bag_with_room_for(item: Dictionary, src_slot: int, preferred: int) -> int:
	var order: Array = []
	if preferred >= 0:
		order.append(preferred)
	for i in range(BASIC_INVENTORY_SIZE):
		if i != preferred:
			order.append(i)
	for i in order:
		if i == src_slot or i < 0 or i >= BASIC_INVENTORY_SIZE:
			continue
		var bag = basic_inventory[i]
		if bag == null or not is_bag(bag):
			continue
		var contents: Array = bag_contents.get(str(i), [])
		if item.get("stackable", false):
			for existing in contents:
				if existing.get("item_id") == item.get("item_id"):
					return i
		if contents.size() < get_bag_size(bag):
			return i
	return -1


# Items stranded under a bag that does not exist (the bug above filed them under bag "-1"): put each in a bag with room, else a free
# character-sheet slot. Anything that fits nowhere stays where it is (never deleted) and is tried again at the next login.
func _rescue_orphaned_items() -> void:
	for key in bag_contents.keys():
		var idx := int(key) if str(key).is_valid_int() else -1
		var valid := idx >= 0 and idx < BASIC_INVENTORY_SIZE and basic_inventory[idx] != null and is_bag(basic_inventory[idx])
		if valid:
			continue
		var stranded: Array = bag_contents[key]
		for item in stranded.duplicate():
			var dest := _bag_with_room_for(item, -1, -1)
			if dest >= 0:
				if not bag_contents.has(str(dest)):
					bag_contents[str(dest)] = []
				bag_contents[str(dest)].append(item)
			else:
				var free := basic_inventory.find(null)
				if free < 0:
					continue
				basic_inventory[free] = item
			stranded.erase(item)
			print("🎒 Recovered %s from a lost bag slot" % str(item.get("name", "an item")))
			GameLog.log_general.call_deferred("[color=#ffdd88]You find %s at the bottom of your pack.[/color]" % str(item.get("name", "an item")))
		if stranded.is_empty():
			bag_contents.erase(key)


func _move_bag_to_basic(bag_slot: int, item_index: int, dst_slot: int) -> void:
	var key := str(bag_slot)
	if not bag_contents.has(key):
		return
	var bag_items: Array = bag_contents[key]
	if item_index < 0 or item_index >= bag_items.size():
		return
	if dst_slot < 0 or dst_slot >= BASIC_INVENTORY_SIZE:
		return
	if basic_inventory[dst_slot] != null:
		return

	var item = bag_items[item_index]
	bag_items.remove_at(item_index)
	basic_inventory[dst_slot] = item

func _swap_bag_items(bag_a: int, index_a: int, bag_b: int, index_b: int) -> void:
	var key_a := str(bag_a)
	var key_b := str(bag_b)
	if not bag_contents.has(key_a) or not bag_contents.has(key_b):
		return

	var items_a: Array = bag_contents[key_a]
	var items_b: Array = bag_contents[key_b]

	if index_a < 0 or index_a >= items_a.size():
		return
	if index_b < 0 or index_b >= items_b.size():
		return

	var tmp = items_a[index_a]
	items_a[index_a] = items_b[index_b]
	items_b[index_b] = tmp
#endregion

#region Equipment Management
func equip_item(item: Dictionary, src_type: String, src_basic_idx: int = -1, src_bag_slot: int = -1, src_item_idx: int = -1) -> bool:
	var item_slot: String = item.get("slot", "none")
	var equip_slot: String = ITEM_SLOT_MAP.get(item_slot, "")
	if equip_slot.is_empty():
		print("⚠️ '%s' cannot be equipped (slot: %s)" % [item.get("name", "?"), item_slot])
		return false

	# Only ONE light is carried: pull a single unit off a stack and leave the rest
	# where it was. (Carried lights are non-stackable so a partly-burnt one can
	# never merge back into a fresh stack.)
	if equip_slot == "light" and item.get("stackable", false) and int(item.get("quantity", 1)) > 1:
		if equipped.get("light", null) != null:
			GameLog.log_general("You are already carrying a light. Unequip it first.")
			return false
		var one: Dictionary = item.duplicate(true)
		one.erase("quantity")
		one["stackable"] = false
		item["quantity"] = int(item["quantity"]) - 1
		equipped["light"] = one
		sync_to_global()
		equipment_changed.emit()
		inventory_changed.emit()
		return true

	var displaced: Variant = equipped.get(equip_slot, null)
	if equip_slot == "light":
		item["stackable"] = false
		item.erase("quantity")
		if displaced is Dictionary:
			displaced.erase("lit")  # swapped out: no longer burning (burn_remaining is kept)

	# Remove item from source, optionally placing displaced item there
	if src_type == "basic" and src_basic_idx >= 0:
		basic_inventory[src_basic_idx] = displaced
	elif src_type == "bag" and src_bag_slot >= 0 and src_item_idx >= 0:
		var key := str(src_bag_slot)
		if bag_contents.has(key):
			if displaced != null:
				bag_contents[key][src_item_idx] = displaced
			else:
				bag_contents[key].remove_at(src_item_idx)
	elif src_type == "equipment":
		# Equipping from one equip slot to another — put displaced in source slot
		var src_slot: String = ITEM_SLOT_MAP.get(displaced.get("slot", "") if displaced else "", "")
		if not src_slot.is_empty() and displaced != null:
			equipped[src_slot] = displaced
		displaced = null

	equipped[equip_slot] = item
	sync_to_global()
	equipment_changed.emit()
	inventory_changed.emit()
	print("✅ Equipped %s → %s slot" % [item.get("name", "?"), equip_slot])
	return true

func unequip_item(equip_slot: String) -> bool:
	var item: Variant = equipped.get(equip_slot, null)
	if item == null:
		return false
	for i in range(BASIC_INVENTORY_SIZE):
		if basic_inventory[i] == null:
			if item is Dictionary:
				item.erase("lit")  # taking a light off snuffs it (burn_remaining is kept)
			basic_inventory[i] = item
			equipped[equip_slot] = null
			sync_to_global()
			equipment_changed.emit()
			inventory_changed.emit()
			print("✅ Unequipped %s → inventory slot %d" % [item.get("name", "?"), i])
			return true
	print("❌ Inventory full — cannot unequip %s" % item.get("name", "?"))
	return false

func get_equipped_armor_class() -> int:
	var total := 0
	for slot in EQUIPMENT_SLOTS:
		var item: Variant = equipped.get(slot, null)
		if item != null:
			total += item.get("armor_class", 0)
	return total

func get_equipped_weapon() -> Dictionary:
	var w: Variant = equipped.get("primary", null)
	return w if w != null else {}
#endregion

func sync_to_global():
	if Global.player_data.is_empty():
		return
	Global.player_data["inventory_data"] = save_inventory_data()
	print("🔄 Inventory synced TO Global")

func sync_from_global():
	if Global.player_data.is_empty():
		return
	var data = Global.player_data.get("inventory_data", {})
	load_inventory_data(data)
	print("🔄 Inventory synced FROM Global")
