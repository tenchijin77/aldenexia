## monster3d.gd - 3D version
## Base class for all 3D enemies in Aldenexia: Lightfall
## Based on 2D Mob pattern, updated to match your exact JSON structure
class_name Monster
extends CharacterBody3D

# ===== EXPORTED STATS (loaded from JSON, can be overridden in editor) =====
@export_group("Stats")
@export var behavior_type := "default"
@export var speed: float = 30.0
@export var max_health: int = 100
@export var damage: int = 15
@export var armor_class: int = 10
@export var level: int = 1
@export var attack_range: float = 2.0
@export var aggro_range: float = 150.0  # Your JSON uses this instead of detection_range

@export_group("Loot & XP")
@export var category: String = "animal"  # undead, animal, humanoid, insect, elemental, reptile
@export var faction: String = "None"
@export var zone: String = "lumora_outskirts"
@export var xp_gain: int = 10
@export var coin_modifier: float = 0.0
@export var is_social: bool = false

@export_group("Animations")
@export var anim_idle: String = ""
@export var anim_walk: String = ""
@export var anim_attack: String = ""

# ===== STATE =====
enum State { IDLE, PATROL, CHASE, ATTACK, DEAD }
var current_state: State = State.IDLE
var current_health: int
var can_attack: bool = true
var attack_timer: float = 0.0
var attack_cooldown: float = 1.5

# ===== REFERENCES =====
var player: CharacterBody3D = null
var spawn_position: Vector3
var patrol_target: Vector3
var move_direction: Vector3 = Vector3.ZERO

# ===== NAVIGATION =====
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# ===== INITIALIZATION =====
func _ready() -> void:
	add_to_group("monsters")

	# Collision layers
	collision_layer = 1 << 3  # Enemy layer (layer 4)
	collision_mask = 1 << 0   # Default mask (layer 1)

	# Load stats from JSON
	var monster_name = get_monster_name()
	var stats = load_monster_stats(monster_name)

	if typeof(stats) == TYPE_DICTIONARY:
		# Core stats
		max_health = stats.get("health", max_health)
		speed = stats.get("speed", speed)
		damage = stats.get("damage", damage)
		armor_class = stats.get("armor_class", armor_class)
		level = stats.get("level", level)
		aggro_range = stats.get("aggro_range", aggro_range)
		behavior_type = stats.get("behavior_type", behavior_type)

		# Loot & XP
		category = stats.get("category", category)
		faction = stats.get("faction", faction)
		zone = stats.get("zone", zone)
		xp_gain = stats.get("xp_gain", xp_gain)
		coin_modifier = stats.get("coin_modifier", coin_modifier)
		is_social = stats.get("is_social", is_social)

		# Animations
		var anims = stats.get("animations", {})
		if typeof(anims) == TYPE_DICTIONARY:
			anim_idle = anims.get("idle", "")
			anim_walk = anims.get("walk", "")
			anim_attack = anims.get("attack", "")

	current_health = max_health
	spawn_position = global_position
	patrol_target = spawn_position

	# Configure NavigationAgent
	if is_inside_tree() and nav_agent:
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = 0.5
		nav_agent.max_speed = speed

	change_state(State.IDLE)

	print("✅ %s (Lv%d) loaded | HP:%d | SPD:%.1f | DMG:%d | AC:%d | Faction:%s | Category:%s" %
		[monster_name, level, max_health, speed, damage, armor_class, faction, category])

# ===== LOAD STATS FROM JSON =====
func load_monster_stats(monster_name: String) -> Dictionary:
	var path = "res://Data/monsters.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var content := file.get_as_text()
		var result: Dictionary = JSON.parse_string(content) as Dictionary
		if result.has(monster_name):
			return result[monster_name]
	return {}

# ===== OVERRIDE IN CHILD CLASSES =====
func get_monster_name() -> String:
	return "monster"

# ===== PHYSICS PROCESS =====
func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	# Update attack cooldown
	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0.0:
			can_attack = true

	# Find player
	if player == null:
		player = get_tree().get_first_node_in_group("player")

	# State machine
	match current_state:
		State.IDLE:
			state_idle(delta)
		State.PATROL:
			state_patrol(delta)
		State.CHASE:
			state_chase(delta)
		State.ATTACK:
			state_attack(delta)

	# Apply movement
	if current_state in [State.PATROL, State.CHASE]:
		handle_movement(delta)

# ===== STATE MACHINE =====
func state_idle(delta: float) -> void:
	# Check aggro range (using your JSON field)
	if player and can_see_player():
		change_state(State.CHASE)
		return

	# Randomly patrol based on behavior
	if behavior_type != "passive" and randf() < 0.01:
		change_state(State.PATROL)

func state_patrol(delta: float) -> void:
	if player and can_see_player():
		change_state(State.CHASE)
		return

	if global_position.distance_to(patrol_target) < 1.0:
		pick_new_patrol_point()

	if is_inside_tree() and nav_agent:
		nav_agent.target_position = patrol_target

func state_chase(delta: float) -> void:
	if not player:
		change_state(State.IDLE)
		return

	var distance: float = global_position.distance_to(player.global_position)

	# Lost aggro
	if distance > aggro_range:
		change_state(State.PATROL)
		return

	# In melee range
	if distance <= attack_range:
		change_state(State.ATTACK)
		return

	if is_inside_tree() and nav_agent:
		nav_agent.target_position = player.global_position

func state_attack(delta: float) -> void:
	if not player:
		change_state(State.IDLE)
		return

	var distance: float = global_position.distance_to(player.global_position)

	# Player escaped
	if distance > attack_range + 1.0:
		change_state(State.CHASE)
		return

	look_at_target(player.global_position)

	if can_attack:
		perform_attack()

# ===== MOVEMENT =====
func handle_movement(delta: float) -> void:
	if not is_inside_tree() or not nav_agent:
		return

	if nav_agent.is_navigation_finished():
		return

	var next_position: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = (next_position - global_position).normalized()
	direction.y = 0

	if direction.length() > 0.01:
		look_at_target(global_position + direction)

	# Convert 2D speed to 3D (your JSON uses 2D speeds like 30.0)
	var speed_3d = speed / 10.0  # Scale down for 3D

	velocity.x = direction.x * speed_3d
	velocity.z = direction.z * speed_3d

	# Gravity
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	move_and_slide()

# ===== COMBAT =====
func perform_attack() -> void:
	can_attack = false
	attack_timer = attack_cooldown

	if player and player.has_method("take_damage"):
		player.take_damage(damage)
		print("%s attacks player for %d damage!" % [get_monster_name(), damage])

	# Call for help if social
	if is_social:
		call_nearby_allies()

# Same pattern as 2D apply_damage
func apply_damage(amount: int, damage_type: String = "physical") -> void:
	if current_state == State.DEAD:
		return

	# Apply armor class reduction (basic formula)
	var damage_reduction = armor_class / 2.0
	var modified_damage = max(1, amount - int(damage_reduction))

	# Child class can modify further
	modified_damage = modify_damage(modified_damage, damage_type)

	current_health = max(current_health - modified_damage, 0)
	print("DEBUG: %s hit for %d damage (AC reduced by %d), health now: %d" %
		[get_monster_name(), modified_damage, int(damage_reduction), current_health])

	# TODO: Update health bar

	# Call for help if social
	if is_social and current_health > 0:
		call_nearby_allies()

	if current_health <= 0:
		die()

# Override in child classes for resistances/weaknesses
func modify_damage(amount: int, damage_type: String) -> int:
	return amount

# Social monsters call nearby allies
func call_nearby_allies() -> void:
	if not is_social:
		return

	var monsters = get_tree().get_nodes_in_group("monsters")
	for monster in monsters:
		if monster == self or not monster is Monster:
			continue

		var ally = monster as Monster
		# Only same faction helps
		if ally.faction != faction or ally.faction == "None":
			continue

		var distance = global_position.distance_to(ally.global_position)
		if distance < aggro_range:
			if ally.current_state == State.IDLE or ally.current_state == State.PATROL:
				ally.change_state(State.CHASE)
				print("🆘 %s calls for help! %s responds!" % [get_monster_name(), ally.get_monster_name()])

func die() -> void:
	change_state(State.DEAD)
	print("💀 %s died! (XP: %d, Coins: %.2f, Category: %s)" % [get_monster_name(), xp_gain, coin_modifier, category])

	# TODO: Award XP to player
	# TODO: Drop loot using category + zone (lumora_outskirts.json)
	# TODO: Drop coins using coin_modifier
	# TODO: AnimationPlayer death animation

	await get_tree().create_timer(2.0).timeout
	queue_free()

# ===== HELPERS =====
func change_state(new_state: State) -> void:
	if current_state == new_state:
		return

	current_state = new_state

	match new_state:
		State.PATROL:
			pick_new_patrol_point()
		State.ATTACK:
			velocity = Vector3.ZERO

func can_see_player() -> bool:
	if not player:
		return false

	var distance = global_position.distance_to(player.global_position)

	# Use aggro_range from JSON
	match behavior_type:
		"passive":
			# Passive mobs only aggro if attacked (aggro_range is smaller)
			return distance <= (aggro_range / 3.0)
		"neutral":
			# Neutral mobs only aggro if very close
			return distance <= (aggro_range / 2.0)
		_:  # aggressive, skitter, etc.
			return distance <= aggro_range

func pick_new_patrol_point() -> void:
	var random_angle: float = randf() * TAU
	var random_distance: float = randf() * 10.0
	patrol_target = spawn_position + Vector3(
		cos(random_angle) * random_distance,
		0,
		sin(random_angle) * random_distance
	)

func look_at_target(target_pos: Vector3) -> void:
	var look_pos: Vector3 = target_pos
	look_pos.y = global_position.y
	look_at(look_pos, Vector3.UP)
