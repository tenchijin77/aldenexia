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
var equipment_slots: Dictionary = {}

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
	if Inventory.equipment_changed.is_connected(_on_equipment_changed) == false:
		Inventory.equipment_changed.connect(_on_equipment_changed)
	if Global.currency_changed.is_connected(_on_currency_changed) == false:
		Global.currency_changed.connect(_on_currency_changed)
	_init_equipment_slots()
	refresh_storage_slots()
	refresh_equipment_slots()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

const _SLOT_LABELS: Dictionary = {
	"ear1": "Earring", "ear2": "Earring", "neck": "Neck", "face": "Face",
	"head": "Head", "finger1": "Ring", "finger2": "Ring",
	"wrist1": "Wrist", "wrist2": "Wrist", "arms": "Arms",
	"hands": "Hands", "shoulders": "Shoulder", "chest": "Chest",
	"back": "Back", "waist": "Belt", "legs": "Legs", "feet": "Feet",
	"trinket1": "Trinket", "trinket2": "Trinket",
	"primary": "Primary", "offhand": "Off Hand", "ranged": "Ranged",
	"ammo": "Ammo", "charm": "Charm", "focus": "Focus",
}

var _pending_slot_cfg: Array = []

func _init_equipment_slots() -> void:
	var block = $main_panel/scroll_container/scroll_wrapper/equipment_block
	_pending_slot_cfg.clear()

	block.add_child(_build_3col("ear1",      "head",    "ear2"))
	block.add_child(_build_3col("",          "neck",    ""))
	block.add_child(_build_3col("shoulders", "face",    "back"))
	block.add_child(_build_3col("wrist1",    "chest",   "wrist2"))
	block.add_child(_build_3col("",          "arms",    ""))
	block.add_child(_build_3col("charm",     "waist",   "focus"))
	block.add_child(_build_3col("finger1",   "hands",   "finger2"))
	block.add_child(_build_3col("",          "legs",    ""))
	block.add_child(_build_3col("",          "feet",    ""))

	block.add_child(_build_section_header("— Weapon Loadout —"))
	block.add_child(_build_row(["primary", "offhand", "ranged", "ammo"]))

	block.add_child(_build_section_header("— Accessories —"))
	block.add_child(_build_row(["trinket1", "trinket2"]))

	for cfg in _pending_slot_cfg:
		var btn = cfg[0]
		var sn: String = cfg[1]
		btn.slot_type = "equipment"
		btn.slot_name = sn
		btn.slot_index = -1
		btn.bag_slot = -1
		btn.item_index = -1
		btn.item_data = {}
		btn.tooltip_text = _SLOT_LABELS.get(sn, sn.capitalize())
		equipment_slots[sn] = btn

func _build_3col(left: String, center: String, right: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_make_slot_or_spacer(left))
	row.add_child(_make_slot_or_spacer(center))
	row.add_child(_make_slot_or_spacer(right))
	return row

func _make_slot_or_spacer(slot_name: String) -> Control:
	if slot_name == "":
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(48, 62)
		return spacer
	return _make_slot_vbox(slot_name)

func _build_section_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
	return lbl

func _build_row(slots: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for sn in slots:
		row.add_child(_make_slot_vbox(sn))
	return row

func _make_slot_vbox(slot_name: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var btn = load("res://Scripts/slot_button.gd").new()
	vbox.add_child(btn)
	_pending_slot_cfg.append([btn, slot_name])

	var lbl := Label.new()
	lbl.text = _SLOT_LABELS.get(slot_name, slot_name.capitalize())
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(lbl)

	return vbox

const DRAG_BAR_HEIGHT := 20.0

func _on_panel_gui_input(event: InputEvent) -> void:
	var panel = $main_panel
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos = event.position
			if pos.x > panel.size.x - RESIZE_MARGIN and pos.y > panel.size.y - RESIZE_MARGIN:
				_resizing = true
			elif pos.y < DRAG_BAR_HEIGHT:
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
	armor_class_label.text = "Armor Class: %d" % (data.get("armor_class", 0) + Inventory.get_equipped_armor_class())
	var weapon := Inventory.get_equipped_weapon()
	attack_label.text = "Attack: %d" % (data.get("attack", 0) + weapon.get("damage", 0))
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
	refresh_equipment_slots()

func refresh_equipment_slots() -> void:
	for slot_name in equipment_slots:
		var btn = equipment_slots[slot_name]
		var item: Variant = Inventory.equipped.get(slot_name, null)
		if item != null:
			btn.item_data = item
			var icon_path: String = item.get("icon", "")
			if icon_path != "" and FileAccess.file_exists(icon_path):
				btn.texture_normal = load(icon_path)
			else:
				btn.texture_normal = null
			btn.tooltip_text = item.get("name", slot_name)
		else:
			btn.item_data = {}
			btn.texture_normal = null
			btn.tooltip_text = slot_name.capitalize()
		btn.queue_redraw()

func _on_inventory_changed():
	refresh_storage_slots()

func _on_equipment_changed() -> void:
	refresh_equipment_slots()

func _on_currency_changed() -> void:
	if not money_label:
		return
	var plat: int = Global.player_data.get("platinum", 0)
	var gold: int = Global.player_data.get("gold",     0)
	var silver: int = Global.player_data.get("silver",  0)
	var copper: int = Global.player_data.get("copper",  0)
	money_label.text = "Money: %dpp  %dgp  %dsp  %dcp" % [plat, gold, silver, copper]
