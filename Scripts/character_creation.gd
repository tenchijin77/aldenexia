# character_creation.gd
extends Control

# Stat Logic
var class_restrictions = {}
var base_stats := {}
var final_stats := {}
var stat_pool := 4
var selected_race := ""

# Class → Casting Stat Map
var casting_stats := {
	"voidknight": "intelligence",
	"gravecaller": "intelligence",
	"runecaster": "intelligence",
	"arcanist": "intelligence",
	"chaosborn": "intelligence",
	"lightsworn": "wisdom",
	"lightmender": "wisdom",
	"spiritcaller": "wisdom",
	"wildspeaker": "wisdom",
	"woodstalker": "wisdom",
	"aetherfist": "wisdom",
	"troubadour": "charisma"
}

# UI References
@onready var name_input = $MarginContainer/VBoxContainer/top_section/name_section/name_input
@onready var race_select = $MarginContainer/VBoxContainer/top_section/race_selection/race_select
@onready var class_select = $MarginContainer/VBoxContainer/top_section/class_selection/class_select

@onready var strength_spin = $MarginContainer/VBoxContainer/GridContainer/strength_section/strength_spinbox
@onready var constitution_spin = $MarginContainer/VBoxContainer/GridContainer/constitution_section/constitution_spinbox
@onready var dexterity_spin = $MarginContainer/VBoxContainer/GridContainer/dexterity_section/dexterity_spinbox
@onready var intelligence_spin = $MarginContainer/VBoxContainer/GridContainer/intelligence_section/intelligence_spinbox
@onready var wisdom_spin = $MarginContainer/VBoxContainer/GridContainer/wisdom_section/wisdom_spinbox
@onready var charisma_spin = $MarginContainer/VBoxContainer/GridContainer/charisma_section/charisma_spinbox
@onready var luck_spin = $MarginContainer/VBoxContainer/GridContainer/luck_section/luck_spinbox

@onready var points_remaining_label = $MarginContainer/VBoxContainer/points_remaining

@onready var confirm_button = $MarginContainer/VBoxContainer/confirm_button
@onready var begin_button = $MarginContainer/VBoxContainer/begin_button

func _ready():
	print("🔥 character_creation.gd script loaded!")

	load_class_restrictions()
	load_character_options()

	race_select.item_selected.connect(_on_race_selected)
	confirm_button.pressed.connect(_on_confirm_pressed)
	begin_button.pressed.connect(_on_begin_button_pressed)

	for spinbox in [
		strength_spin, constitution_spin, dexterity_spin,
		intelligence_spin, wisdom_spin, charisma_spin, luck_spin
	]:
		spinbox.value_changed.connect(_on_spinbox_value_changed)


# load_character_options - Loads races and classes from JSON
func load_character_options():
	if not FileAccess.file_exists("res://Data/character_options.json"):
		push_error("❌ character_options.json does not exist.")
		return

	var file := FileAccess.open("res://Data/character_options.json", FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()

		if typeof(parsed) == TYPE_DICTIONARY:
			var races = parsed.get("races", [])
			var classes = parsed.get("classes", [])

			for race in races:
				race_select.add_item(race)
			for player_class in classes:
				class_select.add_item(player_class)


# load_racial_stats - Loads stats for the selected race
func load_racial_stats(race: String):
	var file = FileAccess.open("res://Data/racial_stats.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()

		if typeof(data) == TYPE_DICTIONARY and data.has(race.to_lower()):
			base_stats = data[race.to_lower()]["base_stats"]
			final_stats = base_stats.duplicate()
			selected_race = race
			stat_pool = 4
			setup_spinboxes()
			update_point_display()


# setup_spinboxes - Initializes stat spinboxes
func setup_spinboxes():
	for key in base_stats.keys():
		var spin = get_node("MarginContainer/VBoxContainer/GridContainer/%s_section/%s_spinbox" % [key, key])
		spin.min_value = base_stats[key]
		spin.max_value = base_stats[key] + 4
		spin.value = base_stats[key]


# _on_spinbox_value_changed - Recalculates points and derived stats
func _on_spinbox_value_changed(value):
	if base_stats.has("strength"):
		stat_pool = 4

		stat_pool -= (strength_spin.value - base_stats["strength"])
		stat_pool -= (constitution_spin.value - base_stats["constitution"])
		stat_pool -= (dexterity_spin.value - base_stats["dexterity"])
		stat_pool -= (intelligence_spin.value - base_stats["intelligence"])
		stat_pool -= (wisdom_spin.value - base_stats["wisdom"])
		stat_pool -= (charisma_spin.value - base_stats["charisma"])
		stat_pool -= (luck_spin.value - base_stats["luck"])

		update_point_display()


# update_point_display - Updates label showing remaining points
func update_point_display():
	points_remaining_label.text = "Points Left: " + str(stat_pool)


# _on_race_selected - Called when a race is selected
func _on_race_selected(index: int):
	var race_name = race_select.get_item_text(index)
	update_class_options_for_race(race_name)
	load_racial_stats(race_name)


# load_class_restrictions - Loads class restrictions from JSON
func load_class_restrictions():
	var file = FileAccess.open("res://Data/class_restrictions.json", FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()

		if typeof(parsed) == TYPE_DICTIONARY:
			class_restrictions = parsed


# update_class_options_for_race - Filters class list by race
func update_class_options_for_race(race: String):
	class_select.clear()
	for player_class in class_restrictions.keys():
		if race in class_restrictions[player_class]:
			class_select.add_item(player_class)


# _on_confirm_pressed - Saves character stats to user save path
func _on_confirm_pressed():
	collect_final_stats()
	var selected_class = class_select.get_item_text(class_select.selected)
	var derived_stats = calculate_derived_stats(final_stats, selected_class)

	var character_data: Dictionary = {
		"player_name": name_input.text,
		"player_class": selected_class,
		"player_race": selected_race,
		"player_level": 1,
		"stats": final_stats,
		"derived": derived_stats,

		"current_health": derived_stats.get("health", 100),
		"current_mana": derived_stats.get("mana", 50),
		"current_stamina": derived_stats.get("stamina", 100),
		"max_stamina": derived_stats.get("stamina", 100),
		"satiety": 100,
		"thirst": 100,

		"xp": 0,
		"xp_next_level": 100,
		"copper": 100,
		"silver": 0,
		"gold": 0,
		"platinum": 0,

		"resistances": {
			"acid": 0,
			"cold": 0,
			"fire": 0,
			"magic": 0,
			"psychic": 0
		},

		"equipment": {
			"ear1": "", "ear2": "",
			"neck": "", "face": "", "head": "",
			"finger1": "", "finger2": "",
			"wrist1": "", "wrist2": "",
			"charm": "",
			"focus": "",
			"arms": "", "hands": "", "shoulders": "",
			"chest": "", "back": "", "waist": "",
			"legs": "", "feet": "",
			"trinket1": "", "trinket2": "",
			"primary": "", "secondary": "", "ranged": "", "ammo": ""
		},

		"character_creation": Global.create_character_creation_timestamp(),
		"playtime_seconds": 0,

		"inventory_data": {
			"basic_inventory": [],
			"bag_contents": {},
			"bank_storage": {}
		}
	}

	var save_dir: String = "user://saves"
	DirAccess.make_dir_recursive_absolute(save_dir)

	var file_name: String = name_input.text.to_lower() + "_character_stats.json"
	var file_path: String = save_dir + "/" + file_name
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(character_data, "\t"))
		file.close()
		print("✅ Character saved to " + file_path)
	else:
		push_error("❌ Failed to write character save file: " + file_path)


# calculate_derived_stats - Computes stats based on base values
func calculate_derived_stats(base_stats: Dictionary, selected_class: String) -> Dictionary:
	var derived := {}
	var required_keys := ["strength", "constitution", "dexterity", "intelligence", "wisdom", "luck"]

	for key in required_keys:
		if not base_stats.has(key):
			print("❌ Missing key:", key, "in base_stats:", base_stats)
			return derived

	derived["max_weight"] = base_stats["strength"] * 15
	derived["health"] = base_stats["constitution"] * 10
	derived["crit_chance"] = (base_stats["dexterity"] + base_stats["luck"]) / 2.0
	derived["mana"] = base_stats["intelligence"] + (base_stats["wisdom"] * 5)
	derived["stamina"] = (base_stats["constitution"] + base_stats["dexterity"]) * 5

	var class_key = selected_class.to_lower()
	var casting_stat: String = casting_stats.get(class_key, "intelligence")
	derived["spell_power"] = base_stats.get(casting_stat, 0) * 2

	return derived


# collect_final_stats - Pulls values from spinboxes into final_stats
func collect_final_stats():
	final_stats["strength"] = strength_spin.value
	final_stats["constitution"] = constitution_spin.value
	final_stats["dexterity"] = dexterity_spin.value
	final_stats["intelligence"] = intelligence_spin.value
	final_stats["wisdom"] = wisdom_spin.value
	final_stats["charisma"] = charisma_spin.value
	final_stats["luck"] = luck_spin.value


# _on_begin_button_pressed - Starts game in Lumora Outskirts
func _on_begin_button_pressed():
	var loaded_data = Global.load_player_data_from_file(name_input.text)
	if loaded_data.is_empty():
		push_error("❌ Failed to load newly created character!")
		return

	if loaded_data.has("inventory_data"):
		Inventory.load_inventory_data(loaded_data.inventory_data)
	
	print("🔥 Begin button pressed!")
	get_tree().change_scene_to_file("res://Scenes/lumora_outskirts3d.tscn")
