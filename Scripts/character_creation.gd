# character_creation.gd - Character creation panel logic using character_options.json

extends Control

var base_stats: Dictionary = {}
var final_stats: Dictionary = {}
var stat_pool: int = 4
var selected_race: String = ""
var selected_class: String = ""

var casting_stats: Dictionary = {
	"voidknight": ["intelligence"],
	"gravecaller": ["intelligence"],
	"runecaster": ["intelligence"],
	"arcanist": ["intelligence"],
	"chaosborn": ["intelligence", "charisma"],
	"lightsworn": ["wisdom"],
	"lightmender": ["wisdom"],
	"spiritcaller": ["wisdom"],
	"wildspeaker": ["wisdom"],
	"woodstalker": ["wisdom"],
	"aetherfist": ["wisdom"],
	"troubadour": ["intelligence", "charisma"]
}

@onready var race_select: OptionButton = $MarginContainer/VBoxContainer/top_row/race_column/race_selection/race_select
@onready var class_select: OptionButton = $MarginContainer/VBoxContainer/top_row/class_column/class_selection/class_select

@onready var strength_spin: SpinBox = $MarginContainer/VBoxContainer/stats_row/stats_column/GridContainer/strength_section/strength_spinbox
@onready var constitution_spin: SpinBox = $MarginContainer/VBoxContainer/stats_row/stats_column/GridContainer/constitution_section/constitution_spinbox
@onready var dexterity_spin: SpinBox = $MarginContainer/VBoxContainer/stats_row/stats_column/GridContainer/dexterity_section/dexterity_spinbox
@onready var intelligence_spin: SpinBox = $MarginContainer/VBoxContainer/stats_row/stats_column/GridContainer/intelligence_section/intelligence_spinbox
@onready var wisdom_spin: SpinBox = $MarginContainer/VBoxContainer/stats_row/stats_column/GridContainer/wisdom_section/wisdom_spinbox
@onready var charisma_spin: SpinBox = $MarginContainer/VBoxContainer/stats_row/stats_column/GridContainer/charisma_section/charisma_spinbox
@onready var luck_spin: SpinBox = $MarginContainer/VBoxContainer/stats_row/stats_column/GridContainer/luck_section/luck_spinbox

@onready var points_remaining_label: Label = $MarginContainer/VBoxContainer/stats_row/stats_column/stats_header/points_remaining
@onready var traits_list: RichTextLabel = $MarginContainer/VBoxContainer/stats_row/traits_panel/traits_list

@onready var race_description: RichTextLabel = $MarginContainer/VBoxContainer/top_row/race_column/race_description
@onready var race_lore: RichTextLabel = $MarginContainer/VBoxContainer/top_row/race_column/race_lore

@onready var class_description: RichTextLabel = $MarginContainer/VBoxContainer/top_row/class_column/class_description
@onready var class_role: Label = $MarginContainer/VBoxContainer/top_row/class_column/class_role
@onready var class_difficulty: Label = $MarginContainer/VBoxContainer/top_row/class_column/class_difficulty

@onready var derived_list: RichTextLabel = $MarginContainer/VBoxContainer/stats_row/derived_stats/derived_list

@onready var name_input: LineEdit = $MarginContainer/VBoxContainer/bottom_row/name_section/name_input
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/bottom_row/confirm_button
@onready var begin_button: Button = $MarginContainer/VBoxContainer/bottom_row/begin_button
@onready var portrait_texture: TextureRect = $MarginContainer/VBoxContainer/top_row/portrait_panel/portrait_texture

func _ready() -> void:
	load_character_options()

	if race_select.item_count > 0:
		_on_race_selected(0)

	race_select.item_selected.connect(_on_race_selected)
	class_select.item_selected.connect(_on_class_selected)
	confirm_button.pressed.connect(_on_confirm_pressed)

	var spinboxes: Array[SpinBox] = [
		strength_spin, constitution_spin, dexterity_spin,
		intelligence_spin, wisdom_spin, charisma_spin, luck_spin
	]

	for spinbox in spinboxes:
		spinbox.value_changed.connect(_on_spinbox_value_changed)

# ---------------------------------------------------------
# LOAD CHARACTER OPTIONS
# ---------------------------------------------------------
func load_character_options() -> void:
	var data: Dictionary = Global.character_options
	if data.is_empty():
		push_error("❌ Global.character_options is empty. Did Global.gd load it?")
		return

	var races: Dictionary = data["races"]
	var classes: Dictionary = data["classes"]

	race_select.clear()
	class_select.clear()

	var race_keys: Array = races.keys()
	race_keys.sort()

	for key in race_keys:
		var race_key: String = str(key)
		var race_data: Dictionary = races[race_key]

		race_select.add_item(race_data["name"])
		race_select.set_item_metadata(race_select.item_count - 1, race_key)

	var class_keys: Array = classes.keys()
	class_keys.sort()

	for key in class_keys:
		var class_key: String = str(key)
		var class_data: Dictionary = classes[class_key]

		class_select.add_item(class_data["name"])
		class_select.set_item_metadata(class_select.item_count - 1, class_key)

# ---------------------------------------------------------
# RACE SELECTION
# ---------------------------------------------------------
func _on_race_selected(index: int) -> void:
	var meta: Variant = race_select.get_item_metadata(index)
	var race_key: String = str(meta)
	selected_race = race_key

	load_racial_stats(race_key)
	load_racial_traits(race_key)
	update_race_description(race_key)
	update_portrait(race_key)
	update_derived_preview()

func update_race_description(race_key: String) -> void:
	var race: Dictionary = Global.character_options["races"][race_key]
	race_description.text = race["description"]
	race_lore.text = race["lore"]

func update_portrait(race_key: String) -> void:
	var race: Dictionary = Global.character_options["races"][race_key]

	if race.has("portrait"):
		var path: String = race["portrait"]
		if ResourceLoader.exists(path):
			portrait_texture.texture = load(path)
		else:
			push_error("❌ Portrait not found: " + path)
	else:
		portrait_texture.texture = null

func load_racial_stats(race_key: String) -> void:
	base_stats = {
		"strength": 10,
		"constitution": 10,
		"dexterity": 10,
		"intelligence": 10,
		"wisdom": 10,
		"charisma": 10,
		"luck": 10
	}

	final_stats = base_stats.duplicate()
	stat_pool = 4

	setup_spinboxes()
	update_point_display()

func load_racial_traits(race_key: String) -> void:
	var races: Dictionary = Global.character_options["races"]
	var race: Dictionary = races[race_key]
	var traits: Dictionary = race["traits"]
	var penalties: Dictionary = race["penalties"]

	traits_list.text = ""

	for key in traits.keys():
		var t_key: String = str(key)
		traits_list.text += "• %s: %s\n" % [t_key, str(traits[t_key])]

	for key in penalties.keys():
		var p_key: String = str(key)
		if p_key != "notes":
			traits_list.text += "• %s: %s\n" % [p_key, str(penalties[p_key])]

	if penalties.has("notes"):
		var notes: Array = penalties["notes"]
		for note in notes:
			traits_list.text += "• %s\n" % str(note)

# ---------------------------------------------------------
# CLASS SELECTION
# ---------------------------------------------------------
func _on_class_selected(index: int) -> void:
	var meta: Variant = class_select.get_item_metadata(index)
	selected_class = str(meta)
	update_class_description(selected_class)
	update_derived_preview()

func update_class_description(class_key: String) -> void:
	var cls: Dictionary = Global.character_options["classes"][class_key]
	class_description.text = cls["description"]
	class_role.text = "Role: " + cls["role"]
	class_difficulty.text = "Difficulty: " + cls["difficulty"]

# ---------------------------------------------------------
# SPINBOX LOGIC
# ---------------------------------------------------------
func setup_spinboxes() -> void:
	for key in base_stats.keys():
		var stat_key: String = str(key)
		var path: String = "MarginContainer/VBoxContainer/stats_row/stats_column/GridContainer/%s_section/%s_spinbox" % [stat_key, stat_key]
		var spin: SpinBox = get_node(path)
		spin.min_value = base_stats[stat_key]
		spin.max_value = base_stats[stat_key] + 4
		spin.value = base_stats[stat_key]

func _on_spinbox_value_changed(value: float) -> void:
	stat_pool = 4

	stat_pool -= int(strength_spin.value - base_stats["strength"])
	stat_pool -= int(constitution_spin.value - base_stats["constitution"])
	stat_pool -= int(dexterity_spin.value - base_stats["dexterity"])
	stat_pool -= int(intelligence_spin.value - base_stats["intelligence"])
	stat_pool -= int(wisdom_spin.value - base_stats["wisdom"])
	stat_pool -= int(charisma_spin.value - base_stats["charisma"])
	stat_pool -= int(luck_spin.value - base_stats["luck"])

	update_point_display()
	update_derived_preview()

func update_point_display() -> void:
	points_remaining_label.text = "Points Left: " + str(stat_pool)

# ---------------------------------------------------------
# DERIVED STATS PREVIEW
# ---------------------------------------------------------
func update_derived_preview() -> void:
	var preview: Dictionary = calculate_derived_stats(final_stats, selected_class)
	derived_list.text = ""

	for key in preview.keys():
		derived_list.text += "%s: %s\n" % [key.capitalize(), str(preview[key])]

# ---------------------------------------------------------
# CONFIRM CHARACTER CREATION
# ---------------------------------------------------------
func _on_confirm_pressed() -> void:
	collect_final_stats()

	var derived_stats: Dictionary = calculate_derived_stats(final_stats, selected_class)

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
			"acid": 0, "cold": 0, "fire": 0, "magic": 0, "psychic": 0
		},

		"equipment": {
			"ear1": "", "ear2": "", "neck": "", "face": "", "head": "",
			"finger1": "", "finger2": "", "wrist1": "", "wrist2": "",
			"charm": "", "focus": "", "arms": "", "hands": "", "shoulders": "",
			"chest": "", "back": "", "waist": "", "legs": "", "feet": "",
			"trinket1": "", "trinket2": "", "primary": "", "secondary": "",
			"ranged": "", "ammo": ""
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
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(character_data, "\t"))
		file.close()
	else:
		push_error("❌ Failed to write character save file: " + file_path)

# ---------------------------------------------------------
# DERIVED STATS
# ---------------------------------------------------------
func calculate_derived_stats(base_stats: Dictionary, selected_class: String) -> Dictionary:
	var derived: Dictionary = {}
	var required_keys: Array[String] = ["strength", "constitution", "dexterity", "intelligence", "wisdom", "luck"]

	for key in required_keys:
		if not base_stats.has(key):
			return derived

	derived["max_weight"] = base_stats["strength"] * 15
	derived["health"] = base_stats["constitution"] * 10
	derived["crit_chance"] = (base_stats["dexterity"] + base_stats["luck"]) / 2.0
	derived["mana"] = base_stats["intelligence"] + (base_stats["wisdom"] * 5)
	derived["stamina"] = (base_stats["constitution"] + base_stats["dexterity"]) * 5

	var class_key: String = selected_class.to_lower()
	var stats: Array = casting_stats.get(class_key, ["intelligence"])
	var total: int = 0

	for s in stats:
		total += base_stats.get(s, 0)

	derived["spell_power"] = total * 2

	return derived

# ---------------------------------------------------------
# FINAL STAT COLLECTION
# ---------------------------------------------------------
func collect_final_stats() -> void:
	final_stats["strength"] = strength_spin.value
	final_stats["constitution"] = constitution_spin.value
	final_stats["dexterity"] = dexterity_spin.value
	final_stats["intelligence"] = intelligence_spin.value
	final_stats["wisdom"] = wisdom_spin.value
	final_stats["charisma"] = charisma_spin.value
	final_stats["luck"] = luck_spin.value

# ---------------------------------------------------------
# BEGIN BUTTON
# ---------------------------------------------------------
func _on_begin_button_pressed() -> void:
	if name_input.text.strip_edges() == "":
		push_error("❌ Please enter a character name before beginning.")
		return

	var character_name := name_input.text.to_lower()
	var data := Global.load_player_data_from_file(character_name)

	if data.is_empty():
		push_error("❌ Could not load character save.")
		return

	get_tree().change_scene_to_file("res://Scenes/lumora_outskirts3d.tscn")
