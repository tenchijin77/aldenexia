# oni_npc.gd — Oni, the town cat. Patrols her waypoints like a guard and hunts
# rats (any monster named in prey_monsters) within hunt_range of her home spot.
# Built on GuardNPC to reuse its navmesh path-following, stuck handling and
# melee resolution; overridden here: the (static, unrigged) cat visual with a
# little procedural bob/lunge instead of animation clips, emote-style chatter
# instead of speech, a much bigger hunting radius, and — unlike guards — she
# can actually be hurt: she registers threat on every rat she hits, so
# monster3d.gd's normal aggro_table logic (the same one pets use) makes the rat
# fight back. Her kills are quiet (no loot/XP), so the player still has to
# hunt rats themselves for Kenji's rat tails. Dies → respawns (npc_respawner.gd).
extends GuardNPC
class_name OniNPC

const MODEL_BASE := "res://models/Oni/Meshy_AI_oni_3d_model_0919110654_image-to-3d-texture"
const HUNT_LEASH_EXTRA := 15.0  # gave up if prey drags her this far past hunt_range from home

@export_group("Model")
@export var model_scale: float = 0.4

@export_group("Hunting")
## monster_name values she will hunt.
@export var prey_monsters: PackedStringArray = ["rat"]
## How far from her home spot she'll notice and chase prey.
@export var hunt_range: float = 60.0

@export_group("Stats")
@export var cat_level: int = 3
@export var cat_health: int = 120
@export var cat_damage: int = 10
@export var cat_armor_class: int = 12
## Walk speed x10 (same units as monsters.json "speed": 35 = 3.5 m/s).
@export var cat_speed: float = 35.0

var _model: Node3D = null
var _bob_time: float = 0.0
var _model_rest_y: float = 0.0
var _lunge_tween: Tween = null


func _ready() -> void:
	flavor_text_path = "res://Data/cat_flavor_text.json"
	super._ready()
	_model = CatModel.build(self, MODEL_BASE, model_scale)
	call_deferred("_finish_model")


func _finish_model() -> void:
	if _model == null:
		return
	var height := CatModel.ground_and_measure(self, _model)
	_model_rest_y = _model.position.y
	if name_label:
		name_label.position.y = height + 0.3


# ── Stats (exported on the scene instead of read from monsters.json) ───────
func _load_guard_stats() -> Dictionary:
	return {
		"level": cat_level,
		"health": cat_health,
		"damage": cat_damage,
		"armor_class": cat_armor_class,
		"speed": cat_speed,
	}


# ── Visuals: no rig, so no animation library ───────────────────────────────
func _setup_animations() -> void:
	pass


# Gentle up/down bob while moving (faster when chasing), and a forward lunge
# tween on each attack (_play_attack_animation below).
func _update_animation() -> void:
	if _model == null or not is_inside_tree():
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	if moving:
		_bob_time += get_physics_process_delta_time() * (16.0 if state == GuardState.ENGAGE else 10.0)
	_model.position.y = _model_rest_y + (absf(sin(_bob_time)) * 0.05 if moving else 0.0)


func _play_attack_animation() -> void:
	_attack_anim_timer = 0.3
	if _model == null:
		return
	if _lunge_tween and _lunge_tween.is_valid():
		_lunge_tween.kill()
	var rest_z := 0.0
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(_model, "position:z", rest_z - 0.35, 0.1)  # -Z is "forward" for this node
	_lunge_tween.tween_property(_model, "position:z", rest_z, 0.2)


# ── Chatter: cats emote instead of talking ─────────────────────────────────
# Lines in Data/cat_flavor_text.json are complete sentences ("Oni flicks her
# tail..."), shown as-is.
func say(line: String) -> void:
	if not _player_in_hear_range():
		return
	GameLog.log_general("[color=#ffd9a0]%s[/color]" % line)


func respond_to_hail() -> void:
	_face_player()
	_say_flavor("hail")


# ── Hunting ────────────────────────────────────────────────────────────────
func _scan_for_targets() -> void:
	var nearest: Node = null
	var nearest_dist := hunt_range
	for monster in get_tree().get_nodes_in_group("monsters"):
		if not is_instance_valid(monster) or monster.get("current_state") == monster.State.DEAD:
			continue
		if not (str(monster.get("monster_name")) in prey_monsters):
			continue
		var dist := home_position.distance_to(monster.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = monster
	if nearest:
		attack_target = nearest
		_engage_origin = global_position
		state = GuardState.ENGAGE
		_say_flavor("engage")


func _process_engage(delta: float) -> void:
	if not is_instance_valid(attack_target) or attack_target.get("current_state") == attack_target.State.DEAD:
		_disengage()
		return
	if home_position.distance_to(attack_target.global_position) > hunt_range + HUNT_LEASH_EXTRA:
		_disengage()
		return

	var distance := global_position.distance_to(attack_target.global_position)
	if distance > ATTACK_RANGE:
		_move_toward(attack_target.global_position, ATTACK_RANGE, delta, move_speed * SPRINT_SPEED_MULTIPLIER)
		return

	_apply_gravity(delta)
	velocity.x = 0.0
	velocity.z = 0.0
	look_at(Vector3(attack_target.global_position.x, global_position.y, attack_target.global_position.z), Vector3.UP)
	if can_attack:
		_perform_attack()


func _disengage() -> void:
	attack_target = null
	state = _default_state
	_current_path.clear()


func _perform_attack() -> void:
	# Registering threat is what lets the rat fight back — same mechanism a
	# pet uses (see pet_minion.gd), and it also pulls an idle rat into combat.
	if is_instance_valid(attack_target) and attack_target.has_method("add_threat"):
		attack_target.add_threat(self, float(maxi(cat_damage, 1)))
	super._perform_attack()


# ── Death / respawn ────────────────────────────────────────────────────────
func on_respawned() -> void:
	attack_target = null
	state = _default_state
	_current_path.clear()
