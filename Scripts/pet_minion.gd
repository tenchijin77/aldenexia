# pet_minion.gd — Player-summoned pet (Voidknight's Morthan's Call skeleton warrior).
# Deliberately NOT a Monster subclass: monster3d.gd's state machine is
# hardcoded to chase/attack "the player" (get_tree().get_nodes_in_group("player")[0]),
# so reusing it here would fight that assumption at every turn. This is a small,
# independent actor instead, reusing the same CombatNode/NavigationAgent3D pattern.
extends CharacterBody3D
class_name PetMinion

enum PetState { FOLLOW, ATTACK, STOP, SIT, GUARD }

const FOLLOW_DISTANCE := 3.0
const ATTACK_RANGE := 2.5
const GUARD_SCAN_RADIUS := 8.0
const GUARD_SCAN_INTERVAL := 1.0
const SIT_REGEN_INTERVAL := 6.0
const GRAVITY := 20.0

var owner_player: Node = null
var command: PetState = PetState.FOLLOW
var attack_target: Node = null
var guard_position: Vector3 = Vector3.ZERO

# Command that ATTACK reverts to once its target dies or becomes invalid —
# lets "Guard" auto-engagements return to holding position instead of following.
var _pre_attack_command: PetState = PetState.FOLLOW

var combat_node: CombatNode
var pet_name: String = "Skeleton Warrior"
var move_speed: float = 3.0

var can_attack: bool = true
var attack_timer: float = 0.0
var attack_cooldown: float = 2.0

var _guard_scan_timer: float = 0.0
var _sit_regen_timer: float = 0.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D


func setup(p_owner: Node) -> void:
	owner_player = p_owner
	global_position = p_owner.global_position + p_owner.global_transform.basis.x * 1.5
	guard_position = global_position

	var stats := _load_skeleton_stats()

	combat_node = CombatNode.new()
	add_child(combat_node)
	combat_node.level = p_owner.combat_node.level
	combat_node.weapon_damage = stats.get("damage", 12)
	combat_node.strength     = 0
	combat_node.constitution = 0
	combat_node.dexterity    = 0
	combat_node.intelligence = 0
	combat_node.wisdom       = 0
	combat_node.charisma     = 0
	combat_node.luck         = 0

	var armor_class: int = stats.get("armor_class", 10)
	combat_node.gear_ac = armor_class - 10

	# "40% of caster's health" per the spectral_minion spell description
	var pet_max_hp: int = max(1, int(p_owner.combat_node.max_hp * 0.4))
	combat_node.gear_hp = pet_max_hp - 50
	combat_node.gear_atk = 15 + combat_node.level * 5
	combat_node._stats_dirty = true
	combat_node.recalculate_derived_stats()
	combat_node.current_hp = combat_node.max_hp

	move_speed = stats.get("speed", 25.0) / 10.0
	if nav_agent:
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = 0.5
		nav_agent.max_speed = move_speed

	add_to_group("pets")


func _load_skeleton_stats() -> Dictionary:
	var file := FileAccess.open("res://Data/monsters.json", FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(result) == TYPE_DICTIONARY and result.has("skeleton"):
			return result["skeleton"]
	return {}


func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_player):
		queue_free()
		return

	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0.0:
			can_attack = true

	match command:
		PetState.FOLLOW:
			_move_toward(owner_player.global_position, FOLLOW_DISTANCE, delta)
		PetState.ATTACK:
			_process_attack(delta)
		PetState.STOP:
			_apply_gravity(delta)
			velocity.x = 0.0
			velocity.z = 0.0
		PetState.SIT:
			_apply_gravity(delta)
			velocity.x = 0.0
			velocity.z = 0.0
			_process_sit_regen(delta)
		PetState.GUARD:
			_move_toward(guard_position, 0.5, delta)
			_process_guard(delta)

	move_and_slide()


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


func _process_attack(delta: float) -> void:
	if not is_instance_valid(attack_target) or not _target_alive(attack_target):
		attack_target = null
		command = _pre_attack_command
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


func _target_alive(target: Node) -> bool:
	return is_instance_valid(target) and target.get("current_state") != target.State.DEAD


func _perform_attack() -> void:
	can_attack = false
	attack_timer = attack_cooldown

	if not (attack_target.get("combat_node") is CombatNode):
		return

	var target_cn: CombatNode = attack_target.combat_node
	var result: Dictionary = combat_node.resolve_attack(target_cn)
	if attack_target.has_method("add_threat"):
		attack_target.add_threat(self, combat_node.generate_threat(result.get("damage", 0)))
	var target_desc: String = attack_target.get("monster_description")
	if target_desc == "":
		target_desc = attack_target.get_monster_name()

	match result.get("result", ""):
		"MISS":
			GameLog.log_combat("%s misses %s!" % [pet_name, target_desc])
		"PARRY":
			GameLog.log_combat("%s's attack is parried!" % pet_name)
		"BLOCK":
			GameLog.log_combat("%s's attack is blocked!" % pet_name)
		"DODGE":
			GameLog.log_combat("%s's attack is dodged!" % pet_name)
		"RIPOSTE":
			GameLog.log_combat("%s is riposted for [b]%d[/b] damage!" % [pet_name, result.get("damage", 0)])
		"HIT":
			var crit: String = " [color=#ffaa00]Critical![/color]" if result.get("is_crit", false) else ""
			GameLog.log_combat("%s hits %s for [b]%d[/b] damage!%s" % [pet_name, target_desc, result.get("damage", 0), crit])

	if not target_cn.is_alive():
		GameLog.log_combat(CombatLogFormatter.death(pet_name, target_desc))
		if attack_target.has_method("die"):
			attack_target.die()
		attack_target = null
		command = _pre_attack_command


func _process_sit_regen(delta: float) -> void:
	_sit_regen_timer += delta
	if _sit_regen_timer < SIT_REGEN_INTERVAL:
		return
	_sit_regen_timer = 0.0
	if combat_node.current_hp < combat_node.max_hp:
		var regen: int = int(combat_node.get_derived_stat("hp_regen") * 3.0)
		combat_node.current_hp = mini(combat_node.current_hp + regen, combat_node.max_hp)


func _process_guard(delta: float) -> void:
	_guard_scan_timer += delta
	if _guard_scan_timer < GUARD_SCAN_INTERVAL:
		return
	_guard_scan_timer = 0.0
	if not is_instance_valid(owner_player):
		return

	# Every monster's own AI only ever targets the player (monster3d.gd hardcodes
	# `player` as its sole target) — so "in ATTACK state near the owner" already
	# means "attacking the owner." No separate aggro-target lookup needed.
	for monster in get_tree().get_nodes_in_group("monsters"):
		if monster.get("current_state") != monster.State.ATTACK:
			continue
		if owner_player.global_position.distance_to(monster.global_position) <= GUARD_SCAN_RADIUS:
			attack_target = monster
			_pre_attack_command = PetState.GUARD
			command = PetState.ATTACK
			return


# ── Commands (called by pet_frame.gd's UI buttons) ─────────────────────────────

func cmd_attack(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		GameLog.log_general("%s has no target to attack." % pet_name)
		return
	attack_target = target
	_pre_attack_command = PetState.FOLLOW
	command = PetState.ATTACK


func cmd_stop() -> void:
	attack_target = null
	command = PetState.STOP


func cmd_back() -> void:
	attack_target = null
	command = PetState.FOLLOW


func cmd_follow() -> void:
	attack_target = null
	command = PetState.FOLLOW


func cmd_sit() -> void:
	attack_target = null
	command = PetState.SIT


func cmd_guard() -> void:
	attack_target = null
	guard_position = global_position
	command = PetState.GUARD


# ── Damage / death ──────────────────────────────────────────────────────────────
# NOTE: monster3d.gd's AI only ever targets the player, so nothing currently
# damages the pet in combat — this is wired up for when that changes, and so
# the pet can still be freed cleanly if damaged by some other future source.

func apply_damage(amount: int, _damage_type: String = "physical") -> void:
	combat_node.take_damage(amount)
	if not combat_node.is_alive():
		die()


func die() -> void:
	GameLog.log_general("[color=#888888]%s dissipates.[/color]" % pet_name)
	queue_free()
