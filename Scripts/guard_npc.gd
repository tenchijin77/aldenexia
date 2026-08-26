# guard_npc.gd — Stationary guard NPC. Responds to a nearby player's "hail"
# (H key or /hail command, handled by player3d.gd:try_hail_nearby_npc()) with
# a random flavor line, and actively engages any monster that wanders within
# 4m of its post. Kills are quiet — no loot, no corpse, immediately removed
# (Monster.die(false, false)) — this is one-directional: monsters have no
# concept of attacking anything but the player (monster3d.gd hardcodes that
# target everywhere), so they won't fight back against a guard.
extends CharacterBody3D
class_name GuardNPC

const ENGAGE_RANGE := 4.0   # how far from home_position a guard will notice a monster
const LEASH_RANGE  := 6.0   # disengage if the target gets this far from home_position
const ATTACK_RANGE := 2.5
const SCAN_INTERVAL := 1.0
const GRAVITY := 20.0

enum GuardState { IDLE, ENGAGE }

@export var npc_name: String = "Lumora Guard"
@export var npc_faction: String = "Wardens of the Sacred Flame"

@onready var name_label: Label3D = $NameLabel
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var _flavor_lines: Array = []

var combat_node: CombatNode
var level: int = 8  # mirrors combat_node.level; exposed at the top level like monster3d.gd's `level`
var home_position: Vector3 = Vector3.ZERO
var state: GuardState = GuardState.IDLE
var attack_target: Node = null
var move_speed: float = 3.0

var can_attack: bool = true
var attack_timer: float = 0.0
var attack_cooldown: float = 1.5

var _scan_timer: float = 0.0


func _ready() -> void:
	add_to_group("npc_guard")
	if name_label:
		name_label.text = npc_name
	_flavor_lines = _load_flavor_lines()
	home_position = global_position
	_setup_combat()


func _load_flavor_lines() -> Array:
	var file := FileAccess.open("res://Data/guard_flavor_text.json", FileAccess.READ)
	if not file:
		return []
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	return data if typeof(data) == TYPE_ARRAY else []


func respond_to_hail() -> void:
	if _flavor_lines.is_empty():
		return
	var line: String = _flavor_lines[randi() % _flavor_lines.size()]
	GameLog.log_general("[color=#cccc88]%s says, \"%s\"[/color]" % [npc_name, line])


# ── Combat setup ──────────────────────────────────────────────────────────────

func _setup_combat() -> void:
	var stats := _load_guard_stats()

	level = stats.get("level", 8)

	combat_node = CombatNode.new()
	add_child(combat_node)
	combat_node.level         = level
	combat_node.weapon_damage = stats.get("damage", 25)
	combat_node.strength      = 0
	combat_node.constitution  = 0
	combat_node.dexterity     = 0
	combat_node.intelligence  = 0
	combat_node.wisdom        = 0
	combat_node.charisma      = 0
	combat_node.luck          = 0

	var armor_class: int = stats.get("armor_class", 25)
	combat_node.gear_ac = armor_class - 10
	var max_hp: int = stats.get("health", 200)
	combat_node.gear_hp = max_hp - 50
	combat_node.gear_atk = 15 + combat_node.level * 5
	combat_node._stats_dirty = true
	combat_node.recalculate_derived_stats()
	combat_node.current_hp = combat_node.max_hp

	move_speed = stats.get("speed", 30.0) / 10.0
	if nav_agent:
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = 0.5
		nav_agent.max_speed = move_speed


func _load_guard_stats() -> Dictionary:
	var file := FileAccess.open("res://Data/monsters.json", FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(result) == TYPE_DICTIONARY and result.has("lumora_guard"):
			return result["lumora_guard"]
	return {}


# ── Engagement state machine ─────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0.0:
			can_attack = true

	match state:
		GuardState.IDLE:
			_scan_timer += delta
			if _scan_timer >= SCAN_INTERVAL:
				_scan_timer = 0.0
				_scan_for_targets()
			_apply_gravity(delta)
			velocity.x = 0.0
			velocity.z = 0.0
		GuardState.ENGAGE:
			_process_engage(delta)

	move_and_slide()


func _scan_for_targets() -> void:
	var nearest: Node = null
	var nearest_dist := ENGAGE_RANGE
	for monster in get_tree().get_nodes_in_group("monsters"):
		if monster.get("current_state") == monster.State.DEAD:
			continue
		var dist := home_position.distance_to(monster.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = monster
	if nearest:
		attack_target = nearest
		state = GuardState.ENGAGE


func _process_engage(delta: float) -> void:
	if not is_instance_valid(attack_target) or attack_target.get("current_state") == attack_target.State.DEAD:
		attack_target = null
		state = GuardState.IDLE
		return

	if home_position.distance_to(attack_target.global_position) > LEASH_RANGE:
		attack_target = null
		state = GuardState.IDLE
		return

	var distance := global_position.distance_to(attack_target.global_position)
	if distance > ATTACK_RANGE:
		_move_toward(attack_target.global_position, ATTACK_RANGE, delta)
		return

	_apply_gravity(delta)
	velocity.x = 0.0
	velocity.z = 0.0
	look_at(attack_target.global_position, Vector3.UP)

	if can_attack:
		_perform_attack()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


func _move_toward(target_pos: Vector3, stop_distance: float, delta: float) -> void:
	_apply_gravity(delta)

	if global_position.distance_to(target_pos) <= stop_distance:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	if not nav_agent:
		return

	nav_agent.target_position = target_pos
	if nav_agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var next_position: Vector3 = nav_agent.get_next_path_position()
	var to_next: Vector3 = next_position - global_position
	var flat_dir := Vector3(to_next.x, 0.0, to_next.z)
	if flat_dir.length() < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var direction := flat_dir.normalized()
	look_at(global_position + direction, Vector3.UP)
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed


func _perform_attack() -> void:
	can_attack = false
	attack_timer = attack_cooldown

	if not (attack_target.get("combat_node") is CombatNode):
		return

	var target_cn: CombatNode = attack_target.combat_node
	var result: Dictionary = combat_node.resolve_attack(target_cn)
	var target_desc: String = attack_target.get("monster_description")
	if target_desc == "":
		target_desc = attack_target.get_monster_name()

	match result.get("result", ""):
		"MISS":
			GameLog.log_combat("%s misses %s!" % [npc_name, target_desc])
		"PARRY":
			GameLog.log_combat("%s's attack is parried!" % npc_name)
		"BLOCK":
			GameLog.log_combat("%s's attack is blocked!" % npc_name)
		"DODGE":
			GameLog.log_combat("%s's attack is dodged!" % npc_name)
		"RIPOSTE":
			GameLog.log_combat("%s is riposted for [b]%d[/b] damage!" % [npc_name, result.get("damage", 0)])
		"HIT":
			var crit: String = " [color=#ffaa00]Critical![/color]" if result.get("is_crit", false) else ""
			GameLog.log_combat("%s hits %s for [b]%d[/b] damage!%s" % [npc_name, target_desc, result.get("damage", 0), crit])

	if not target_cn.is_alive():
		GameLog.log_combat("[color=#88ccff]%s dispatches %s.[/color]" % [npc_name, target_desc])
		if attack_target.has_method("die"):
			attack_target.die(false, false)
		attack_target = null
		state = GuardState.IDLE
