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

## The language this NPC speaks (Data/languages.json id); players who don't know it hear it scrambled (Languages).
@export var language: String = "common"
## Other languages it also speaks and understands; it answers in whichever one you addressed it in (Sahren: Djhanid).
@export var extra_languages: Array[String] = []

const ENGAGE_RANGE := 8.0          # stationary guards: how far from home_position they'll notice a monster (was 4 m; 8 m per playtest T8)
const PATROL_ENGAGE_RANGE := 8.0   # patrolling guards: how far from their CURRENT position — they have no fixed post to measure from
const LEASH_RANGE  := 14.0         # disengage if the target gets this far from wherever combat started (_engage_origin): must exceed the engage range
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

var _stall_noted := {}   # patrol waypoints already reported as skipped (reported once each)
var _flavor: NPCFlavorText
var _conversation: NPCConversation = null
var _merchant_lines: Dictionary = {}
var _hail_hooks: Array = []   # Data/guard_topics.json "hail_hooks" for this guard (see _hail_hook_line())
const TOPICS_PATH := "res://Data/guard_topics.json"

var combat_node: CombatNode
var level: int = 8  # mirrors combat_node.level; exposed at the top level like monster3d.gd's `level`
var home_position: Vector3 = Vector3.ZERO
var _home_yaw: float = 0.0   # which way the post faces: restored after a fight
var _face_hold_until_msec := 0   # after facing someone (a hail, a conversation) the guard keeps facing them this long before turning back to the post
const FACE_HOLD_SECONDS := 10.0
const POST_RETURN_DISTANCE := 1.5   # a stationary guard further than this from its post walks back to it
const POST_ARRIVAL := 0.8
var state: GuardState = GuardState.IDLE
var _default_state: GuardState = GuardState.IDLE  # what to return to once combat ends — IDLE for stationary guards, PATROL for patrolling ones
var attack_target: Node = null
var target_key: String = ""   # who this guard is fighting (TargetFrame.target_key_of), for "target's target"
var _engage_origin: Vector3 = Vector3.ZERO  # where this guard was standing when it started the current fight — leash reference point (works for both stationary and patrolling guards)
var move_speed: float = 3.0

var can_attack: bool = true
var attack_timer: float = 0.0
## Bumped on every swing so a puppet (see _is_puppet()) can replay the attack animation.
var attack_seq: int = 0
var _seen_attack_seq: int = 0
var _puppet_hidden: bool = false
var attack_cooldown: float = 1.5
const REGEN_INTERVAL := 6.0
var _regen_timer: float = 0.0

## Set by GateRaidManager while a raid is on: guards go out to meet monsters in group "raiders" up to this far from their post
## (0 = normal, only what wanders within a few metres). With raid_soften a guard only wears a raider down to RAID_SOFTEN_FLOOR of
## its health and leaves the killing to the players, who then get the XP and the loot (guard kills are quiet: no corpse).
var raid_alert_range: float = 0.0
var raid_soften: bool = false
const RAID_SOFTEN_FLOOR := 0.5

var _scan_timer: float = 0.0
var _banter_timer: float = 0.0
var _banter_interval: float = 420.0

var _patrol_points: Array[Vector3] = []
var _patrol_index: int = 0
# Progress watchdogs — a guard must never be able to stand still forever. Patrol: no closer to the current waypoint for
# PATROL_STALL_SKIP seconds -> give up on it and head for the next. Engage: chasing a monster without getting closer for
# ENGAGE_STALL_GIVE_UP seconds -> drop it, and ignore it for IGNORE_UNREACHABLE_SECONDS so the scan doesn't re-pick it.
const PATROL_STALL_SKIP := 20.0
const ENGAGE_STALL_GIVE_UP := 8.0
const IGNORE_UNREACHABLE_SECONDS := 30.0
const PROGRESS_EPSILON := 0.5
var _patrol_best_dist: float = INF
var _patrol_stall_timer: float = 0.0
var _engage_best_dist: float = INF
var _engage_stall_timer: float = 0.0
var _ignored_targets: Dictionary = {}  # monster instance id -> Time.get_ticks_msec() until which it is ignored


# Distance on the ground plane only. Navmesh points sit up to ~0.8 m above the floor a guard's feet are on, so a 3D
# distance can stay above an arrival threshold even when the guard is standing right on the point — Bryn froze on a path
# corner exactly like that (0.2 m away horizontally, 0.83 m in 3D, arrival threshold 0.75).
static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _ready() -> void:
	add_to_group("npc_guard")
	if name_label:
		name_label.text = npc_name
	_flavor = NPCFlavorText.new(flavor_text_path)
	home_position = global_position
	_home_yaw = rotation.y
	NPCRespawner.register_home(self)
	_banter_interval = randf_range(BANTER_MIN_INTERVAL, BANTER_MAX_INTERVAL)
	_setup_conversation()
	_setup_patrol()
	_setup_combat()
	_setup_animations()


# Guards answer keywords (Data/guard_topics.json): their own topics first, then the shared ones. Not Oni: she's a cat (_can_talk()).
func _can_talk() -> bool:
	return true


func _setup_conversation() -> void:
	if not _can_talk():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TOPICS_PATH)) if FileAccess.file_exists(TOPICS_PATH) else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var topics: Array = []
	topics.append_array(parsed.get("by_name", {}).get(npc_name, []))
	topics.append_array(parsed.get("shared", []))
	_hail_hooks = parsed.get("hail_hooks", {}).get(npc_name, [])
	_merchant_lines = parsed.get("merchant_lines", {})
	_conversation = NPCConversation.new(self, topics, HEAR_RANGE)
	add_to_group("npc_talker")


# ── Conversation (npc_conversation.gd) ──
func speak(line: String) -> void:
	say(line)


func face_player() -> void:
	_face_player()


func can_answer(player: Node, text: String) -> bool:
	return _conversation != null and _conversation.can_answer(player, text)


func hear_say(player: Node, text: String) -> void:
	if _conversation != null:
		_conversation.hear(player, text)


# ── Hand-ins (Quests: an item dragged onto a guard, EverQuest style) ──
const INTERACT_RANGE := 8.0


func receive_item_drop(item: Dictionary, player: Node) -> void:
	if global_position.distance_to(player.global_position) > INTERACT_RANGE:
		GameLog.log_general("You are too far away from %s." % npc_name)
		return
	_face_player()
	var existing := get_tree().root.get_node_or_null("GiveWindow")
	if existing:
		existing.queue_free()
	var win := GiveWindow.new()
	win.name = "GiveWindow"
	get_tree().root.add_child(win)
	win.setup(self, player)
	win.offer_item(item)


# Called by the Give window: true closes it (finished), false leaves it open.
func try_give(item_id: String, player: Node) -> bool:
	var result := Quests.try_hand_in(npc_name, item_id, player)
	var text: String = str(result.get("text", ""))
	match str(result.get("result", "")):
		"wrong_item":
			say("I have no use for that, friend.")
			return false
		"have_enough":
			say("I have all the %s I need. Keep it." % str(result.get("item_name", "those")).to_lower())
			return false
		"complete", "already_done":
			if not text.is_empty():
				say(text)
			return true
		_:
			if not text.is_empty():
				say(text)
			return false


func progress_summary() -> String:
	return Quests.progress_summary(npc_name)


# Where the traveling merchant is, from his timetable (merchant_schedule.gd) — so a guard knows even when he's in another
# zone: on his way to a stop here (and where it is, X/Z as /loc shows them), trading at one, leaving, elsewhere, or away.
# Templates in Data/guard_topics.json "merchant_lines": {stop} {x} {z} {minutes} {zone}.
func dynamic_lines(name: String) -> Array:
	if name != "merchant_remark":
		return []
	var r := MerchantSchedule.report(ZoneInfo.current_id(), Time.get_unix_time_from_system())
	var pool = _merchant_lines.get(str(r.get("key", "away")), [])
	if typeof(pool) != TYPE_ARRAY:
		return []
	return pool.map(func(line): return str(line).replace("{stop}", str(r.get("stop", ""))).replace("{x}", str(r.get("x", 0))) \
			.replace("{z}", str(r.get("z", 0))).replace("{minutes}", str(r.get("minutes", 0))).replace("{zone}", str(r.get("zone", ""))) \
			.replace("{s}", "" if int(r.get("minutes", 0)) == 1 else "s"))


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
	var hook := _hail_hook_line()
	if hook != "":
		say(hook)
		return
	_say_flavor("hail")


# A guard with work for you says so when hailed (Data/guard_topics.json "hail_hooks"): the first hook whose requirements
# hold — a topic's conditions, plus "after_quest": id (that quest must be complete) — replaces the random hail line.
func _hail_hook_line() -> String:
	return "" if _conversation == null else _conversation.hook_line(_hail_hooks)


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
		_face_hold_until_msec = Time.get_ticks_msec() + int(FACE_HOLD_SECONDS * 1000.0)


# `broadcast` = an unprompted line (banter, engage callout) decided on the server that every
# nearby player should hear; a hail reply stays local to whoever hailed.
func _say_flavor(category: String, broadcast: bool = false) -> void:
	var line := _flavor.get_line(category)
	if line == "":
		return
	if broadcast:
		say_to_all(line)
	else:
		say(line)


# Server-side speech: says it locally and tells every peer, each of which applies its own
# hearing range in say().
func say_to_all(line: String) -> void:
	say(line)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_say.rpc(line)


@rpc("authority", "call_remote", "reliable")
func _rpc_say(line: String) -> void:
	say(line)


# A shout carries much farther than talk (a raid warning, a rally): every player within SHOUT_RANGE of this guard hears it.
const SHOUT_RANGE := 70.0


func shout_to_all(line: String) -> void:
	_shout(line)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_shout.rpc(line)


@rpc("authority", "call_remote", "reliable")
func _rpc_shout(line: String) -> void:
	_shout(line)


func _shout(line: String) -> void:
	var player := TargetFrame.local_player()
	if is_instance_valid(player) and global_position.distance_to(player.global_position) <= SHOUT_RANGE:
		var spoken := Languages.npc_line(Languages.voice_of(self), line)
		GameLog.log_general("[color=#ffdd88]%s shouts%s, \"%s\"[/color]" % [npc_name, spoken[0], NPCConversation.format(spoken[1])])


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
	var spoken := Languages.npc_line(Languages.voice_of(self), line)
	GameLog.log_general("[color=#cccc88]%s says%s, \"%s\"[/color]" % [npc_name, spoken[0], NPCConversation.format(spoken[1])])


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
	combat_node.name = "CombatNode"  # the scene's MultiplayerSynchronizer replicates HP by this exact path
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
	var death_anim := Player3D.pick_variant(animation_player, "death")
	if not death_anim.is_empty():
		animation_player.play(death_anim)


# ── Engagement state machine ─────────────────────────────────────────────────

# In a multiplayer game the guards' AI runs ONLY on the server; every other peer's copy is
# a puppet that just plays back what the server replicates (position, rotation, velocity,
# state, attack_seq, visible, HP — see the scene's MultiplayerSynchronizer). Before this
# every peer ran its own guards/Oni, so each machine saw them somewhere different.
func _is_puppet() -> bool:
	return Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and not is_multiplayer_authority()


func _puppet_process(delta: float) -> void:
	if _attack_anim_timer > 0.0:
		_attack_anim_timer -= delta
	if attack_seq != _seen_attack_seq:
		_seen_attack_seq = attack_seq
		_play_attack_animation()
	if visible == _puppet_hidden:  # replicated visibility flipped — the server killed/respawned it (NPCRespawner)
		_puppet_hidden = not visible
		NPCRespawner.mirror_hidden(self, _puppet_hidden)
	if visible:
		_update_animation()


func _physics_process(delta: float) -> void:
	if _is_puppet():
		_puppet_process(delta)
		return

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
			_say_flavor("banter", true)
	else:
		_banter_timer = 0.0

	match state:
		GuardState.IDLE:
			_scan_timer += delta
			if _scan_timer >= SCAN_INTERVAL:
				_scan_timer = 0.0
				_scan_for_targets()
			if state == GuardState.IDLE and Vector2(global_position.x - home_position.x, global_position.z - home_position.z).length() > POST_RETURN_DISTANCE:
				_move_toward(home_position, POST_ARRIVAL, delta)   # a fight (or a raid) drew this guard off its post: walk back
			else:
				_apply_gravity(delta)
				velocity.x = 0.0
				velocity.z = 0.0
				if Time.get_ticks_msec() >= _face_hold_until_msec:
					rotation.y = lerp_angle(rotation.y, _home_yaw, minf(4.0 * delta, 1.0))   # and face the way it was posted (once done facing whoever hailed)
		GuardState.PATROL:
			_scan_timer += delta
			if _scan_timer >= SCAN_INTERVAL:
				_scan_timer = 0.0
				_scan_for_targets()
			if state == GuardState.PATROL:  # _scan_for_targets() may have just switched us to ENGAGE
				_process_patrol(delta)
		GuardState.ENGAGE:
			_process_engage(delta)
	if state != GuardState.ENGAGE and target_key != "":
		target_key = ""

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
	var to_target := _flat_distance(global_position, target)
	if to_target <= WAYPOINT_ARRIVAL:
		_advance_patrol()
		return
	# Watchdog: no real progress toward this waypoint for a long time (unreachable, wedged...) -> move on to the next.
	if to_target < _patrol_best_dist - PROGRESS_EPSILON:
		_patrol_best_dist = to_target
		_patrol_stall_timer = 0.0
	else:
		_patrol_stall_timer += delta
		if _patrol_stall_timer >= PATROL_STALL_SKIP:
			# Harmless (it just carries on to the next point) — noted once per waypoint, not as a warning with a stack trace.
			if not _stall_noted.has(_patrol_index):
				_stall_noted[_patrol_index] = true
				print("%s skipped patrol waypoint #%d (no progress for %d s)." % [npc_name, _patrol_index, int(PATROL_STALL_SKIP)])
			_advance_patrol()


func _advance_patrol() -> void:
	_patrol_index = (_patrol_index + 1) % _patrol_points.size()
	_patrol_best_dist = INF
	_patrol_stall_timer = 0.0
	_current_path.clear()


func _scan_for_targets() -> void:
	var is_patrolling := not _patrol_points.is_empty()
	var engage_range: float = PATROL_ENGAGE_RANGE if is_patrolling else ENGAGE_RANGE
	var origin: Vector3 = global_position if is_patrolling else home_position

	var nearest: Node = null
	var nearest_dist := engage_range
	var now_ms := Time.get_ticks_msec()
	for monster in get_tree().get_nodes_in_group("monsters"):
		if monster.get("current_state") == monster.State.DEAD:
			continue
		if int(_ignored_targets.get(monster.get_instance_id(), 0)) > now_ms:
			continue  # gave up on this one recently (couldn't reach it)
		var dist := origin.distance_to(monster.global_position)
		# During a raid a raider is engaged from much farther off (and preferred over anything that merely wandered close).
		if raid_alert_range > 0.0 and monster.is_in_group("raiders") and dist <= raid_alert_range:
			dist = minf(dist, engage_range) - 1000.0 + dist * 0.001
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
	var fighting_key := TargetFrame.target_key_of(attack_target)
	if fighting_key != target_key:
		target_key = fighting_key
	if not is_instance_valid(attack_target) or attack_target.get("current_state") == attack_target.State.DEAD:
		attack_target = null
		state = _default_state
		_current_path.clear()  # combat may have moved us off the cached patrol path — force a fresh one
		return

	var leash := LEASH_RANGE
	if raid_alert_range > 0.0 and attack_target.is_in_group("raiders"):
		leash = raid_alert_range + 15.0   # a raider drawn to the gate is chased right out to where it stands
	if _engage_origin.distance_to(attack_target.global_position) > leash:
		attack_target = null
		state = _default_state
		_current_path.clear()
		return

	var distance := global_position.distance_to(attack_target.global_position)
	if distance > ATTACK_RANGE:
		_move_toward(attack_target.global_position, ATTACK_RANGE, delta, move_speed * SPRINT_SPEED_MULTIPLIER)
		# Watchdog: chasing without getting any closer (behind a wall, across water...) -> stop, and don't pick it again for a while.
		if distance < _engage_best_dist - PROGRESS_EPSILON:
			_engage_best_dist = distance
			_engage_stall_timer = 0.0
		else:
			_engage_stall_timer += delta
			if _engage_stall_timer >= ENGAGE_STALL_GIVE_UP:
				_ignored_targets[attack_target.get_instance_id()] = Time.get_ticks_msec() + int(IGNORE_UNREACHABLE_SECONDS * 1000.0)
				attack_target = null
				state = _default_state
				_current_path.clear()
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
			and _flat_distance(global_position, _current_path[_current_path_index]) < CORNER_ARRIVAL:
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
	if _clear_or_walkable(space.intersect_ray(query)):
		return direction  # clear ahead (or just a hillside to walk up), no steering needed

	for angle_deg in OBSTACLE_AVOID_ANGLES_DEG:
		var candidate := direction.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var candidate_query := PhysicsRayQueryParameters3D.create(origin, origin + candidate * OBSTACLE_CHECK_DISTANCE)
		candidate_query.exclude = [self]
		if _clear_or_walkable(space.intersect_ray(candidate_query)):
			return candidate

	return direction  # nothing clear found — keep the original heading rather than freeze; the stuck-detector will recover if this doesn't work out


# A ray result that doesn't block: nothing hit, or a surface flat enough to walk up (a hillside on the Terrain3D ground).
func _clear_or_walkable(hit: Dictionary) -> bool:
	return hit.is_empty() or hit["normal"].y >= 0.6


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


# The server logs the fight locally and relays it, so every player near the guard reads it
# (each peer's own log window applies its 10 m combat range to the position).
func _log_fight(text: String) -> void:
	GameLog.log_combat(text, global_position)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer():
		Net.broadcast_combat_message(text, global_position)


func _perform_attack() -> void:
	can_attack = false
	attack_timer = attack_cooldown
	attack_seq += 1
	_play_attack_animation()

	if not (attack_target.get("combat_node") is CombatNode):
		return

	var target_cn: CombatNode = attack_target.combat_node
	# Raid, players nearby: harry the raider but leave it for them to finish (see raid_soften above).
	if raid_soften and attack_target.is_in_group("raiders") and target_cn.current_hp <= int(target_cn.max_hp * RAID_SOFTEN_FLOOR):
		return
	var result: Dictionary = combat_node.resolve_attack(target_cn)
	if raid_soften and attack_target.is_in_group("raiders") and target_cn.current_hp <= 0:
		target_cn.current_hp = 1   # a guard never lands the killing blow on a raider while players are there to take it
	var target_desc: String = attack_target.get("monster_description")
	if target_desc == "":
		target_desc = attack_target.get_monster_name()

	match result.get("result", ""):
		"MISS":
			_log_fight("%s misses %s!" % [npc_name, target_desc])
		"PARRY":
			_log_fight("%s's attack is parried!" % npc_name)
		"BLOCK":
			_log_fight("%s's attack is blocked!" % npc_name)
		"DODGE":
			_log_fight("%s's attack is dodged!" % npc_name)
		"RIPOSTE":
			_log_fight("%s is riposted for [b]%d[/b] damage!" % [npc_name, result.get("damage", 0)])
		"HIT":
			var crit: String = " [color=#ffaa00]Critical![/color]" if result.get("is_crit", false) else ""
			_log_fight("%s hits %s for [b]%d[/b] damage!%s" % [npc_name, target_desc, result.get("damage", 0), crit])

	if not target_cn.is_alive():
		_log_fight("[color=#88ccff]%s dispatches %s.[/color]" % [npc_name, target_desc])
		if attack_target.has_method("die"):
			attack_target.die(false, false)
		attack_target = null
		state = _default_state
		_current_path.clear()  # combat may have moved us off the cached patrol path — force a fresh one
