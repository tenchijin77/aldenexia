# character_sheet.gd
extends CanvasLayer

#region Character Info
@onready var name_label = $main_panel/scroll_container/scroll_wrapper/stat_block/name_label
@onready var class_label = $main_panel/scroll_container/scroll_wrapper/stat_block/class_label
@onready var level_label = $main_panel/scroll_container/scroll_wrapper/stat_block/level_label
@onready var xp_label = $main_panel/scroll_container/scroll_wrapper/stat_block/xp_label
@onready var health_label = $main_panel/scroll_container/scroll_wrapper/stat_block/health_label
@onready var mana_label = $main_panel/scroll_container/scroll_wrapper/stat_block/mana_label
@onready var stamina_label = $main_panel/scroll_container/scroll_wrapper/stat_block/stamina_label
#endregion

#region Primary Stats
@onready var strength_label = $main_panel/scroll_container/scroll_wrapper/stat_block/strength_label
@onready var constitution_label = $main_panel/scroll_container/scroll_wrapper/stat_block/constitution_label
@onready var dexterity_label = $main_panel/scroll_container/scroll_wrapper/stat_block/dexterity_label
@onready var intelligence_label = $main_panel/scroll_container/scroll_wrapper/stat_block/intelligence_label
@onready var wisdom_label = $main_panel/scroll_container/scroll_wrapper/stat_block/wisdom_label
@onready var charisma_label = $main_panel/scroll_container/scroll_wrapper/stat_block/charisma_label
@onready var luck_label = $main_panel/scroll_container/scroll_wrapper/stat_block/luck_label
#endregion

#region Resistances
@onready var acid_label = $main_panel/scroll_container/scroll_wrapper/resist_block/acid_label
@onready var cold_label = $main_panel/scroll_container/scroll_wrapper/resist_block/cold_label
@onready var fire_label = $main_panel/scroll_container/scroll_wrapper/resist_block/fire_label
@onready var magic_label = $main_panel/scroll_container/scroll_wrapper/resist_block/magic_label
@onready var psychic_label = $main_panel/scroll_container/scroll_wrapper/resist_block/psychic_label
#endregion

#region Equipment (All your existing labels)
@onready var ear1_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/ear1_label
@onready var neck_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/neck_label
@onready var face_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/face_label
@onready var head_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/head_label
@onready var ear2_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/ear2_label
@onready var finger1_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/finger1_label
@onready var wrist1_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/wrist1_label
@onready var arms_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/arms_label
@onready var hands_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/hands_label
@onready var wrist2_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/wrist2_label
@onready var finger2_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/finger2_label
@onready var shoulders_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/shoulders_label
@onready var chest_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/chest_label
@onready var back_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/back_label
@onready var waist_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/waist_label
@onready var legs_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/legs_label
@onready var feet_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/feet_label
@onready var trinket1_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/trinket1_label
@onready var trinket2_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/trinket2_label
@onready var primary_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/primary_label
@onready var secondary_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/secondary_label
@onready var ranged_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/ranged_label
@onready var ammo_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/ammo_label
@onready var charm_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/charm_label
@onready var focus_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/focus_label
#endregion

func _ready():
	print("✅ Character sheet _ready()")

func set_character_data(data: Dictionary):
	print("✅ Character sheet: set_character_data called")

	if typeof(data) != TYPE_DICTIONARY:
		push_error("❌ Invalid data type received")
		return

	# Basic info
	name_label.text = "Name: " + data.get("player_name", "Unknown")
	class_label.text = "Class: " + data.get("player_class", "Unknown")
	level_label.text = "Level: %d" % data.get("player_level", 1)

	# XP
	var player_level = data.get("player_level", 1)
	var current_xp = data.get("xp", 0)
	var xp_next = data.get("xp_next_level", 100)
	if player_level >= Global.max_player_level:
		xp_label.text = "XP: %d / MAX" % current_xp
	else:
		xp_label.text = "XP: %d / %d" % [current_xp, xp_next]

	# Vitals
	var derived = data.get("derived", {})
	var cur_hp = data.get("current_health", 100)
	var max_hp = derived.get("health", 100)
	var cur_mp = data.get("current_mana", 50)
	var max_mp = derived.get("mana", 50)
	var cur_stam = data.get("current_stamina", 100)
	var max_stam = data.get("max_stamina", 100)
	var satiety = data.get("satiety", 100)
	var thirst = data.get("thirst", 100)

	health_label.text = "HP: %d/%d" % [cur_hp, max_hp]
	mana_label.text = "MP: %d/%d" % [cur_mp, max_mp]
	stamina_label.text = "Stamina: %d/%d | Hunger: %d | Thirst: %d" % [cur_stam, max_stam, satiety, thirst]

	# Primary stats
	var stats = data.get("stats", {})
	strength_label.text = "STR: %d" % stats.get("strength", 0)
	constitution_label.text = "CON: %d" % stats.get("constitution", 0)
	dexterity_label.text = "DEX: %d" % stats.get("dexterity", 0)
	intelligence_label.text = "INT: %d" % stats.get("intelligence", 0)
	wisdom_label.text = "WIS: %d" % stats.get("wisdom", 0)
	charisma_label.text = "CHA: %d" % stats.get("charisma", 0)
	luck_label.text = "LUCK: %d" % stats.get("luck", 0)

	# Resistances
	var resist = data.get("resistances", {})
	acid_label.text = "Acid: %d%%" % resist.get("acid", 0)
	cold_label.text = "Cold: %d%%" % resist.get("cold", 0)
	fire_label.text = "Fire: %d%%" % resist.get("fire", 0)
	magic_label.text = "Magic: %d%%" % resist.get("magic", 0)
	psychic_label.text = "Psychic: %d%%" % resist.get("psychic", 0)

	# Equipment
	var eq = data.get("equipment", {})
	ear1_label.text = "Ear 1: " + (eq.get("ear1", "") if eq.get("ear1", "") != "" else "Empty")
	ear2_label.text = "Ear 2: " + (eq.get("ear2", "") if eq.get("ear2", "") != "" else "Empty")
	neck_label.text = "Neck: " + (eq.get("neck", "") if eq.get("neck", "") != "" else "Empty")
	face_label.text = "Face: " + (eq.get("face", "") if eq.get("face", "") != "" else "Empty")
	head_label.text = "Head: " + (eq.get("head", "") if eq.get("head", "") != "" else "Empty")
	finger1_label.text = "Finger 1: " + (eq.get("finger1", "") if eq.get("finger1", "") != "" else "Empty")
	finger2_label.text = "Finger 2: " + (eq.get("finger2", "") if eq.get("finger2", "") != "" else "Empty")
	wrist1_label.text = "Wrist 1: " + (eq.get("wrist1", "") if eq.get("wrist1", "") != "" else "Empty")
	wrist2_label.text = "Wrist 2: " + (eq.get("wrist2", "") if eq.get("wrist2", "") != "" else "Empty")
	arms_label.text = "Arms: " + (eq.get("arms", "") if eq.get("arms", "") != "" else "Empty")
	hands_label.text = "Hands: " + (eq.get("hands", "") if eq.get("hands", "") != "" else "Empty")
	shoulders_label.text = "Shoulders: " + (eq.get("shoulders", "") if eq.get("shoulders", "") != "" else "Empty")
	chest_label.text = "Chest: " + (eq.get("chest", "") if eq.get("chest", "") != "" else "Empty")
	back_label.text = "Back: " + (eq.get("back", "") if eq.get("back", "") != "" else "Empty")
	waist_label.text = "Waist: " + (eq.get("waist", "") if eq.get("waist", "") != "" else "Empty")
	legs_label.text = "Legs: " + (eq.get("legs", "") if eq.get("legs", "") != "" else "Empty")
	feet_label.text = "Feet: " + (eq.get("feet", "") if eq.get("feet", "") != "" else "Empty")
	trinket1_label.text = "Trinket 1: " + (eq.get("trinket1", "") if eq.get("trinket1", "") != "" else "Empty")
	trinket2_label.text = "Trinket 2: " + (eq.get("trinket2", "") if eq.get("trinket2", "") != "" else "Empty")
	primary_label.text = "Primary: " + (eq.get("primary", "") if eq.get("primary", "") != "" else "Empty")
	secondary_label.text = "Secondary: " + (eq.get("secondary", "") if eq.get("secondary", "") != "" else "Empty")
	ranged_label.text = "Ranged: " + (eq.get("ranged", "") if eq.get("ranged", "") != "" else "Empty")
	ammo_label.text = "Ammo: " + (eq.get("ammo", "") if eq.get("ammo", "") != "" else "Empty")
	charm_label.text = "Charm: " + (eq.get("charm", "") if eq.get("charm", "") != "" else "Empty")
	focus_label.text = "Focus: " + (eq.get("focus", "") if eq.get("focus", "") != "" else "Empty")

	print("✅ Character sheet updated for: %s" % name_label.text)

func _input(event: InputEvent):
	if Input.is_action_just_pressed("toggle_character_sheet"):
		queue_free()
		get_viewport().set_input_as_handled()
