#player3d.gd - player controller logic
extends CharacterBody3D
class_name Player3D

## Player 3D Movement Controller
## Implements: WASD movement, jump, stamina, crouch

#region Configuration
const WALK_SPEED: float = 5.0
const RUN_SPEED: float = 8.0
const CROUCH_SPEED: float = 2.5
const JUMP_VELOCITY: float = 6.0  # ~1.5m height
const TURN_SPEED: float = PI  # 180° per second

# Stamina system
const MAX_STAMINA: float = 100.0
const STAMINA_DRAIN_RUN: float = 0.5
const STAMINA_DRAIN_JUMP_STANDING: float = 5.0
const STAMINA_DRAIN_JUMP_RUNNING: float = 3.0
const STAMINA_REGEN_WALK: float = 2.0
const STAMINA_REGEN_STAND: float = 5.0
const STAMINA_REGEN_SIT: float = 10.0

# Movement modifiers
const BACKWARD_SPEED_MULT: float = 0.75
const AIR_CONTROL_MULT: float = 0.3
const STUMBLE_DURATION: float = 0.2
#endregion

#region State Variables
var current_stamina: float = MAX_STAMINA
var is_running: bool = true  # Default to run (toggle with Shift)
var is_crouching: bool = false
var is_in_air: bool = false
var stumble_timer: float = 0.0

# Movement state
var movement_direction: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
#endregion

#region Node References
@onready var camera_rig: Node3D = $CameraRig
#endregion

func _ready() -> void:
	print("[Player3D] Player initialized")

func _physics_process(delta: float) -> void:
	# Handle stumble
	if stumble_timer > 0.0:
		stumble_timer -= delta
		return  # Can't move while stumbling
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		is_in_air = true
	else:
		if is_in_air and velocity.y < -10.0:  # Hard landing
			stumble_timer = STUMBLE_DURATION
			print("[Player3D] Hard landing! Stumble for ", STUMBLE_DURATION, "s")
		is_in_air = false
	
	# Handle input
	handle_toggle_run()
	handle_crouch()
	handle_jump()
	handle_movement(delta)
	
	# Update stamina
	update_stamina(delta)
	
	# Apply movement
	move_and_slide()

func handle_toggle_run() -> void:
	if Input.is_action_just_pressed("toggle_run"):  # Shift key
		is_running = not is_running
		print("[Player3D] Run mode: ", "ON" if is_running else "OFF")

func handle_crouch() -> void:
	if Input.is_action_pressed("crouch"):  # Ctrl key
		if not is_crouching:
			is_crouching = true
			print("[Player3D] Crouching")
			# TODO: Adjust collision capsule height
	else:
		if is_crouching:
			is_crouching = false
			print("[Player3D] Standing up")
			# TODO: Restore collision capsule height

func handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if current_stamina <= 0.0:
			print("[Player3D] Too tired to jump!")
			return
		
		# Calculate stamina cost
		var jump_cost: float = STAMINA_DRAIN_JUMP_STANDING
		if velocity.length() > 1.0:  # Moving while jumping
			jump_cost = STAMINA_DRAIN_JUMP_RUNNING
		
		current_stamina = max(0.0, current_stamina - jump_cost)
		velocity.y = JUMP_VELOCITY
		print("[Player3D] Jump! Stamina: ", current_stamina)

func handle_movement(delta: float) -> void:
	# Get input direction (local to player)
	var input_dir := Vector2.ZERO
	
	# Forward/backward (W/S)
	if Input.is_action_pressed("move_forward"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_backward"):
		input_dir.y -= 1.0
	
	# Strafe (Q/E)
	if Input.is_action_pressed("strafe_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("strafe_right"):
		input_dir.x += 1.0
	
	# Turn (A/D) - rotates character
	var turn_input: float = 0.0
	if Input.is_action_pressed("turn_left"):
		turn_input += 1.0
	if Input.is_action_pressed("turn_right"):
		turn_input -= 1.0
	
	if turn_input != 0.0:
		rotate_y(turn_input * TURN_SPEED * delta)
	
	# Calculate movement direction (world space)
	movement_direction = Vector3.ZERO
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		movement_direction = (transform.basis * Vector3(input_dir.x, 0, -input_dir.y)).normalized()
	
	# Determine speed
	current_speed = WALK_SPEED
	
	if is_crouching:
		current_speed = CROUCH_SPEED
	elif is_running and current_stamina > 0.0:
		current_speed = RUN_SPEED
	
	# Apply backward penalty
	if input_dir.y < 0:  # Moving backward
		current_speed *= BACKWARD_SPEED_MULT
	
	# Calculate target velocity
	var target_velocity := movement_direction * current_speed
	
	# Apply air control if jumping
	var control_mult: float = 1.0 if is_on_floor() else AIR_CONTROL_MULT
	
	velocity.x = lerp(velocity.x, target_velocity.x, 10.0 * delta * control_mult)
	velocity.z = lerp(velocity.z, target_velocity.z, 10.0 * delta * control_mult)

func update_stamina(delta: float) -> void:
	var is_moving: bool = velocity.length() > 0.1
	
	# Drain stamina
	if is_running and is_moving and is_on_floor() and current_stamina > 0.0:
		current_stamina = max(0.0, current_stamina - STAMINA_DRAIN_RUN * delta)
		if current_stamina == 0.0:
			print("[Player3D] Exhausted! Forced to walk")
	
	# Regen stamina
	else:
		var regen_rate: float = STAMINA_REGEN_STAND
		
		if is_moving:
			regen_rate = STAMINA_REGEN_WALK
		# TODO: Add sitting check for faster regen
		
		current_stamina = min(MAX_STAMINA, current_stamina + regen_rate * delta)

#region Debug Info
func _process(_delta: float) -> void:
	# Debug display (remove later)
	if Input.is_action_just_pressed("ui_accept"):  # Space for now
		print("=== PLAYER DEBUG ===")
		print("Position: ", global_position)
		print("Velocity: ", velocity)
		print("Stamina: ", current_stamina, "/", MAX_STAMINA)
		print("Running: ", is_running)
		print("Crouching: ", is_crouching)
		print("On floor: ", is_on_floor())
#endregion
