# player3d.gd - 3D player controller with RPG systems
extends CharacterBody3D
class_name Player3D

## Player 3D Controller with RPG Systems
## Combines movement (from original 3D) with health/mana/combat (from 2D)


#region Movement configuration
const WALK_SPEED: float = 5.0
const RUN_SPEED: float = 8.0
const CROUCH_SPEED: float = 2.5
const JUMP_VELOCITY: float = 6.0
const TURN_SPEED: float = PI

const BACKWARD_SPEED_MULT: float = 0.75
const AIR_CONTROL_MULT: float = 0.3
const STUMBLE_DURATION: float = 0.2
#endregion

#region Stamina system
const MAX_STAMINA: float = 100.0
const STAMINA_DRAIN_RUN: float = 10.0      # per second
const STAMINA_DRAIN_JUMP: float = 15.0     # per jump
const STAMINA_REGEN_STAND: float = 10.0    # per second (standing)
const STAMINA_REGEN_SIT: float = 20.0      # per second (sitting)

var max_stamina: float = MAX_STAMINA
var current_stamina: float = MAX_STAMINA
#endregion

#region RPG stats
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
var backpack_scene := preload("res://Scenes/backpack_ui.tscn")

var backpack_instance: Node = null
var caster_classes := [
	"voidknight", "gravecaller", "runecaster", "arcanist", "chaosborn",
	"lightsworn", "lightmender", "spiritcaller", "wildspeaker",
	"woodstalker", "aetherfist", "troubadour"
]
#endregion

#region Vitals system (hunger / thirst)
var satiety: int = 100  # Hunger (0 = starving, 100 = full)
var thirst: int = 100   # Thirst (0 = dehydrated, 100 = hydrated)

const SATIETY_DECAY_RATE: float = 1.0   # per minute
const THIRST_DECAY_RATE: float = 2.0    # per minute
const DECAY_INTERVAL: float = 60.0      # seconds

var satiety_timer: float = 0.0
var thirst_timer: float = 0.0
#endregion

#region Combat
var spells: Array = []
var dying: bool = false
var attacking: bool = false
var attack_cooldown: float = 0.0
var attack_cooldown_duration: float = 1.0
#endregion

#region Movement state
var is_running: bool = true
var is_crouching: bool = false
var is_in_air: bool = false
var stumble_timer: float = 0.0
var movement_direction: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var last_direction: Vector3 = Vector3.FORWARD
var is_sitting: bool = false
#endregion

#region Node references
@onready var camera_rig: Node3D = $CameraRig
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
# TODO: Add 3D UI references when created
# @onready var health_bar = $HealthBar3D
# @onready var mana_bar = $ManaBar3D
# @onready var name_label = $NameLabel3D
#endregion

#region Character sheet
var character_sheet_scene = preload("res://Scenes/character_sheet.tscn")
var character_sheet_instance: Node = null
#endregion

#region Initialization
func _ready() -> void:
	add_to_group("player")

	load_faction_standing()
	load_spells()
	load_player_data_from_global()

	print("[Player3D] ✅ Player initialized: %s (HP: %d/%d)" % [player_name, current_health, max_health])
#endregion

#region Physics process (movement / stamina / combat)
func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_backpack"):
		toggle_backpack()

	if dying:
		return

	# Handle stumble
	if stumble_timer > 0.0:
		stumble_timer -= delta
		return

	# Gravity and landing
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		is_in_air = true
	else:
		if is_in_air and velocity.y < -10.0:
			stumble_timer = STUMBLE_DURATION
		is_in_air = false

	# Input + movement only if not sitting
	if not is_sitting:
		handle_toggle_run()
		handle_crouch()
		handle_jump()
		handle_movement(delta)

	handle_combat()
	update_stamina(delta)

	move_and_slide()
#endregion

#region Process (regen / vitals decay / cooldowns)
func _process(delta: float) -> void:
	if dying:
		return

	# Health / mana regeneration
	regen_timer += delta
	if regen_timer >= regen_interval:
		regen_timer = 0.0

		if current_health < max_health:
			var regen_h := health_regen_rate
			if satiety < 25:
				regen_h *= 0.8
			current_health = min(current_health + regen_h, max_health)
			# if health_bar: health_bar.value = current_health

		if current_mana < max_mana:
			var regen_m := mana_regen_rate
			if thirst < 25:
				regen_m *= 0.8
			current_mana = min(current_mana + regen_m, max_mana)
			# if mana_bar: mana_bar.value = current_mana

	# Attack cooldown
	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	# Vitals decay
	update_vitals_decay(delta)
#endregion

#region Vitals decay system
func update_vitals_decay(delta: float) -> void:
	satiety_timer += delta
	thirst_timer += delta

	# Satiety decay
	if satiety_timer >= DECAY_INTERVAL:
		satiety_timer = 0.0
		satiety = max(satiety - int(SATIETY_DECAY_RATE), 0)

		if satiety <= 0:
			apply_starvation_damage()
		elif satiety < 25:
			print("🍖 Warning: Getting hungry! (%d/100)" % satiety)

	# Thirst decay
	if thirst_timer >= DECAY_INTERVAL:
		thirst_timer = 0.0
		thirst = max(thirst - int(THIRST_DECAY_RATE), 0)

		if thirst <= 0:
			apply_dehydration_damage()
		elif thirst < 25:
			print("💧 Warning: Getting thirsty! (%d/100)" % thirst)


func apply_starvation_damage() -> void:
	var damage: int = int(max_health * 0.01)
	current_health = max(current_health - damage, 1)
	print("💀 STARVING! Taking %d damage." % damage)


func apply_dehydration_damage() -> void:
	var damage: int = int(max_health * 0.02)
	current_health = max(current_health - damage, 1)
	print("💀 DEHYDRATED! Taking %d damage." % damage)


func get_stat_penalty() -> float:
	var penalty := 1.0
	if satiety < 25:
		penalty *= 0.95
	if thirst < 25:
		penalty *= 0.90
	return penalty
#endregion

#region Movement handlers
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

		current_stamina -= STAMINA_DRAIN_JUMP
		current_stamina = max(current_stamina, 0.0)
		velocity.y = JUMP_VELOCITY


func handle_movement(delta: float) -> void:
	# Sitting blocks movement
	if is_sitting:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED)
		current_speed = 0.0
		return

	# Turning (A/D)
	if Input.is_action_pressed("turn_left"):
		rotation.y -= TURN_SPEED * delta
	if Input.is_action_pressed("turn_right"):
		rotation.y += TURN_SPEED * delta

	# Strafing (Q/E)
	var strafe := 0.0
	if Input.is_action_pressed("strafe_left"):
		strafe -= 1.0
	if Input.is_action_pressed("strafe_right"):
		strafe += 1.0

	# Forward/back (W/S)
	var forward := 0.0
	if Input.is_action_pressed("move_forward"):
		forward += 1.0
	if Input.is_action_pressed("move_backward"):
		forward -= 1.0

	# Determine speed
	var target_speed: float
	if is_crouching:
		target_speed = CROUCH_SPEED
	elif is_running and current_stamina > 0.0:
		target_speed = RUN_SPEED
	else:
		target_speed = WALK_SPEED

	# Backward penalty
	if forward < 0.0:
		target_speed *= BACKWARD_SPEED_MULT

	# Air control
	if not is_on_floor():
		target_speed *= AIR_CONTROL_MULT

	# Build movement vector in local space
	var local_move := Vector3(strafe, 0, -forward).normalized()

	# Convert to world space
	var world_move := global_transform.basis * local_move

	velocity.x = world_move.x * target_speed
	velocity.z = world_move.z * target_speed

	current_speed = Vector2(velocity.x, velocity.z).length()



func update_stamina(delta: float) -> void:
	var is_moving := current_speed > 0.1

	# Sitting toggle
	if Input.is_action_just_pressed("sit"):
		is_sitting = not is_sitting
		if is_sitting:
			is_running = false
			is_crouching = false

	# Drain stamina when running
	if is_moving and is_running and is_on_floor():
		current_stamina -= STAMINA_DRAIN_RUN * delta

	# Regenerate stamina
	if not is_moving and not is_running and is_on_floor():
		var regen_rate := STAMINA_REGEN_STAND
		if is_sitting:
			regen_rate = STAMINA_REGEN_SIT
		current_stamina += regen_rate * delta

	current_stamina = clamp(current_stamina, 0.0, max_stamina)

	# If out of stamina, force walk
	if current_stamina <= 0.0:
		is_running = false
#endregion

#region Combat system
func handle_combat() -> void:
	if Input.is_action_just_pressed("melee_attack") and attack_cooldown <= 0.0:
		perform_melee_attack()

	if Input.is_action_just_pressed("toggle_character_sheet"):
		toggle_character_sheet()
	# TODO: Spell casting hooks
	# if Input.is_action_just_pressed("spell_1"):
	#     cast_spell(0)


func perform_melee_attack() -> void:
	if attacking or dying:
		return

	attacking = true
	attack_cooldown = attack_cooldown_duration

	var attack_range := 3.0
	var monsters := get_tree().get_nodes_in_group("monsters")
	var closest_monster: Node = null
	var closest_distance := attack_range

	for monster in monsters:
		if not is_instance_valid(monster):
			continue
		var distance := global_position.distance_to(monster.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_monster = monster

	if closest_monster:
		var base_damage := 10
		var str_bonus: float = float(stats.get("strength", 10)) / 2.0
		var penalty := get_stat_penalty()
		var total_damage := int((base_damage + str_bonus) * penalty)

		if closest_monster.has_method("apply_damage"):
			closest_monster.apply_damage(total_damage, "physical")
			print("⚔️ Player attacks for %d damage!" % total_damage)
		else:
			print("⚔️ Swing and a miss!")
	else:
		print("⚔️ No target in range.")

	await get_tree().create_timer(0.3).timeout
	attacking = false


func take_damage(amount: int) -> void:
	if dying:
		return

	var damage_reduction := armor_class / 2.0
	var modified_damage: int = max(1, amount - int(damage_reduction))

	current_health = max(current_health - modified_damage, 0)
	# if health_bar: health_bar.value = current_health

	print("💔 Player took %d damage (AC reduced by %d). Current health: %d/%d" %
		[modified_damage, int(damage_reduction), current_health, max_health])

	if current_health <= 0:
		die()


func die() -> void:
	dying = true
	print("💀 Player defeated!")
	# TODO: Death animation / game over / respawn
#endregion

#region Character sheet management
func toggle_character_sheet() -> void:
	if character_sheet_instance:
		character_sheet_instance.queue_free()
		character_sheet_instance = null
		print("📋 Character sheet closed")
	else:
		character_sheet_instance = character_sheet_scene.instantiate()
		get_tree().root.add_child(character_sheet_instance)

		if character_sheet_instance.has_method("set_character_data"):
			var current_data := {
				"player_name": player_name,
				"player_class": Global.player_data.get("player_class", "Unknown"),
				"player_level": Global.player_data.get("player_level", 1),
				"xp": Global.player_data.get("xp", 0),
				"xp_next_level": Global.player_data.get("xp_next_level", 100),
				"current_health": current_health,
				"current_mana": current_mana,
				"current_stamina": current_stamina,
				"max_stamina": max_stamina,
				"satiety": satiety,
				"thirst": thirst,
				"stats": stats,
				"derived": Global.player_data.get("derived", {}),
				"resistances": Global.player_data.get("resistances", {}),
				"equipment": Global.player_data.get("equipment", {}),
				"character_creation": Global.player_data.get("character_creation", {}),
				"playtime_seconds": Global.get_total_playtime()
			}
			character_sheet_instance.set_character_data(current_data)

		print("📋 Character sheet opened")
#endregion

#region Character data loading
func load_player_data_from_global() -> void:
	if Global.player_data.is_empty():
		push_error("❌ No player data found in Global!")
		return

	load_character_data(Global.player_data)

	satiety = Global.player_data.get("satiety", 100)
	thirst = Global.player_data.get("thirst", 100)
	current_stamina = Global.player_data.get("current_stamina", MAX_STAMINA)
	max_stamina = Global.player_data.get("max_stamina", MAX_STAMINA)


func load_character_data(data: Dictionary) -> void:
	print("DEBUG: Player3D: load_character_data called")
	if typeof(data) != TYPE_DICTIONARY:
		push_error("❌ Invalid character data type")
		return

	player_name = data.get("player_name", "Unnamed Player")
	stats = data.get("stats", {})
	var derived_data: Dictionary = data.get("derived", {})

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
#endregion

#region Spells and faction
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

#region Helper functions
func get_last_direction() -> Vector3:
	return last_direction
#endregion

func toggle_backpack() -> void:
	if backpack_instance:
		backpack_instance.queue_free()
		backpack_instance = null
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		print("🎒 Backpack closed")
	else:
		backpack_instance = backpack_scene.instantiate()
		get_tree().root.add_child(backpack_instance)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		print("🎒 Backpack opened")
