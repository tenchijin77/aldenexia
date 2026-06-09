## monster3d.gd - 3D version
## Base class for all 3D enemies in Aldenexia: Lightfall
## Based on 2D Mob pattern, updated to match your exact JSON structure
class_name Monster
extends CharacterBody3D

# ===== EXPORTED STATS (loaded from JSON, can be overridden in editor) =====
@export_group("Stats")
@export var monster_name: String = ""  # Set this in the editor to load from monsters.json
@export var behavior_type := "default"
@export var speed: float = 30.0
@export var max_health: int = 100
@export var damage: int = 15
@export var armor_class: int = 10
@export var level: int = 1
@export var attack_range: float = 2.0
@export var aggro_range: float = 150.0  # Raw JSON value (2D-era units); scaled to 3D meters at runtime
const AGGRO_RANGE_SCALE: float = 10.0   # Matches speed scale (speed/10 = m/s)
const MAX_AGGRO_DISTANCE: float = 5.0   # Hard cap: monsters never aggro beyond this many meters

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
var can_attack: bool = true
var combat_node: CombatNode

# Kept for backward compat — always mirrors combat_node.current_hp
var monster_description: String = ""
var current_health: int:
	get: return combat_node.current_hp if combat_node else 0
var attack_timer: float = 0.0
var attack_cooldown: float = 1.5
var is_lootable: bool = false
var pending_loot: Array = []
var loot_window: Node = null

# ===== CURRENCY =====
const CURRENCY_MAP: Dictionary = {
	"copper_coin":   "copper",
	"silver_coin":   "silver",
	"gold_coin":     "gold",
	"platinum_coin": "platinum"
}

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

	# Load stats from JSON — use exported name if set, else fall back to subclass override
	if monster_name.is_empty():
		monster_name = get_monster_name()
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
		monster_description = stats.get("description", monster_name)

		# Animations
		var anims = stats.get("animations", {})
		if typeof(anims) == TYPE_DICTIONARY:
			anim_idle = anims.get("idle", "")
			anim_walk = anims.get("walk", "")
			anim_attack = anims.get("attack", "")

	combat_node = CombatNode.new()
	add_child(combat_node)
	_configure_combat_node()

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
func load_monster_stats(p_monster_name: String) -> Dictionary:
	var path = "res://Data/monsters.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(result) == TYPE_DICTIONARY and result.has(p_monster_name):
			return result[p_monster_name]
	return {}

# ===== COMBAT NODE SETUP =====
func _configure_combat_node() -> void:
	combat_node.level = level
	combat_node.weapon_damage = damage

	# Zero base stats so gear values fully control AC, ATK, and HP.
	combat_node.strength     = 0
	combat_node.constitution = 0
	combat_node.dexterity    = 0
	combat_node.intelligence = 0
	combat_node.wisdom       = 0
	combat_node.charisma     = 0
	combat_node.luck         = 0

	# get_ac() = 10 + gear_ac + dex/2 → with dex=0: gear_ac = armor_class - 10
	combat_node.gear_ac = armor_class - 10

	# max_hp = 50 + con*10 + gear_hp → with con=0: gear_hp = max_health - 50
	combat_node.gear_hp = max_health - 50

	# ATK scaled by level for reasonable hit rates vs the player.
	# hit_chance = (atk - target_ac) + level_modifier + rand(0-20), clamped 5-95
	combat_node.gear_atk = 15 + level * 5

	combat_node._stats_dirty = true
	combat_node.recalculate_derived_stats()
	combat_node.current_hp = combat_node.max_hp

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

	# Find player safely
	if not is_instance_valid(player):
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
		else:
			return


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

	# Movement and gravity
	if current_state in [State.PATROL, State.CHASE]:
		handle_movement(delta)
	else:
		# Always apply gravity so monsters don't float when idle or attacking
		if not is_on_floor():
			velocity.y -= 20.0 * delta
		move_and_slide()

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

	# Lost aggro — leash uses the same effective range so monsters don't chase forever
	var leash_range: float = minf(aggro_range / AGGRO_RANGE_SCALE, MAX_AGGRO_DISTANCE)
	if distance > leash_range:
		change_state(State.PATROL)
		return

	# In melee range
	if distance <= attack_range:
		change_state(State.ATTACK)
		return

	if is_inside_tree() and nav_agent:
		nav_agent.target_position = player.global_position
		print("CHASE: target =", nav_agent.target_position)

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
	var to_next: Vector3 = next_position - global_position
	var flat_dir: Vector3 = Vector3(to_next.x, 0, to_next.z)

	if flat_dir.length() < 0.1:
		return

	var direction: Vector3 = flat_dir.normalized()
	look_at_target(global_position + direction)

	var speed_3d = speed / 10.0
	velocity.x = direction.x * speed_3d
	velocity.z = direction.z * speed_3d

	if not is_on_floor():
		velocity.y -= 20.0 * delta

	move_and_slide()




# ===== COMBAT =====
func perform_attack() -> void:
	can_attack = false
	attack_timer = attack_cooldown

	if not player:
		return

	if "combat_node" in player and player.combat_node is CombatNode:
		var result = combat_node.resolve_attack(player.combat_node)
		# Sync our HP in case of riposte (resolve_attack modifies both sides directly)
		if not combat_node.is_alive():
			die()
			return
		if result["damage"] > 0:
			if player.has_method("apply_damage"):
				player.apply_damage(result["damage"])
			elif player.has_method("take_damage"):
				player.take_damage(result["damage"])
		var desc: String = monster_description if monster_description != "" else get_monster_name()
		var msg: String = CombatLogFormatter.monster_attack(result, desc, get_damage_type())
		if not msg.is_empty():
			GameLog.log_combat(msg)
	elif player.has_method("take_damage"):
		player.take_damage(damage)
		var desc: String = monster_description if monster_description != "" else get_monster_name()
		GameLog.log_combat("%s hits you for [b]%d[/b] damage!" % [desc.capitalize(), damage])

	if is_social:
		call_nearby_allies()

func apply_damage(amount: int, damage_type: String = "physical") -> void:
	if current_state == State.DEAD:
		return

	# Allow child classes to apply resistances/weaknesses before CombatNode takes over
	var modified_damage = modify_damage(amount, damage_type)
	combat_node.take_damage(modified_damage)

	print("DEBUG: %s hit for %d, HP: %d/%d" %
		[get_monster_name(), modified_damage, combat_node.current_hp, combat_node.max_hp])

	if is_social and combat_node.is_alive():
		call_nearby_allies()

	if not combat_node.is_alive():
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
			if (ally.current_state == State.IDLE or ally.current_state == State.PATROL) \
				and ally.combat_node.is_alive():
				ally.change_state(State.CHASE)
				print("🆘 %s calls for help! %s responds!" % [get_monster_name(), ally.get_monster_name()])

func get_damage_type() -> String:
	match category:
		"humanoid": return "slashing"
		"animal":   return "blunt"
		"insect":   return "piercing"
		"reptile":  return "piercing"
		"undead":   return "blunt"
		_:          return "generic"

func die() -> void:
	change_state(State.DEAD)
	print("💀 %s died! (XP: %d, Coins: %.2f, Category: %s)" % [monster_name, xp_gain, coin_modifier, category])

	pending_loot = roll_loot()
	is_lootable = not pending_loot.is_empty()
	if is_lootable:
		print("  → Right-click corpse to loot")

	# Award XP to player
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var p := players[0]
		var cur_xp: int    = Global.player_data.get("xp", 0)
		var xp_next: int   = Global.player_data.get("xp_next_level", 100)
		var new_xp: int    = cur_xp + xp_gain
		Global.player_data["xp"] = new_xp
		GameLog.log_general("You gain [b]%d[/b] experience points. (%d / %d)" % [xp_gain, new_xp, xp_next])

		# Level-up loop (handles multiple level-ups from one kill)
		while Global.player_data.get("xp", 0) >= Global.player_data.get("xp_next_level", 999999):
			var cur_lvl: int = Global.player_data.get("player_level", 1)
			if cur_lvl >= Global.xp_table.get("max_level", 20):
				break
			var new_lvl: int   = cur_lvl + 1
			var next_thresh: int = int(Global.xp_table.get(str(new_lvl + 1), 0))
			Global.player_data["player_level"]   = new_lvl
			Global.player_data["xp_next_level"]  = next_thresh if next_thresh > 0 else 999999
			GameLog.log_general("[color=#ffdd44][b]You have reached level %d![/b][/color]" % new_lvl)
			if p.has_method("on_level_up"):
				p.on_level_up(new_lvl)

		Global.save_player_data_to_file()

	# TODO: AnimationPlayer death animation

	await get_tree().create_timer(60.0).timeout
	if not is_inside_tree():
		return  # already despawned via _on_fully_looted
	is_lootable = false
	if is_instance_valid(loot_window):
		loot_window.queue_free()
	queue_free()

func open_loot_window() -> void:
	if is_instance_valid(loot_window):
		return
	loot_window = load("res://Scenes/corpse_loot_window.tscn").instantiate()
	get_tree().root.add_child(loot_window)
	loot_window.setup(monster_name.capitalize(), pending_loot)
	loot_window.all_looted.connect(_on_fully_looted)


func _on_fully_looted() -> void:
	is_lootable = false
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(loot_window):
		loot_window.queue_free()
	queue_free()

# ===== LOOT =====
func roll_loot() -> Array:
	var loot_data := _load_loot_data()
	if loot_data.is_empty():
		return []

	var drops: Array = []

	# Roll once against the shared category table (e.g. all "undead")
	var cat_table: Array = loot_data.get("category_loot_tables", {}).get(category, [])
	drops.append_array(_roll_table(cat_table))

	# Roll once against the specific monster's table
	var mob_table: Array = _find_mob_loot(monster_name, loot_data)
	drops.append_array(_roll_table(mob_table))

	# Apply coin_modifier as a percentage bonus on all currency drops
	for drop in drops:
		if CURRENCY_MAP.has(drop["item"]):
			drop["quantity"] = int(drop["quantity"] * (1.0 + coin_modifier))

	return drops

func _load_loot_data() -> Dictionary:
	var file := FileAccess.open("res://Data/solgrave_expanse_loot.json", FileAccess.READ)
	if not file:
		push_error("❌ solgrave_expanse_loot.json not found")
		return {}
	var result = JSON.parse_string(file.get_as_text())
	return result if typeof(result) == TYPE_DICTIONARY else {}

func _find_mob_loot(mob_name: String, loot_data: Dictionary) -> Array:
	# Search all zones for the mob name — zone field on monster may not match loot file zones
	for zone in loot_data.get("zone_loot_tables", {}).values():
		if zone.has(mob_name):
			return zone[mob_name]
	return []

func _roll_table(table: Array) -> Array:
	var results: Array = []
	for entry in table:
		if randf() < entry.get("chance", 0.0):
			var qty: int = randi_range(entry.get("min", 1), entry.get("max", 1))
			results.append({"item": entry["item"], "quantity": qty})
	return results


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

	var distance: float = global_position.distance_to(player.global_position)
	var effective_range: float = minf(aggro_range / AGGRO_RANGE_SCALE, MAX_AGGRO_DISTANCE)

	match behavior_type:
		"passive":
			return distance <= (effective_range / 3.0)
		"neutral":
			return distance <= (effective_range / 2.0)
		_:  # aggressive, skitter, etc.
			return distance <= effective_range

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
	if global_position.distance_squared_to(look_pos) > 0.0001:
		look_at(look_pos, Vector3.UP)
