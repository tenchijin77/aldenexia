# character_creation.gd - Character creation panel logic using character_options.json

extends Control

var base_stats: Dictionary = {}
var final_stats: Dictionary = {}
var stat_pool: int = 4
var selected_race: String = ""
var selected_class: String = ""
var selected_sex: String = "male"
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
	"spiritweaver": ["wisdom"],
	"wildspeaker": ["wisdom"],
	"woodstalker": ["wisdom"],
	"aetherfist": ["wisdom"],
	"troubadour": ["intelligence", "charisma"]
}

@onready var race_select: OptionButton = $MarginContainer/VBoxContainer/top_row/race_column/race_selection/race_select
@onready var sex_select: OptionButton = $MarginContainer/VBoxContainer/top_row/race_column/sex_selection/sex_select
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
@onready var back_button: Button = $MarginContainer/VBoxContainer/bottom_row/back_button
@onready var portrait_texture: TextureRect = $MarginContainer/VBoxContainer/top_row/portrait_panel/portrait_texture

# Server mode (Global.server_creation set by the Join a Server screen): Confirm builds the character in
# memory instead of writing user://saves, and Begin hands it to the server, which stores it there.
var _pending_server_character: Dictionary = {}
var _status_label: Label

func _ready() -> void:
	load_class_restrictions()
	load_character_options()

	sex_select.clear()
	sex_select.add_item("Male")
	sex_select.set_item_metadata(0, "male")
	sex_select.add_item("Female")
	sex_select.set_item_metadata(1, "female")
	sex_select.select(0)
	selected_sex = "male"

	race_select.item_selected.connect(_on_race_selected)
	sex_select.item_selected.connect(_on_sex_selected)
	class_select.item_selected.connect(_on_class_selected)
	confirm_button.pressed.connect(_on_confirm_pressed)
	back_button.pressed.connect(_on_back_button_pressed)

	# Reached via the multiplayer menu's "Create New Character" shortcut —
	# relabel Begin so it's clear this returns to Multiplayer instead of
	# launching a single-player game. See global.gd's return_to_multiplayer_menu.
	if Global.return_to_multiplayer_menu:
		begin_button.text = "Done — Return to Multiplayer"
	if not Global.server_creation.is_empty():
		begin_button.text = "Enter the World"
		name_input.max_length = 16
		name_input.placeholder_text = "Letters and numbers, 2-16"
		_status_label = Label.new()
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.45))
		$MarginContainer/VBoxContainer.add_child(_status_label)

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

func _on_sex_selected(index: int) -> void:
	var meta: Variant = sex_select.get_item_metadata(index)
	selected_sex = str(meta)
	update_portrait(selected_race)

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
	# portrait is {"male": path, "female": path} — one placeholder image for
	# every race/sex today, swapped out per-race-per-sex once real art exists.
	var path: String = ""
	if race.has("portrait") and typeof(race["portrait"]) == TYPE_DICTIONARY:
		var portraits: Dictionary = race["portrait"]
		path = str(portraits.get(selected_sex, portraits.values()[0] if not portraits.is_empty() else ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		portrait_texture.texture = load(path)
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

	var descriptions: Dictionary = Global.character_options.get("trait_descriptions", {})
	for key in traits.keys():
		var label := str(key).replace("_", " ").capitalize()
		var value = traits[key]
		# Yes/no traits read as just their name; numeric ones keep their value.
		var line := "• %s" % label if typeof(value) == TYPE_BOOL and value else "• %s: %s" % [label, str(value)]
		if descriptions.has(key):
			line += " — %s" % str(descriptions[key])
		traits_list.text += line + "\n"

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
	if not Global.server_creation.is_empty() and Net.sanitize_name(name_input.text).is_empty():
		_status_label.text = "Server character names use letters and numbers only, 2 to 16 characters."
		return
	collect_final_stats()
	# character_options.json uses lowercase keys; all match statements expect PascalCase.
	var p_class: String = selected_class.capitalize()
	var derived_stats: Dictionary = calculate_derived_stats(final_stats, selected_class)

	var character_data: Dictionary = {
		"player_name": name_input.text,
		"player_class": p_class,
		"player_race": selected_race,
		"player_sex": selected_sex,
		"player_level": 1,
		"stats": final_stats,
		"known_spells": get_starting_spells(p_class),
		"known_skills": get_starting_skills(p_class),
		"action_bar_slots": build_starting_action_bar(p_class),
		"satiety": 100,
		"thirst": 100,

		"xp": 0,
		"xp_next_level": 100,
		"copper": 20,
		"silver": 0,
		"gold": 0,
		"platinum": 0,

		"resistances": racial_resistances.duplicate(),

		"equipment": get_starting_equipment(p_class),

		"character_creation": Global.create_character_creation_timestamp(),
		"playtime_seconds": 0,

		"inventory_data": build_starting_inventory(p_class),
		"skill_levels": build_starting_skill_levels(p_class),
	}

	if not Global.server_creation.is_empty():
		_pending_server_character = character_data
		_status_label.text = "%s is ready — press Enter the World to create it on the server." % name_input.text
		return

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
		"Lightmender", "Spiritweaver":
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
	# Spell-less classes (Aetherfist) would otherwise start with a completely
	# empty bar despite already knowing skills via get_starting_skills() —
	# fill remaining slots with those instead so there's something to test.
	# Left off classes that already have spells so their bar isn't cluttered
	# with passive weapon-proficiency skills (1h_slashing, dodge, etc.) they'd
	# never click.
	if slots.is_empty():
		for skill in get_starting_skills(p_class):
			slots.append({"type": "skill", "name": skill})
	while slots.size() < 12:
		slots.append({"type": "", "name": ""})
	return slots


# Every class's first two level-1 spells from player_spells.json, granted
# outright at character creation — no scroll/learning step needed for these
# two. Everything else (including further level-1 spells like Taunt for the
# tank classes) is scroll-only, bought from a vendor.
const STARTING_SPELLS := {
	"Blademaster":  ["power_strike", "battle_shout"],
	"Lightsworn":   ["holy_strike", "blessing_of_light"],
	"Voidknight":   ["life_siphon", "shadow_aura"],
	"Spiritweaver": ["spirit_mend", "earth_totem", "phantasmal_echo"],
	"Lightmender":  ["cure_wounds", "bless"],
	"Wildspeaker":  ["regrowth", "entangle", "summon_spirit_of_the_woods"],
	"Woodstalker":  ["aimed_shot", "hunters_mark"],
	"Shadowblade":  ["backstab", "shadowstep"],
	"Troubadour":   ["song_of_courage", "dissonant_chord"],
	"Gravecaller":  ["shadow_bolt", "raise_skeleton"],
	"Runecaster":   ["charm", "illusionary_bolt"],
	"Arcanist":     ["magic_missile", "arcane_armor"],
	"Aetherfist":   ["flurry_of_blows", "wind_stance"],
	"Chaosborn":    ["chaos_bolt", "wild_surge"],
}

func get_starting_spells(p_class: String) -> Array:
	return STARTING_SPELLS.get(p_class, []).duplicate()


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
	# ("rusty_sword" used to be hardcoded into this base array itself, so every
	# class — including casters — got a sword by default, and the melee cases
	# below actually granted a *second*, duplicate one via push_front.)
	var gear: Array[String] = ["ragged_hood", "ragged_tunic", "ragged_leggings", "torn_boots", "cloth_cape"]
	match p_class:
		"Blademaster", "Voidknight", "Lightsworn":
			gear.push_front("rusty_sword")
		"Shadowblade", "Woodstalker":
			gear.push_front("dagger")
		"Aetherfist":
			gear.push_front("worn_hand_wraps")

	# No starting scroll case anymore — the class's first two spells are now
	# granted directly via known_spells (get_starting_spells() above), and
	# every other spell (including further level-1s like Taunt) is bought
	# from a vendor instead.
	var gear_start: int = 1

	for i in range(gear.size()):
		if gear_start + i < Inventory.BASIC_INVENTORY_SIZE:
			Inventory.basic_inventory[gear_start + i] = Inventory.create_item_instance(gear[i])

	return Inventory.save_inventory_data()

# ---------------------------------------------------------
# STARTING SKILL LEVELS
# ---------------------------------------------------------
func build_starting_skill_levels(p_class: String) -> Dictionary:
	var file := FileAccess.open("res://Data/player_skills.json", FileAccess.READ)
	if not file:
		return {}
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var class_map: Dictionary = data.get("class_skills", {})
	return class_map.get(p_class, {}).duplicate()

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
	if not Global.server_creation.is_empty():
		_begin_on_server()
		return
	if name_input.text.strip_edges() == "":
		push_error("❌ Please enter a character name before beginning.")
		return

	var character_name := name_input.text.to_lower()
	var data := Global.load_player_data_from_file(character_name)

	if data.is_empty():
		push_error("❌ Could not load character save.")
		return

	if Global.return_to_multiplayer_menu:
		get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")
		return

	get_tree().change_scene_to_file(Global.START_ZONE_PATH)


# Sends the character built by Confirm to the server. The zone loads first and the server creates the
# character during login (net.gd); if it refuses (name taken...) the player lands back on Join a Server.
func _begin_on_server() -> void:
	if _pending_server_character.is_empty():
		_status_label.text = "Press Confirm first to finish designing your character."
		return
	var target: Dictionary = Global.server_creation
	Global.server_creation = {}
	Global.return_to_join_server_menu = false  # a successful join must not reopen the menu at the next camp-out
	Net.begin_join_server(target["address"], target["port"], str(_pending_server_character["player_name"]), target["password"], _pending_server_character)


# ---------------------------------------------------------
# BACK BUTTON — cancel out of character creation. Returns to wherever this
# screen was reached from: the multiplayer menu (if flagged) or the main menu.
# ---------------------------------------------------------
func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")
