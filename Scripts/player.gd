# player.gd
extends CharacterBody2D

@export var speed = 200.0
@export var max_health := 100 # Initial default, will be overwritten by load_character_data
@export var current_health := 100 # Initial default, will be overwritten by load_character_data
@export var max_mana := 100 # Initial default, will be overwritten by load_character_data
@export var current_mana := 100 # Initial default, will be overwritten by load_character_data
@export var player_name := "Default Hero" # Changed default to indicate it's a fallback, will be overwritten by load_character_data

@export var health_regen_rate := 1.0
@export var mana_regen_rate := 2.0
@export var regen_interval := 2.0
var regen_timer := 0.0

var armor_class := 0
var stats: Dictionary = {} # This will be populated by load_character_data
var last_direction: Vector2 = Vector2.RIGHT # Initial direction
var faction_standing: Dictionary = {"Villagers of Lumora": 50}

var caster_classes := [
	"voidknight", "gravecaller", "runecaster", "arcanist", "wildmage",
	"lightsworn", "lightmender", "spiritcaller", "wildspeaker", "woodstalker"
]

# Attack-related variables
var magic_missile_scene: PackedScene = preload("res://Scenes/magic_missile.tscn") # Explicit type
var ranged_attack_scene: PackedScene = preload("res://Scenes/ranged_attack.tscn") # Explicit type
var magic_missile_cooldown := 0.0
var magic_missile_cooldown_duration := 10.0 # From spell data or a default
var ranged_attack_cooldown := 0.0
var ranged_attack_cooldown_duration := 2.0
var spells: Array = []

@onready var player_warrior := $player_warrior # Make sure this is your AnimatedSprite2D or similar
@onready var player_caster := $player_caster # Make sure this is your AnimatedSprite2D or similar
@onready var health_bar := $health_bar
@onready var mana_bar := $mana_bar
@onready var name_label := $name_label


func _ready():
	health_bar.max_value = max_health
	health_bar.value = current_health
	name_label.text = player_name

	mana_bar.visible = false
	player_warrior.visible = true
	player_caster.visible = false

	load_faction_standing()
	load_spells()

	print("DEBUG: Final visibility - Warrior: ", player_warrior.visible, ", Caster: ", player_caster.visible)
	if not ResourceLoader.exists("res://Scenes/ranged_attack.tscn"):
		print("ERROR: ranged_attack.tscn not found!")
	if not ResourceLoader.exists("res://Scenes/magic_missile.tscn"):
		print("ERROR: magic_missile.tscn not found!")

	# --- NEW / MODIFIED LOAD LOGIC FOR INITIAL GAME STARTUP ---
	if Global.current_character_data.is_empty():
		# If Global.current_character_data isn't set yet (e.g., first game launch, no save loaded from main menu)
		# Load a default character file. If "Annadaeus" is in a specific JSON file,
		# replace "jethro_character_stats.json" with "annadaeus_character_stats.json" here.
		var default_character_file_path = "res://Data/jethro_character_stats.json" # <--- ADJUST THIS PATH IF ANNADAEUS IS IN A DIFFERENT FILE!
		print("DEBUG: Global character data is empty. Attempting to load default character from: ", default_character_file_path)
		var file_data = load_json_file(default_character_file_path)
		if file_data:
			load_character_data(file_data)
		else:
			push_error("❌ Failed to load default character data from " + default_character_file_path + ". Character sheet might be blank.")
	else:
		# If Global.current_character_data already contains data (e.g., loaded from a main menu save)
		print("DEBUG: Global character data already set. Initializing player with existing data.")
		load_character_data(Global.current_character_data)
	# --- END NEW / MODIFIED LOAD LOGIC ---

	update_player_label()
	print("✅ Player _ready() finished. Player name:", player_name)


# load_character_data - Initializes player stats from provided dictionary
# THIS IS THE PRIMARY FUNCTION CALLED BY YOUR GLOBAL/SAVE MANAGER
func load_character_data(data: Dictionary):
	print("DEBUG: Player: load_character_data called with data: ", data)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("❌ Invalid character data type passed to player. Expected Dictionary, got %s." % typeof(data))
		return

	player_name = data.get("player_name", "Unnamed Player")
	stats = data.get("stats", {})
	var derived_data = data.get("derived", {})

	# Initialize resistances if they don't exist in the loaded data (for backward compatibility)
	data["resistances"] = data.get("resistances", {
		"acid": 0, "cold": 0, "fire": 0, "magic": 0, "psychic": 0
	})
	
	# Initialize equipment if it doesn't exist in the loaded data (for backward compatibility)
	data["equipment"] = data.get("equipment", {
		"ear1": "", "neck": "", "face": "", "head": "", "ear2": "",
		"finger1": "", "wrist1": "", "arms": "", "hands": "", "wrist2": "",
		"finger2": "", "shoulders": "", "chest": "", "back": "", "waist": "",
		"legs": "", "feet": "", "trinket1": "", "trinket2": "",
		"primary": "", "secondary": "", "ranged": "", "ammo": ""
	})

	# NEW: Initialize player_level and xp
	data["player_level"] = data.get("player_level", 1)
	data["xp"] = data.get("xp", 0)

	if derived_data.has("health"):
		max_health = derived_data["health"]
		current_health = data.get("current_health", max_health)
		health_bar.max_value = max_health
		health_bar.value = current_health
	else:
		push_warning("Derived health not found in character data. Using default: %d" % max_health)

	if derived_data.has("mana"):
		max_mana = derived_data["mana"]
		current_mana = data.get("current_mana", max_mana)
	else:
		push_warning("Derived mana not found in character data. Using default: %d" % max_mana)

	apply_racial_modifiers(data.get("player_race", ""))
	apply_mana_regen_bonus()

	var selected_class: String = data.get("player_class", "UNKNOWN").to_lower()
	print("DEBUG: Loaded player_class from data: ", data.get("player_class", "UNKNOWN"))
	print("DEBUG: Normalized selected_class (lowercase): ", selected_class)

	var is_caster: bool = caster_classes.has(selected_class)
	print("DEBUG: Caster classes array: ", caster_classes)
	print("DEBUG: Does caster_classes contain selected_class ('", selected_class, "')? ", is_caster)

	mana_bar.visible = is_caster
	if is_caster:
		mana_bar.max_value = max_mana
		mana_bar.value = current_mana
		player_caster.visible = true
		player_warrior.visible = false
		print("🧙 Caster sprite enabled for class:", selected_class)
	else:
		player_caster.visible = false
		player_warrior.visible = true
		print("⚔️ Warrior sprite enabled for class:", selected_class)

	# After loading, recalculate xp_next_level for current level
	_calculate_xp_next_level(data)

	# Update Global.current_character_data with any initialized/calculated values
	Global.current_character_data = data.duplicate() # Make a copy to avoid direct modification issues

	update_player_label()
	print("✅ Loaded stats for", player_name)

# NEW: Internal function to calculate XP needed for next level
func _calculate_xp_next_level(data_dict: Dictionary):
	var current_level: int = data_dict.get("player_level", 1)
	var max_level: int = Global.max_player_level # Get max level from Global

	if current_level >= max_level:
		data_dict["xp_next_level"] = data_dict.get("xp", 0) # Or -1, or 0, or specific "MAX"
		print("DEBUG: Player is at max level. XP next level set to current XP.")
	elif Global.xp_table.has(str(current_level + 1)): # XP table keys are strings
		data_dict["xp_next_level"] = Global.xp_table[str(current_level + 1)]
		print("DEBUG: XP needed for Level %d: %d" % [current_level + 1, data_dict["xp_next_level"]])
	else:
		data_dict["xp_next_level"] = 99999999 # Fallback to a very high number if level not found
		push_warning("⚠️ XP table does not have data for level %d. Setting xp_next_level to a large number." % (current_level + 1))


# NEW: Function to add experience to the player
func add_xp(amount: int):
	if Global.current_character_data.get("player_level", 1) >= Global.max_player_level:
		print("Player is already max level. Cannot gain more XP.")
		return

	var current_xp = Global.current_character_data.get("xp", 0)
	var xp_to_next_level = Global.current_character_data.get("xp_next_level", 0) # This should be correctly set by _calculate_xp_next_level

	current_xp += amount
	print("Gained %d XP. Current XP: %d" % [amount, current_xp])

	while current_xp >= xp_to_next_level and Global.current_character_data.get("player_level", 1) < Global.max_player_level:
		var current_level = Global.current_character_data.get("player_level", 1)
		
		# Spend the XP needed for this level
		current_xp -= xp_to_next_level
		
		# Level up!
		current_level += 1
		Global.current_character_data["player_level"] = current_level
		Global.current_character_data["xp"] = current_xp # Carry over remaining XP

		print("🎉 Level Up! Player is now Level %d!" % current_level)
		# You might want to trigger other effects here:
		# - Play a sound
		# - Show a particle effect
		# - Grant skill points or stat bonuses (requires further logic)

		# Recalculate XP needed for the new next level
		if current_level < Global.max_player_level:
			xp_to_next_level = Global.xp_table.get(str(current_level + 1), 99999999) # Get next level's XP
			Global.current_character_data["xp_next_level"] = xp_to_next_level
			print("New XP needed for next level (%d): %d" % [current_level + 1, xp_to_next_level])
		else:
			Global.current_character_data["xp_next_level"] = Global.current_character_data["xp"] # Max level, XP needed is current XP
			print("Player reached MAX LEVEL (%d)!" % Global.max_player_level)

	Global.current_character_data["xp"] = current_xp # Save final current XP after loop
	# You'd typically save Global.current_character_data to a file here as well, or at regular save points.
	# For testing, you could call save_character_data_to_file() here:
	# save_character_data_to_file("res://Data/jethro_character_stats.json") # Or your Annadaeus file


# NEW HELPER: load_json_file - Loads JSON data from a specified file path
func load_json_file(file_path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var content: String = file.get_as_text()
		var data: Variant = JSON.parse_string(content)
		file.close()
		if typeof(data) == TYPE_DICTIONARY:
			return data
		else:
			push_error("❌ Failed to parse JSON or content is not a Dictionary from " + file_path)
			return {}
	else:
		push_error("❌ Failed to open JSON file: " + file_path)
		return {}


# load_spells - Loads player spells from JSON
func load_spells():
	print("DEBUG: Attempting to load player_spells.json")
	var file_data = load_json_file("res://Data/player_spells.json")
	if file_data: # If load_json_file returns a dictionary, it's not an array, so check if it's not empty
		if typeof(file_data) == TYPE_ARRAY: # Ensure spells data is an array
			spells = file_data
			print("✅ Loaded spells from player_spells.json")
		else:
			push_error("❌ Failed to parse player_spells.json: content is not an Array.")
	else:
		push_error("❌ Failed to open player_spells.json or file is empty.")


# apply_racial_modifiers - Applies stat modifiers based on race
func apply_racial_modifiers(race_name: String):
	var race: String = race_name.to_lower()
	if race == "troll" or race == "lizardkin":
		health_regen_rate *= 1.15
		if race == "lizardkin":
			armor_class += 2


# apply_mana_regen_bonus - Applies mana regeneration bonus based on skills
func apply_mana_regen_bonus():
	var meditation_skill: int = stats.get("wisdom", 0)
	mana_regen_rate = 1 + float(meditation_skill) / 2.0


# update_player_label - Updates the player's name display
func update_player_label():
	if is_instance_valid(name_label):
		name_label.text = player_name
	else:
		push_error("Label node is invalid or path is incorrect! Check the path to name_label.")


# _physics_process - Handles player movement and cooldowns
func _physics_process(delta: float):
	var input_direction: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("ui_right"):
		input_direction.x += 1
	if Input.is_action_pressed("ui_left"):
		input_direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		input_direction.y += 1
	if Input.is_action_pressed("ui_up"):
		input_direction.y -= 1
		
	if input_direction.length() > 0:
		velocity = input_direction.normalized() * speed
		last_direction = input_direction.normalized()
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	# Update cooldowns
	if magic_missile_cooldown > 0:
		magic_missile_cooldown = max(magic_missile_cooldown - delta, 0)
	if ranged_attack_cooldown > 0:
		ranged_attack_cooldown = max(ranged_attack_cooldown - delta, 0)


# _input - Handles player actions (attacks, character sheet toggle)
func _input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.is_action_pressed("ui_accept"):
			print("DEBUG: Left click detected - triggering melee attack")
			melee_attack()
		elif event.is_action_pressed("ranged_attack"):
			print("DEBUG: Right click detected - Action: ranged_attack, Warrior visible: ", player_warrior.visible, ", Caster visible: ", player_caster.visible)
			if player_warrior.visible:
				var mouse_pos: Vector2 = get_global_mouse_position()
				ranged_attack(mouse_pos)
			elif player_caster.visible:
				cast_magic_missile()
			else:
				print("ERROR: Neither warrior nor caster sprite is visible for right-click action!")
	
	if Input.is_action_just_pressed("toggle_character_sheet"):
		print("DEBUG: Input.is_action_just_pressed('toggle_character_sheet') triggered. Calling toggle_character_sheet().")
		toggle_character_sheet()


# melee_attack - Performs a melee attack
func melee_attack():
	var melee_range := 50.0
	var melee_damage: int = stats.get("strength", 10)
	var attack_position: Vector2 = global_position + last_direction * (melee_range / 2)
	var monsters: Array[Node] = get_tree().get_nodes_in_group("monsters")
	for monster in monsters:
		if monster is CharacterBody2D and is_instance_valid(monster) and monster.global_position.distance_to(attack_position) < melee_range:
			if monster.has_method("apply_damage"):
				monster.apply_damage(melee_damage)
				print("⚔️ Melee hit on", monster.name, "for", melee_damage, "damage")
			else:
				print("WARNING: Monster", monster.name, "does not have 'apply_damage' method.")


# ranged_attack - Fires a physical projectile
func ranged_attack(mouse_pos: Vector2):
	if ranged_attack_cooldown > 0:
		print("🕒 Ranged attack on cooldown:", ranged_attack_cooldown, "seconds remaining")
		return

	ranged_attack_cooldown = ranged_attack_cooldown_duration
	var projectile: Area2D = ranged_attack_scene.instantiate()
	if projectile:
		projectile.global_position = global_position
		var direction: Vector2 = (mouse_pos - global_position).normalized()
		projectile.direction = direction
		get_tree().current_scene.add_child(projectile)
		print("🏹 Fired ranged attack toward mouse position: ", mouse_pos)
	else:
		push_error("ERROR: Failed to instantiate ranged_attack.tscn")


# cast_magic_missile - Casts a magic missile spell
func cast_magic_missile():
	if magic_missile_cooldown > 0:
		print("🕒 Magic Missile on cooldown:", magic_missile_cooldown, "seconds remaining")
		return

	var spell_results: Array = spells.filter(func(s): return s["spell_id"] == 477)
	if spell_results.is_empty():
		push_warning("⚠️ Magic Missile spell (ID 477) not found in player_spells.json")
		return
	var spell: Dictionary = spell_results[0]
	
	var mana_cost: int = spell.get("mana_cost", 0)
	if current_mana < mana_cost:
		print("⚡ Insufficient mana:", current_mana, "/", mana_cost)
		return

	current_mana = max(current_mana - mana_cost, 0)
	mana_bar.value = current_mana
	magic_missile_cooldown = spell.get("recast_time", magic_missile_cooldown_duration)

	var base_direction: Vector2 = last_direction
	var closest_monster: CharacterBody2D = null

	var monsters: Array[Node] = get_tree().get_nodes_in_group("monsters")
	if not monsters.is_empty():
		var find_closest = func(closest: CharacterBody2D, m: Node):
			if not is_instance_valid(m) or not (m is CharacterBody2D): return closest
			var dist: float = m.global_position.distance_to(global_position)
			return m if closest == null or dist < closest.global_position.distance_to(global_position) else closest
		closest_monster = monsters.reduce(find_closest, null)
		
	if closest_monster:
		base_direction = (closest_monster.global_position - global_position).normalized()
	else:
		base_direction = (get_global_mouse_position() - global_position).normalized()

	var angles: Array[float] = [-15, 0, 15]
	for angle in angles:
		var missile: Area2D = magic_missile_scene.instantiate()
		if missile:
			missile.global_position = global_position
			missile.target = closest_monster
			var rad: float = deg_to_rad(angle)
			missile.direction = base_direction.rotated(rad)
			get_tree().current_scene.add_child(missile)
		else:
			push_error("ERROR: Failed to instantiate magic_missile.tscn")
	print("🪄 Cast Magic Missile: 3 bolts, %d mana consumed" % mana_cost)


# toggle_character_sheet - Opens or closes the character sheet UI
func toggle_character_sheet():
	print("DEBUG: toggle_character_sheet() called from player.gd.") 

	if not ResourceLoader.exists("res://Scenes/character_sheet.tscn"):
		push_error("❌ Error: character_sheet.tscn does not exist at 'res://Scenes/character_sheet.tscn'. Check path.")
		return

	var character_sheet_scene: PackedScene = preload("res://Scenes/character_sheet.tscn")
	
	var existing_character_sheet: CanvasLayer = get_tree().current_scene.find_child("character_sheet")
	print("DEBUG: Existing character sheet found (or not):", existing_character_sheet)
	
	if not is_instance_valid(existing_character_sheet):
		var instance_sheet: CanvasLayer = character_sheet_scene.instantiate() 
		instance_sheet.name = "character_sheet"

		instance_sheet.process_mode = Node.PROCESS_MODE_ALWAYS
		print("DEBUG: Character sheet instance process_mode set to ALWAYS.") 

		get_tree().current_scene.add_child(instance_sheet) 

		if Global.current_character_data and is_instance_valid(instance_sheet):
			instance_sheet.set_character_data(Global.current_character_data)
			print("DEBUG: Passed character data to character sheet.")
		else:
			push_warning("⚠️ Global.current_character_data not found when opening character sheet. Sheet may not display correctly.")

		print("📋 Character sheet opened.")
	else:
		print("DEBUG: Attempting to close character sheet from player.gd fallback.") 
		if is_instance_valid(existing_character_sheet):
			existing_character_sheet.queue_free()

		print("📋 Character sheet closed.")


# _process - Handles regeneration over time
func _process(delta: float):
	regen_timer += delta
	if regen_timer >= regen_interval:
		regen_timer = 0.0

		if current_health < max_health:
			current_health = min(current_health + health_regen_rate, max_health)
			health_bar.value = current_health

		if mana_bar.visible and current_mana < max_mana:
			current_mana = min(current_mana + mana_regen_rate, max_mana)
			mana_bar.value = current_mana


# apply_damage - Reduces player health
func apply_damage(amount: int):
	current_health = max(current_health - amount, 0)
	health_bar.value = current_health
	print("Player took %d damage. Current health: %d" % [amount, current_health])
	if current_health <= 0:
		print("Player defeated!")


# get_last_direction - Returns the player's last movement direction
func get_last_direction() -> Vector2:
	return last_direction


# get_faction_standing - Returns faction standing for a given faction
func get_faction_standing(faction_name: String) -> int:
	return faction_standing.get(faction_name, 0)


# load_faction_standing - Loads faction data from JSON
func load_faction_standing():
	var file_data = load_json_file("res://Data/player_faction.json")
	if file_data and file_data.has("factions"):
		for faction in file_data["factions"]:
			if faction.has("name") and faction.has("standing"):
				faction_standing[faction["name"]] = faction["standing"]
			else:
				push_warning("Faction entry missing 'name' or 'standing' in player_faction.json: %s" % faction)
		print("✅ Loaded faction standing from player_faction.json")
	else:
		push_error("❌ Failed to parse player_faction.json or 'factions' key not found.")


# save_faction_standing - Saves current faction data to JSON
func save_faction_standing():
	var file: FileAccess = FileAccess.open("user://saves/player_faction.json", FileAccess.WRITE)
	if file:
		var factions_array: Array = []
		for faction_name in faction_standing.keys():
			factions_array.append({
				"name": faction_name,
				"standing": faction_standing.get(faction_name)
			})
		var json_output: Dictionary = {"factions": factions_array}
		file.store_string(JSON.stringify(json_output, "\t"))
		file.close()
		print("💾 Faction standing saved to user://saves/player_faction.json")
	else:
		push_error("❌ Failed to write faction save file: user://saves/player_faction.json")
