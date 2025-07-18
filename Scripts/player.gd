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
	# Initial UI setup using @export defaults. These will be overwritten by load_character_data()
	# if data is passed from character creation/load game. This is good for testing the scene directly.
	health_bar.max_value = max_health
	health_bar.value = current_health
	# The initial name_label.text will be the default here. It will be updated by load_character_data if called.
	name_label.text = player_name # Display initial default name

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

	# If you want to load test data immediately when player scene starts (e.g., for direct scene testing)
	# You can uncomment this, but normally game management loads the character.
	# This would be for development convenience only.
	# load_character_data_from_file() # This loads from res://Data/character_stats.json


# load_character_data - Initializes player stats from provided dictionary
# THIS IS THE PRIMARY FUNCTION CALLED BY YOUR GLOBAL/SAVE MANAGER
func load_character_data(data: Dictionary):
	print("DEBUG: Player: load_character_data called with data: ", data)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("❌ Invalid character data type passed to player. Expected Dictionary, got %s." % typeof(data))
		return

	# CRITICAL: Update player_name first from the loaded data
	player_name = data.get("player_name", "Unnamed Player") # Ensure this updates the player_name variable

	stats = data.get("stats", {})
	var derived_data = data.get("derived", {}) # Renamed to avoid conflict with 'derived' member variable if any

	# NEW: Initialize resistances if they don't exist in the loaded data (for backward compatibility)
	data["resistances"] = data.get("resistances", {
		"acid": 0,
		"cold": 0,
		"fire": 0,
		"magic": 0,
		"psychic": 0
	})
	
	# NEW: Initialize equipment if it doesn't exist in the loaded data (for backward compatibility)
	data["equipment"] = data.get("equipment", {
		"ear1": "", "neck": "", "face": "", "head": "", "ear2": "",
		"finger1": "", "wrist1": "", "arms": "", "hands": "", "wrist2": "",
		"finger2": "", "shoulders": "", "chest": "", "back": "", "waist": "",
		"legs": "", "feet": "", "trinket1": "", "trinket2": "",
		"primary": "", "secondary": "", "ranged": "", "ammo": ""
	})

	if derived_data.has("health"):
		max_health = derived_data["health"]
		current_health = data.get("current_health", max_health) # Get current_health from save if exists, else use max
		health_bar.max_value = max_health
		health_bar.value = current_health
	else:
		push_warning("Derived health not found in character data. Using default: %d" % max_health)

	if derived_data.has("mana"):
		max_mana = derived_data["mana"]
		current_mana = data.get("current_mana", max_mana) # Get current_mana from save if exists, else use max
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

	# CRITICAL FIX: Call update_player_label() *after* player_name has been updated from data
	update_player_label()
	print("✅ Loaded stats for", player_name)


# load_character_data_from_file - Loads character stats from a hardcoded JSON file (Legacy/Debug Only)
# This function is here for debugging convenience, but typically you'd load via a Save/Load Manager.
func load_character_data_from_file():
	print("DEBUG: (Legacy) Attempting to load character_stats.json from res://Data/")
	var file: FileAccess = FileAccess.open("res://Data/character_stats.json", FileAccess.READ)
	if file:
		var content: String = file.get_as_text()
		var data: Variant = JSON.parse_string(content) # JSON.parse_string can return Variant

		file.close()

		if typeof(data) == TYPE_DICTIONARY:
			# Call the main loading function for consistency
			load_character_data(data)
			print("✅ (Legacy) Loaded stats for", player_name, " from res://Data/character_stats.json")
		else:
			push_error("❌ (Legacy) JSON parsing failed or returned non-dictionary for character_stats.json")
	else:
		push_error("❌ (Legacy) Failed to open character_stats.json at res://Data/. This should ideally not be called in production.")


# load_spells - Loads player spells from JSON
func load_spells():
	print("DEBUG: Attempting to load player_spells.json")
	var file: FileAccess = FileAccess.open("res://Data/player_spells.json", FileAccess.READ)
	if file:
		var content: String = file.get_as_text()
		var data: Variant = JSON.parse_string(content)
		file.close()
		if typeof(data) == TYPE_ARRAY:
			spells = data
			print("✅ Loaded spells from player_spells.json")
		else:
			push_error("❌ Failed to parse player_spells.json: content is not an Array.")
	else:
		push_error("❌ Failed to open player_spells.json.")


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
		last_direction = input_direction.normalized() # Update last_direction for aiming
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
	# Handle specific mouse button events for attacks
	if event is InputEventMouseButton:
		if event.is_action_pressed("ui_accept"): # Left click for melee
			print("DEBUG: Left click detected - triggering melee attack")
			melee_attack()
		elif event.is_action_pressed("ranged_attack"): # Right click for ranged/spell
			print("DEBUG: Right click detected - Action: ranged_attack, Warrior visible: ", player_warrior.visible, ", Caster visible: ", player_caster.visible)
			if player_warrior.visible:
				var mouse_pos: Vector2 = get_global_mouse_position()
				ranged_attack(mouse_pos)
			elif player_caster.visible:
				cast_magic_missile()
			else:
				print("ERROR: Neither warrior nor caster sprite is visible for right-click action!")
	
	# Handle character sheet toggle using the global Input singleton
	# This ensures it works regardless of the specific InputEvent type (e.g., mouse motion won't crash it)
	if Input.is_action_just_pressed("toggle_character_sheet"):
		print("DEBUG: Input.is_action_just_pressed('toggle_character_sheet') triggered. Calling toggle_character_sheet().")
		toggle_character_sheet()


# melee_attack - Performs a melee attack
func melee_attack():
	var melee_range := 50.0
	var melee_damage: int = stats.get("strength", 10) # Base damage on strength or default. Explicit type int.
	var attack_position: Vector2 = global_position + last_direction * (melee_range / 2)
	var monsters: Array[Node] = get_tree().get_nodes_in_group("monsters")
	for monster in monsters:
		if monster is CharacterBody2D and is_instance_valid(monster) and monster.global_position.distance_to(attack_position) < melee_range:
			# Consider checking if monster has apply_damage method
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
		# Assuming Area2D has a 'direction' property, or you'll need a script on it
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

	# Determine base direction: target closest monster, else mouse position
	var base_direction: Vector2 = last_direction # Default to player's last movement direction
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
		# If no target, use mouse direction for better player control
		base_direction = (get_global_mouse_position() - global_position).normalized()

	# Fire 3 projectiles with slight spread
	var angles: Array[float] = [-15, 0, 15]
	for angle in angles:
		var missile: Area2D = magic_missile_scene.instantiate()
		if missile:
			missile.global_position = global_position
			# Assuming Area2D has a 'target' and 'direction' property, or you'll need a script on it
			missile.target = closest_monster # Assign target for homing (if found)
			var rad: float = deg_to_rad(angle)
			missile.direction = base_direction.rotated(rad)
			get_tree().current_scene.add_child(missile)
		else:
			push_error("ERROR: Failed to instantiate magic_missile.tscn")
	print("🪄 Cast Magic Missile: 3 bolts, %d mana consumed" % mana_cost)


# toggle_character_sheet - Opens or closes the character sheet UI
# This function is responsible for opening and closing the character sheet UI.
func toggle_character_sheet():
	print("DEBUG: toggle_character_sheet() called from player.gd.") 

	# Ensure the scene exists before attempting to preload
	if not ResourceLoader.exists("res://Scenes/character_sheet.tscn"):
		push_error("❌ Error: character_sheet.tscn does not exist at 'res://Scenes/character_sheet.tscn'. Check path.")
		return

	var character_sheet_scene: PackedScene = preload("res://Scenes/character_sheet.tscn")
	
	var existing_character_sheet: CanvasLayer = get_tree().current_scene.find_child("character_sheet")
	print("DEBUG: Existing character sheet found (or not):", existing_character_sheet)
	
	if not is_instance_valid(existing_character_sheet): # If the sheet is NOT currently open
		# --- Open the character sheet ---
		var instance_sheet: CanvasLayer = character_sheet_scene.instantiate() 
		
		instance_sheet.name = "character_sheet" # Assign a unique name so we can find this specific instance later

		# Set the process mode so it continues to receive input/process even if the game is paused
		instance_sheet.process_mode = Node.PROCESS_MODE_ALWAYS # Crucial for pause menu behavior
		print("DEBUG: Character sheet instance process_mode set to ALWAYS.") 

		get_tree().current_scene.add_child(instance_sheet) 

		# --- Pass the loaded character data to the newly opened sheet ---
		# This is the critical part to get data from Global to the sheet
		if Global.current_character_data and is_instance_valid(instance_sheet):
			instance_sheet.set_character_data(Global.current_character_data)
			print("DEBUG: Passed character data to character sheet.")
		else:
			push_warning("⚠️ Global.current_character_data not found when opening character sheet. Sheet may not display correctly.")

		print("📋 Character sheet opened.")
	else:
		# --- Close the existing character sheet ---
		# We'll rely on the character_sheet.gd's own _input to queue_free itself
		# when the 'C' key is pressed while it's open.
		# This 'else' block serves as a robust fallback to ensure it closes.
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
		# Handle player death (e.g., game over screen)


# get_last_direction - Returns the player's last movement direction
func get_last_direction() -> Vector2:
	return last_direction


# get_faction_standing - Returns faction standing for a given faction
func get_faction_standing(faction_name: String) -> int:
	return faction_standing.get(faction_name, 0)


# load_faction_standing - Loads faction data from JSON
func load_faction_standing():
	var file: FileAccess = FileAccess.open("res://Data/player_faction.json", FileAccess.READ)
	if file:
		var json_data: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(json_data) == TYPE_DICTIONARY and json_data.has("factions"):
			for faction in json_data["factions"]:
				if faction.has("name") and faction.has("standing"):
					faction_standing[faction["name"]] = faction["standing"]
				else:
					push_warning("Faction entry missing 'name' or 'standing' in player_faction.json: %s" % faction)
			print("✅ Loaded faction standing from player_faction.json")
		else:
			push_error("❌ Failed to parse player_faction.json or 'factions' key not found. Content: %s" % json_data)
	else:
		push_error("❌ Failed to open player_faction.json.")


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
