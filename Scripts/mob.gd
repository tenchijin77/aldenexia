# mob.gd — Legacy 2D mob base class (deprecated; active game uses monster3d.gd)
# Kept alive because mob_spawner.tscn and some 2D monster scripts still reference it.
class_name Mob
extends CharacterBody2D

@export var behavior_type := "default"
@export var speed: float = 100.0

@onready var name_label: Label = $name_label
@onready var health_bar: ProgressBar = $health_bar

var combat_node: CombatNode
var move_direction: Vector2 = Vector2.ZERO
var movement_offset := 0.0
var target_player: Node = null
var attack_timer: float = 0.0
var attack_cooldown: float = 2.0
const MELEE_RANGE := 40.0


func _ready():
	add_to_group("monsters")
	collision_layer = 1 << 3
	collision_mask  = 1 << 0
	movement_offset = randf_range(0.0, TAU)

	combat_node = CombatNode.new()
	add_child(combat_node)

	var stats = _load_stats(get_monster_name())
	if not stats.is_empty():
		_configure_combat_node(stats)
		behavior_type  = stats.get("behavior_type", behavior_type)
		attack_cooldown = stats.get("weapon_speed", attack_cooldown)
		if name_label:
			name_label.text = stats.get("description", get_monster_name())

	if health_bar:
		health_bar.max_value = combat_node.max_hp
		health_bar.value     = combat_node.current_hp


func _configure_combat_node(stats: Dictionary):
	var lvl     = stats.get("level",        1)
	var flat_hp = stats.get("health",       50)
	var flat_ac = stats.get("armor_class",  10)
	var flat_dmg = stats.get("damage",       5)

	combat_node.level          = lvl
	combat_node.weapon_damage  = flat_dmg
	combat_node.strength = 0
	combat_node.constitution = 0
	combat_node.dexterity = 0
	combat_node.intelligence = 0
	combat_node.wisdom = 0
	combat_node.charisma = 0
	combat_node.luck = 0
	combat_node.gear_ac  = flat_ac - 10
	combat_node.gear_hp  = flat_hp - 50
	combat_node.gear_atk = 40 + lvl * 10
	combat_node._stats_dirty = true
	combat_node.recalculate_derived_stats()
	combat_node.current_hp = combat_node.max_hp


func _load_stats(monster_name: String) -> Dictionary:
	var file := FileAccess.open("res://Data/monsters.json", FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(result) == TYPE_DICTIONARY and result.has(monster_name):
			return result[monster_name]
	return {}


func get_monster_name() -> String:
	return "mob"


func _physics_process(delta: float):
	attack_timer -= delta
	velocity = get_move_direction() * speed
	move_and_slide()
	if target_player and is_instance_valid(target_player):
		_try_attack()


func get_move_direction() -> Vector2:
	var t = Time.get_ticks_msec() / 1000.0 + movement_offset
	return Vector2.RIGHT.rotated(fmod(t, TAU)).normalized()


func set_target(node: Node): target_player = node
func clear_target(): target_player = null


func _try_attack():
	if attack_timer > 0 or global_position.distance_to(target_player.global_position) > MELEE_RANGE:
		return
	attack_timer = attack_cooldown
	if "combat_node" in target_player and target_player.combat_node is CombatNode:
		var result = combat_node.resolve_attack(target_player.combat_node)
		sync_health_bar()
		if not combat_node.is_alive(): die()
		if result["damage"] > 0 and target_player.has_method("apply_damage"):
			target_player.apply_damage(result["damage"])
	elif target_player.has_method("apply_damage"):
		target_player.apply_damage(combat_node.weapon_damage)


func apply_damage(amount: int):
	combat_node.take_damage(amount)
	sync_health_bar()
	if not combat_node.is_alive():
		die()


func sync_health_bar():
	if health_bar:
		health_bar.value = combat_node.current_hp


func die():
	queue_free()
