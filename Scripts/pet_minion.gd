# pet_minion.gd — Player-summoned pet (Voidknight's Morthan's Call skeleton warrior).
# Deliberately NOT a Monster subclass: monster3d.gd's state machine is
# hardcoded to chase/attack "the player" (get_tree().get_nodes_in_group("player")[0]),
# so reusing it here would fight that assumption at every turn. This is a small,
# independent actor instead, reusing the same CombatNode/NavigationAgent3D pattern.
extends CharacterBody3D
class_name PetMinion

# Emitted only on these two specific, voluntary/combat removals — NOT on
# tree_exited, which also fires when the whole zone (pet included) is freed
# during a scene change (/camp, /exit, Save & Exit). player3d.gd used to key
# persistence off tree_exited and that scene-teardown case fired it too,
# silently overwriting a correct "pet is still alive" save with "gone" right
# after logging out with a live pet. died additionally costs the pet's gear;
# dismissed does not.
signal died
signal dismissed

enum PetState { FOLLOW, ATTACK, SIT, GUARD, ASSIST }

const FOLLOW_DISTANCE := 4.5  # how far behind the player's facing to trail
const FOLLOW_ARRIVAL := 1.0   # tolerance around that spot before it's "close enough"
const ATTACK_RANGE := 2.5
# Faster than the player's own RUN_SPEED (8.0, player3d.gd) — the skeleton's
# base monsters.json speed (2.5 m/s) is nowhere near fast enough to keep pace
# while the player sprints, so the pet always moves at this speed (Follow,
# Guard's return-to-post, and closing distance to an Attack target alike),
# never its own "walking" pace.
const SPRINT_SPEED := 10.0
const GUARD_SCAN_RADIUS := 5.0
const GUARD_SCAN_INTERVAL := 1.0
const REGEN_INTERVAL := 6.0
# How recently the owner must have taken a hit to count as "under attack right
# now" for Follow/Guard/Assist's auto-defend reaction.
const DEFEND_REACTION_WINDOW_MS := 1500
# Same idea for Assist's "join the owner's fight" reaction — how recently the
# owner must have actually landed an attack (not just have autoattack
# toggled on) for the pet to jump in on their current target.
const ASSIST_REACTION_WINDOW_MS := 4000   # was 1500: a caster's swings/casts are further apart than that, so the pet dropped out between them
const AUTO_ENGAGE_SCAN_INTERVAL := 0.5
const GRAVITY := 20.0
const ATTACK_ANIMS := ["attack_horizontal", "attack_downward"]

var owner_player: Node = null
var command: PetState = PetState.FOLLOW
var attack_target: Node = null
var guard_position: Vector3 = Vector3.ZERO

# Command that ATTACK reverts to once its target dies or becomes invalid —
# lets auto-engagements (Guard's proximity scan, Follow/Assist's reactions
# below) return to holding position/mode instead of always defaulting to
# Follow. Also what "Back" recalls to.
var _pre_attack_command: PetState = PetState.FOLLOW
var _standing_command: PetState = PetState.FOLLOW  # last explicitly-picked Follow/Guard/Assist
var _auto_engage_timer: float = 0.0

var combat_node: CombatNode
var pet_name: String = "Skeleton Warrior"
var move_speed: float = 3.0

var can_attack: bool = true
var attack_timer: float = 0.0
var attack_cooldown: float = 2.0

var _guard_scan_timer: float = 0.0
var _fall_timer: float = 0.0
var _regen_timer: float = 0.0
var _attack_anim_timer: float = 0.0

# Gear bonuses applied on top of the base skeleton stats — kept as separate
# fields (rather than folded into combat_node directly) so re-equipping can
# just call _recalculate_stats() again without re-reading monsters.json.
var gear_weapon_damage: int = 0
var gear_armor_class: int = 0

var animation_player: AnimationPlayer = null
# Set alongside every animation_player.play() call below, replicated (see
# pet_minion.tscn/phantasmal_echo_pet.tscn's MultiplayerSynchronizer) so a
# non-authoritative peer just mirrors whatever animation the owning player's
# own client decided, instead of running its own (removed) AI to decide.
var anim_state: String = ""
var _base_stats: Dictionary = {}

# Fraction of the owner's max_hp this pet spawns with — set by player3d.gd's
# _build_pet() (PET_HP_PERCENT_OVERRIDES) before setup() runs, for a stronger
# variant that reuses this same scene/model (e.g. Gravecaller's raise_skeleton
# vs. Voidknight's spectral_minion — same skeleton thrall, just tankier per
# its own spell description). Left as a plain default rather than an
# overridden method since every use so far is "the same pet, different
# number," not different construction logic.
var hp_percent_of_caster: float = 0.4

# Self-managed NavigationServer3D.query_path() movement — NavigationAgent3D's
# get_next_path_position() was found to go stale over distance/after external
# repositioning (see guard_npc.gd's patrol and player3d.gd's /follow, both
# rewritten for the same reason). Follow/guard/attack all funnel through
# _move_toward() below, so fixing it here covers all three commands at once.
const REPATH_INTERVAL := 0.75
const WAYPOINT_EPSILON := 0.4
# Only forces an immediate repath on a big, discontinuous jump in the desired
# destination (e.g. switching from "walk to the dead monster" back to "walk
# to the player" the instant combat ends) — NOT on the player's own continuous
# walking drift during a normal Follow, which can cover several meters between
# the 0.75s timer's own repaths at sprint speed and should just ride that
# timer instead of re-querying the nav server on nearly every frame.
const RETARGET_THRESHOLD := 8.0
var _nav_path: Array = []
var _nav_path_target: Vector3 = Vector3.ZERO
var _repath_timer: float = 0.0

# Local obstacle steering + stuck-recovery, ported from guard_npc.gd after the
# pet was found getting wedged on town-area props the baked navmesh doesn't
# cleanly route around — a fresh path alone isn't enough when the obstacle
# itself sits ON the path, so this casts a short ray ahead and sidesteps
# around anything it hits, with the stuck timer as a fallback that forces a
# full repath if sidestepping still isn't enough.
const OBSTACLE_CHECK_DISTANCE := 1.5
const OBSTACLE_AVOID_ANGLES_DEG := [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]
const STUCK_THRESHOLD := 2.0
const STUCK_MOVE_EPSILON := 0.1
var _stuck_timer: float = 0.0
var _last_stuck_check_pos: Vector3 = Vector3.ZERO
var _stuck_repath_requested: bool = false

# Escape hatch for a genuine navmesh gap/seam at a specific spot (confirmed via
# temporary debug logging: the pet froze at nearly the same world coordinates
# twice, on open flat ground with nothing to obstruct it — not a caching or
# logic bug, an actual hole in the baked navmesh that no amount of repathing fixes).
# If the stuck-detector fires twice in a row without the pet actually moving,
# it stops trusting the navmesh path for a few seconds and just walks straight
# at the target (still using the obstacle raycast for real collision), which
# gets it across a small gap the navmesh doesn't cover.
const DIRECT_FALLBACK_MS := 4000
var _consecutive_stuck_count: int = 0
var _direct_fallback_until_ms: int = 0


# Layer 7 (bit value 64): "solid world geometry only" — see setup() below for why the pet's own collision_mask is set to
# exactly this, instead of the default (layer 1, shared by players/guards/pets/world alike).
const WORLD_ONLY_MASK := 1 << 6


func _ready() -> void:
	_setup_visual()


# Uses the Voidknight's dedicated Skeleton Pet model/animations (added
# 2026-09-15) instead of the generic humanoid mob model skeletons/bandits
# still share. Only idle/walk/attack_horizontal/attack_downward/death exist
# for this model (no jump/sit/run — _update_animation() here never plays
# those).
func _setup_visual() -> void:
	# Re-rigged 2026-09-18 ("Version 2" — new mesh/texture/animation set).
	# No new death clip was provided this time, so skeleton_pet_animations.res
	# reuses the original folder's "Skeleton Pet Standing Death Forward 01.fbx"
	# alongside the new idle/walk/attack clips.
	var character_scene := load("res://models/Skeleton Pet/Meshy_AI_voidknight_skeleton_h_biped_Character_output.fbx")
	if not character_scene:
		return
	var character: Node3D = character_scene.instantiate()
	character.name = "Character"
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)
	add_child(character)

	animation_player = character.get_node("AnimationPlayer")
	var lib := load("res://models/Skeleton Pet/skeleton_pet_animations.res") as AnimationLibrary
	if lib and animation_player:
		if animation_player.has_animation_library(""):
			animation_player.remove_animation_library("")
		animation_player.add_animation_library("", lib)

	_apply_texture_override(character, "res://models/Skeleton Pet/Meshy_AI_voidknight_skeleton_h_biped_texture_0.png")


# Meshy-sourced FBX exports never carry their real texture through to Godot
# reliably (confirmed recurring bug across every model built this way), so
# apply it as a runtime material override instead of trusting the FBX's own
# material.
func _apply_texture_override(node: Node, texture_path: String) -> void:
	var tex := load(texture_path) as Texture2D
	if not tex:
		push_warning("⚠️ Pet texture override not found: %s" % texture_path)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	_apply_material_recursive(node, mat)


func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_material_recursive(child, mat)


# Overridden by phantasmal_echo_pet.gd — the TitleLabel subtitle text is
# "<OwnerName's %s>" for whatever this returns.
func _pet_title() -> String:
	return "risen minion"


func _pick_random_name() -> String:
	var file := FileAccess.open("res://Data/pet_names.json", FileAccess.READ)
	if not file:
		return "Skeleton Warrior"
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	var names: Array = result.get("names", []) if typeof(result) == TYPE_DICTIONARY else []
	if names.is_empty():
		return "Skeleton Warrior"
	return names[randi() % names.size()]


func setup(p_owner: Node, preset_name: String = "") -> void:
	owner_player = p_owner
	global_position = p_owner.global_position + p_owner.global_transform.basis.x * 1.5
	guard_position = global_position

	# The pet no longer physically collides with players (owner or party) — found 2026-09-21: in a tight melee (everyone wanting
	# to be within ~2.5m of the same target) there just isn't always room to route AROUND a body via the raycast steering above,
	# and the pet would end up permanently a step short of its own attack range, physically wedged against whoever was closest.
	# collision_layer stays the default (1) — monsters, world, anything else that currently detects a pet on layer 1 is
	# unaffected — but collision_mask becomes WORLD_ONLY_MASK: the pet's OWN move_and_slide only resolves against bodies on
	# THAT bit, which only real solid geometry carries (see lumora_outskirts3d.tscn's LumoraOutskirts_Collision:
	# collision_layer = 65 = 1 | WORLD_ONLY_MASK — the +1 keeps it detectable by everything that already expected world
	# geometry on layer 1, e.g. monster3d.gd's own mask). Players/pets/guards were never retagged, so this excludes them from
	# the pet's own collision resolution while leaving the ground/walls fully solid. ANY NEW ZONE'S terrain StaticBody3D MUST
	# be tagged the same way (collision_layer = 65, or at minimum include WORLD_ONLY_MASK) or a pet there will fall through the
	# floor — if that's ever missed, _tick_fall_recovery() below is the safety net that brings it back rather than losing it.
	# The raycast-based obstacle steering (_ray_blocked) is untouched and independent of this: it still "sees" players and
	# steers around them whenever there is room to, this only removes the HARD physical block when there is not.
	collision_mask = WORLD_ONLY_MASK
	pet_name = preset_name if not preset_name.is_empty() else _pick_random_name()
	if has_node("NameLabel"):
		$NameLabel.text = pet_name
	if has_node("TitleLabel"):
		var owner_name: String = p_owner.player_name if "player_name" in p_owner else "Someone"
		$TitleLabel.text = "<%s's %s>" % [owner_name, _pet_title()]

	var stats := _load_skeleton_stats()
	_base_stats = stats

	combat_node = CombatNode.new()
	combat_node.name = "CombatNode"
	add_child(combat_node)
	combat_node.level = p_owner.combat_node.level
	combat_node.strength     = 0
	combat_node.constitution = 0
	combat_node.dexterity    = 0
	combat_node.intelligence = 0
	combat_node.wisdom       = 0
	combat_node.charisma     = 0
	combat_node.luck         = 0

	# Default 40% of caster's health per the spectral_minion spell description
	# — see hp_percent_of_caster's doc comment for how a stronger variant
	# (e.g. Gravecaller's raise_skeleton at 80%) overrides this.
	var pet_max_hp: int = max(1, int(p_owner.combat_node.max_hp * hp_percent_of_caster))
	combat_node.gear_hp = pet_max_hp - 50
	combat_node.gear_atk = 15 + combat_node.level * 5
	_recalculate_stats()
	combat_node.current_hp = combat_node.max_hp

	move_speed = SPRINT_SPEED

	add_to_group("pets")


# Called by player3d.gd's _summon_spectral_minion() right after setup(), and
# again any time pet gear changes while this instance is alive — see
# equip_to_pet()/unequip_from_pet() in player3d.gd.
func apply_gear_bonus(weapon_dmg: int, armor_ac: int) -> void:
	gear_weapon_damage = weapon_dmg
	gear_armor_class = armor_ac
	_recalculate_stats()


func _recalculate_stats() -> void:
	if not combat_node:
		return
	combat_node.weapon_damage = _base_stats.get("damage", 12) + gear_weapon_damage
	var base_armor_class: int = _base_stats.get("armor_class", 10)
	combat_node.gear_ac = (base_armor_class - 10) + gear_armor_class
	combat_node._stats_dirty = true
	combat_node.recalculate_derived_stats()


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

	# Non-authoritative peers (every client but the pet's own owner, in
	# multiplayer — always true in single-player, same authority-gating
	# pattern as player3d.gd/monster3d.gd) never run AI/combat/movement here:
	# they just mirror replicated position/rotation/anim_state, same as a
	# replicated monster puppet. queue_free() on the owner's client (death,
	# dismiss) propagates removal to every peer automatically via the
	# MultiplayerSpawner this pet was spawned through.
	if not is_multiplayer_authority():
		_play_replicated_animation()
		return

	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0.0:
			can_attack = true

	if _attack_anim_timer > 0.0:
		_attack_anim_timer -= delta

	_process_regen(delta)

	match command:
		PetState.FOLLOW:
			if not _maintain_min_owner_distance(delta):
				_move_toward(_follow_spot(), FOLLOW_ARRIVAL, delta)
			_process_auto_engage(delta, false)
		PetState.ASSIST:
			if not _maintain_min_owner_distance(delta):
				_move_toward(_follow_spot(), FOLLOW_ARRIVAL, delta)
			_process_auto_engage(delta, true)
		PetState.ATTACK:
			_process_attack(delta)
		PetState.SIT:
			_apply_gravity(delta)
			velocity.x = 0.0
			velocity.z = 0.0
		PetState.GUARD:
			if not _maintain_min_owner_distance(delta):
				_move_toward(guard_position, 0.5, delta)
			_process_guard(delta)
			_process_auto_engage(delta, false)

	move_and_slide()
	if command != PetState.ATTACK and command != PetState.SIT:
		_face_nearest_enemy_if_idle()
	_update_animation()
	if has_node("NameLabel"):
		$NameLabel.visible = Global.settings.get("show_name_tags", true)


func _update_animation() -> void:
	if not animation_player or animation_player.get_animation_list().is_empty():
		return
	if _attack_anim_timer > 0.0:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	var anim_name := "walk" if moving else "idle"
	anim_state = anim_name  # replicated to non-authoritative peers — see _play_replicated_animation()
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, 0.15)


# Non-authoritative peers never run _update_animation()/_play_attack_animation()
# (no local AI to decide with) — they just mirror whatever anim_state the
# owning player's own client replicated out, same pattern as player3d.gd's
# own puppet branch / monster3d.gd's replicated monsters.
func _play_replicated_animation() -> void:
	if not animation_player or animation_player.get_animation_list().is_empty():
		return
	if animation_player.current_animation != anim_state and animation_player.has_animation(anim_state):
		animation_player.play(anim_state, 0.15)


func _play_attack_animation() -> void:
	if not animation_player or animation_player.get_animation_list().is_empty():
		return
	var anim_name: String = ATTACK_ANIMS[randi() % ATTACK_ANIMS.size()]
	anim_state = anim_name  # replicated — see _play_replicated_animation()
	animation_player.play(anim_name, 0.1)
	_attack_anim_timer = animation_player.get_animation(anim_name).length


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_tick_fall_recovery(delta)
	else:
		velocity.y = 0.0
		_fall_timer = 0.0


# Safety net for a genuine off-navmesh drop (a cliff edge, a gap the baked navmesh doesn't cover) — chasing straight at a moving
# target's exact position (see _process_attack()) can walk the pet off one the same way a player could, and with nothing below
# it, is_on_floor() never becomes true again and velocity.y grows without limit: the pet would otherwise fall forever, lost.
# Found in a live-server test: a pet chasing a boss that wandered near map geometry fell to y=-55000+ over about a minute and
# was never seen again. After falling this long uninterrupted, it teleports back to the owner instead.
const FALL_RECOVERY_SECONDS := 4.0

func _tick_fall_recovery(delta: float) -> void:
	_fall_timer += delta
	if _fall_timer < FALL_RECOVERY_SECONDS:
		return
	_fall_timer = 0.0
	if not is_instance_valid(owner_player):
		return
	global_position = owner_player.global_position + owner_player.global_transform.basis.x * 1.5
	velocity = Vector3.ZERO
	_nav_path.clear()
	_say("...falls back in beside you, having gone somewhere it shouldn't have.")


# A point FOLLOW_DISTANCE behind wherever the player is currently facing,
# rather than just "the player's position" with a stop-radius around it — the
# old approach let the pet approach from any angle and could end up nose-to-
# nose with (or clipped into) the player before the radius check kicked in.
#
# Snapped onto the navmesh before returning: the raw "behind" point is a
# free-floating offset that can easily land inside a wall, off a ledge, or
# past a doorway edge in dense town geometry. Pathing to an off-navmesh point
# ends at the nearest reachable spot to it, which can still be farther than
# FOLLOW_ARRIVAL away — the pet then perpetually believes it still needs to
# move but can never close that last bit, a real dead end (not a caching
# issue), which is exactly why re-issuing Follow didn't help: as long as the
# player stands in the same spot, the freshly computed "behind" point hits
# the same wall every time.
# Arriving at the follow spot (FOLLOW_DISTANCE behind the player's facing)
# via navmesh pathing can route the pet in an arc that passes close by or
# through the player's own collision capsule while re-routing, reading as
# stuttering. Checked first, every frame, ahead of any pathing: if already
# closer than this to the owner, just steer straight away from them instead
# of computing a path at all, taking priority over Follow/Assist/Guard's
# normal destination until clear. Returns true when it took over movement
# this frame (caller should skip its own _move_toward() call).
# Kept well below FOLLOW_DISTANCE minus FOLLOW_ARRIVAL (its old value equaled
# FOLLOW_DISTANCE exactly) — the pet's normal resting zone around the follow
# spot used to straddle this exact threshold, so ordinary navmesh-snap slop
# made it flicker between "arrived, stop" and "too close, push away" every
# few frames — the real cause of the reported stutter, not turning-in-place
# (that was a separate, already-fixed issue — see _follow_spot()'s caching).
const MIN_OWNER_DISTANCE := 2.0

func _maintain_min_owner_distance(delta: float) -> bool:
	if not is_instance_valid(owner_player):
		return false
	var away: Vector3 = global_position - owner_player.global_position
	away.y = 0.0
	var dist := away.length()
	if dist >= MIN_OWNER_DISTANCE or dist < 0.001:
		return false

	_apply_gravity(delta)
	var dir := away.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	look_at(global_position + dir, Vector3.UP)
	_nav_path.clear()
	return true


# Cosmetic only — a pet standing around in Follow/Assist/Guard (not actively
# moving this frame) turns to face whatever living monster is nearest, within
# AWARENESS_RADIUS, so it visibly reacts to a threat wandering close instead
# of staring at whatever direction it happened to stop facing. Never called
# while Attack (already faces its real target) or Sit (should just sit).
const AWARENESS_RADIUS := 15.0

func _face_nearest_enemy_if_idle() -> void:
	if Vector2(velocity.x, velocity.z).length() >= 0.1:
		return
	var nearest: Node = null
	var nearest_dist := AWARENESS_RADIUS
	for monster in get_tree().get_nodes_in_group("monsters"):
		if not _target_alive(monster):
			continue
		var d := global_position.distance_to(monster.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = monster
	if not nearest:
		return
	var to_target: Vector3 = nearest.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > 0.1:
		look_at(global_position + to_target.normalized(), Vector3.UP)


# Only recomputed once the owner has actually moved FOLLOW_SPOT_REFRESH_DIST
# since the last update — recomputing every frame from the owner's current
# facing meant simply turning in place (no translation at all) swept the
# "behind them" point in an arc, and the pet would chase it as if the owner
# had walked somewhere. Standing still and spinning now leaves the pet alone;
# it only repositions once the owner actually walks away.
const FOLLOW_SPOT_REFRESH_DIST := 0.5
var _cached_follow_spot: Vector3 = Vector3.ZERO
var _follow_spot_owner_pos: Vector3 = Vector3.ZERO
var _follow_spot_initialized: bool = false

func _follow_spot() -> Vector3:
	if _follow_spot_initialized and owner_player.global_position.distance_to(_follow_spot_owner_pos) <= FOLLOW_SPOT_REFRESH_DIST:
		return _cached_follow_spot

	var forward: Vector3 = -owner_player.global_transform.basis.z.normalized()
	var raw_spot: Vector3 = owner_player.global_position - forward * FOLLOW_DISTANCE
	var snapped: Vector3 = raw_spot
	if is_inside_tree():
		var map_rid: RID = get_world_3d().navigation_map
		var s: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, raw_spot)
		snapped = s if s != Vector3.ZERO else raw_spot

	_cached_follow_spot = snapped
	_follow_spot_owner_pos = owner_player.global_position
	_follow_spot_initialized = true
	return _cached_follow_spot


# `dodge_owner`: true routes around the owner's own body like any other obstacle instead of ignoring it — used while chasing an
# enemy (ATTACK), where the owner is neither the destination nor (with Assist in particular) unlikely to be standing between the
# pet and its target. Follow/Guard/the owner-proximity catch-up movement always pass false: there the owner often IS the
# destination (or right next to it), and dodging them there is either meaningless or actively wrong.
func _move_toward(target_pos: Vector3, stop_distance: float, delta: float, dodge_owner: bool = false) -> void:
	_apply_gravity(delta)
	_tick_stuck_detector(delta)

	if global_position.distance_to(target_pos) <= stop_distance:
		velocity.x = 0.0
		velocity.z = 0.0
		_nav_path.clear()
		return

	var direct_fallback_active := Time.get_ticks_msec() < _direct_fallback_until_ms

	if not direct_fallback_active:
		_repath_timer -= delta
		var need_repath := _repath_timer <= 0.0 or _nav_path.is_empty() or _stuck_repath_requested \
			or _nav_path_target.distance_to(target_pos) > RETARGET_THRESHOLD
		if need_repath:
			_stuck_repath_requested = false
			_repath_timer = REPATH_INTERVAL
			_recompute_nav_path(target_pos)

		while _nav_path.size() > 1 and global_position.distance_to(_nav_path[0]) < WAYPOINT_EPSILON:
			_nav_path.remove_at(0)

	# While the fallback is armed, ignore the cached path entirely and walk
	# straight at the real target — see DIRECT_FALLBACK_MS above.
	var next_position: Vector3 = target_pos if direct_fallback_active or _nav_path.is_empty() else _nav_path[0]
	var to_next: Vector3 = next_position - global_position
	var flat_dir := Vector3(to_next.x, 0.0, to_next.z)
	if flat_dir.length() < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var direction := flat_dir.normalized()
	direction = _steer_around_obstacles(direction)
	look_at(global_position + direction, Vector3.UP)
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed


# Detects "hasn't actually moved in a while despite trying to" and forces a
# fresh repath next _move_toward() call.
func _tick_stuck_detector(delta: float) -> void:
	if global_position.distance_to(_last_stuck_check_pos) > STUCK_MOVE_EPSILON:
		_stuck_timer = 0.0
		_last_stuck_check_pos = global_position
		_consecutive_stuck_count = 0
		return
	_stuck_timer += delta
	if _stuck_timer < STUCK_THRESHOLD:
		return
	_stuck_timer = 0.0
	_last_stuck_check_pos = global_position
	_stuck_repath_requested = true
	_consecutive_stuck_count += 1

	if _consecutive_stuck_count >= 2:
		_direct_fallback_until_ms = Time.get_ticks_msec() + DIRECT_FALLBACK_MS


# Short forward raycast; if something's directly ahead, try a handful of
# alternate headings and take the first one that's actually clear.
func _steer_around_obstacles(direction: Vector3, dodge_owner: bool = false) -> Vector3:
	if not is_inside_tree():
		return direction
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 0.9, 0)

	if not _ray_blocked(space, origin, direction, dodge_owner):
		return direction

	for angle_deg in OBSTACLE_AVOID_ANGLES_DEG:
		var candidate := direction.rotated(Vector3.UP, deg_to_rad(angle_deg))
		if not _ray_blocked(space, origin, candidate, dodge_owner):
			return candidate

	return direction


# A hit only counts as a real obstacle to dodge if its surface is fairly
# vertical (a wall or prop) — a shallow-angle hit is just rising ground (dune
# slopes, ramps), and treating that as an "obstacle" made the pet zigzag
# constantly on any open terrain with a slope, cutting its effective speed
# well below move_speed and letting the player outrun it.
func _ray_blocked(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, dodge_owner: bool = false) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * OBSTACLE_CHECK_DISTANCE)
	# The owner is excluded from being flagged as an "obstacle" by default — Follow/Guard end up right next to them (often
	# closer than a dodge-and-detour would ever settle for), so a route that grazes their collision capsule shouldn't be
	# dodged, or worse, get the pet stuck endlessly trying to route around a body that IS (or is right next to) the
	# destination. When chasing an enemy instead (dodge_owner=true — see _move_toward()), the owner is neither the
	# destination nor unlikely to be standing in the way (Assist puts the pet right where the owner is already fighting), so
	# the owner is treated like anyone else this pet isn't its own — a real body to walk around rather than push against.
	# The pet itself is always excluded, and other players/pets/NPCs were never excluded, so this already worked for a party
	# member standing in the way; only the owner's own special case needed narrowing.
	query.exclude = [self] if (dodge_owner or not is_instance_valid(owner_player)) else [self, owner_player]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return false
	var normal: Vector3 = result.get("normal", Vector3.UP)
	return absf(normal.y) < 0.6


func _recompute_nav_path(target_pos: Vector3) -> void:
	_nav_path.clear()
	_nav_path_target = target_pos
	if not is_inside_tree():
		return
	var query := NavigationPathQueryParameters3D.new()
	query.map = get_world_3d().navigation_map
	query.start_position = global_position
	query.target_position = target_pos
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	for p in result.path:
		_nav_path.append(p)
	if _nav_path.size() > 1:
		_nav_path.remove_at(0)  # path[0] is just our own current position


func _process_attack(delta: float) -> void:
	if not is_instance_valid(attack_target) or not _target_alive(attack_target):
		attack_target = null
		command = _pre_attack_command
		return

	var distance := global_position.distance_to(attack_target.global_position)
	if distance > ATTACK_RANGE:
		# Straight at the target's own position (same pattern as GuardNPC.gd's chase), not a flank spot behind it — a flank spot is
		# recomputed every frame from the target's FACING, so against an enemy that is turning (chasing the player, as most do) that spot
		# orbits it in a circle. The pet then chased the circling point instead of the enemy and could go the whole rest of a fight
		# without ever landing within its own attack range: it stood still in Attack mode, never swinging ("the pet keeps dropping out of
		# attacking"). Reproduced headlessly against a turning boss and confirmed fixed the same way.
		_move_toward(attack_target.global_position, ATTACK_RANGE * 0.85, delta, true)
		return

	_apply_gravity(delta)
	velocity.x = 0.0
	velocity.z = 0.0
	look_at(attack_target.global_position, Vector3.UP)

	if can_attack:
		_perform_attack()


# target.State.DEAD (a Monster-only enum) used to crash outright the moment
# this was ever called with a non-Monster target — e.g. _process_auto_engage()
# below calls this on owner_player.current_target before confirming it's
# actually a monster, so simply targeting anything else (the pet itself, to
# heal it; another player) crashed instantly. combat_node.is_alive() is the
# same "is this thing actually dead" check every entity type here already
# supports (Monster, Player3D, PetMinion alike), so it works generically
# instead of assuming the target's concrete type.
func _target_alive(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	var cn = target.get("combat_node") if "combat_node" in target else null
	if cn is CombatNode:
		return cn.is_alive()
	return true


# ── Ranged pets (Phantasmal Echo, Wildspeaker's spirit): the projectile ─────────────────────────────────────────────
# Launches the pet's bolt. The pet owner's machine (the pet's multiplayer authority) makes the bolt that actually
# deals `dmg` on impact and tells every OTHER player to show a visual-only copy, so the shot is seen by everyone —
# before this the bolt was a local node that only the owner ever saw.
func _launch_bolt(target: Node, dmg: int, color: Color) -> void:
	_spawn_bolt(target, dmg, color, false, Vector3.ZERO)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and is_multiplayer_authority() and is_instance_valid(target):
		_rpc_show_bolt.rpc(target.get_path(), target.global_position + Vector3(0, 1.0, 0), color)


func _spawn_bolt(target: Node, dmg: int, color: Color, visual_only: bool, fixed_pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var bolt: SpectralBolt = load("res://Scenes/spectral_bolt.tscn").instantiate()
	bolt.bolt_color = color
	bolt.visual_only = visual_only
	bolt.fixed_target = fixed_pos
	bolt.target = target
	bolt.damage = dmg
	bolt.source_pet = self
	scene.add_child(bolt)
	bolt.global_position = global_position + Vector3(0, 1.1, 0)


@rpc("authority", "call_remote", "unreliable")
func _rpc_show_bolt(target_path: NodePath, target_pos: Vector3, color: Color) -> void:
	_spawn_bolt(get_node_or_null(target_path), 0, color, true, target_pos)


func _perform_attack() -> void:
	can_attack = false
	attack_timer = attack_cooldown
	_play_attack_animation()

	if not (attack_target.get("combat_node") is CombatNode):
		return

	var target_cn: CombatNode = attack_target.combat_node
	var result: Dictionary = combat_node.resolve_attack(target_cn)

	# Multiplayer: relay real damage to whoever actually owns this monster's
	# authoritative combat_node — same reasoning as player3d.gd's own melee/
	# spell relays. Credits the KILL (if any) to the pet's owner, not the pet
	# itself (pets have no save data of their own to grant XP into).
	var target_is_networked_monster: bool = attack_target is Monster and not attack_target.is_multiplayer_authority()
	if target_is_networked_monster and result.get("damage", 0) > 0 and is_instance_valid(owner_player):
		attack_target.apply_networked_damage.rpc_id(1, result["damage"], owner_player.get_multiplayer_authority())

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
		# Networked monster's own death/removal/XP-credit already happens
		# server-side once the relayed damage above lands.
		if not target_is_networked_monster and attack_target.has_method("die"):
			attack_target.die()
		attack_target = null
		command = _pre_attack_command


# Same EQ-style 6s tick as the player (player3d.gd's REGEN_INTERVAL) — regens
# passively in any state, at 3x rate while sitting, same multiplier the
# player gets.
func _process_regen(delta: float) -> void:
	_regen_timer += delta
	if _regen_timer < REGEN_INTERVAL:
		return
	_regen_timer = 0.0
	if combat_node.current_hp >= combat_node.max_hp:
		return
	var regen: int = combat_node.get_derived_stat("hp_regen")
	if command == PetState.SIT:
		regen = int(regen * 3.0)
	combat_node.current_hp = mini(combat_node.current_hp + regen, combat_node.max_hp)


func _process_guard(delta: float) -> void:
	_guard_scan_timer += delta
	if _guard_scan_timer < GUARD_SCAN_INTERVAL:
		return
	_guard_scan_timer = 0.0

	# Pure proximity to the held guard point — any living monster that wanders
	# within range gets engaged, whether or not it's already attacking anyone.
	for monster in get_tree().get_nodes_in_group("monsters"):
		if not _target_alive(monster):
			continue
		if guard_position.distance_to(monster.global_position) <= GUARD_SCAN_RADIUS:
			_engage(monster)
			return


# Two reactive triggers, checked from Follow/Guard/Assist alike (never while
# already fighting): "defend" — the owner was just hit, so attack whatever hit
# them — and, only when assist_mode is true (the Assist command), "join in" —
# the owner is actively fighting something themselves, so pile on the same
# target. Both reuse existing state rather than needing new signals: defend
# reads player3d.gd's last_damage_time_ms + current_target (already kept in
# sync by _register_attacker() whenever the player takes a hit), and assist
# reads the player's own autoattack_enabled + current_target.
func _process_auto_engage(delta: float, assist_mode: bool) -> void:
	_auto_engage_timer += delta
	if _auto_engage_timer < AUTO_ENGAGE_SCAN_INTERVAL:
		return
	_auto_engage_timer = 0.0
	if not is_instance_valid(owner_player):
		return

	var recently_hit: bool = "last_damage_time_ms" in owner_player \
		and Time.get_ticks_msec() - owner_player.last_damage_time_ms < DEFEND_REACTION_WINDOW_MS
	if recently_hit:
		var attacker: Node = owner_player.get("current_target")
		if is_instance_valid(attacker) and _target_alive(attacker) and attacker.is_in_group("monsters"):
			_engage(attacker)
			return

	# Requires the owner to have actually just attacked, not merely that
	# autoattack_enabled is true — that toggle is sticky across target
	# changes, so simply clicking a new target while it was already on from a
	# previous fight used to make the pet jump in before the owner had done
	# anything to the new target themselves. last_attack_time_ms is set at
	# every real attack action (autoattack swing, melee_attack key, damaging
	# spell cast), so this now genuinely means "I just attacked," not "I
	# have attacking toggled on and something is selected."
	if assist_mode and "last_attack_time_ms" in owner_player \
			and Time.get_ticks_msec() - owner_player.last_attack_time_ms < ASSIST_REACTION_WINDOW_MS:
		var owner_target: Node = owner_player.get("current_target")
		if is_instance_valid(owner_target) and _target_alive(owner_target) and owner_target.is_in_group("monsters"):
			_engage(owner_target)


func _engage(target: Node) -> void:
	attack_target = target
	_pre_attack_command = _standing_command
	command = PetState.ATTACK


# ── Commands (called by pet_frame.gd's UI buttons) ─────────────────────────────
# Each prints a short flavor line in the pet's "voice" (GameLog.log_general),
# distinct from GameLog.log_combat's attack-resolution lines above.

func _say(line: String) -> void:
	GameLog.log_general("[color=#aa88ff]%s says, \"%s\"[/color]" % [pet_name, line])


# Command flavor lines, one overridable function per command — same override
# pattern as _pet_title()/_pick_random_name() above. Base text here is the
# original Voidknight skeleton thrall's voice ("dark lord"/"master"); a
# subclass for a different class's pet (e.g. phantasmal_echo_pet.gd's
# benevolent spirit guardian) overrides whichever lines don't fit instead of
# duplicating the cmd_*() state-management logic below just to change text.
func _phrase_attack(target_desc: String) -> String:
	return "I will destroy %s master!" % target_desc

func _phrase_follow() -> String:
	return "I will stay close and guard you, dark lord."

func _phrase_sit() -> String:
	return "Retiring for a bit..."

func _phrase_guard() -> String:
	return "I will protect this area from your enemies, m'lord"

func _phrase_assist() -> String:
	return "I will join your fight, master."

func _phrase_dismiss() -> String:
	return "Until I can be of assistance again. Farewell, master."


func cmd_attack(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		GameLog.log_general("%s has no target to attack." % pet_name)
		return
	var target_desc: String = target.get("monster_description")
	if target_desc == "":
		target_desc = target.get_monster_name() if target.has_method("get_monster_name") else str(target.name)
	_engage(target)
	_say(_phrase_attack(target_desc))


# Immediately breaks off combat and returns to whichever of Follow/Guard/
# Assist was last explicitly chosen — distinct from Follow itself now that
# Follow no longer doubles as a "stop attacking" button.
func cmd_back() -> void:
	attack_target = null
	command = _standing_command
	_say(_phrase_follow())


func cmd_follow() -> void:
	attack_target = null
	command = PetState.FOLLOW
	_standing_command = PetState.FOLLOW
	_persist_mode()
	_say(_phrase_follow())


func cmd_sit() -> void:
	attack_target = null
	command = PetState.SIT
	_persist_mode()
	_say(_phrase_sit())


func cmd_guard() -> void:
	attack_target = null
	guard_position = global_position
	command = PetState.GUARD
	_standing_command = PetState.GUARD
	_persist_mode()
	_say(_phrase_guard())


# Replaces the old Stop button — rather than just standing down, the pet now
# shadows whatever the player is fighting.
func cmd_assist() -> void:
	attack_target = null
	command = PetState.ASSIST
	_standing_command = PetState.ASSIST
	_persist_mode()
	_say(_phrase_assist())


# Saves whichever of Follow/Guard/Assist/Sit was last picked (never ATTACK —
# that's transient) so the pet resumes the same mode on the next login instead
# of always defaulting back to Follow. Mirrors pet_active/pet_name's own
# persistence in player3d.gd's _summon_spectral_minion()/_restore_pet_if_saved().
func _persist_mode() -> void:
	Global.player_data["pet_mode"] = command
	Global.save_player_data_to_file()


# The owner died and woke at their bind point: the pet appears beside them at once (it used to walk the whole way back),
# stops fighting, and every monster near where it was forgets it (so nothing chases it to town).
func recall_to_owner() -> void:
	if not is_instance_valid(owner_player):
		return
	var was_at := global_position
	for monster in get_tree().get_nodes_in_group("monsters"):
		if is_instance_valid(monster) and monster is Node3D and (monster as Node3D).global_position.distance_to(was_at) <= 40.0:
			if monster.is_multiplayer_authority():
				monster.forget_attacker(get_path())
			elif Net.is_multiplayer_game and multiplayer.has_multiplayer_peer():
				monster.forget_attacker.rpc_id(1, get_path())
	attack_target = null
	if command == PetState.ATTACK:
		command = _standing_command
	global_position = owner_player.global_position + owner_player.global_transform.basis.x * 1.5
	velocity = Vector3.ZERO
	guard_position = global_position
	_nav_path.clear()
	_fall_timer = 0.0


# Voluntary desummon — distinct from die() (no combat, no "dissipates" line).
func cmd_dismiss() -> void:
	_say(_phrase_dismiss())
	dismissed.emit()
	queue_free()


# ── Damage / death ──────────────────────────────────────────────────────────────
# monster3d.gd's aggro_table can put the pet ahead of the player in threat
# (see add_threat() calls above), so monsters really can target and kill it.

func apply_damage(amount: int, _damage_type: String = "physical") -> void:
	combat_node.take_damage(amount)
	if not combat_node.is_alive():
		die()


func die() -> void:
	GameLog.log_general("[color=#888888]%s dissipates.[/color]" % pet_name)
	died.emit()
	queue_free()
