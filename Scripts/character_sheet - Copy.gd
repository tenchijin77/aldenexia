# character_sheet.gd
extends CanvasLayer

var stats: Dictionary = {}
var derived: Dictionary = {}
var resistances: Dictionary = {}
var weight: Dictionary = {}
var equipped: Dictionary = {}
var combat: Dictionary = {}
var level: int = 1
var experience: int = 0
var player_name: String = ""
var player_class: String = ""

func _ready():
	visible = false
	load_character_data()
	update_labels()
	# Initialize experience_bar if it exists
	if $main_panel/scroll_container/scroll_wrapper/stat_block.get_node("experience_bar"):
		var exp_bar = $main_panel/scroll_container/scroll_wrapper/stat_block.get_node("experience_bar")
		exp_bar.max_value = 1000  # Adjust based on your game's max experience
		exp_bar.value = experience

func load_character_data():
	var file := FileAccess.open("res://Data/character_stats.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		if typeof(data) == TYPE_DICTIONARY:
			stats = data.get("stats", {})
			derived = data.get("derived", {})
			resistances = data.get("resistances", {})
			weight = data.get("weight", {})
			equipped = data.get("equipped", {})
			combat = data.get("combat", {})
			level = data.get("level", 1)
			experience = data.get("experience", 0)
			player_name = data.get("player_name", "Unnamed")
			player_class = data.get("player_class", "Adventurer")
		else:
			push_error("Invalid JSON structure in character_stats.json")
		file.close()
	else:
		push_error("Failed to open character_stats.json. Path: res://Data/character_stats.json")

func update_labels():
	var stat_block := $main_panel/scroll_container/scroll_wrapper/stat_block
	var resist_block := $main_panel/scroll_container/scroll_wrapper/resist_block
	var equipment_block := $main_panel/scroll_container/scroll_wrapper/equipment_block

	if stat_block:
		stat_block.get_node("strength_label").text = "Strength: " + str(stats.get("strength", 0))
		stat_block.get_node("constitution_label").text = "Constitution: " + str(stats.get("constitution", 0))
		stat_block.get_node("dexterity_label").text = "Dexterity: " + str(stats.get("dexterity", 0))
		stat_block.get_node("intelligence_label").text = "Intelligence: " + str(stats.get("intelligence", 0))
		stat_block.get_node("wisdom_label").text = "Wisdom: " + str(stats.get("wisdom", 0))
		stat_block.get_node("charisma_label").text = "Charisma: " + str(stats.get("charisma", 0))
		stat_block.get_node("luck_label").text = "Luck: " + str(stats.get("luck", 0))
		stat_block.get_node("health_label").text = "Health: " + str(derived.get("health", 0))
		stat_block.get_node("mana_label").text = "Mana: " + str(derived.get("mana", 0))
		stat_block.get_node("stamina_label").text = "Stamina: " + str(derived.get("stamina_points", 0))
		stat_block.get_node("crit_chance_label").text = "Crit Chance: " + str(derived.get("crit_chance", 0)) + "%"
		stat_block.get_node("spell_power_label").text = "Spell Power: " + str(derived.get("spell_power", 0))
		stat_block.get_node("armor_class_label").text = "Armor Class: " + str(combat.get("armor_class", 0))
		stat_block.get_node("attack_label").text = "Attack: " + str(combat.get("attack", 0))
		stat_block.get_node("weight_label").text = "Weight: " + str(weight.get("current", 0)) + " / " + str(weight.get("max", 0)) + " lbs"
		stat_block.get_node("level_label").text = "Level: " + str(level)
		stat_block.get_node("class_label").text = "Class: " + player_class
		stat_block.get_node("name_label").text = "Name: " + player_name

	if resist_block:
		resist_block.get_node("acid_label").text = "Acid: " + str(resistances.get("acid", 0))
		resist_block.get_node("cold_label").text = "Cold: " + str(resistances.get("cold", 0))
		resist_block.get_node("fire_label").text = "Fire: " + str(resistances.get("fire", 0))
		resist_block.get_node("magic_label").text = "Magic: " + str(resistances.get("magic", 0))
		resist_block.get_node("psychic_label").text = "Psychic: " + str(resistances.get("psychic", 0))

	if equipment_block:
		equipment_block.get_node("ear1_label").text = "Ear 1: " + str(equipped.get("ear1", "None"))
		equipment_block.get_node("neck_label").text = "Neck: " + str(equipped.get("neck", "None"))
		equipment_block.get_node("face_label").text = "Face: " + str(equipped.get("face", "None"))
		equipment_block.get_node("head_label").text = "Head: " + str(equipped.get("head", "None"))
		equipment_block.get_node("ear2_label").text = "Ear 2: " + str(equipped.get("ear2", "None"))
		equipment_block.get_node("finger1_label").text = "Finger 1: " + str(equipped.get("finger1", "None"))
		equipment_block.get_node("wrist1_label").text = "Wrist 1: " + str(equipped.get("wrist1", "None"))
		equipment_block.get_node("arms_label").text = "Arms: " + str(equipped.get("arms", "None"))
		equipment_block.get_node("hands_label").text = "Hands: " + str(equipped.get("hands", "None"))
		equipment_block.get_node("wrist2_label").text = "Wrist 2: " + str(equipped.get("wrist2", "None"))
		equipment_block.get_node("finger2_label").text = "Finger 2: " + str(equipped.get("finger2", "None"))
		equipment_block.get_node("shoulders_label").text = "Shoulders: " + str(equipped.get("shoulders", "None"))
		equipment_block.get_node("chest_label").text = "Chest: " + str(equipped.get("chest", "None"))
		equipment_block.get_node("back_label").text = "Back: " + str(equipped.get("back", "None"))
		equipment_block.get_node("waist_label").text = "Waist: " + str(equipped.get("waist", "None"))
		equipment_block.get_node("legs_label").text = "Legs: " + str(equipped.get("legs", "None"))
		equipment_block.get_node("feet_label").text = "Feet: " + str(equipped.get("feet", "None"))
		equipment_block.get_node("trinket1_label").text = "Trinket 1: " + str(equipped.get("trinket1", "None"))
		equipment_block.get_node("trinket2_label").text = "Trinket 2: " + str(equipped.get("trinket2", "None"))
		equipment_block.get_node("primary_label").text = "Primary: " + str(equipped.get("primary", "None"))
		equipment_block.get_node("secondary_label").text = "Secondary: " + str(equipped.get("secondary", "None"))
		equipment_block.get_node("ranged_label").text = "Ranged: " + str(equipped.get("ranged", "None"))
		equipment_block.get_node("ammo_label").text = "Ammo: " + str(equipped.get("ammo", "None"))

func _input(event):
	if event.is_action_pressed("toggle_character_sheet"):
		visible = !visible
		if visible:
			update_labels()
