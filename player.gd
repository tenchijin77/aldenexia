extends CharacterBody2D

@export var speed = 200.0

@onready var animated_sprite = $AnimatedSprite2D # Assuming your AnimatedSprite2D is named PlayerSprite, update this to match

var last_direction: Vector2 = Vector2.RIGHT # Initialize to a default direction (e.g., facing right)
var faction_standing: Dictionary = {"Villagers of Lumora": 50} # Example faction standing

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
