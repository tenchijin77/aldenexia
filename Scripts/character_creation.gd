extends Control

# Stat Logic
var class_restrictions = {}
var base_stats := {}
var final_stats := {}
var stat_pool := 4
var selected_race := ""

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

	# Connect SpinBox signals to shared handler
	for spinbox in [
		strength_spin, constitution_spin, dexterity_spin,
		intelligence_spin, wisdom_spin, charisma_spin, luck_spin
	]:
		spinbox.value_changed.connect(_on_spinbox_value_changed)

func load_character_options():
	print("📂 Loading character_options.json...")

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

			print("✅ Dropdowns populated.")
		else:
			push_error("❌ character_options.json is not a dictionary.")

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
		else:
			print("❌ Race not found in JSON:", race)

func setup_spinboxes():
	strength_spin.min_value = base_stats["strength"]
	strength_spin.max_value = base_stats["strength"] + 4
	strength_spin.value = base_stats["strength"]

	constitution_spin.min_value = base_stats["constitution"]
	constitution_spin.max_value = base_stats["constitution"] + 4
	constitution_spin.value = base_stats["constitution"]

	dexterity_spin.min_value = base_stats["dexterity"]
	dexterity_spin.max_value = base_stats["dexterity"] + 4
	dexterity_spin.value = base_stats["dexterity"]

	intelligence_spin.min_value = base_stats["intelligence"]
	intelligence_spin.max_value = base_stats["intelligence"] + 4
	intelligence_spin.value = base_stats["intelligence"]

	wisdom_spin.min_value = base_stats["wisdom"]
	wisdom_spin.max_value = base_stats["wisdom"] + 4
	wisdom_spin.value = base_stats["wisdom"]

	charisma_spin.min_value = base_stats["charisma"]
	charisma_spin.max_value = base_stats["charisma"] + 4
	charisma_spin.value = base_stats["charisma"]

	luck_spin.min_value = base_stats["luck"]
	luck_spin.max_value = base_stats["luck"] + 4
	luck_spin.value = base_stats["luck"]

func _on_spinbox_value_changed(value):
	stat_pool = 4  # Reset pool

	stat_pool -= (strength_spin.value - base_stats["strength"])
	stat_pool -= (constitution_spin.value - base_stats["constitution"])
	stat_pool -= (dexterity_spin.value - base_stats["dexterity"])
	stat_pool -= (intelligence_spin.value - base_stats["intelligence"])
	stat_pool -= (wisdom_spin.value - base_stats["wisdom"])
	stat_pool -= (charisma_spin.value - base_stats["charisma"])
	stat_pool -= (luck_spin.value - base_stats["luck"])

	update_point_display()

	if stat_pool < 0:
		print("⚠️ Overallocated! Consider clamping or disabling further changes.")

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
			print("✅ Loaded class restrictions.")
		else:
			push_error("❌ class_restrictions.json format error.")
	else:
		push_error("❌ Unable to open class_restrictions.json")

func update_class_options_for_race(race: String):
	class_select.clear()
	for player_class in class_restrictions.keys():
		if race in class_restrictions[player_class]:
			class_select.add_item(player_class)

func _on_confirm_pressed():
	collect_final_stats()

	var character_data = {
		"player_name": name_input.text,
		"player_class": class_select.get_item_text(class_select.selected),
		"player_race": selected_race,
		"stats": final_stats
	}

	var json_string = JSON.stringify(character_data, "\t")
	var file = FileAccess.open("res://Data/character_stats.json", FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("✅ Character saved successfully.")
	else:
		push_error("❌ Failed to open character_stats.json for writing.")

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
