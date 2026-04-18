# player3d.gd - 3D player controller with RPG systems
# Based on 2D player.gd pattern, adapted for 3D
extends CharacterBody3D
class_name Player3D

## Player 3D Controller with RPG Systems
## Combines movement (from original 3D) with health/mana/combat (from 2D)

#region Movement Configuration
const WALK_SPEED: float = 5.0
const RUN_SPEED: float = 8.0
const CROUCH_SPEED: float = 2.5
const JUMP_VELOCITY: float = 6.0
const TURN_SPEED: float = PI

# Stamina system
const MAX_STAMINA: float = 100.0
const STAMINA_DRAIN_RUN: float = 0.5
const STAMINA_DRAIN_JUMP: float = 5.0
const STAMINA_REGEN_WALK: float = 2.0
const STAMINA_REGEN_STAND: float = 5.0

const BACKWARD_SPEED_MULT: float = 0.75
const AIR_CONTROL_MULT: float = 0.3
const STUMBLE_DURATION: float = 0.2
#endregion

#region RPG Stats (from 2D player)
@export var max_health := 100
@export var current_health := 100
@export var max_mana := 100
@export var current_mana := 100
@export var player_name := "Default Hero"

@export var health_regen_rate := 1.0
@export var mana_regen_rate := 2.0
@export var regen_interval := 2.0
var regen_timer := 0.0

var armor_class := 0
var stats: Dictionary = {}
var faction_standing: Dictionary = {"Villagers of Lumora": 50}

var caster_classes := [
	"voidknight", "gravecaller", "runecaster", "arcanist", "chaosborn",
	"lightsworn", "lightmender", "spiritcaller", "wildspeaker", "woodstalker", "aetherfist"
]
#endregion

#region Combat
var spells: Array = []
var dying: bool = false
var attacking: bool = false
var attack_cooldown: float = 0.0
var attack_cooldown_duration: float = 1.0
#endregion

#region Movement State
var current_stamina: float = MAX_STAMINA
var is_running: bool = true
var is_crouching: bool = false
var is_in_air: bool = false
var stumble_timer: float = 0.0
var movement_direction: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var last_direction: Vector3 = Vector3.FORWARD
#endregion

#region Node References
@onready var camera_rig: Node3D = $CameraRig
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
# TODO: Add UI references when you create the 3D UI
# @onready var health_bar = $HealthBar3D
# @onready var mana_bar = $ManaBar3D
# @onready var name_label = $NameLabel3D
#endregion

#region Initialization
func _ready() -> void:
	add_to_group("player")  # Important for monsters to find player!

	# Initial UI setup (if UI nodes exist)
	# if health_bar:
	#	 health_bar.max_value = max_health
	#	 health_bar.value = current_health
	# if name_label:
	#	 name_label.text = player_name

	load_faction_standing()
	load_spells()

	print("[Player3D] ✅ Player initialized: %s (HP: %d/%d)" % [player_name, current_health, max_health])
#endregion

#region Physics Process
func _physics_process(delta: float) -> void:
	if dying:
		return

	# Handle stumble
	if stumble_timer > 0.0:
		stumble_timer -= delta
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		is_in_air = true
	else:
		if is_in_air and velocity.y < -10.0:
			stumble_timer = STUMBLE_DURATION
		is_in_air = false

	# Handle input
	handle_toggle_run()
	handle_crouch()
	handle_jump()
	handle_movement(delta)
	handle_combat()

	# Update stamina
	update_stamina(delta)

	# Apply movement
	move_and_slide()
#endregion

#region Process (for regen)
func _process(delta: float) -> void:
	# Health and mana regeneration (from 2D player)
	regen_timer += delta
	if regen_timer >= regen_interval:
		regen_timer = 0.0

		if current_health < max_health:
			current_health = min(current_health + health_regen_rate, max_health)
			# if health_bar: health_bar.value = current_health

		if current_mana < max_mana:
			current_mana = min(current_mana + mana_regen_rate, max_mana)
			# if mana_bar: mana_bar.value = current_mana

	# Update attack cooldown
	if attack_cooldown > 0.0:
		attack_cooldown -= delta
#endregion

#region Movement Handlers
func handle_toggle_run() -> void:
	if Input.is_action_just_pressed("toggle_run"):
		is_running = not is_running

func handle_crouch() -> void:
	if Input.is_action_pressed("crouch"):
		if not is_crouching:
			is_crouching = true
			# TODO: Adjust collision capsule height
	else:
		if is_crouching:
			is_crouching = false
			# TODO: Restore collision capsule height

func handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if current_stamina <= 0.0:
			return

		var stamina_cost = STAMINA_DRAIN_JUMP
		current_stamina -= stamina_cost
		velocity.y = JUMP_VELOCITY

func handle_movement(delta: float) -> void:
	# Get input direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()

	if direction.length() > 0.1:
		last_direction = direction  # Save for combat targeting

	# Determine speed
	var target_speed: float
	if is_crouching:
		target_speed = CROUCH_SPEED
	elif is_running and current_stamina > 0:
		target_speed = RUN_SPEED
	else:
		target_speed = WALK_SPEED

	# Apply backward penalty
	if input_dir.y > 0:  # Moving backward
		target_speed *= BACKWARD_SPEED_MULT

	# Apply air control
	if not is_on_floor():
		target_speed *= AIR_CONTROL_MULT

	# Set velocity
	if direction != Vector3.ZERO:
		velocity.x = direction.x * target_speed
		velocity.z = direction.z * target_speed

		# Rotate to face movement direction
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, TURN_SPEED * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, target_speed)
		velocity.z = move_toward(velocity.z, 0, target_speed)

	current_speed = Vector2(velocity.x, velocity.z).length()

func update_stamina(delta: float) -> void:
	var is_moving = current_speed > 0.1

	# Drain stamina when running
	if is_moving and is_running and is_on_floor():
		current_stamina -= STAMINA_DRAIN_RUN * delta

	# Regenerate stamina
	if not is_running or not is_moving:
		var regen_rate = STAMINA_REGEN_STAND if not is_moving else STAMINA_REGEN_WALK
		current_stamina += regen_rate * delta

	current_stamina = clamp(current_stamina, 0.0, MAX_STAMINA)
#endregion

#region Combat System (adapted from 2D)
func handle_combat() -> void:
	# Basic melee attack (left click)
	if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
		perform_melee_attack()

	# TODO: Add spell casting on number keys
	# if Input.is_action_just_pressed("spell_1"):
	#	 cast_spell(0)

func perform_melee_attack() -> void:
	if attacking or dying:
		return

	attacking = true
	attack_cooldown = attack_cooldown_duration

	# Find nearest monster in melee range
	var attack_range = 3.0
	var monsters = get_tree().get_nodes_in_group("monsters")
	var closest_monster: Monster = null
	var closest_distance = attack_range

	for monster in monsters:
		if not monster is Monster:
			continue
		var distance = global_position.distance_to(monster.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_monster = monster

	if closest_monster:
		# Calculate damage (basic formula)
		var base_damage = 10  # TODO: Get from equipped weapon
		var str_bonus = stats.get("strength", 10) / 2  # Str modifier
		var total_damage = int(base_damage + str_bonus)

		closest_monster.apply_damage(total_damage, "physical")
		print("⚔️ Player attacks %s for %d damage!" % [closest_monster.get_monster_name(), total_damage])
	else:
		print("⚔️ Swing and a miss!")

	# TODO: Play attack animation
	await get_tree().create_timer(0.3).timeout
	attacking = false

# Called by monsters when they attack player
func take_damage(amount: int) -> void:
	if dying:
		return

	# Apply armor class reduction
	var damage_reduction = armor_class / 2.0
	var modified_damage = max(1, amount - int(damage_reduction))

	current_health = max(current_health - modified_damage, 0)
	# if health_bar: health_bar.value = current_health

	print("💔 Player took %d damage (AC reduced by %d). Current health: %d/%d" %
		[modified_damage, int(damage_reduction), current_health, max_health])

	if current_health <= 0:
		die()

func die() -> void:
	dying = true
	print("💀 Player defeated!")
	# TODO: Play death animation
	# TODO: Show game over screen
	# TODO: Respawn or reload
#endregion

#region Character Data Loading (from 2D player)
func load_character_data(data: Dictionary) -> void:
	print("DEBUG: Player3D: load_character_data called")
	if typeof(data) != TYPE_DICTIONARY:
		push_error("❌ Invalid character data type")
		return

	player_name = data.get("player_name", "Unnamed Player")
	stats = data.get("stats", {})
	var derived_data = data.get("derived", {})

	# Initialize resistances and equipment
	data["resistances"] = data.get("resistances", {
		"acid": 0, "cold": 0, "fire": 0, "magic": 0, "psychic": 0
	})
	data["equipment"] = data.get("equipment", {})

	if derived_data.has("health"):
		max_health = derived_data["health"]
		current_health = data.get("current_health", max_health)

	if derived_data.has("mana"):
		max_mana = derived_data["mana"]
		current_mana = data.get("current_mana", max_mana)

	apply_racial_modifiers(data.get("player_race", ""))

	var selected_class: String = data.get("player_class", "UNKNOWN").to_lower()
	var is_caster: bool = caster_classes.has(selected_class)

	# if mana_bar: mana_bar.visible = is_caster

	# if name_label: name_label.text = player_name

	print("✅ Loaded stats for %s (Class: %s, HP: %d, Mana: %d)" %
		[player_name, selected_class, max_health, max_mana])

func apply_racial_modifiers(race_name: String) -> void:
	# TODO: Copy racial modifier logic from 2D player if needed
	pass

func load_spells() -> void:
	var file: FileAccess = FileAccess.open("res://Data/player_spells.json", FileAccess.READ)
	if file:
		var content: String = file.get_as_text()
		var data: Variant = JSON.parse_string(content)
		file.close()
		if typeof(data) == TYPE_ARRAY:
			spells = data
			print("✅ Loaded %d spells from player_spells.json" % spells.size())
		else:
			push_error("❌ Failed to parse player_spells.json")
	else:
		push_error("❌ Failed to open player_spells.json")

func load_faction_standing() -> void:
	var file: FileAccess = FileAccess.open("res://Data/player_faction.json", FileAccess.READ)
	if file:
		var json_data: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(json_data) == TYPE_DICTIONARY and json_data.has("factions"):
			for faction in json_data["factions"]:
				if faction.has("name") and faction.has("standing"):
					faction_standing[faction["name"]] = faction["standing"]
			print("✅ Loaded faction standing")
	else:
		print("⚠️ player_faction.json not found (optional)")

func get_faction_standing(faction_name: String) -> int:
	return faction_standing.get(faction_name, 0)
#endregion

#region Helper Functions
func get_last_direction() -> Vector3:
	return last_direction
#endregion
