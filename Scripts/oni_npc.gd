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
const MODEL_ANIMATED := "res://models/Oni/oni_animated.glb"   # the user's rig, animated (tools/blender/animate_cat.py)
var _anim: AnimationPlayer = null
var _last_pos := Vector3.INF
var _speed := 0.0
const HUNT_LEASH_EXTRA := 15.0  # gave up if prey drags her this far past hunt_range from home

@export_group("Model")
@export var model_scale: float = 0.4

@export_group("Hunting")
## monster_name values she will hunt.
@export var prey_monsters: PackedStringArray = ["rat"]
## How far from her home spot she'll notice and chase prey.
@export var hunt_range: float = 25.0

@export_group("Chat text")
## Shown when a player pets her (/pet). {name} = her name.
@export_multiline var pet_text: String = "You pet {name}. She begins to purr happily!"

@export_group("Stats")
@export var cat_level: int = 3
@export var cat_health: int = 200
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
	add_to_group("pettable")  # /pet finds anything in this group
	_model = CatModel.build_animated(self, MODEL_ANIMATED, MODEL_BASE, model_scale)   # walks, runs, swishes her tail
	_anim = CatModel.animation_player(_model)
	if _anim != null and _anim.has_animation("idle"):
		_anim.play("idle")
	call_deferred("_finish_model")


func _can_talk() -> bool:
	return false  # she is a cat


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
	if _anim != null:
		# idle / walk / run by how far she really moved this frame (her AI runs on the server; this runs everywhere)
		var dt := maxf(get_physics_process_delta_time(), 0.001)
		var p := global_position
		var step := 0.0 if _last_pos == Vector3.INF else Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length() / dt
		_last_pos = p
		_speed = lerpf(_speed, minf(step, 12.0), 0.2)
		CatModel.animate_by_speed(_anim, _speed)
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
	Sfx.play("cat_meow", self)
	_say_flavor("hail")


# /pet — see player3d.gd's try_pet_nearby(). Shown regardless of distance to the
# viewer (say()'s hearing range doesn't apply — the petter is right here).
func receive_pet(_petter: Node) -> void:
	Sfx.play("cat_meow", self)
	if state != GuardState.ENGAGE:  # don't spin around mid-hunt
		_face_player()
	GameLog.log_general("[color=#ffd9a0]%s[/color]" % pet_text.replace("{name}", npc_name))


# ── Hunting ────────────────────────────────────────────────────────────────
func _scan_for_targets() -> void:
	var nearest: Node = null
	var nearest_dist := hunt_range
	for monster in get_tree().get_nodes_in_group("monsters"):
		if not is_instance_valid(monster) or monster.get("current_state") == monster.State.DEAD:
			continue
		if not (str(monster.get("monster_name")) in prey_monsters):
			continue
		if int(_ignored_targets.get(monster.get_instance_id(), 0)) > Time.get_ticks_msec():
			continue  # couldn't reach this one recently
		var dist := home_position.distance_to(monster.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = monster
	if nearest:
		attack_target = nearest
		_engage_origin = global_position
		_engage_best_dist = INF
		_engage_stall_timer = 0.0
		state = GuardState.ENGAGE
		_say_flavor("engage", true)


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
		# Same watchdog as GuardNPC: chasing without getting closer -> give up and ignore that rat for a while.
		if distance < _engage_best_dist - PROGRESS_EPSILON:
			_engage_best_dist = distance
			_engage_stall_timer = 0.0
		else:
			_engage_stall_timer += delta
			if _engage_stall_timer >= ENGAGE_STALL_GIVE_UP:
				_ignored_targets[attack_target.get_instance_id()] = Time.get_ticks_msec() + int(IGNORE_UNREACHABLE_SECONDS * 1000.0)
				_disengage()
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
