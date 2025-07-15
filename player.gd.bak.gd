extends CharacterBody2D

@export var speed = 200.0
@export var player_name: String = "Adventurer": set = _set_player_name # Configurable player name with setter

@onready var animated_sprite = $AnimatedSprite2D # Assuming your AnimatedSprite2D is named PlayerSprite
@onready var name_label = $NameLabel # Reference to the Label node for the player's name

var last_direction: Vector2 = Vector2.RIGHT # Initialize to a default direction (e.g., facing right)
var faction_standing: Dictionary = {"Villagers of Lumora": 50} # Example faction standing

func _ready():
	# Initialize the name label
	if name_label:
		_set_player_name(player_name) # Use setter to initialize
		_update_label_position()
	else:
		print("ERROR: NameLabel node not found as child of Player!")

func _physics_process(delta):
	if not Global.is_chat_active: # Only process movement if chat is not active
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
	else:
		velocity = Vector2.ZERO # Stop movement if chat is active
		if animated_sprite:
			animated_sprite.play("Idle") # Ensure idle animation during chat

	move_and_slide()

# Setter for player_name to update the label dynamically
func _set_player_name(value: String):
	player_name = value
	if name_label:
		name_label.text = player_name
		_update_label_position()

# Update label position based on sprite and label size
func _update_label_position():
	if name_label and animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Idle"):
		var texture_height = animated_sprite.sprite_frames.get_frame_texture("Idle", 0).get_size().y
		name_label.position = Vector2(-name_label.size.x / 2, -texture_height - 20)
	else:
		print("ERROR: Cannot update label position due to missing sprite or animation.")

# New function: Returns the player's last non-zero movement direction
func get_last_direction() -> Vector2:
	return last_direction

# New function: Returns the player's standing with a given faction
func get_faction_standing(faction_name: String) -> int:
	if faction_standing.has(faction_name):
		return faction_standing[faction_name]
	return 0 # Default to neutral if faction not found
