# character_creation.gd - Character creation panel logic using character_options.json

extends Control

var base_stats: Dictionary = {}
var final_stats: Dictionary = {}
var stat_pool: int = 4
var selected_race: String = ""
var selected_class: String = ""
var class_restrictions: Dictionary = {}
var racial_resistances: Dictionary = {}

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
	load_class_restrictions()
	load_character_options()

	race_select.item_selected.connect(_on_race_selected)
	class_select.item_selected.connect(_on_class_selected)
	confirm_button.pressed.connect(_on_confirm_pressed)

	var spinboxes: Array[SpinBox] = [
		strength_spin, constitution_spin, dexterity_spin,
		intelligence_spin, wisdom_spin, charisma_spin, luck_spin
	]
	for spinbox in spinboxes:
		spinbox.value_changed.connect(_on_spinbox_value_changed)

	if race_select.item_count > 0:
		_on_race_selected(0)

# ---------------------------------------------------------
# LOAD CLASS RESTRICTIONS
# ---------------------------------------------------------
func load_class_restrictions() -> void:
	var file = FileAccess.open("res://Data/class_restrictions.json", FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			class_restrictions = parsed
		else:
			push_error("❌ class_restrictions.json failed to parse")

# ---------------------------------------------------------
# LOAD CHARACTER OPTIONS
# ---------------------------------------------------------
func load_character_options() -> void:
	var data: Dictionary = Global.character_options
	if data.is_empty():
		push_error("❌ Global.character_options is empty. Did Global.gd load it?")
		return

	var races: Dictionary = data["races"]

	race_select.clear()
	class_select.clear()

	var race_keys: Array = races.keys()
	race_keys.sort()

	for key in race_keys:
		var race_key: String = str(key)
		var race_data: Dictionary = races[race_key]
		race_select.add_item(race_data["name"])
		race_select.set_item_metadata(race_select.item_count - 1, race_key)

# ---------------------------------------------------------
# RACE SELECTION
# ---------------------------------------------------------
func _on_race_selected(index: int) -> void:
	var meta: Variant = race_select.get_item_metadata(index)
	var race_key: String = str(meta)
	selected_race = race_key

	var race_display_name: String = Global.character_options["races"][race_key]["name"]
	update_class_options_for_race(race_display_name)

	load_racial_stats(race_key)
	load_racial_traits(race_key)
	update_race_description(race_key)
	update_portrait(race_key)
	update_derived_preview()

	if class_select.item_count > 0:
		_on_class_selected(0)

func update_class_options_for_race(race_display_name: String) -> void:
	class_select.clear()
	var classes: Dictionary = Global.character_options["classes"]
	var class_keys: Array = classes.keys()
	class_keys.sort()
	for key in class_keys:
		var class_key: String = str(key)
		var class_display_name: String = classes[class_key]["name"]
		if class_restrictions.has(class_display_name):
			if race_display_name in class_restrictions[class_display_name]:
				class_select.add_item(class_display_name)
				class_select.set_item_metadata(class_select.item_count - 1, class_key)

func update_race_description(race_key: String) -> void:
	var race: Dictionary = Global.character_options["races"][race_key]
	race_description.text = race["description"]
	race_lore.text = race["lore"]

func update_portrait(race_key: String) -> void:
	var race: Dictionary = Global.character_options["races"][race_key]
	if race.has("portrait") and race["portrait"] != "":
		var path: String = race["portrait"]
		if ResourceLoader.exists(path):
			portrait_texture.texture = load(path)
		else:
			portrait_texture.texture = null
	else:
		portrait_texture.texture = null

func load_racial_stats(race_key: String) -> void:
	var race_name = Global.character_options["races"][race_key]["name"].to_lower()
	var file = FileAccess.open("res://Data/racial_stats.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(data) == TYPE_DICTIONARY and data.has(race_name):
			base_stats = data[race_name]["base_stats"]
			racial_resistances = data[race_name].get("resistances", { "acid": 0, "cold": 0, "fire": 0, "magic": 0, "psychic": 0 })
		else:
			base_stats = { "strength": 10, "constitution": 10, "dexterity": 10, "intelligence": 10, "wisdom": 10, "charisma": 10, "luck": 10 }
			racial_resistances = { "acid": 0, "cold": 0, "fire": 0, "magic": 0, "psychic": 0 }
	else:
		base_stats = { "strength": 10, "constitution": 10, "dexterity": 10, "intelligence": 10, "wisdom": 10, "charisma": 10, "luck": 10 }
		racial_resistances = { "acid": 0, "cold": 0, "fire": 0, "magic": 0, "psychic": 0 }

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
		traits_list.text += "• %s: %s\n" % [str(key), str(traits[key])]

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

func _on_spinbox_value_changed(_value: float) -> void:
	stat_pool = 4
	stat_pool -= int(strength_spin.value - base_stats["strength"])
	stat_pool -= int(constitution_spin.value - base_stats["constitution"])
	stat_pool -= int(dexterity_spin.value - base_stats["dexterity"])
	stat_pool -= int(intelligence_spin.value - base_stats["intelligence"])
	stat_pool -= int(wisdom_spin.value - base_stats["wisdom"])
	stat_pool -= int(charisma_spin.value - base_stats["charisma"])
	stat_pool -= int(luck_spin.value - base_stats["luck"])

	var remaining: int = max(0, stat_pool)
	strength_spin.max_value = strength_spin.value + remaining
	constitution_spin.max_value = constitution_spin.value + remaining
	dexterity_spin.max_value = dexterity_spin.value + remaining
	intelligence_spin.max_value = intelligence_spin.value + remaining
	wisdom_spin.max_value = wisdom_spin.value + remaining
	charisma_spin.max_value = charisma_spin.value + remaining
	luck_spin.max_value = luck_spin.value + remaining

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
		"known_spells": get_starting_spells(selected_class),
		"known_skills": get_starting_skills(selected_class),
		"action_bar_slots": build_starting_action_bar(selected_class),
		"satiety": 100,
		"thirst": 100,

		"xp": 0,
		"xp_next_level": 100,
		"copper": 20,
		"silver": 0,
		"gold": 0,
		"platinum": 0,

		"resistances": racial_resistances.duplicate(),

		"equipment": get_starting_equipment(selected_class),

		"character_creation": Global.create_character_creation_timestamp(),
		"playtime_seconds": 0,

		"inventory_data": build_starting_inventory(selected_class),
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
# STARTING EQUIPMENT & SPELLS
# ---------------------------------------------------------
func get_starting_equipment(_p_class: String) -> Dictionary:
	# All slots empty — player equips gear manually from the bag
	return {
		"ear1": "", "ear2": "", "neck": "", "face": "", "head": "",
		"finger1": "", "finger2": "", "wrist1": "", "wrist2": "",
		"charm": "", "focus": "", "arms": "", "hands": "", "shoulders": "",
		"chest": "", "back": "", "waist": "", "legs": "", "feet": "",
		"trinket1": "", "trinket2": "", "primary": "", "secondary": "",
		"ranged": "", "ammo": ""
	}


func get_starting_skills(p_class: String) -> Array:
	match p_class:
		"Blademaster":
			return ["1h_slashing", "parry", "dodge", "weapon_mastery"]
		"Shadowblade":
			return ["1h_piercing", "backstab", "dodge", "dual_wield"]
		"Voidknight":
			return ["1h_slashing", "parry", "dodge", "weapon_mastery"]
		"Lightsworn":
			return ["1h_slashing", "block", "shield_defense", "weapon_mastery"]
		"Aetherfist", "Zenblade":
			return ["hand_to_hand", "dodge", "mantis_fist"]
		"Woodstalker":
			return ["archery", "dodge", "throwing"]
		"Arcanist", "Runecaster", "Chaosborn":
			return ["spell_casting", "evocation", "concentration"]
		"Lightmender", "Spiritcaller":
			return ["spell_casting", "concentration", "channeling"]
		"Gravecaller":
			return ["spell_casting", "necromancy", "concentration"]
		"Troubadour":
			return ["spell_casting", "enchantment", "concentration"]
		"Wildspeaker":
			return ["spell_casting", "alteration", "concentration"]
		_:
			return []


func build_starting_action_bar(p_class: String) -> Array:
	var slots: Array = []
	for spell in get_starting_spells(p_class):
		slots.append({"type": "spell", "name": spell})
	while slots.size() < 12:
		slots.append({"type": "", "name": ""})
	return slots


func get_starting_spells(p_class: String) -> Array:
	var file := FileAccess.open("res://Data/player_spells.json", FileAccess.READ)
	if not file:
		return []
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_ARRAY:
		return []
	var spells: Array = []
	for spell in data:
		var reqs: Dictionary = spell.get("class_level_requirements", {})
		if reqs.has(p_class) and int(reqs[p_class]) <= 1:
			spells.append(spell.get("spell_name", ""))
	return spells


# ---------------------------------------------------------
# STARTING INVENTORY
# ---------------------------------------------------------
func build_starting_inventory(p_class: String) -> Dictionary:
	Inventory.initialize_basic_inventory()
	Inventory._initialize_equipment()

	# Slot 0: small bag holds consumables (4-slot capacity fits exactly)
	Inventory.basic_inventory[0] = Inventory.create_item_instance("small_bag")
	Inventory.bag_contents["0"] = [
		Inventory.create_item_instance("faded_note"),
		Inventory.create_item_instance("iron_rations", 20),
		Inventory.create_item_instance("water_flask", 20),
		Inventory.create_item_instance("torch", 5),
	]

	# Slots 1+: starting gear placed directly so player can drag to equipment slots
	var gear: Array[String] = ["ragged_hood", "ragged_tunic", "ragged_leggings", "torn_boots", "cloth_cape", "rusty_sword"]
	match p_class:
		"Blademaster", "Voidknight", "Lightsworn":
			gear.push_front("rusty_sword")
		"Shadowblade", "Woodstalker":
			gear.push_front("dagger")

	for i in range(gear.size()):
		Inventory.basic_inventory[i + 1] = Inventory.create_item_instance(gear[i])

	return Inventory.save_inventory_data()

# ---------------------------------------------------------
# DERIVED STATS
# ---------------------------------------------------------
func calculate_derived_stats(stats: Dictionary, class_key: String) -> Dictionary:
	var derived: Dictionary = {}
	var required_keys: Array[String] = ["strength", "constitution", "dexterity", "intelligence", "wisdom", "luck"]

	for key in required_keys:
		if not stats.has(key):
			return derived

	derived["max_weight"] = stats["strength"] * 15
	derived["health"] = stats["constitution"] * 10
	derived["crit_chance"] = (stats["dexterity"] + stats["luck"]) / 2.0
	derived["mana"] = stats["intelligence"] + (stats["wisdom"] * 5)
	derived["stamina"] = (stats["constitution"] + stats["dexterity"]) * 5

	var cast_stats: Array = casting_stats.get(class_key.to_lower(), ["intelligence"])
	var total: int = 0
	for s in cast_stats:
		total += stats.get(s, 0)
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
