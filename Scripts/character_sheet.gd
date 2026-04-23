extends CanvasLayer

# UI references
@onready var name_label = $main_panel/scroll_container/scroll_wrapper/stat_block/name_label
@onready var class_label = $main_panel/scroll_container/scroll_wrapper/stat_block/class_label
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

# Storage slots (12 basic inventory slots)
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

func _ready():
	if Inventory.inventory_changed.is_connected(_on_inventory_changed) == false:
		Inventory.inventory_changed.connect(_on_inventory_changed)
	refresh_storage_slots()

func refresh_storage_slots():
	for i in range(Inventory.BASIC_INVENTORY_SIZE):
		var slot = storage_slots[i]
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

			if item.has("icon") and item.icon is String and FileAccess.file_exists(item.icon):
				slot.texture_normal = load(item.icon)
			else:
				slot.texture_normal = null

			slot.tooltip_text = item.get("name", "Unknown Item")

func set_character_data(data: Dictionary):
	name_label.text = "Name: %s" % data.get("player_name", "")
	class_label.text = "Class: %s" % data.get("player_class", "")
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
	crit_chance_label.text = "Crit Chance: %d%%" % data.get("crit_chance", 0)
	armor_class_label.text = "Armor Class: %d" % data.get("armor_class", 0)
	attack_label.text = "Attack: %d" % data.get("attack", 0)
	weight_label.text = "Weight: %d" % data.get("max_weight", 0)
	xp_label.text = "XP: %d / %d" % [data.get("xp", 0), data.get("xp_next_level", 0)]

	refresh_storage_slots()

func _on_inventory_changed():
	refresh_storage_slots()
