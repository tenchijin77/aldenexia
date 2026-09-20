# guard_npc.gd — Guard NPC, stationary by default. Responds to a nearby
# player's "hail" (H key or /hail command, handled by
# player3d.gd:try_hail_nearby_npc()) with a random flavor line, and calls out
# when it engages a monster. Day/night transitions trigger a scripted
# back-and-forth between two guards instead of each guard commenting
# individually — see npc_scripted_conversation.gd and the
# "GuardConversations" node in the outskirts scene. Also banters to itself
# periodically while not in combat — see BANTER_MIN/MAX_INTERVAL below.
# Actively engages any monster that wanders within ENGAGE_RANGE (stationary)
# or PATROL_ENGAGE_RANGE (patrolling — see patrol_waypoints below) of it.
# Kills are quiet — no loot, no corpse, immediately removed
# (Monster.die(false, false)) — this is one-directional: monsters have no
# concept of attacking anything but the player (monster3d.gd hardcodes that
# target everywhere), so they won't fight back against a guard.
extends CharacterBody3D
class_name GuardNPC

const ENGAGE_RANGE := 4.0          # stationary guards: how far from home_position they'll notice a monster
const PATROL_ENGAGE_RANGE := 3.0   # patrolling guards: how far from their CURRENT position — they have no fixed post to measure from
const LEASH_RANGE  := 6.0          # disengage if the target gets this far from wherever combat started (_engage_origin)
const ATTACK_RANGE := 2.5
const WAYPOINT_ARRIVAL := 1.5      # how close counts as "reached" a patrol waypoint
# 1.0 (the original value) meant a patrolling guard could cover almost its
# entire PATROL_ENGAGE_RANGE (3m, at ~3 m/s) between two consecutive scans —
# confirmed as the cause of a report that Bryn "walked through a group of
# enemies and only engaged the one he ran into directly": most of that group
# was only ever in range during the gap between checks. 0.2 caps travel
# between scans to ~0.6m, reliably catching anything the engage range
# actually covers. Stationary guards don't move, so this doesn't change
# anything for them beyond a slightly earlier reaction — harmless.
const SCAN_INTERVAL := 0.2
# Matches monster3d.gd's CHASE_SPEED_MULTIPLIER — same "aggroed = urgent, not
# a stroll" feel, applied while a guard is closing distance on an engage
# target (see _process_engage()). Not applied to patrol movement.
const SPRINT_SPEED_MULTIPLIER := 2.0
const GRAVITY := 20.0
const HEAR_RANGE := 5.0     # say() is silent to the log if the player is farther than this
const BANTER_MIN_INTERVAL := 300.0  # 5 min
const BANTER_MAX_INTERVAL := 540.0  # 9 min — randomized per-guard (not a flat 7 min) so multiple guards don't banter in lockstep

enum GuardState { IDLE, ENGAGE, PATROL }

@export var npc_name: String = "Lumora Guard"
@export var npc_faction: String = "Wardens of the Sacred Flame"
## Seconds after dying before this NPC returns at its original spot.
@export var respawn_seconds: float = 120.0
@export var flavor_text_path: String = "res://Data/guard_flavor_text.json"
# Marker3D nodes (or any Node3D) walked in order and looped. Empty (the
# default) = stationary, unchanged from before — set this on a guard instance
# to make it patrol instead.
@export var patrol_waypoints: Array[NodePath] = []

@onready var name_label: Label3D = $NameLabel
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var animation_player: AnimationPlayer = get_node_or_null("Character/AnimationPlayer")  # null for unrigged NPCs (Oni)

var _flavor: NPCFlavorText

var combat_node: CombatNode
var level: int = 8  # mirrors combat_node.level; exposed at the top level like monster3d.gd's `level`
var home_position: Vector3 = Vector3.ZERO
var state: GuardState = GuardState.IDLE
var _default_state: GuardState = GuardState.IDLE  # what to return to once combat ends — IDLE for stationary guards, PATROL for patrolling ones
var attack_target: Node = null
var _engage_origin: Vector3 = Vector3.ZERO  # where this guard was standing when it started the current fight — leash reference point (works for both stationary and patrolling guards)
var move_speed: float = 3.0

var can_attack: bool = true
var attack_timer: float = 0.0
var attack_cooldown: float = 1.5
const REGEN_INTERVAL := 6.0
var _regen_timer: float = 0.0

var _scan_timer: float = 0.0
var _banter_timer: float = 0.0
var _banter_interval: float = 420.0

var _patrol_points: Array[Vector3] = []
var _patrol_index: int = 0


func _ready() -> void:
	add_to_group("npc_guard")
	if name_label:
		name_label.text = npc_name
	_flavor = NPCFlavorText.new(flavor_text_path)
	home_position = global_position
	NPCRespawner.register_home(self)
	_banter_interval = randf_range(BANTER_MIN_INTERVAL, BANTER_MAX_INTERVAL)
	_setup_patrol()
	_setup_combat()
	_setup_animations()


func _setup_patrol() -> void:
	for path in patrol_waypoints:
		var marker := get_node_or_null(path)
		if marker:
			_patrol_points.append(marker.global_position)
	if not _patrol_points.is_empty():
		_default_state = GuardState.PATROL
		state = GuardState.PATROL


func respond_to_hail() -> void:
	_face_player()
	_say_flavor("hail")


# Anything that reduces a guard to 0 HP through the normal attack path (monsters
# call die() on their target) sends it through the shared respawn helper — see
# npc_respawner.gd. Nothing currently targets guards, so this is plumbing for
# when something does.
func die() -> void:
	NPCRespawner.handle_death(self, respawn_seconds)


func on_respawned() -> void:
	attack_target = null
	state = _default_state
	_current_path.clear()


func _face_player() -> void:
	var player: Node3D = TargetFrame.local_player()
	if not is_instance_valid(player):
		return
	var target_pos := player.global_position
	target_pos.y = global_position.y  # stay upright, don't tilt up/down toward the player
	if target_pos.distance_to(global_position) > 0.01:
		look_at(target_pos, Vector3.UP)


func _say_flavor(category: String) -> void:
	var line := _flavor.get_line(category)
	if line == "":
		return
	say(line)


# Speaks an exact line (as opposed to _say_flavor's random pick from this
# guard's own flavor file) — used by npc_scripted_conversation.gd to hand
# specific dialogue to specific guards during a scripted exchange. Only
# reaches the log if the player is actually close enough to hear it (both
# hail responses AND unprompted lines like engage callouts or the day/night
# scripted guard-to-guard conversation) — previously broadcast globally
# regardless of the player's distance from the speaking guard.
func say(line: String) -> void:
	if not _player_in_hear_range():
		return
	GameLog.log_general("[color=#cccc88]%s says, \"%s\"[/color]" % [npc_name, line])


func _player_in_hear_range() -> bool:
	var player := TargetFrame.local_player()
	if not is_instance_valid(player):
		return false
	return global_position.distance_to(player.global_position) <= HEAR_RANGE


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
		# Kept modest (0.75, up from the original 0.5) rather than the 1.5
		# monster3d.gd uses for the same underlying navmesh-vs-floor-height
		# issue — loosening this far enough to reliably swallow the mismatch
		# on its own (confirmed elsewhere up to ~0.7m) also makes the agent
		# consider itself "arrived" near tight passages, and a patrol guard
		# walking a long cross-map route hits exactly that: 1.5 sent Guard
		# Bryn straight through a gate-post wall corner near the very start
		# of his route. _tick_stuck_detector() (in _move_toward(), see its
		# comment) is the real fix for the vertical-mismatch deadlock now —
		# this just gives normal cornering a little slack for minor jitter.
		nav_agent.path_desired_distance = 0.75
		nav_agent.target_desired_distance = 0.75
		nav_agent.max_speed = move_speed


func _load_guard_stats() -> Dictionary:
	var file := FileAccess.open("res://Data/monsters.json", FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(result) == TYPE_DICTIONARY and result.has("lumora_guard"):
			return result["lumora_guard"]
	return {}


# ── Animation ─────────────────────────────────────────────────────────────────
# Guards use their own dedicated Mixamo model (models/Lumora Guardsman/,
# replacing the earlier models/guard/ "Paladin J Nordstrom" placeholder
# 2026-09-15). Every clip (idle/walk/run/attack/death) is a native download
# for this exact character — no cross-model bone retargeting needed this
# time, unlike the old set's walk/death (see git history if that hack is ever
# needed again elsewhere).
func _setup_animations() -> void:
	if not animation_player:
		return
	var lib := load("res://models/Lumora Guardsman/guard_animations.res") as AnimationLibrary
	if not lib:
		return
	if animation_player.has_animation_library(""):
		animation_player.remove_animation_library("")
	animation_player.add_animation_library("", lib)
	_apply_texture_override("res://models/Lumora Guardsman/Meshy_AI_Lumora_Guardsman_Rig_biped_texture_0.png")


# Meshy-sourced FBX exports never carry their real texture through to Godot
# reliably (confirmed recurring bug across every model built this way), so
# apply it as a runtime material override instead of trusting the FBX's own
# material.
func _apply_texture_override(texture_path: String) -> void:
	var tex := load(texture_path) as Texture2D
	if not tex:
		push_warning("⚠️ Guard texture override not found: %s" % texture_path)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	_apply_material_recursive(get_node("Character"), mat)


func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_material_recursive(child, mat)


var _attack_anim_timer: float = 0.0  # counts down while an attack swing should stay visible


func _update_animation() -> void:
	if not animation_player or animation_player.get_animation_list().is_empty():
		return
	if _attack_anim_timer > 0.0:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	var anim_name := "idle"
	if moving:
		# Mirrors monster3d.gd's chase-run pattern: sprinting to close on an
		# engage target plays "run" instead of the patrol/idle "walk".
		anim_name = "run" if state == GuardState.ENGAGE else "walk"
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, 0.15)


func _play_attack_animation() -> void:
	if not animation_player or not animation_player.has_animation("attack"):
		return
	animation_player.play("attack", 0.1)
	_attack_anim_timer = animation_player.get_animation("attack").length


# Not called anywhere yet — guards have no health/damage-taking system in this
# codebase (monsters only ever attack the player, never a guard; see the file
# header), so nothing currently puts a guard in a state to die. Wired here so
# it's a one-line hookup whenever guard vulnerability gets built.
func play_death_animation() -> void:
	if animation_player and animation_player.has_animation("death"):
		animation_player.play("death")


# ── Engagement state machine ─────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0.0:
			can_attack = true

	if _attack_anim_timer > 0.0:
		_attack_anim_timer -= delta

	# Out-of-combat regen (same 6s EQ-tick as the player/pet/monsters) —
	# prevents a guard being chipped down over repeated fights with no risk.
	if state != GuardState.ENGAGE:
		_regen_timer += delta
		if _regen_timer >= REGEN_INTERVAL:
			_regen_timer = 0.0
			if combat_node.current_hp < combat_node.max_hp:
				combat_node.current_hp = mini(combat_node.current_hp + combat_node.get_derived_stat("hp_regen"), combat_node.max_hp)
	else:
		_regen_timer = 0.0

	# Banter periodically while not fighting — timer resets (not just pauses)
	# on entering combat, so a fresh ~5-9 min interval starts once the fight
	# ends rather than potentially firing right as combat wraps up.
	if state != GuardState.ENGAGE:
		_banter_timer += delta
		if _banter_timer >= _banter_interval:
			_banter_timer = 0.0
			_banter_interval = randf_range(BANTER_MIN_INTERVAL, BANTER_MAX_INTERVAL)
			_say_flavor("banter")
	else:
		_banter_timer = 0.0

	match state:
		GuardState.IDLE:
			_scan_timer += delta
			if _scan_timer >= SCAN_INTERVAL:
				_scan_timer = 0.0
				_scan_for_targets()
			_apply_gravity(delta)
			velocity.x = 0.0
			velocity.z = 0.0
		GuardState.PATROL:
			_scan_timer += delta
			if _scan_timer >= SCAN_INTERVAL:
				_scan_timer = 0.0
				_scan_for_targets()
			if state == GuardState.PATROL:  # _scan_for_targets() may have just switched us to ENGAGE
				_process_patrol(delta)
		GuardState.ENGAGE:
			_process_engage(delta)

	move_and_slide()
	_update_animation()


func _process_patrol(delta: float) -> void:
	if _patrol_points.is_empty():
		_apply_gravity(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var target: Vector3 = _patrol_points[_patrol_index]
	_move_toward(target, WAYPOINT_ARRIVAL, delta)
	if global_position.distance_to(target) <= WAYPOINT_ARRIVAL:
		_patrol_index = (_patrol_index + 1) % _patrol_points.size()


func _scan_for_targets() -> void:
	var is_patrolling := not _patrol_points.is_empty()
	var engage_range: float = PATROL_ENGAGE_RANGE if is_patrolling else ENGAGE_RANGE
	var origin: Vector3 = global_position if is_patrolling else home_position

	var nearest: Node = null
	var nearest_dist := engage_range
	for monster in get_tree().get_nodes_in_group("monsters"):
		if monster.get("current_state") == monster.State.DEAD:
			continue
		var dist := origin.distance_to(monster.global_position)
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
		attack_target = null
		state = _default_state
		_current_path.clear()  # combat may have moved us off the cached patrol path — force a fresh one
		return

	if _engage_origin.distance_to(attack_target.global_position) > LEASH_RANGE:
		attack_target = null
		state = _default_state
		_current_path.clear()
		return

	var distance := global_position.distance_to(attack_target.global_position)
	if distance > ATTACK_RANGE:
		_move_toward(attack_target.global_position, ATTACK_RANGE, delta, move_speed * SPRINT_SPEED_MULTIPLIER)
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


# Self-managed path-following via direct NavigationServer3D.query_path()
# calls, rather than NavigationAgent3D's own target_position/
# get_next_path_position() state — rewritten 2026-09-14 (Session 39) after
# Guard Bryn's long patrol route exposed NavigationAgent3D going stale over
# a long-distance target: two different fix attempts (loosening
# path_desired_distance, then a stuck-detector that snapped position and/or
# nudged toward a freshly-queried corner) both still left him orbiting the
# same few meters near a gate pillar indefinitely. What finally isolated it:
# a fresh NavigationServer3D.query_path() called directly from his exact
# stuck position, every time, consistently returned short, sane, correct-
# looking corners — but nav_agent.get_next_path_position() kept offering a
# corner that led right back to the same spot, meaning the AGENT's own
# internal path had gone stale relative to where he actually was (most
# likely from being externally repositioned by the earlier stuck-detector
# attempts, but the underlying "trust the agent's cached path" approach was
# fragile regardless). This bypasses that entirely: _current_path is our own
# corner list, recomputed via query_path() whenever it's empty, stale
# (target changed), or a stuck timer expires — never relying on the agent to
# track "where am I on my own path" across an externally-moved position.
var _current_path: Array[Vector3] = []
var _current_path_index: int = 0
var _current_path_target: Vector3 = Vector3.ZERO

const STUCK_THRESHOLD := 2.0
const STUCK_MOVE_EPSILON := 0.1
const CORNER_ARRIVAL := 0.75
var _stuck_timer: float = 0.0
var _last_stuck_check_pos: Vector3 = Vector3.ZERO


func _move_toward(target_pos: Vector3, stop_distance: float, delta: float, speed_override: float = -1.0) -> void:
	var move_at_speed: float = speed_override if speed_override > 0.0 else move_speed
	_apply_gravity(delta)
	_tick_stuck_detector(delta)

	if global_position.distance_to(target_pos) <= stop_distance:
		velocity.x = 0.0
		velocity.z = 0.0
		_current_path.clear()
		return

	var need_repath := _current_path.is_empty() \
		or _current_path_target.distance_to(target_pos) > 0.5 \
		or _stuck_repath_requested
	if need_repath:
		_stuck_repath_requested = false
		_recompute_path(target_pos)

	if _current_path.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		return

	while _current_path_index < _current_path.size() - 1 \
			and global_position.distance_to(_current_path[_current_path_index]) < CORNER_ARRIVAL:
		_current_path_index += 1

	var next_position: Vector3 = _current_path[_current_path_index]
	var to_next: Vector3 = next_position - global_position
	var flat_dir := Vector3(to_next.x, 0.0, to_next.z)
	if flat_dir.length() < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var direction := flat_dir.normalized()
	direction = _steer_around_obstacles(direction)
	look_at(global_position + direction, Vector3.UP)
	velocity.x = direction.x * move_at_speed
	velocity.z = direction.z * move_at_speed


# Local obstacle avoidance, layered on top of the global path-following
# above — added 2026-09-14 (Session 41) after a second stuck report (the
# wagon crash site, unrelated geometry to the gate area fixed last session)
# showed the underlying issue isn't isolated to one spot: debris/prop
# collision the baked navmesh doesn't cleanly route around can turn up
# anywhere on a long cross-map patrol route. Rather than chase down and
# hand-fix every individual piece of geometry, this casts a short ray along
# the intended direction before committing to it; if something's directly
# ahead, it tries a handful of alternate headings (widening outward, left
# and right alternating) and walks the first one that's actually clear
# instead — a real-time sidestep around whatever's in the way, independent
# of whether the navmesh accounts for it. The existing stuck-detector still
# serves as the fallback for anything this can't steer around (forces a
# fresh global repath), so the two work together: this handles the
# immediate obstacle, stuck-detection handles being well and truly wedged.
const OBSTACLE_CHECK_DISTANCE := 1.5
const OBSTACLE_AVOID_ANGLES_DEG := [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]

func _steer_around_obstacles(direction: Vector3) -> Vector3:
	if not is_inside_tree():
		return direction
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 0.9, 0)  # roughly chest height on this capsule

	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * OBSTACLE_CHECK_DISTANCE)
	query.exclude = [self]
	if not space.intersect_ray(query):
		return direction  # clear ahead, no steering needed

	for angle_deg in OBSTACLE_AVOID_ANGLES_DEG:
		var candidate := direction.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var candidate_query := PhysicsRayQueryParameters3D.create(origin, origin + candidate * OBSTACLE_CHECK_DISTANCE)
		candidate_query.exclude = [self]
		if not space.intersect_ray(candidate_query):
			return candidate

	return direction  # nothing clear found — keep the original heading rather than freeze; the stuck-detector will recover if this doesn't work out


func _recompute_path(target_pos: Vector3) -> void:
	_current_path.clear()
	_current_path_index = 0
	_current_path_target = target_pos
	if not is_inside_tree():
		return
	var map_rid: RID = get_world_3d().navigation_map
	var query := NavigationPathQueryParameters3D.new()
	query.map = map_rid
	query.start_position = global_position
	query.target_position = target_pos
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	for p in result.path:
		_current_path.append(p)
	if _current_path.size() > 1:
		_current_path_index = 1  # path[0] is just our own current position


# Detects "hasn't actually moved in a while despite trying to" and forces a
# fresh repath next _move_toward() call — covers both a genuine navmesh/floor
# height mismatch (confirmed elsewhere in this project, up to ~0.7m) and any
# physical corner-wedge move_and_slide() deflected the guard into that a
# stale cached path wouldn't route around.
var _stuck_repath_requested: bool = false

func _tick_stuck_detector(delta: float) -> void:
	if global_position.distance_to(_last_stuck_check_pos) > STUCK_MOVE_EPSILON:
		_stuck_timer = 0.0
		_last_stuck_check_pos = global_position
		return
	_stuck_timer += delta
	if _stuck_timer < STUCK_THRESHOLD:
		return
	_stuck_timer = 0.0
	_last_stuck_check_pos = global_position
	_stuck_repath_requested = true


func _perform_attack() -> void:
	can_attack = false
	attack_timer = attack_cooldown
	_play_attack_animation()

	if not (attack_target.get("combat_node") is CombatNode):
		return

	var target_cn: CombatNode = attack_target.combat_node
	var result: Dictionary = combat_node.resolve_attack(target_cn)
	var target_desc: String = attack_target.get("monster_description")
	if target_desc == "":
		target_desc = attack_target.get_monster_name()

	match result.get("result", ""):
		"MISS":
			GameLog.log_combat("%s misses %s!" % [npc_name, target_desc], global_position)
		"PARRY":
			GameLog.log_combat("%s's attack is parried!" % npc_name, global_position)
		"BLOCK":
			GameLog.log_combat("%s's attack is blocked!" % npc_name, global_position)
		"DODGE":
			GameLog.log_combat("%s's attack is dodged!" % npc_name, global_position)
		"RIPOSTE":
			GameLog.log_combat("%s is riposted for [b]%d[/b] damage!" % [npc_name, result.get("damage", 0)], global_position)
		"HIT":
			var crit: String = " [color=#ffaa00]Critical![/color]" if result.get("is_crit", false) else ""
			GameLog.log_combat("%s hits %s for [b]%d[/b] damage!%s" % [npc_name, target_desc, result.get("damage", 0), crit], global_position)

	if not target_cn.is_alive():
		GameLog.log_combat("[color=#88ccff]%s dispatches %s.[/color]" % [npc_name, target_desc], global_position)
		if attack_target.has_method("die"):
			attack_target.die(false, false)
		attack_target = null
		state = _default_state
		_current_path.clear()  # combat may have moved us off the cached patrol path — force a fresh one
