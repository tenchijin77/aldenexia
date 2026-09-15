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
const MAX_AGGRO_DISTANCE: float = 5.0   # Hard cap: monsters never *notice* the player by sight beyond this many meters (can_see_player()) — once aggroed (by sight, or by taking damage/threat from any range, e.g. a spell pull), there is no leash — see state_chase()
const CHASE_SPEED_MULTIPLIER: float = 2.0  # only while actively chasing (not patrolling) — see handle_movement()
const ASSIST_RANGE: float = 5.0  # call_nearby_allies() — real meters, see the fix note there

# Humanoid-shaped mob types get the same Mixamo character model/animations as
# the player and guards instead of the generic placeholder box, swapped in at
# runtime by _setup_humanoid_visual() — see monster_template.tscn, which is
# shared by every mob type and keeps the box as the default/fallback visual.
const HUMANOID_MOB_TYPES: Array = ["bandit", "skeleton", "goblin"]
const ATTACK_ANIMS := ["attack_horizontal", "attack_downward"]

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

@export_group("Appraisal")  # display-only data for player3d.gd's Insight Check
@export var resistances: Array = []
@export var weaknesses: Array = []
@export var special_ability: String = ""
@export var is_boss: bool = false
@export var secret_note: String = ""
@export var corruption: String = ""

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
const IDLE_MIN_DURATION: float = 2.0  # how long a non-passive monster waits in IDLE before patrolling
const IDLE_MAX_DURATION: float = 5.0
var _idle_timer: float = 0.0
var _idle_duration: float = 3.0

# ===== AGGRO / THREAT =====
# Node -> accumulated threat. Populated by add_threat() whenever the player
# or their pet deals damage/heals near this monster (see
# player3d.gd:attack_current_target()/cast_spell(), pet_minion.gd's attack).
# Initial engagement is still purely proximity-based (can_see_player(),
# unchanged) — this table only decides WHO gets attacked once already
# fighting, so a stance's threat_mult (Shadow Ascendant/Necrotic Bastion)
# actually has something to influence. Guards are deliberately never part of
# this — monsters still can't target them (see guard_npc.gd's one-directional
# combat note).
var aggro_table: Dictionary = {}

# ===== NAVIGATION =====
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Only set for HUMANOID_MOB_TYPES — see _setup_humanoid_visual()
var animation_player: AnimationPlayer = null
var _attack_anim_timer: float = 0.0

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

		# Appraisal (display-only)
		resistances     = stats.get("resistances", resistances)
		weaknesses      = stats.get("weaknesses", weaknesses)
		special_ability = stats.get("special_ability", special_ability)
		is_boss         = stats.get("is_boss", is_boss)
		secret_note     = stats.get("secret_note", secret_note)
		corruption      = stats.get("corruption", corruption)

	if monster_name in HUMANOID_MOB_TYPES:
		_setup_humanoid_visual()

	combat_node = CombatNode.new()
	add_child(combat_node)
	_configure_combat_node()

	spawn_position = global_position
	patrol_target = spawn_position

	# Configure NavigationAgent
	if is_inside_tree() and nav_agent:
		# "Have I reached this waypoint" is checked in full 3D (including Y),
		# and the baked navmesh surface can sit a good bit above the true
		# collision floor at a given spot (measured up to ~0.7m on this
		# terrain) — too small a value here means a monster can get
		# permanently stuck waiting to close a vertical gap gravity will
		# never let it close, never advancing past the first waypoint.
		nav_agent.path_desired_distance = 1.5
		nav_agent.target_desired_distance = 1.5
		nav_agent.max_speed = speed

	change_state(State.IDLE)

	print("✅ %s (Lv%d) loaded | HP:%d | SPD:%.1f | DMG:%d | AC:%d | Faction:%s | Category:%s" %
		[monster_name, level, max_health, speed, damage, armor_class, faction, category])


# ===== HUMANOID VISUAL (reuses the player/guard Mixamo model + shared anim library) =====

func _setup_humanoid_visual() -> void:
	mesh_instance.visible = false

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0, 0.9, 0)

	var character_scene := load("res://models/player/character.fbx")
	var character: Node3D = character_scene.instantiate()
	character.name = "Character"
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)  # same 180°-Y facing fix baked into player3d.tscn/guard_npc.tscn's Character node
	add_child(character)

	animation_player = character.get_node("AnimationPlayer")
	var lib := load("res://models/player/player_animations.res") as AnimationLibrary
	if lib and animation_player:
		if animation_player.has_animation_library(""):
			animation_player.remove_animation_library("")
		animation_player.add_animation_library("", lib)


func _update_animation() -> void:
	if not animation_player or animation_player.get_animation_list().is_empty():
		return
	if _attack_anim_timer > 0.0:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	var anim_name := "idle"
	if moving:
		anim_name = "run" if current_state == State.CHASE else "walk"
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, 0.15)


func _play_attack_animation() -> void:
	if not animation_player or animation_player.get_animation_list().is_empty():
		return
	var anim_name: String = ATTACK_ANIMS[randi() % ATTACK_ANIMS.size()]
	animation_player.play(anim_name, 0.1)
	_attack_anim_timer = animation_player.get_animation(anim_name).length


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

	# Real, level-scaled secondary stats — NOT flatly zeroed. Balance pass,
	# 2026-09-14: every base stat used to be 0, with only gear_atk/gear_ac/
	# gear_hp (flat, level-derived) controlling combat. Since melee damage
	# comes from weapon_damage + STR/2, hit chance from weapon_skill*2 + STR
	# + DEX/2 + gear_atk, and magic resistance from CON/2 + WIS/2, zeroing
	# every stat silently collapsed monster accuracy AND zeroed their magic
	# resistance entirely (confirmed: every monster had exactly 0% arcane
	# resist) — which is why a single Life Siphon (~70 flat damage) could
	# one-shot a rat (20 HP) five times over and take a bandit (80 HP) to
	# 12% remaining, fully unresisted, while monsters barely hit the player
	# back (e.g. a level-3 bandit: 41% hit chance for 6% of player HP).
	var stat_scale: int = 8 + level * 3
	combat_node.strength     = stat_scale
	combat_node.constitution = stat_scale
	combat_node.dexterity    = stat_scale
	combat_node.intelligence = 5
	combat_node.wisdom       = 5
	combat_node.charisma     = 5
	combat_node.luck         = 5

	# get_ac() = 10 + gear_ac + dex/2 + class_ac_bonus(0, monsters have no class)
	combat_node.gear_ac = armor_class - 10

	# max_hp = 50 + con*10 + gear_hp — compensate so the JSON's hand-tuned
	# max_health stays the authoritative number despite constitution no
	# longer being 0 (don't want stats to silently inflate per-mob HP pools
	# on top of what's already been balanced there).
	combat_node.gear_hp = max_health - 50 - combat_node.constitution * 10

	# ATK scaled by level for reasonable hit rates vs the player. Left at its
	# original, more modest formula — the strength/dexterity contributions
	# above now do most of the scaling work themselves.
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

	if _attack_anim_timer > 0.0:
		_attack_anim_timer -= delta

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

	_update_animation()

func add_threat(attacker: Node, amount: float) -> void:
	if amount <= 0.0 or not is_instance_valid(attacker):
		return
	aggro_table[attacker] = aggro_table.get(attacker, 0.0) + amount
	# Being attacked pulls a monster into combat immediately, regardless of
	# can_see_player()'s (short, behavior-scaled) vision range — otherwise a
	# monster can take damage all day while standing in IDLE/PATROL, since
	# those states only ever check for the player by sight, never by threat.
	if current_state == State.IDLE or current_state == State.PATROL:
		change_state(State.CHASE)


# Tank Taunt abilities call this instead of add_threat() — a flat threat bump
# isn't reliable (a healer/DPS could already be far ahead), so this sets the
# tank's threat to just above whatever the current highest entry is,
# guaranteeing an immediate target switch regardless of the existing gap.
func taunt(attacker: Node, margin: float = 1.0) -> void:
	if not is_instance_valid(attacker):
		return
	var highest: float = aggro_table.get(player, 0.0)
	for t in aggro_table.values():
		highest = max(highest, t)
	aggro_table[attacker] = max(aggro_table.get(attacker, 0.0), highest) + margin
	if current_state == State.IDLE or current_state == State.PATROL:
		change_state(State.CHASE)

func get_current_target() -> Node:
	if aggro_table.is_empty():
		return player
	var best: Node = player
	var best_threat: float = aggro_table.get(player, 0.0)
	for attacker in aggro_table:
		if not is_instance_valid(attacker):
			continue
		if aggro_table[attacker] > best_threat:
			best_threat = aggro_table[attacker]
			best = attacker
	return best if is_instance_valid(best) else player

# ===== STATE MACHINE =====
func state_idle(delta: float) -> void:
	# Check aggro range (using your JSON field)
	if player and can_see_player():
		change_state(State.CHASE)
		return

	# Passive creatures stay put until aggroed; everything else patrols after
	# a short, randomized wait (deterministic timer, not a per-frame RNG roll
	# — the old 1%-per-frame chance averaged ~1.7s, close enough in theory,
	# but combined with a 10-unit wander radius it read as barely moving at
	# all in practice — see PATROL_RADIUS/pick_new_patrol_point() below).
	if behavior_type == "passive":
		return
	_idle_timer += delta
	if _idle_timer >= _idle_duration:
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

	var target: Node = get_current_target()
	var distance: float = global_position.distance_to(target.global_position)

	# No leash, by design — once aggroed, a monster chases until it or its
	# target dies. This is deliberate EQ-style behavior: a distance-based
	# give-up would let players train mobs through an area and shake them by
	# just running past a leash point.

	# In melee range
	if distance <= attack_range:
		change_state(State.ATTACK)
		return

	if is_inside_tree() and nav_agent:
		nav_agent.target_position = target.global_position
		print("CHASE: target =", nav_agent.target_position)

func state_attack(delta: float) -> void:
	if not player:
		change_state(State.IDLE)
		return

	var target: Node = get_current_target()
	var distance: float = global_position.distance_to(target.global_position)

	# Target escaped
	if distance > attack_range + 1.0:
		change_state(State.CHASE)
		return

	look_at_target(target.global_position)

	if can_attack:
		perform_attack()

# ===== MOVEMENT =====
# Gravity/move_and_slide() must run every call regardless of whether there's
# horizontal nav movement to do this frame — a monster can be legitimately
# "not yet at its next waypoint" for purely vertical reasons (the navmesh
# surface a waypoint sits on can differ from the actual collision floor by a
# bit, e.g. by roughly cell_height), and gating gravity behind the same
# "close enough, nothing to do" check used to deadlock those monsters
# permanently: they needed gravity to reach the height that check would
# consider "arrived," but gravity was gated behind that exact check.
func handle_movement(delta: float) -> void:
	if not is_inside_tree() or not nav_agent:
		return

	velocity.x = 0.0
	velocity.z = 0.0

	if not nav_agent.is_navigation_finished():
		var next_position: Vector3 = nav_agent.get_next_path_position()
		var to_next: Vector3 = next_position - global_position
		var flat_dir: Vector3 = Vector3(to_next.x, 0, to_next.z)

		if flat_dir.length() >= 0.1:
			var direction: Vector3 = flat_dir.normalized()
			look_at_target(global_position + direction)

			var speed_3d = speed / 10.0
			if current_state == State.CHASE:
				speed_3d *= CHASE_SPEED_MULTIPLIER  # most base speeds (2.5-3.5 m/s) trail the player's 5 m/s walk — an aggroed monster should feel urgent, not be outrun at a stroll
			speed_3d *= (1.0 - combat_node.get_modifier("speed_slow"))
			velocity.x = direction.x * speed_3d
			velocity.z = direction.z * speed_3d

	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0

	move_and_slide()




# ===== COMBAT =====
func perform_attack() -> void:
	can_attack = false
	attack_timer = attack_cooldown * (1.0 + combat_node.get_modifier("attack_speed_slow"))
	_play_attack_animation()

	var target: Node = get_current_target()
	if not target:
		return

	if "combat_node" in target and target.combat_node is CombatNode:
		var result = combat_node.resolve_attack(target.combat_node)
		# resolve_attack() already applies the hit directly to
		# target.combat_node.current_hp ("target.current_hp -= damage" inside
		# combatnode.gd) — do NOT also call target.take_damage()/apply_damage()
		# here, that double-applies the same hit. Confirmed via a headless
		# test (2026-09-14): monster attacks against the player were landing
		# for exactly double the damage resolve_attack() itself reported,
		# because this used to call player.take_damage(result["damage"], ...)
		# on top of resolve_attack()'s own direct mutation. A real, serious
		# contributor to monsters feeling far too strong after the balance
		# pass — the math was right, the damage was just being applied twice.
		if not combat_node.is_alive():
			die()
			return

		var desc: String = monster_description if monster_description != "" else get_monster_name()
		if target == player:
			var msg: String = CombatLogFormatter.monster_attack(result, desc, get_damage_type())
			if not msg.is_empty():
				GameLog.log_combat(msg)
			if result.get("damage", 0) > 0 and target.has_method("on_combat_node_hit"):
				target.on_combat_node_hit(self)
		else:
			var target_name: String = target.get("pet_name") if "pet_name" in target else "your ally"
			_log_attack_on_other(result, desc, target_name)
			if not target.combat_node.is_alive() and target.has_method("die"):
				target.die()
	elif target.has_method("take_damage"):
		target.take_damage(damage)
		if target == player:
			var desc: String = monster_description if monster_description != "" else get_monster_name()
			GameLog.log_combat("%s hits you for [b]%d[/b] damage!" % [desc.capitalize(), damage])

	if is_social:
		call_nearby_allies()


func _log_attack_on_other(result: Dictionary, attacker_desc: String, target_name: String) -> void:
	var cap := attacker_desc.capitalize()
	match result.get("result", ""):
		"MISS":
			GameLog.log_combat("%s misses %s!" % [cap, target_name], global_position)
		"PARRY":
			GameLog.log_combat("%s's attack on %s is parried!" % [cap, target_name], global_position)
		"BLOCK":
			GameLog.log_combat("%s's attack on %s is blocked!" % [cap, target_name], global_position)
		"DODGE":
			GameLog.log_combat("%s's attack on %s is dodged!" % [cap, target_name], global_position)
		"RIPOSTE":
			GameLog.log_combat("%s is riposted by %s for [b]%d[/b] damage!" % [cap, target_name, result.get("damage", 0)], global_position)
		"HIT":
			var crit: String = " [color=#ffaa00]Critical![/color]" if result.get("is_crit", false) else ""
			GameLog.log_combat("%s hits %s for [b]%d[/b] damage!%s" % [cap, target_name, result.get("damage", 0), crit], global_position)

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

		# Bug fixed 2026-09-14: this compared a real meter distance against
		# aggro_range, which is the RAW, unscaled JSON value (2D-era units —
		# see aggro_range's own doc comment) — e.g. a bandit's aggro_range is
		# 200.0, so allies anywhere in roughly a 200m radius would come
		# assist, not the handful of meters it looked like. ASSIST_RANGE is a
		# real, deliberately short meter distance instead.
		var distance = global_position.distance_to(ally.global_position)
		if distance < ASSIST_RANGE:
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

const DEATH_LINE_PATH := "res://Data/humanoid_death_lines.json"

func die(award_xp: bool = true, drop_loot: bool = true) -> void:
	change_state(State.DEAD)
	print("💀 %s died! (XP: %d, Coins: %.2f, Category: %s)" % [monster_name, xp_gain, coin_modifier, category])

	if category == "humanoid":
		var line := NPCFlavorText.new(DEATH_LINE_PATH).get_line("death")
		if line != "":
			var desc: String = monster_description if monster_description != "" else get_monster_name()
			GameLog.log_general("[color=#cc8888]%s says, \"%s\"[/color]" % [desc.capitalize(), line])

	if drop_loot:
		pending_loot = _auto_process_loot(roll_loot())
		is_lootable = not pending_loot.is_empty()
		if is_lootable:
			print("  → Right-click corpse to loot")
	else:
		pending_loot = []
		is_lootable = false

	# Award XP to player
	if award_xp:
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
				GameLog.log_general("[color=#ffdd44][b]Fortune smiles upon you; your adventures have made you stronger! You are now level %d.[/b][/color]" % new_lvl)
				if p.has_method("on_level_up"):
					p.on_level_up(new_lvl)

			Global.save_player_data_to_file()

	if animation_player and animation_player.has_animation("death"):
		animation_player.play("death")

	if not drop_loot:
		queue_free()
		return

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

# Currency is always auto-collected (no reason to ever manually click for
# coins). Everything else is resolved against the player's saved loot
# preference — "loot"/"sell" auto-loot it here, "ignore" discards it, and
# anything with no saved preference is left for the loot window to show.
func _auto_process_loot(drops: Array) -> Array:
	var remaining: Array = []
	for drop in drops:
		var item_id: String = drop["item"]
		if CURRENCY_MAP.has(item_id):
			var currency_field: String = CURRENCY_MAP[item_id]
			Global.grant_currency(currency_field, drop["quantity"])
			Global.play_coin_sound()
			GameLog.log_general("[color=#ffd966]You receive %d %s.[/color]" % [drop["quantity"], currency_field.capitalize()])
			continue
		match Global.get_loot_preference(item_id):
			"loot", "sell":
				if Inventory.get_item_definition(item_id).is_empty():
					remaining.append(drop)  # not a real item yet — fall back to manual
				elif Inventory.add_item(item_id, drop["quantity"]):
					GameLog.log_general("You automatically loot %s." % item_id.replace("_", " ").capitalize())
				else:
					remaining.append(drop)  # inventory full — leave it for the manual loot window instead of vanishing
			"ignore":
				pass  # discarded silently
			_:
				remaining.append(drop)
	return remaining


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
		State.IDLE:
			_idle_timer = 0.0
			_idle_duration = randf_range(IDLE_MIN_DURATION, IDLE_MAX_DURATION)
		State.PATROL:
			pick_new_patrol_point()
		State.CHASE:
			if get_current_target() == player:
				var desc: String = monster_description if monster_description != "" else get_monster_name()
				GameLog.log_combat("[color=orange]%s attacks you![/color]" % desc.capitalize())
		State.ATTACK:
			velocity = Vector3.ZERO

# Called on every monster when the player is incapacitated/dies (see
# player3d.gd's die()) — clears aggro and heads straight back to spawn_position
# instead of picking a random nearby patrol point, so it reads as "giving up
# and walking home" rather than just wandering off. can_see_player() (below)
# separately makes sure a monster won't re-aggro the same downed player while
# they're still incapacitated/dead-pending-respawn.
func force_disengage() -> void:
	if current_state == State.DEAD:
		return
	aggro_table.clear()
	if current_state in [State.CHASE, State.ATTACK]:
		change_state(State.PATROL)
		patrol_target = spawn_position


func can_see_player() -> bool:
	if not player:
		return false
	if "dying" in player and player.dying:
		return false  # incapacitated or dead-pending-respawn — ignore, per force_disengage() above

	var distance: float = global_position.distance_to(player.global_position)
	var effective_range: float = minf(aggro_range / AGGRO_RANGE_SCALE, MAX_AGGRO_DISTANCE)

	match behavior_type:
		"passive":
			return distance <= (effective_range / 3.0)
		"neutral":
			return distance <= (effective_range / 2.0)
		_:  # aggressive, skitter, etc.
			return distance <= effective_range

const PATROL_MIN_DISTANCE: float = 5.0   # avoid trivially-short legs that don't read as movement
const PATROL_MAX_DISTANCE: float = 18.0  # was a flat 10.0 with no minimum — too tight a bubble to look like real wandering

func pick_new_patrol_point() -> void:
	var random_angle: float = randf() * TAU
	var random_distance: float = randf_range(PATROL_MIN_DISTANCE, PATROL_MAX_DISTANCE)
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
