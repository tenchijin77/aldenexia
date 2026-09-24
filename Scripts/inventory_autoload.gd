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
# The bank (banker_npc.gd opens bank_window.gd): BANK_SIZE slots per character, keyed "0".."23" -> item, saved with the
# character like the bags. A bag put in a bank slot works like one in a character-sheet slot: its contents live in
# bank_storage["bags"]["<slot>"] and show under the bank grid (slot type "bank_bag"). A bag can be deposited full — its
# contents go with it — and a kit / crafting bag keeps its rules in the bank. Items move by drag and drop while the bank
# window is open (move_item_between_slots() -> _move_any()).
const BANK_SIZE := 24
var bank_storage: Dictionary = {}

func get_bank_slot(index: int) -> Dictionary:
	var item: Variant = bank_storage.get(str(index))
	return item if typeof(item) == TYPE_DICTIONARY else {}


func get_bank_bag_contents(bank_slot: int) -> Array:
	return _bank_bags().get(str(bank_slot), [])


func _bank_bags() -> Dictionary:
	if typeof(bank_storage.get("bags")) != TYPE_DICTIONARY:
		bank_storage["bags"] = {}
	return bank_storage["bags"]


# The contents dictionary a top-level slot's bag keeps its items in: bag_contents for a character-sheet slot, the bank's
# own for a bank slot. null for any other kind of slot.
func _contents_home(t: String) -> Variant:
	match t:
		"basic":
			return bag_contents
		"bank":
			return _bank_bags()
	return null


func _slot_get(t: String, index: int, bag_slot: int, item_index: int) -> Dictionary:
	match t:
		"basic":
			return get_basic_inventory_slot(index)
		"bank":
			return get_bank_slot(index)
		"bag", "bank_bag":
			var home: Dictionary = bag_contents if t == "bag" else _bank_bags()
			var contents: Array = home.get(str(bag_slot), [])
			return contents[item_index] if item_index >= 0 and item_index < contents.size() else {}
	return {}


func _slot_put(t: String, index: int, bag_slot: int, item_index: int, item: Dictionary) -> void:
	match t:
		"basic":
			basic_inventory[index] = item
		"bank":
			bank_storage[str(index)] = item
		"bag", "bank_bag":
			var home: Dictionary = bag_contents if t == "bag" else _bank_bags()
			var contents: Array = home.get(str(bag_slot), [])
			if item_index >= 0 and item_index < contents.size():
				contents[item_index] = item
			else:
				contents.append(item)
			home[str(bag_slot)] = contents


func _slot_clear(t: String, index: int, bag_slot: int, item_index: int) -> void:
	match t:
		"basic":
			basic_inventory[index] = null
		"bank":
			bank_storage.erase(str(index))
		"bag", "bank_bag":
			var home: Dictionary = bag_contents if t == "bag" else _bank_bags()
			var contents: Array = home.get(str(bag_slot), [])
			if item_index >= 0 and item_index < contents.size():
				contents.remove_at(item_index)


# The bag (in a slot of type `container_t`: "basic" for bags, "bank" for bank bags) the item can go in: `preferred` first.
func _container_with_room(container_t: String, item: Dictionary, preferred: int) -> int:
	if container_t == "basic":
		return _bag_with_room_for(item, -1, preferred)
	var order: Array = [preferred] if preferred >= 0 else []
	for i in BANK_SIZE:
		if i != preferred:
			order.append(i)
	for i in order:
		var bag := get_bank_slot(i)
		if not is_bag(bag) or not bag_accepts(bag, item):
			continue
		var contents: Array = get_bank_bag_contents(i)
		if item.get("stackable", false) and contents.any(func(e): return e.get("item_id") == item.get("item_id")):
			return i
		if contents.size() < get_bag_size(bag):
			return i
	return -1


# ── One-click moves: Deposit / Withdraw (right-click menu while the bank is open) and Sort ──

# Where `item` should go on one side ("pack": character-sheet slots + bags, "bank": bank slots + bank bags), as
# {t, i, b, x} for _move_any(), or {} when there is no room. In order: onto a stack of the same item, into a crafting bag
# (kit / Large Crafting Bag) that takes it, a free top-level slot, then any ordinary bag with room. A bag with things in it
# can only go to a free top-level slot.
func _find_destination(side: String, item: Dictionary, has_contents: bool) -> Dictionary:
	var top_t := "basic" if side == "pack" else "bank"
	var in_t := "bag" if side == "pack" else "bank_bag"
	var slots := BASIC_INVENTORY_SIZE if side == "pack" else BANK_SIZE
	var home: Dictionary = bag_contents if side == "pack" else _bank_bags()
	var id := str(item.get("item_id", ""))
	if not has_contents and item.get("stackable", false):
		for i in slots:
			var top := _slot_get(top_t, i, -1, -1)
			if not top.is_empty() and not is_bag(top) and top.get("item_id") == id:
				return {"t": top_t, "i": i, "b": -1, "x": -1}
			if is_bag(top) and bag_accepts(top, item):
				var contents: Array = home.get(str(i), [])
				for x in contents.size():
					if contents[x].get("item_id") == id:
						return {"t": in_t, "i": -1, "b": i, "x": x}
	var free_top := {}
	for i in slots:
		if _slot_get(top_t, i, -1, -1).is_empty():
			free_top = {"t": top_t, "i": i, "b": -1, "x": -1}
			break
	if has_contents:
		return free_top
	for restricted_pass in [true, false]:
		for i in _slots_by_bag_rank(slots, func(n): return _slot_get(top_t, n, -1, -1)):
			var bag := _slot_get(top_t, i, -1, -1)
			if not is_bag(bag) or is_restricted_bag(bag) != restricted_pass or not bag_accepts(bag, item):
				continue
			if home.get(str(i), []).size() < get_bag_size(bag):
				return {"t": in_t, "i": -1, "b": i, "x": -1}
		if restricted_pass and not free_top.is_empty():
			return free_top
	return {}


# Right-click > Deposit (from the pack into the bank) or Withdraw (from the bank into the pack) — the whole stack, or the
# whole bag with what is in it. False (and says why) when there's no room on the other side.
func quick_bank_move(t: String, i: int, b: int, x: int) -> bool:
	var item := _slot_get(t, i, b, x)
	if item.is_empty():
		return false
	var to_bank := t in ["basic", "bag"]
	var home: Variant = _contents_home(t)
	var has_contents: bool = home != null and not (home as Dictionary).get(str(i), []).is_empty()
	var dst := _find_destination("bank" if to_bank else "pack", item, has_contents)
	if dst.is_empty():
		GameLog.log_general("[color=#ff8866]There is no room %s for that.[/color]" % ("in your bank" if to_bank else "in your bags"))
		return false
	_move_any(t, i, b, x, dst["t"], dst["i"], dst["b"], dst["x"])
	sync_to_global()
	inventory_changed.emit()
	return true


# The Sort button (character sheet / backpack): every crafting material that a crafting bag (a kit or the Large Crafting
# Bag in a character-sheet slot) will take goes into it, and split stacks of the same item are joined. Returns how many
# items moved.
func sort_pack() -> int:
	var moved := 0
	# 1. Join split stacks (the later stack is added to the first one of the same item).
	var seen := {}
	for loc in _pack_locations():
		var item := _slot_get(loc["t"], loc["i"], loc["b"], loc["x"])
		if item.is_empty() or not item.get("stackable", false) or is_bag(item):
			continue
		var id := str(item.get("item_id"))
		if not seen.has(id):
			seen[id] = item
			continue
		var first: Dictionary = seen[id]
		first["quantity"] = int(first.get("quantity", 1)) + int(item.get("quantity", 1))
		item["quantity"] = 0
	_drop_empty_stacks()
	# 2. Crafting materials out of character-sheet slots and ordinary bags, into crafting bags with room. Plan every move
	# first (so indexes stay put), then take the items out and put them in.
	var room := {}
	for bag_slot in _slots_by_bag_rank(BASIC_INVENTORY_SIZE, get_basic_inventory_slot):
		var bag := get_basic_inventory_slot(bag_slot)
		if is_restricted_bag(bag):
			room[bag_slot] = get_bag_size(bag) - bag_contents.get(str(bag_slot), []).size()
	var moves: Array = []
	for loc in _pack_locations():
		var item := _slot_get(loc["t"], loc["i"], loc["b"], loc["x"])
		if item.is_empty() or is_bag(item):
			continue
		if loc["t"] == "bag" and is_restricted_bag(get_basic_inventory_slot(loc["b"])):
			continue  # already in a crafting bag
		for bag_slot in room:
			if int(room[bag_slot]) > 0 and bag_accepts(get_basic_inventory_slot(bag_slot), item):
				room[bag_slot] = int(room[bag_slot]) - 1
				moves.append({"loc": loc, "item": item, "to": bag_slot})
				break
	var from_bags := {}  # bag slot -> indexes to take out
	for m in moves:
		if m["loc"]["t"] == "basic":
			basic_inventory[m["loc"]["i"]] = null
		else:
			var key := str(m["loc"]["b"])
			if not from_bags.has(key):
				from_bags[key] = []
			from_bags[key].append(int(m["loc"]["x"]))
	for key in from_bags:
		var indexes: Array = from_bags[key]
		indexes.sort()
		indexes.reverse()
		for x in indexes:
			bag_contents[key].remove_at(x)
	for m in moves:
		var key := str(m["to"])
		if not bag_contents.has(key):
			bag_contents[key] = []
		bag_contents[key].append(m["item"])
	moved = moves.size()
	sync_to_global()
	inventory_changed.emit()
	return moved


# Every place in the pack that can hold an item: character-sheet slots, then each bag's items.
func _pack_locations() -> Array:
	var out: Array = []
	for i in BASIC_INVENTORY_SIZE:
		out.append({"t": "basic", "i": i, "b": -1, "x": -1})
	for i in BASIC_INVENTORY_SIZE:
		if is_bag(get_basic_inventory_slot(i)):
			for x in bag_contents.get(str(i), []).size():
				out.append({"t": "bag", "i": -1, "b": i, "x": x})
	return out


func _drop_empty_stacks() -> void:
	for i in BASIC_INVENTORY_SIZE:
		var item = basic_inventory[i]
		if item != null and item.get("stackable", false) and int(item.get("quantity", 1)) <= 0:
			basic_inventory[i] = null
	for key in bag_contents:
		var contents: Array = bag_contents[key]
		for x in range(contents.size() - 1, -1, -1):
			if contents[x].get("stackable", false) and int(contents[x].get("quantity", 1)) <= 0:
				contents.remove_at(x)


# One move between any two of: character-sheet slot, bag slot, bank slot, bank-bag slot (used whenever the bank is involved).
# The same stackable item merges; otherwise the two swap (or it simply moves into an empty slot). A bag's contents always
# travel with it between top-level slots (character sheet <-> bank); a bag with things in it can't go inside another bag.
func _move_any(src_t: String, src_i: int, src_bag: int, src_idx: int, dst_t: String, dst_i: int, dst_bag: int, dst_idx: int) -> void:
	var moving := _slot_get(src_t, src_i, src_bag, src_idx)
	if moving.is_empty():
		return
	var src_top := src_t in ["basic", "bank"]
	var dst_top := dst_t in ["basic", "bank"]
	var dst_in_bag := dst_t in ["bag", "bank_bag"]
	var container_t := "basic" if dst_t == "bag" else "bank"
	if dst_in_bag and dst_bag < 0:  # an empty backpack tile belongs to no particular bag: any bag with room
		dst_bag = _container_with_room(container_t, moving, -1)
		dst_idx = -1
		if dst_bag < 0:
			GameLog.log_general("[color=#ff8866]There is no room for that.[/color]")
			return
	var target := _slot_get(dst_t, dst_i, dst_bag, dst_idx)
	# Merge a stack onto the same item.
	if not target.is_empty() and moving.get("stackable", false) and target.get("item_id") == moving.get("item_id"):
		target["quantity"] = int(target.get("quantity", 1)) + int(moving.get("quantity", 1))
		_slot_clear(src_t, src_i, src_bag, src_idx)
		return
	var src_contents: Array = _contents_home(src_t).get(str(src_i), []) if src_top else []
	var dst_contents: Array = _contents_home(dst_t).get(str(dst_i), []) if dst_top else []
	if not src_contents.is_empty() and not dst_top:
		GameLog.log_general("[color=#ff8866]Empty the %s before putting it inside another bag.[/color]" % str(moving.get("name", "bag")))
		return
	if not dst_contents.is_empty() and not src_top:
		GameLog.log_general("[color=#ff8866]Empty the %s before putting it inside another bag.[/color]" % str(target.get("name", "bag")))
		return
	if dst_in_bag:
		var bag := _slot_get(container_t, dst_bag, -1, -1)
		if not is_bag(bag):
			return
		if not bag_accepts(bag, moving):
			GameLog.log_general("[color=#ff8866]The %s only holds %s.[/color]" % [str(bag.get("name", "bag")), bag_holds_text(bag)])
			return
		if target.is_empty() and _contents_home(container_t).get(str(dst_bag), []).size() >= get_bag_size(bag):
			GameLog.log_general("[color=#ff8866]The %s is full.[/color]" % str(bag.get("name", "bag")))
			return
	if src_t in ["bag", "bank_bag"] and not target.is_empty():
		var src_container := _slot_get("basic" if src_t == "bag" else "bank", src_bag, -1, -1)
		if not bag_accepts(src_container, target):
			GameLog.log_general("[color=#ff8866]That won't fit in the %s.[/color]" % str(src_container.get("name", "bag")))
			return
	# Swap (or a plain move into an empty slot), then the bags' contents follow their bags.
	if target.is_empty():
		_slot_clear(src_t, src_i, src_bag, src_idx)
		_slot_put(dst_t, dst_i, dst_bag, dst_idx, moving)
	else:
		_slot_put(dst_t, dst_i, dst_bag, dst_idx, moving)
		_slot_put(src_t, src_i, src_bag, src_idx, target)
	if src_top:
		_contents_home(src_t).erase(str(src_i))
	if dst_top:
		_contents_home(dst_t).erase(str(dst_i))
	if dst_top and not src_contents.is_empty():
		_contents_home(dst_t)[str(dst_i)] = src_contents
	if src_top and not dst_contents.is_empty():
		_contents_home(src_t)[str(src_i)] = dst_contents
#endregion

#region Initialization
func _ready():
	inventory_changed.connect(_retry_orphans)
	load_item_data()
	_load_crafting_materials()
	initialize_basic_inventory()
	_initialize_equipment()
	print("✅ Inventory system initialized")

func load_item_data():
	# Loads every item definition from items.json (the one source of item data; tools/export_crafting.py appends new
	# crafting items there)
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


# A different character is about to be loaded or created: nothing of the previous one may carry over. Bags past the
# first and the bank used to survive a character switch (build_starting_inventory() only reset slots, equipment and
# bag 0), and _rescue_orphaned_items() then moved the old bags' contents into the new character (test 27).
func reset_for_new_character() -> void:
	basic_inventory = []
	for i in range(BASIC_INVENTORY_SIZE):
		basic_inventory.append(null)
	equipped = {}
	for slot in EQUIPMENT_SLOTS:
		equipped[slot] = null
	bag_contents = {}
	bank_storage = {}
	_orphans_waiting = 0
	_orphan_notice_shown = false


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
# CRAFTING BAGS. A portable crafting kit (any item with a "tradeskill_station") is also a KIT_BAG_SIZE-slot bag, but it only
# holds that craft's materials: the ingredients of every recipe that can be made with the kit (Data/tradeskill_recipes.json).
# A bag with "bag_accepts": "crafting" (the Large Crafting Bag) holds any crafting material at all: every recipe ingredient
# and everything a gathering node gives. Worked out from the recipe data at startup, so new recipes need no list updating.
const KIT_BAG_SIZE := 8
const RECIPES_PATH := "res://Data/tradeskill_recipes.json"
const GATHERING_PATH := "res://Data/gathering_nodes.json"
var _kit_materials := {}        # kit station id -> {item_id: true}
var _crafting_materials := {}   # {item_id: true}


func is_bag(item: Dictionary) -> bool:
	# Checks if an item is a bag (a crafting kit counts: it holds its craft's materials)
	return item.get("type") == "bag" or item.has("tradeskill_station")

func get_bag_size(item: Dictionary) -> int:
	# Returns bag's slot capacity
	if not is_bag(item):
		return 0
	return int(item.get("bag_size", KIT_BAG_SIZE if item.has("tradeskill_station") else 0))


# Whether `bag` may hold `item`. An ordinary bag takes anything; a kit only its craft's materials; a "crafting" bag any
# crafting material. A restricted bag never takes another bag.
func bag_accepts(bag: Dictionary, item: Dictionary) -> bool:
	var item_id := str(item.get("item_id", ""))
	if bag.has("tradeskill_station"):
		return not is_bag(item) and _kit_materials.get(str(bag["tradeskill_station"]), {}).has(item_id)
	if str(bag.get("bag_accepts", "")) == "crafting":
		return not is_bag(item) and _crafting_materials.has(item_id)
	return true


# "tailoring materials" / "crafting materials" — for messages and tooltips ("" for an ordinary bag).
func bag_holds_text(bag: Dictionary) -> String:
	if bag.has("tradeskill_station"):
		return "%s materials" % str(bag.get("skill", "crafting"))
	if str(bag.get("bag_accepts", "")) == "crafting":
		return "crafting materials"
	return ""


# How specific a bag is, for choosing where an item goes: 0 = a kit (one craft's materials), 1 = the Large Crafting Bag
# (any material), 2 = an ordinary bag. Items go to the most specific bag that takes them.
func bag_rank(bag: Dictionary) -> int:
	if bag.has("tradeskill_station"):
		return 0
	return 1 if is_restricted_bag(bag) else 2


# Slot numbers 0..count-1 ordered by the rank of the bag in them (kits first); `get_item` returns what's in a slot.
func _slots_by_bag_rank(count: int, get_item: Callable) -> Array:
	var order: Array = range(count)
	order.sort_custom(func(a, b):
		var ra := bag_rank(get_item.call(a)) if is_bag(get_item.call(a)) else 3
		var rb := bag_rank(get_item.call(b)) if is_bag(get_item.call(b)) else 3
		return ra < rb or (ra == rb and a < b))
	return order


func is_restricted_bag(bag: Dictionary) -> bool:
	return bag.has("tradeskill_station") or not str(bag.get("bag_accepts", "")).is_empty()


# What each crafting bag may hold (see CRAFTING BAGS above).
func _load_crafting_materials() -> void:
	var recipes_file: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECIPES_PATH)) if FileAccess.file_exists(RECIPES_PATH) else null
	if typeof(recipes_file) != TYPE_DICTIONARY:
		return
	var groups: Dictionary = recipes_file.get("ingredient_groups", {})
	var recipes: Dictionary = recipes_file.get("recipes", {})
	for recipe_id in recipes:
		var recipe: Dictionary = recipes[recipe_id]
		var ids: Array = []
		for ingredient in recipe.get("ingredients", {}):
			if groups.has(ingredient):
				ids.append_array(groups[ingredient])
			else:
				ids.append(ingredient)
		for id in ids:
			_crafting_materials[id] = true
			for station in recipe.get("stations", []):
				if not _kit_materials.has(station):
					_kit_materials[station] = {}
				_kit_materials[station][id] = true
	var nodes_file: Variant = JSON.parse_string(FileAccess.get_file_as_string(GATHERING_PATH)) if FileAccess.file_exists(GATHERING_PATH) else null
	if typeof(nodes_file) == TYPE_DICTIONARY:
		for node_id in nodes_file.get("nodes", {}):
			var gives := str(nodes_file["nodes"][node_id].get("item", ""))
			if not gives.is_empty():
				_crafting_materials[gives] = true

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
	var added := _add_item(item_id, quantity)
	if added and not Net.is_dedicated_server:
		Quests.on_item_gained.call_deferred(item_id)  # picking up a quest item can start its quest (deferred: never mid-load)
	return added


func _add_item(item_id: String, quantity: int = 1) -> bool:
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

	# A crafting material goes straight into a crafting bag (its kit first, then the Large Crafting Bag) that takes it and has room.
	for bag_slot in _slots_by_bag_rank(BASIC_INVENTORY_SIZE, get_basic_inventory_slot):
		var bag = basic_inventory[bag_slot]
		if bag == null or not is_restricted_bag(bag) or not bag_accepts(bag, def.merged({"item_id": item_id})):
			continue
		if bag_contents.get(str(bag_slot), []).size() < get_bag_size(bag) and add_to_bag(bag_slot, item_id, quantity):
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

	if not bag_accepts(bag, item):
		return false

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

# Takes the whole entry (the full stack) out of a character-sheet slot ("basic") or a bag slot ("bag") and returns it — for
# dropping it on the ground or destroying it (slot_button.gd). {} if the slot no longer holds `expected_id` (it changed
# since the player picked it up) or it is a bag that still has things in it.
func take_from_slot(slot_type: String, slot_index: int, bag_slot: int, item_index: int, expected_id: String) -> Dictionary:
	if slot_type == "basic":
		var item := get_basic_inventory_slot(slot_index)
		if item.is_empty() or str(item.get("item_id", "")) != expected_id:
			return {}
		if is_bag(item) and not bag_contents.get(str(slot_index), []).is_empty():
			GameLog.log_general("[color=#ff8866]Empty the %s first.[/color]" % str(item.get("name", "bag")))
			return {}
		return remove_from_basic_inventory(slot_index)
	if slot_type == "bag":
		var contents: Array = bag_contents.get(str(bag_slot), [])
		if item_index < 0 or item_index >= contents.size() or str(contents[item_index].get("item_id", "")) != expected_id:
			return {}
		return remove_from_bag(bag_slot, item_index)
	return {}


# Whether everything in `incoming` ([{item_id, quantity}]) would fit after `outgoing` (same shape) has been taken out — worked
# out on a copy, nothing changes. Used by a trade before it commits (trade_relay.gd), so a full pack can't lose the items.
func can_fit_all(incoming: Array, outgoing: Array = []) -> bool:
	var basic: Array = basic_inventory.duplicate(true)
	var bags: Dictionary = bag_contents.duplicate(true)
	for entry in outgoing:
		var left := int(entry.get("quantity", 1))
		var id := str(entry.get("item_id", ""))
		for i in basic.size():
			if left > 0 and basic[i] != null and basic[i].get("item_id") == id and not is_bag(basic[i]):
				var q := int(basic[i].get("quantity", 1)) if basic[i].get("stackable", false) else 1
				if q <= left:
					basic[i] = null
				else:
					basic[i]["quantity"] = q - left
				left -= mini(q, left)
		for key in bags:
			var contents: Array = bags[key]
			for j in range(contents.size() - 1, -1, -1):
				if left > 0 and contents[j].get("item_id") == id:
					var q := int(contents[j].get("quantity", 1)) if contents[j].get("stackable", false) else 1
					if q <= left:
						contents.remove_at(j)
					else:
						contents[j]["quantity"] = q - left
					left -= mini(q, left)
	for entry in incoming:
		var id := str(entry.get("item_id", ""))
		if not item_data.has(id):
			return false
		var item := create_item_instance(id, int(entry.get("quantity", 1)))
		if item.get("stackable", false) and _sim_has_stack(basic, bags, id):
			continue
		if _sim_place(basic, bags, item):
			continue
		return false
	return true


func _sim_has_stack(basic: Array, bags: Dictionary, id: String) -> bool:
	for slot in basic:
		if slot != null and not is_bag(slot) and slot.get("item_id") == id:
			return true
	for key in bags:
		for existing in bags[key]:
			if existing.get("item_id") == id:
				return true
	return false


# Same order as add_item(): a crafting bag that takes it, a free character-sheet slot, then any bag with room.
func _sim_place(basic: Array, bags: Dictionary, item: Dictionary) -> bool:
	for restricted_pass in [true, false]:
		for i in _slots_by_bag_rank(basic.size(), func(n): return basic[n] if basic[n] != null else {}):
			var bag = basic[i]
			if bag == null or not is_bag(bag) or is_restricted_bag(bag) != restricted_pass or not bag_accepts(bag, item):
				continue
			var contents: Array = bags.get(str(i), [])
			if contents.size() < get_bag_size(bag):
				contents.append(item)
				bags[str(i)] = contents
				return true
		if restricted_pass:
			var free := basic.find(null)
			if free >= 0:
				basic[free] = item
				return true
	return false


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
			# The description too (so an old kit tells you it is now a crafting bag); like the icon, it is only text.
			if item_data[item_id].has("description"):
				node["description"] = item_data[item_id]["description"]
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

	if src_type in ["bank", "bank_bag"] or dst_type in ["bank", "bank_bag"]:
		if src_type in ["basic", "bag", "bank", "bank_bag"] and dst_type in ["basic", "bag", "bank", "bank_bag"]:
			_move_any(src_type, src_basic_index, src_bag_slot, src_item_index, dst_type, dst_basic_index, dst_bag_slot, dst_item_index)
	elif src_type == "basic" and dst_type == "basic":
		_swap_basic_slots(src_basic_index, dst_basic_index)
	elif src_type == "basic" and dst_type == "bag":
		_move_basic_to_bag(src_basic_index, dst_bag_slot)
	elif src_type == "bag" and dst_type == "basic":
		_move_bag_to_basic(src_bag_slot, src_item_index, dst_basic_index)
	elif src_type == "bag" and dst_type == "bag":
		if dst_item_index < 0 and dst_bag_slot >= 0 and dst_bag_slot != src_bag_slot:
			_move_bag_to_bag(src_bag_slot, src_item_index, dst_bag_slot)  # onto an empty slot of a particular bag
		else:
			_swap_bag_items(src_bag_slot, src_item_index, dst_bag_slot, dst_item_index)

	sync_to_global()
	inventory_changed.emit()

# A bag's contents are filed under the basic slot the bag sits in (bag_contents["<slot>"]), so moving a bag between slots has
# to move its contents with it. It didn't: dragging a bag to another slot left its contents under the old slot number, where
# nothing shows them — the items vanished until the next login's orphan rescue (test 19: "10 tanning oil disappeared").
func _swap_basic_slots(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= BASIC_INVENTORY_SIZE or b >= BASIC_INVENTORY_SIZE or a == b:
		return
	var tmp = basic_inventory[a]
	basic_inventory[a] = basic_inventory[b]
	basic_inventory[b] = tmp
	var contents_a: Variant = bag_contents.get(str(a))
	var contents_b: Variant = bag_contents.get(str(b))
	bag_contents.erase(str(a))
	bag_contents.erase(str(b))
	if contents_a != null:
		bag_contents[str(b)] = contents_a
	if contents_b != null:
		bag_contents[str(a)] = contents_b

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
		if bag == null or not is_bag(bag) or not bag_accepts(bag, item):
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
	var waiting := 0
	for key in bag_contents.keys():
		var idx := int(key) if str(key).is_valid_int() else -1
		var valid := idx >= 0 and idx < BASIC_INVENTORY_SIZE and basic_inventory[idx] != null and is_bag(basic_inventory[idx])
		if valid:
			continue
		var stranded: Array = bag_contents[key]
		for item in stranded.duplicate():
			if _merge_into_existing_stack(item):
				pass
			else:
				var dest := _bag_with_room_for(item, -1, -1)
				if dest >= 0:
					if not bag_contents.has(str(dest)):
						bag_contents[str(dest)] = []
					bag_contents[str(dest)].append(item)
				else:
					var free := basic_inventory.find(null)
					if free < 0:
						waiting += 1
						continue
					basic_inventory[free] = item
			stranded.erase(item)
			print("🎒 Recovered %s from a lost bag slot" % str(item.get("name", "an item")))
			GameLog.log_general.call_deferred("[color=#ffdd88]You find %s at the bottom of your pack.[/color]" % str(item.get("name", "an item")))
		if stranded.is_empty():
			bag_contents.erase(key)
	_orphans_waiting = waiting
	if waiting > 0 and not _orphan_notice_shown:
		_orphan_notice_shown = true
		GameLog.log_general.call_deferred("[color=#ffdd88]%d item%s at the bottom of your pack need%s room — free a bag slot and %s drop in.[/color]" % [
			waiting, "" if waiting == 1 else "s", "s" if waiting == 1 else "", "it will" if waiting == 1 else "they will"])


# A stranded stackable item joins a stack of the same item already in the basic slots or a bag (needs no free slot).
func _merge_into_existing_stack(item: Dictionary) -> bool:
	if not item.get("stackable", false):
		return false
	var id: String = str(item.get("item_id", ""))
	for slot in basic_inventory:
		if slot != null and not is_bag(slot) and slot.get("item_id") == id:
			slot["quantity"] = int(slot.get("quantity", 1)) + int(item.get("quantity", 1))
			return true
	for bag_slot in range(BASIC_INVENTORY_SIZE):
		var bag = basic_inventory[bag_slot]
		if bag == null or not is_bag(bag):
			continue
		for existing in bag_contents.get(str(bag_slot), []):
			if existing.get("item_id") == id:
				existing["quantity"] = int(existing.get("quantity", 1)) + int(item.get("quantity", 1))
				return true
	return false


# Stranded items that had no room at login wait until there is some: every inventory change tries again.
var _orphans_waiting := 0
var _orphan_notice_shown := false
var _rescuing := false

func _retry_orphans() -> void:
	if _orphans_waiting <= 0 or _rescuing:
		return
	_rescuing = true
	var before := _orphans_waiting
	_rescue_orphaned_items()
	if _orphans_waiting < before:
		sync_to_global()
		inventory_changed.emit()  # redraw the bags with what just dropped in (the _rescuing guard stops a loop)
	_rescuing = false


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

# Moves an item into another bag's empty slot (the character sheet shows each bag separately), if that bag takes it and has room.
func _move_bag_to_bag(src_bag: int, index: int, dst_bag: int) -> void:
	var src: Array = bag_contents.get(str(src_bag), [])
	var bag := get_basic_inventory_slot(dst_bag)
	if index < 0 or index >= src.size() or not is_bag(bag):
		return
	var item: Dictionary = src[index]
	if not bag_accepts(bag, item):
		GameLog.log_general("[color=#ff8866]The %s only holds %s.[/color]" % [str(bag.get("name", "bag")), bag_holds_text(bag)])
		return
	var key := str(dst_bag)
	if not bag_contents.has(key):
		bag_contents[key] = []
	if bag_contents[key].size() >= get_bag_size(bag):
		GameLog.log_general("[color=#ff8866]The %s is full.[/color]" % str(bag.get("name", "bag")))
		return
	src.remove_at(index)
	bag_contents[key].append(item)


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

	if bag_a != bag_b and (not bag_accepts(get_basic_inventory_slot(bag_b), items_a[index_a]) \
			or not bag_accepts(get_basic_inventory_slot(bag_a), items_b[index_b])):
		GameLog.log_general("[color=#ff8866]That bag only holds %s.[/color]" % bag_holds_text(get_basic_inventory_slot(bag_b) if not bag_accepts(get_basic_inventory_slot(bag_b), items_a[index_a]) else get_basic_inventory_slot(bag_a)))
		return
	var tmp = items_a[index_a]
	items_a[index_a] = items_b[index_b]
	items_b[index_b] = tmp
#endregion

#region Equipment Management
# Equipping or taking something off plays the equip sound when it works.
func equip_item(item: Dictionary, src_type: String, src_basic_idx: int = -1, src_bag_slot: int = -1, src_item_idx: int = -1) -> bool:
	var done := _equip_item(item, src_type, src_basic_idx, src_bag_slot, src_item_idx)
	if done:
		Sfx.play("equip")
	return done


func unequip_item(equip_slot: String) -> bool:
	var done := _unequip_item(equip_slot)
	if done:
		Sfx.play("equip")
	return done


func _equip_item(item: Dictionary, src_type: String, src_basic_idx: int = -1, src_bag_slot: int = -1, src_item_idx: int = -1) -> bool:
	var item_slot: String = item.get("slot", "none")
	var equip_slot: String = ITEM_SLOT_MAP.get(item_slot, "")
	if equip_slot.is_empty():
		print("⚠️ '%s' cannot be equipped (slot: %s)" % [item.get("name", "?"), item_slot])
		return false
	# Armour type (ArmorTypes): a Gravecaller can't put on plate. Items already worn stay on (nothing is stripped at login).
	var wearer_class := str(Global.player_data.get("player_class", ""))
	if not ArmorTypes.can_wear(item, wearer_class):
		GameLog.log_general("[color=#ff8866]%s[/color]" % ArmorTypes.refusal(item, wearer_class))
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

func _unequip_item(equip_slot: String) -> bool:
	var item: Variant = equipped.get(equip_slot, null)
	if item == null:
		return false
	if item is Dictionary:
		(item as Dictionary).erase("lit")  # taking a light off snuffs it (burn_remaining is kept)
	# A free character-sheet slot first (as before), else any bag with room — it used to give up when the character-sheet
	# slots were full, so Unequip silently did nothing (test 23).
	if basic_inventory.find(null) < 0:
		var bag := _bag_with_room_for(item, -1, -1)
		if bag < 0:
			GameLog.log_general("[color=#ff8866]There is no room in your bags to take off the %s.[/color]" % str(item.get("name", "item")))
			return false
		if not bag_contents.has(str(bag)):
			bag_contents[str(bag)] = []
		bag_contents[str(bag)].append(item)
		equipped[equip_slot] = null
		sync_to_global()
		equipment_changed.emit()
		inventory_changed.emit()
		return true
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
