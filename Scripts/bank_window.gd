# bank_window.gd — the bank (opened by right-clicking or hailing the banker, banker_npc.gd). Inventory.BANK_SIZE slots
# that belong to the character and are saved with it. Drag items between the bank and your bags / character-sheet slots
# (either way; the same item stacks together); right-click a slot to inspect it. Closes itself when you walk away from
# the banker. Built on GameWindow like the quest journal.
extends GameWindow

const POSITION_KEY := "bank"
const SLOT_SIZE := Vector2(48, 48)
const COLUMNS := 6
const MAX_DISTANCE := 8.0

var _banker: Node3D = null
var _grid: GridContainer
var _count: Label


func _ready() -> void:
	build_frame("Bank", POSITION_KEY, Vector2(360, 330), Vector2(330, 260))
	_count = header("")
	body.add_child(_count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	var hint := header("Drag items here from your bags, and back again.")
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
	var used := 0
	for i in Inventory.BANK_SIZE:
		var item := Inventory.get_bank_slot(i)
		var slot = load("res://Scripts/slot_button.gd").new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.ignore_texture_size = true
		slot.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		slot.slot_type = "bank"
		slot.slot_index = i
		slot.item_data = item
		if not item.is_empty():
			used += 1
			slot.texture_normal = ItemIcon.texture(item)
			slot.tooltip_text = ItemIcon.tooltip(item)
		_grid.add_child(slot)
	_count.text = "%d / %d slots used" % [used, Inventory.BANK_SIZE]
