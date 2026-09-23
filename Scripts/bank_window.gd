# bank_window.gd — the bank (opened by right-clicking or hailing the banker, banker_npc.gd). Inventory.BANK_SIZE slots
# that belong to the character and are saved with it. Drag items between the bank and your bags / character-sheet slots
# (either way; the same item stacks together); right-click a slot to inspect it. A bag in a bank slot opens its own slots
# below the bank grid, like a bag on the character sheet (and a full bag can be banked whole). Closes itself when you walk
# away from the banker. Built on GameWindow like the quest journal.
extends GameWindow

const POSITION_KEY := "bank"
const SLOT_SIZE := Vector2(48, 48)
const COLUMNS := 6
const MAX_DISTANCE := 8.0

var _banker: Node3D = null
var _grid: GridContainer
var _count: Label
var _bag_sections: VBoxContainer


func _ready() -> void:
	add_to_group("bank_window")
	open_sound = "bank_vault"  # while it's open, right-clicking an item offers Deposit / Withdraw (slot_button.gd)
	build_frame("Bank", POSITION_KEY, Vector2(380, 420), Vector2(360, 300))
	_count = header("")
	body.add_child(_count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	content.add_child(_grid)
	_bag_sections = VBoxContainer.new()
	_bag_sections.add_theme_constant_override("separation", 8)
	content.add_child(_bag_sections)
	scroll.custom_minimum_size = Vector2(COLUMNS * (SLOT_SIZE.x + 6) + 14, 230)
	var hint := header("Drag items here from your bags and back, or right-click an item > Deposit / Withdraw.")
	hint.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	body.add_child(hint)
	Inventory.inventory_changed.connect(_refresh)
	_refresh()


func set_banker(banker: Node3D) -> void:
	_banker = banker


func _process(_delta: float) -> void:
	var player := TargetFrame.local_player() as Node3D
	if is_instance_valid(_banker) and is_instance_valid(player) and player.global_position.distance_to(_banker.global_position) > MAX_DISTANCE:
		GameLog.log_general("You walk away from the bank.")
		queue_free()


func _refresh() -> void:
	if not is_instance_valid(_grid):
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for child in _bag_sections.get_children():
		_bag_sections.remove_child(child)
		child.queue_free()
	var used := 0
	for i in Inventory.BANK_SIZE:
		var item := Inventory.get_bank_slot(i)
		var slot := _slot("bank", i, -1, -1, item)
		if not item.is_empty():
			used += 1
			if Inventory.is_bag(item):
				var holds := Inventory.bag_holds_text(item)
				slot.tooltip_text += "\n(%d-slot bag%s — its slots are below)" % [Inventory.get_bag_size(item), (" for " + holds) if not holds.is_empty() else ""]
				_add_bag_section(i, item)
		_grid.add_child(slot)
	_count.text = "%d / %d bank slots used" % [used, Inventory.BANK_SIZE]


# A bag sitting in bank slot `bank_slot`: its name, how full it is, and a slot for each of its places.
func _add_bag_section(bank_slot: int, bag: Dictionary) -> void:
	var contents := Inventory.get_bank_bag_contents(bank_slot)
	var capacity := Inventory.get_bag_size(bag)
	var holds := Inventory.bag_holds_text(bag)
	var title := header("%s — %d / %d%s" % [str(bag.get("name", "Bag")), contents.size(), capacity, ("  •  %s only" % holds) if not holds.is_empty() else ""])
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	_bag_sections.add_child(title)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_bag_sections.add_child(grid)
	for index in capacity:
		var item: Dictionary = contents[index] if index < contents.size() else {}
		grid.add_child(_slot("bank_bag", -1, bank_slot, index if index < contents.size() else -1, item))


func _slot(type: String, index: int, bag_slot: int, item_index: int, item: Dictionary) -> Control:
	var slot = load("res://Scripts/slot_button.gd").new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.ignore_texture_size = true
	slot.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	slot.slot_type = type
	slot.slot_index = index
	slot.bag_slot = bag_slot
	slot.item_index = item_index
	slot.item_data = item
	if not item.is_empty():
		slot.texture_normal = ItemIcon.texture(item)
		slot.tooltip_text = ItemIcon.tooltip(item)
	return slot
