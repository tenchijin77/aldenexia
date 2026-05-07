#character_sheet.gd - player's inventory/paperdoll display
extends CanvasLayer

@onready var name_label = $main_panel/scroll_container/scroll_wrapper/stat_block/name_label
@onready var class_label = $main_panel/scroll_container/scroll_wrapper/stat_block/class_label
@onready var race_label = $main_panel/scroll_container/scroll_wrapper/stat_block/race_label
@onready var level_label = $main_panel/scroll_container/scroll_wrapper/stat_block/level_label
@onready var strength_label = $main_panel/scroll_container/scroll_wrapper/stat_block/strength_label
@onready var constitution_label = $main_panel/scroll_container/scroll_wrapper/stat_block/constitution_label
@onready var dexterity_label = $main_panel/scroll_container/scroll_wrapper/stat_block/dexterity_label
@onready var intelligence_label = $main_panel/scroll_container/scroll_wrapper/stat_block/intelligence_label
@onready var wisdom_label = $main_panel/scroll_container/scroll_wrapper/stat_block/wisdom_label
@onready var charisma_label = $main_panel/scroll_container/scroll_wrapper/stat_block/charisma_label
@onready var luck_label = $main_panel/scroll_container/scroll_wrapper/stat_block/luck_label
@onready var health_label = $main_panel/scroll_container/scroll_wrapper/stat_block/health_label
@onready var mana_label = $main_panel/scroll_container/scroll_wrapper/stat_block/mana_label
@onready var stamina_label = $main_panel/scroll_container/scroll_wrapper/stat_block/stamina_label
@onready var spell_power_label = $main_panel/scroll_container/scroll_wrapper/stat_block/spell_power_label
@onready var crit_chance_label = $main_panel/scroll_container/scroll_wrapper/stat_block/crit_chance_label
@onready var armor_class_label = $main_panel/scroll_container/scroll_wrapper/stat_block/armor_class_label
@onready var attack_label = $main_panel/scroll_container/scroll_wrapper/stat_block/attack_label
@onready var weight_label = $main_panel/scroll_container/scroll_wrapper/stat_block/weight_label
@onready var xp_label = $main_panel/scroll_container/scroll_wrapper/stat_block/xp_label

@onready var storage_slots = [
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_0,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_1,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_2,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_3,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_4,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_5,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_6,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_7,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_8,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_9,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_10,
	$main_panel/scroll_container/scroll_wrapper/storage_block/slot_11
]

var money_label: Label
var _dragging := false
var _resizing := false
const RESIZE_MARGIN := 16.0
var resistance_label: Label

func _ready():
	$main_panel.gui_input.connect(_on_panel_gui_input)
	var storage_block = $main_panel/scroll_container/scroll_wrapper/storage_block
	storage_block.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	money_label = Label.new()
	$main_panel/scroll_container/scroll_wrapper/stat_block.add_child(money_label)
	resistance_label = Label.new()
	$main_panel/scroll_container/scroll_wrapper/stat_block.add_child(resistance_label)
	if Inventory.inventory_changed.is_connected(_on_inventory_changed) == false:
		Inventory.inventory_changed.connect(_on_inventory_changed)
	refresh_storage_slots()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_panel_gui_input(event: InputEvent) -> void:
	var panel = $main_panel
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos = event.position
			if pos.x > panel.size.x - RESIZE_MARGIN and pos.y > panel.size.y - RESIZE_MARGIN:
				_resizing = true
			else:
				_dragging = true
		else:
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _dragging:
			panel.offset_left += event.relative.x
			panel.offset_top += event.relative.y
			panel.offset_right += event.relative.x
			panel.offset_bottom += event.relative.y
		elif _resizing:
			panel.offset_right = max(panel.offset_left + 200, panel.offset_right + event.relative.x)
			panel.offset_bottom = max(panel.offset_top + 150, panel.offset_bottom + event.relative.y)

func refresh_storage_slots():
	for i in range(Inventory.BASIC_INVENTORY_SIZE):
		var slot = storage_slots[i]
		slot.custom_minimum_size = Vector2(48, 48)
		slot.ignore_texture_size = true
		slot.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		slot.slot_type = "basic"
		slot.slot_index = i
		slot.bag_slot = -1
		slot.item_index = -1

		var item = Inventory.basic_inventory[i]
		if item == null:
			slot.item_data = {}
			slot.texture_normal = null
			slot.tooltip_text = ""
		else:
			slot.item_data = item
			if item.has("icon") and item.get("icon") is String and FileAccess.file_exists(item.get("icon", "")):
				slot.texture_normal = load(item.get("icon"))
			else:
				slot.texture_normal = null
			slot.tooltip_text = item.get("name", "Unknown Item")

		slot.queue_redraw()

func set_character_data(data: Dictionary):
	name_label.text = "Name: %s" % data.get("player_name", "").capitalize()
	race_label.text = "Race: %s" % data.get("player_race", "").capitalize()
	class_label.text = "Class: %s" % data.get("player_class", "").capitalize()
	level_label.text = "Level: %d" % data.get("player_level", 1)
	strength_label.text = "Strength: %d" % data.stats.get("strength", 0)
	constitution_label.text = "Constitution: %d" % data.stats.get("constitution", 0)
	dexterity_label.text = "Dexterity: %d" % data.stats.get("dexterity", 0)
	intelligence_label.text = "Intelligence: %d" % data.stats.get("intelligence", 0)
	wisdom_label.text = "Wisdom: %d" % data.stats.get("wisdom", 0)
	charisma_label.text = "Charisma: %d" % data.stats.get("charisma", 0)
	luck_label.text = "Luck: %d" % data.stats.get("luck", 0)

	health_label.text = "Health: %d / %d" % [data.get("current_health", 0), data.get("max_health", 0)]
	mana_label.text = "Mana: %d / %d" % [data.get("current_mana", 0), data.get("max_mana", 0)]
	stamina_label.text = "Stamina: %d / %d" % [data.get("current_stamina", 0), data.get("max_stamina", 0)]

	spell_power_label.text = "Spell Power: %d" % data.get("spell_power", 0)
	crit_chance_label.text = "Crit Chance: %.1f%%" % data.get("crit_chance", 0)
	armor_class_label.text = "Armor Class: %d" % data.get("armor_class", 0)
	attack_label.text = "Attack: %d" % data.get("attack", 0)
	weight_label.text = "Weight: %d" % data.get("max_weight", 0)
	xp_label.text = "XP: %d / %d" % [data.get("xp", 0), data.get("xp_next_level", 0)]

	var plat = data.get("platinum", 0)
	var gold = data.get("gold", 0)
	var silver = data.get("silver", 0)
	var copper = data.get("copper", 0)
	if money_label:
		money_label.text = "Money: %dpp  %dgp  %dsp  %dcp" % [plat, gold, silver, copper]
	var res: Dictionary = data.get("resistances", {})
	if resistance_label:
		resistance_label.text = "Resist:  Acid %d  Cold %d  Fire %d  Magic %d  Psychic %d" % [
		res.get("acid", 0), res.get("cold", 0), res.get("fire", 0),
		res.get("magic", 0), res.get("psychic", 0)
	]
	refresh_storage_slots()

func _on_inventory_changed():
	refresh_storage_slots()
