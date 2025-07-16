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
	"wildmage": "intelligence",
	"lightsworn": "wisdom",
	"lightmender": "wisdom",
	"spiritcaller": "wisdom",
	"wildspeaker": "wisdom",
	"woodstalker": "wisdom"
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
@onready var health_label = $MarginContainer/VBoxContainer/derived_stats_section/health_label
@onready var weight_label = $MarginContainer/VBoxContainer/derived_stats_section/weight_label

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

func setup_spinboxes():
	for key in base_stats.keys():
		var spin = get_node("MarginContainer/VBoxContainer/GridContainer/%s_section/%s_spinbox" % [key, key])
		spin.min_value = base_stats[key]
		spin.max_value = base_stats[key] + 4
		spin.value = base_stats[key]

func _on_spinbox_value_changed(value):
	if base_stats.has("strength"):
		stat_pool = 4  # Reset pool

		stat_pool -= (strength_spin.value - base_stats["strength"])
		stat_pool -= (constitution_spin.value - base_stats["constitution"])
		stat_pool -= (dexterity_spin.value - base_stats["dexterity"])
		stat_pool -= (intelligence_spin.value - base_stats["intelligence"])
		stat_pool -= (wisdom_spin.value - base_stats["wisdom"])
		stat_pool -= (charisma_spin.value - base_stats["charisma"])
		stat_pool -= (luck_spin.value - base_stats["luck"])

		update_point_display()

		var preview_stats := {
			"strength": strength_spin.value,
			"constitution": constitution_spin.value,
			"dexterity": dexterity_spin.value,
			"intelligence": intelligence_spin.value,
			"wisdom": wisdom_spin.value,
			"charisma": charisma_spin.value,
			"luck": luck_spin.value
		}
		var current_class = class_select.get_item_text(class_select.selected)
		var derived := calculate_derived_stats(preview_stats, current_class)
	else:
		print("⛔ Skipping preview — base_stats not ready yet.")

func update_point_display():
	points_remaining_label.text = "Points Left: " + str(stat_pool)

func _on_race_selected(index: int):
	var race_name = race_select.get_item_text(index)
	update_class_options_for_race(race_name)
	load_racial_stats(race_name)

func load_class_restrictions():
	var file = FileAccess.open("res://Data/class_restrictions.json", FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()

		if typeof(parsed) == TYPE_DICTIONARY:
			class_restrictions = parsed

func update_class_options_for_race(race: String):
	class_select.clear()
	for player_class in class_restrictions.keys():
		if race in class_restrictions[player_class]:
			class_select.add_item(player_class)

func _on_confirm_pressed():
	collect_final_stats()
	var selected_class = class_select.get_item_text(class_select.selected)

	var character_data = {
		"player_name": name_input.text,
		"player_class": selected_class,
		"player_race": selected_race,
		"stats": final_stats,
		"derived": calculate_derived_stats(final_stats, selected_class)
	}

	var json_string = JSON.stringify(character_data, "\t")
	var file = FileAccess.open("res://Data/character_stats.json", FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("✅ Character saved with derived stats!")
	else:
		push_error("❌ Failed to write character_stats.json")

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

	var class_key = selected_class.to_lower()
	var casting_stat: String = casting_stats.get(class_key, "intelligence")
	derived["spell_power"] = base_stats.get(casting_stat, 0) * 2

	return derived

func collect_final_stats():
	final_stats["strength"] = strength_spin.value
	final_stats["constitution"] = constitution_spin.value
	final_stats["dexterity"] = dexterity_spin.value
	final_stats["intelligence"] = intelligence_spin.value
	final_stats["wisdom"] = wisdom_spin.value
	final_stats["charisma"] = charisma_spin.value
	final_stats["luck"] = luck_spin.value

func _on_begin_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/lumora_outskirts.tscn")
