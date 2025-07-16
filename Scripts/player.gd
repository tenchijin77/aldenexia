#player.gd
extends CharacterBody2D

@export var speed = 200.0
@export var max_health := 100
@export var player_name := "Ross of Lumora" # Default, to be overwritten

@onready var animated_sprite = $AnimatedSprite2D # Assuming your AnimatedSprite2D is named PlayerSprite, update this to match
@onready var health_bar := $health_bar
@onready var name_label := $name_label

var last_direction: Vector2 = Vector2.RIGHT # Initialize to a default direction (e.g., facing right)
var faction_standing: Dictionary = {"Villagers of Lumora": 50} # Example faction standing
var current_health := max_health
var stats: Dictionary = {}


func _ready():
	health_bar.max_value = max_health
	health_bar.value = current_health
	name_label.text = player_name
	load_faction_standing() 
	load_character_data()
	update_player_label()
	

func load_character_data():
	print("DEBUG: Attempting to load character_stats.json")
	var file = FileAccess.open("res://Data/character_stats.json", FileAccess.READ)
	if file: 
		var content = file.get_as_text()
		print("DEBUG: File content:", content)
		var data = JSON.parse_string(content)
		if typeof(data) == TYPE_DICTIONARY:
			stats = data
			player_name = stats.get("player_name", player_name)
			print("DEBUG: Loaded player_name from JSON:", player_name)
		else:
			print("DEBUG: JSON parsing failed or returned non-dictionary")
		file.close()
	else:
		print("DEBUG: Failed to open character_stats.json")




func update_player_label():
	var label = $name_label
	if label:
		label.text = player_name
	else:
		print("Label is playing hide and seek! Check the path!")

func _physics_process(delta):
	var input_direction = Vector2.ZERO
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
		last_direction = input_direction.normalized() # Update last_direction only when moving

		# Play walk animation
		if animated_sprite:
			animated_sprite.play("Moving") # Assuming you have a "walk" animation
			if input_direction.x < 0:
				animated_sprite.flip_h = true
			elif input_direction.x > 0:
				animated_sprite.flip_h = false
	else:
		velocity = Vector2.ZERO # Stop if no input
		# Play idle animation when not moving
		if animated_sprite:
			animated_sprite.play("Idle") # Assuming you have an "idle" animation

	move_and_slide()

# New function: Returns the player's last non-zero movement direction
func get_last_direction() -> Vector2:
	return last_direction

# New function: Returns the player's standing with a given faction
func get_faction_standing(faction_name: String) -> int:
	if faction_standing.has(faction_name):
		return faction_standing[faction_name]
	return 0 # Default to neutral if faction not found

# Load faction from player_faction.json

func load_faction_standing():
	var file = FileAccess.open("res://Data/player_faction.json", FileAccess.READ)
	if file:
		var json_data = JSON.parse_string(file.get_as_text())
		if json_data and json_data.has("factions"):
			for faction in json_data["factions"]:
				faction_standing[faction["name"]] = faction["standing"]
		file.close()

# Save faction to player_faction.json

func save_faction_standing():
	var file = FileAccess.open("res://Data/player_faction.json", FileAccess.WRITE)
	if file:
		var factions_array = []
		for faction_name in faction_standing.keys():
			factions_array.append({
				"name": faction_name,
				"standing": faction_standing[faction_name]
			})
		var json_output = {"factions": factions_array}
		file.store_string(JSON.stringify(json_output, "\t"))  # Pretty print
		file.close()
	

#apply damage or healing (to be added later)
func apply_damage(amount: int):
	current_health = max(current_health - amount, 0)
	health_bar.value = current_health
	
