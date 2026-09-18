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

# Humanoid-shaped mob types get a Mixamo character model/animations instead
# of the generic placeholder box, swapped in at runtime by
# _setup_humanoid_visual() — see monster_template.tscn, which is shared by
# every mob type and keeps the box as the default/fallback visual.
# goblin_scout/goblin_warrior weren't in this list before 2026-09-16 (a
# pre-existing gap — those monster_names got the plain box even though
# they've always been "humanoid" in concept); added once they got real
# dedicated models below. "bandit" and base "goblin" have no dedicated model
# of their own yet, so they still fall back to DEFAULT_HUMANOID_MOB_MODEL
# (the shared player model) same as before — see MOB_MODELS.
const HUMANOID_MOB_TYPES: Array = ["bandit", "skeleton", "goblin", "goblin_scout", "goblin_warrior"]
const ATTACK_ANIMS := ["attack_horizontal", "attack_downward"]

# Per-species dedicated models (added 2026-09-16) — mirrors player3d.gd's
# CHARACTER_MODELS/DEFAULT_CHARACTER_MODEL pattern. Anything in
# HUMANOID_MOB_TYPES but not listed here falls back to
# DEFAULT_HUMANOID_MOB_MODEL.
const MOB_MODELS := {
	"skeleton": {
		"scene":   "res://models/mobs/fallen scout skeleton/Meshy_AI_Fallen_Scout_Skeleton_biped_Character_output.fbx",
		"library": "res://models/mobs/fallen scout skeleton/skeleton_animations.res",
		"texture_override": "res://models/mobs/fallen scout skeleton/Meshy_AI_Fallen_Scout_Skeleton_biped_texture_0.png",
	},
	"goblin_warrior": {
		"scene":   "res://models/mobs/desert goblin/Meshy_AI_Desert_Goblin_Warrior_biped_Character_output.fbx",
		"library": "res://models/mobs/desert goblin/goblin_warrior_animations.res",
		"texture_override": "res://models/mobs/desert goblin/Meshy_AI_Desert_Goblin_Warrior_biped_texture_0.png",
	},
	"goblin_scout": {
		"scene":   "res://models/mobs/desert goblin scout/Meshy_AI_Desert_Goblin_Scout_R_biped_Character_output.fbx",
		"library": "res://models/mobs/desert goblin scout/goblin_scout_animations.res",
		"texture_override": "res://models/mobs/desert goblin scout/Meshy_AI_Desert_Goblin_Scout_R_biped_texture_0.png",
	},
	# "goblin" (the base type, distinct from goblin_warrior/goblin_scout) has
	# no dedicated asset of its own — reuses the Desert Goblin Warrior model,
	# closing the gap the comment below used to describe.
	"goblin": {
		"scene":   "res://models/mobs/desert goblin/Meshy_AI_Desert_Goblin_Warrior_biped_Character_output.fbx",
		"library": "res://models/mobs/desert goblin/goblin_warrior_animations.res",
		"texture_override": "res://models/mobs/desert goblin/Meshy_AI_Desert_Goblin_Warrior_biped_texture_0.png",
	},
}
const DEFAULT_HUMANOID_MOB_MODEL := {
	"scene":   "res://models/player/character.fbx",
	"library": "res://models/player/player_animations.res",
}

# Non-humanoid critters with a real (but unrigged — single static mesh, no
# skeleton/animations, same Meshy image-to-3D pipeline as the Wildspeaker
# pet's placeholder) model now available — added 2026-09-17. Mapped by the
# exact monster-description match confirmed against the zone's own mob list:
# "rat" = "A Desert Scavenger", "spiderling" = "A Spiderling Swarmer" (this
# folder is literally named "juvenile spider").
const CRITTER_MODELS := {
	"rat": {
		"scene": "res://models/mobs/desert scavenger/Meshy_AI_desert_rodent_monster_0916015343_image-to-3d-texture.fbx",
		"albedo": "res://models/mobs/desert scavenger/Meshy_AI_desert_rodent_monster_0916015343_image-to-3d-texture.png",
		"normal": "res://models/mobs/desert scavenger/Meshy_AI_desert_rodent_monster_0916015343_image-to-3d-texture_normal.png",
		"roughness": "res://models/mobs/desert scavenger/Meshy_AI_desert_rodent_monster_0916015343_image-to-3d-texture_roughness.png",
		"metallic": "res://models/mobs/desert scavenger/Meshy_AI_desert_rodent_monster_0916015343_image-to-3d-texture_metallic.png",
	},
	"spiderling": {
		"scene": "res://models/mobs/juvenile spider/Meshy_AI_juvenile_spider_monst_0916005348_image-to-3d-texture.fbx",
		"albedo": "res://models/mobs/juvenile spider/Meshy_AI_juvenile_spider_monst_0916005348_image-to-3d-texture.png",
		"normal": "res://models/mobs/juvenile spider/Meshy_AI_juvenile_spider_monst_0916005348_image-to-3d-texture_normal.png",
		"roughness": "res://models/mobs/juvenile spider/Meshy_AI_juvenile_spider_monst_0916005348_image-to-3d-texture_roughness.png",
		"metallic": "res://models/mobs/juvenile spider/Meshy_AI_juvenile_spider_monst_0916005348_image-to-3d-texture_metallic.png",
	},
}

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
enum State { IDLE, PATROL, CHASE, ATTACK, DEAD, FLEEING, CHARMED }
var current_state: State = State.IDLE
var can_attack: bool = true
var combat_node: CombatNode

# ===== FEAR (2026-09-17) =====
const FLEE_DIRECTION_INTERVAL := 4.0
const FLEE_COLLISION_RADIUS := 1.5  # "runs into another social enemy" proximity check
var _flee_time_remaining: float = 0.0
var _flee_direction_timer: float = 0.0
var _flee_direction: Vector3 = Vector3.ZERO
var _pre_flee_state: State = State.IDLE

# ===== CHARM (2026-09-17) =====
# Charm hands the player a temporary "pet" out of a hostile monster, using
# the exact same command interface/UI as a real PetMinion (pet_frame.gd) —
# see player3d.gd's "charm" effect_type case, which opens that window against
# this monster instead of building a new one. `command`/`pet_name` and the
# cmd_*() methods below exist purely to satisfy that shared interface
# (PetMinion.PetState's int values: FOLLOW=0, ATTACK=1, SIT=2, GUARD=3,
# ASSIST=4) — pet_frame.gd has no idea it isn't a real PetMinion.
var is_charmed: bool = false
var pet_name: String = ""
var command: int = 0
var charm_owner: Node = null
var charm_attack_target: Node = null
var guard_position: Vector3 = Vector3.ZERO
var _charm_time_remaining: float = 0.0
const CHARM_GUARD_SCAN_RADIUS := 8.0
# Set alongside every animation_player.play() call below, replicated (see
# monster_template.tscn's MultiplayerSynchronizer) so a non-authoritative
# client just mirrors whatever animation the server/single-player simulation
# decided, instead of running its own (removed) AI to decide independently.
var anim_state: String = ""

# Kept for backward compat — always mirrors combat_node.current_hp
var monster_description: String = ""
var current_health: int:
	get: return combat_node.current_hp if combat_node else 0
var attack_timer: float = 0.0
var attack_cooldown: float = 1.5
# Out-of-combat regen (same 6s EQ-tick as the player/pet) — without this a
# monster could be fought down to near-death, disengaged from, and finished
# off on a second pass with zero risk, repeated indefinitely to cheese any
# encounter that's actually hard. Only ticks while IDLE/PATROL (see
# _physics_process below).
const REGEN_INTERVAL := 6.0
var _regen_timer: float = 0.0
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
	elif monster_name in CRITTER_MODELS:
		_setup_critter_visual()

	combat_node = CombatNode.new()
	combat_node.name = "CombatNode"
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


# ===== HUMANOID VISUAL (per-species model if MOB_MODELS has one, else the
# shared player/guard Mixamo model + anim library — see MOB_MODELS above) =====

func _setup_humanoid_visual() -> void:
	mesh_instance.visible = false

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0, 0.9, 0)

	var model_info: Dictionary = MOB_MODELS.get(monster_name, DEFAULT_HUMANOID_MOB_MODEL)
	var character_scene := load(model_info["scene"])
	var character: Node3D = character_scene.instantiate()
	character.name = "Character"
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)  # same 180°-Y facing fix baked into player3d.tscn/guard_npc.tscn's Character node
	add_child(character)

	animation_player = character.get_node("AnimationPlayer")
	var lib := load(model_info["library"]) as AnimationLibrary
	if lib and animation_player:
		if animation_player.has_animation_library(""):
			animation_player.remove_animation_library("")
		animation_player.add_animation_library("", lib)

	if model_info.has("texture_override"):
		_apply_texture_override(character, model_info["texture_override"])


# Meshy-sourced FBX exports never carry their real texture through to Godot
# reliably (confirmed recurring bug across every model built this way), so
# apply it as a runtime material override instead of trusting the FBX's own
# material.
func _apply_texture_override(node: Node, texture_path: String) -> void:
	var tex := load(texture_path) as Texture2D
	if not tex:
		push_warning("⚠️ Mob texture override not found: %s" % texture_path)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	_apply_material_recursive(node, mat)


# Non-humanoid critter with a real but unrigged model (single static mesh,
# no AnimationPlayer) — same shape as wildspeaker_pet.gd's model handling.
# No animation swapping needed since there's nothing to swap; _update_animation()
# below already no-ops harmlessly when animation_player is null.
func _setup_critter_visual() -> void:
	mesh_instance.visible = false

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.0
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0, 0.5, 0)

	var model_info: Dictionary = CRITTER_MODELS[monster_name]
	var character_scene := load(model_info["scene"])
	if not character_scene:
		return
	var character: Node3D = character_scene.instantiate()
	character.name = "Character"
	# Same 180°-Y facing fix every Meshy/Mixamo model in this codebase needs —
	# unverified for these two specific meshes' pivot/scale yet (see
	# phantasmal_echo_pet.gd's comment on how that one needed a couple of
	# correction passes); adjust here first if either critter turns out
	# sunk into the ground or oddly scaled once seen in-game.
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)
	add_child(character)

	_apply_critter_material(character, model_info)


# Same texture-never-survives-FBX-export issue as every other Meshy model
# here — applied as a runtime material override using all of this asset
# type's real PBR maps (normal/roughness/metallic), same as
# phantasmal_echo_pet.gd's _apply_spirit_pet_material().
func _apply_critter_material(node: Node, model_info: Dictionary) -> void:
	var albedo := load(model_info.get("albedo", "")) as Texture2D
	if not albedo:
		push_warning("⚠️ Critter texture override not found for %s" % monster_name)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo

	var normal := load(model_info.get("normal", "")) as Texture2D
	if normal:
		mat.normal_enabled = true
		mat.normal_texture = normal

	var roughness := load(model_info.get("roughness", "")) as Texture2D
	if roughness:
		mat.roughness_texture = roughness

	var metallic := load(model_info.get("metallic", "")) as Texture2D
	if metallic:
		mat.metallic_texture = metallic
		mat.metallic = 1.0  # metallic_texture modulates this scalar — 1.0 lets the map through unscaled

	_apply_material_recursive(node, mat)


func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_material_recursive(child, mat)


func _update_animation() -> void:
	if not animation_player or animation_player.get_animation_list().is_empty():
		return
	if _attack_anim_timer > 0.0:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	var anim_name := "idle"
	if moving:
		anim_name = "run" if current_state == State.CHASE else "walk"
	anim_state = anim_name  # replicated to non-authoritative peers — see _play_replicated_animation()
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, 0.15)


# Non-authoritative peers never run _update_animation()/_play_attack_animation()
# (no local AI to decide with) — they just mirror whatever anim_state the
# authoritative server/single-player simulation replicated out, same pattern
# as player3d.gd's own puppet branch.
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
	# Per-viewer, not networked — see TargetFrame.is_hidden_from_local_player().
	# No monster data actually grants invisibility yet (nothing calls
	# apply_effect("invisibility", ...) on a monster's own combat_node), so
	# this is a no-op today; it's here so a future invisible-mob ability just
	# works without touching rendering code again. Runs regardless of
	# authority/DEAD state — even a corpse should respect see-invisible.
	if has_node("Character"):
		$Character.visible = not TargetFrame.is_hidden_from_local_player(self)

	# Non-authoritative peers (every client but the server, in a multiplayer
	# game — always true in single-player, see project_multiplayer_netcode
	# memory's authority-gating pattern) never run any AI/combat/movement
	# below: they just mirror whatever position/rotation/anim_state/HP the
	# authoritative side replicates via monster_template.tscn's
	# MultiplayerSynchronizer. Runs before the DEAD check (not after) so a
	# puppet still plays the death animation once current_state replicates to
	# DEAD, instead of freezing on whatever animation was last playing.
	if not is_multiplayer_authority():
		_play_replicated_animation()
		return

	if current_state == State.DEAD:
		return

	# Update attack cooldown
	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0.0:
			can_attack = true

	if _attack_anim_timer > 0.0:
		_attack_anim_timer -= delta

	if current_state == State.IDLE or current_state == State.PATROL:
		_regen_timer += delta
		if _regen_timer >= REGEN_INTERVAL:
			_regen_timer = 0.0
			if combat_node.current_hp < combat_node.max_hp:
				combat_node.current_hp = mini(combat_node.current_hp + combat_node.get_derived_stat("hp_regen"), combat_node.max_hp)
	else:
		_regen_timer = 0.0

	# Find player safely — the local one specifically: monster3d.gd isn't
	# networked yet (see project_multiplayer_netcode memory), so each client
	# still runs its own fully independent copy of every monster; picking
	# index 0 here could grab another connected player's puppet instead of
	# the one this client's own simulation should actually care about.
	if not is_instance_valid(player):
		player = TargetFrame.local_player()
		if not is_instance_valid(player):
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
		State.FLEEING:
			state_fleeing(delta)
		State.CHARMED:
			state_charmed(delta)

	# Movement and gravity
	if current_state in [State.PATROL, State.CHASE, State.CHARMED]:
		handle_movement(delta)
	elif current_state == State.FLEEING:
		pass  # state_fleeing() above already moved it this frame
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


# Called by the generic spell-effect system (player3d.gd's
# _apply_generic_spell_effect(), "fear" case) instead of the old
# can't-attack-for-a-bit approximation every other CC effect still uses —
# fear gets its own real behavior per the user's spec: run in a random
# direction, picking a new one every FLEE_DIRECTION_INTERVAL seconds, for the
# spell's full duration, then resume whatever it was doing before.
func apply_fear(duration: float) -> void:
	if current_state == State.DEAD:
		return
	if current_state != State.FLEEING:
		_pre_flee_state = current_state
	_flee_time_remaining = duration
	_flee_direction_timer = 0.0  # forces an immediate direction pick this frame
	change_state(State.FLEEING)


func state_fleeing(delta: float) -> void:
	_flee_time_remaining -= delta
	if _flee_time_remaining <= 0.0:
		change_state(State.CHASE if not aggro_table.is_empty() else _pre_flee_state)
		return

	_flee_direction_timer -= delta
	if _flee_direction_timer <= 0.0:
		_flee_direction_timer = FLEE_DIRECTION_INTERVAL
		var angle := randf() * TAU
		_flee_direction = Vector3(cos(angle), 0, sin(angle))

	# Direct movement, not nav_agent pathing — fleeing has no destination, just
	# a heading, and doesn't need to be graceful about it (same reasoning
	# guard_npc.gd's/pet_minion.gd's "stuck" direct-fallback movement uses:
	# straight-line movement plus a short obstacle check is good enough when
	# real pathing isn't the point).
	if _flee_direction != Vector3.ZERO:
		look_at_target(global_position + _flee_direction)
		var speed_3d: float = (speed / 10.0) * (1.0 - combat_node.get_modifier("speed_slow"))
		velocity.x = _flee_direction.x * speed_3d
		velocity.z = _flee_direction.z * speed_3d
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	_check_flee_collision_aggro()


# "If the monster runs into another social enemy, the enemy will become
# aggressive and attack the player" — proximity-based rather than a real
# physics collision callback, same trade-off pet_minion.gd's obstacle check
# makes for "good enough, not physically exact."
func _check_flee_collision_aggro() -> void:
	if not is_instance_valid(player):
		return
	for other in get_tree().get_nodes_in_group("monsters"):
		if other == self or not is_instance_valid(other) or not (other is Monster):
			continue
		var m: Monster = other
		if not m.is_social or m.current_state == State.DEAD or m.current_state == State.FLEEING:
			continue
		if global_position.distance_to(m.global_position) <= FLEE_COLLISION_RADIUS:
			m.add_threat(player, 1.0)


# Called by player3d.gd's "charm" effect_type case. Clears any existing
# aggro (a charmed monster fighting the player makes no sense) and hands
# control to whoever cast it, via the same command set pet_frame.gd already
# knows how to drive.
func apply_charm(duration: float, owner: Node) -> void:
	if current_state == State.DEAD:
		return
	is_charmed = true
	charm_owner = owner
	charm_attack_target = null
	aggro_table.clear()
	pet_name = monster_description if monster_description != "" else get_monster_name()
	command = 0  # PetMinion.PetState.FOLLOW
	_charm_time_remaining = duration
	change_state(State.CHARMED)


# Reverts to a normal hostile monster — on duration expiry, cmd_dismiss(), or
# the charmer no longer being valid. Re-aggros on the player rather than
# resetting to IDLE, matching the "it was hostile a moment ago" expectation
# (an un-charmed monster shouldn't just wander off).
func _end_charm() -> void:
	is_charmed = false
	charm_owner = null
	charm_attack_target = null
	aggro_table.clear()
	if is_instance_valid(player):
		add_threat(player, 1.0)
	else:
		change_state(State.IDLE)


func state_charmed(delta: float) -> void:
	if not is_instance_valid(charm_owner):
		_end_charm()
		return
	_charm_time_remaining -= delta
	if _charm_time_remaining <= 0.0:
		GameLog.log_general("[color=#ffcc66]%s shakes off your charm.[/color]" % pet_name.capitalize())
		_end_charm()
		return

	match command:
		0:  # FOLLOW
			if nav_agent:
				nav_agent.target_position = charm_owner.global_position
		1:  # ATTACK
			_charm_pursue_and_attack(charm_attack_target, delta)
		2:  # SIT
			if nav_agent:
				nav_agent.target_position = global_position
		3:  # GUARD
			if not (is_instance_valid(charm_attack_target) and _target_alive_generic(charm_attack_target)):
				charm_attack_target = _find_nearest_hostile_to(charm_owner, CHARM_GUARD_SCAN_RADIUS)
			if is_instance_valid(charm_attack_target):
				_charm_pursue_and_attack(charm_attack_target, delta)
			elif nav_agent:
				nav_agent.target_position = guard_position
		4:  # ASSIST
			if "current_target" in charm_owner and is_instance_valid(charm_owner.current_target):
				charm_attack_target = charm_owner.current_target
			_charm_pursue_and_attack(charm_attack_target, delta)


func _charm_pursue_and_attack(target: Node, _delta: float) -> void:
	if not is_instance_valid(target) or not _target_alive_generic(target):
		charm_attack_target = null
		return
	var distance := global_position.distance_to(target.global_position)
	if distance <= attack_range:
		if nav_agent:
			nav_agent.target_position = global_position
		look_at_target(target.global_position)
		if can_attack:
			_perform_charmed_attack(target)
	elif nav_agent:
		nav_agent.target_position = target.global_position


func _target_alive_generic(target: Node) -> bool:
	var cn = target.get("combat_node")
	return cn is CombatNode and cn.is_alive()


# Finds the nearest hostile-to-the-player monster within radius of `origin`
# for Guard mode — mirrors pet_minion.gd's own guard-scan idea, adapted since
# a charmed monster's "hostiles" are other monsters, not the player.
func _find_nearest_hostile_to(origin: Node3D, radius: float) -> Node:
	var nearest: Node = null
	var nearest_dist: float = radius
	for other in get_tree().get_nodes_in_group("monsters"):
		if other == self or not (other is Monster) or not is_instance_valid(other):
			continue
		var m: Monster = other
		if m.current_state == State.DEAD or m.is_charmed:
			continue
		var dist: float = origin.global_position.distance_to(m.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = m
	return nearest


# Attacks another Monster on the charmer's behalf — deliberately separate
# from perform_attack() (which resolves against get_current_target(), an
# aggro-table lookup keyed on attacking the player) since a charmed monster's
# target is an explicit charm_attack_target instead.
func _perform_charmed_attack(target: Node) -> void:
	can_attack = false
	_play_attack_animation()
	var base_cooldown: float = _attack_anim_timer if _attack_anim_timer > 0.0 else attack_cooldown
	attack_timer = base_cooldown * (1.0 + combat_node.get_modifier("attack_speed_slow"))

	if not (target.get("combat_node") is CombatNode):
		return
	var result: Dictionary = combat_node.resolve_attack(target.combat_node)
	var desc: String = target.get("monster_description")
	if desc == "" and target.has_method("get_monster_name"):
		desc = target.get_monster_name()
	_log_attack_on_other(result, pet_name, desc)
	if not target.combat_node.is_alive() and target.has_method("die"):
		target.die()
		charm_attack_target = null


# ── Commands (pet_frame.gd's exact interface — see PetMinion's cmd_*()) ────
func cmd_attack(target: Node) -> void:
	if not is_instance_valid(target):
		GameLog.log_general("%s has no target to attack." % pet_name.capitalize())
		return
	charm_attack_target = target
	command = 1


func cmd_follow() -> void:
	charm_attack_target = null
	command = 0


func cmd_sit() -> void:
	charm_attack_target = null
	command = 2


func cmd_guard() -> void:
	charm_attack_target = null
	guard_position = global_position
	command = 3


func cmd_assist() -> void:
	charm_attack_target = null
	command = 4


func cmd_back() -> void:
	charm_attack_target = null
	command = 0


func cmd_dismiss() -> void:
	GameLog.log_general("[color=#ffcc66]You release %s from your charm.[/color]" % pet_name.capitalize())
	_end_charm()


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
	_play_attack_animation()
	# Match the actual swing clip length (humanoid mobs only — _attack_anim_timer
	# stays 0 for the placeholder-box mobs with no AnimationPlayer, so they fall
	# back to the flat attack_cooldown default) rather than the old flat 1.5s,
	# so a humanoid mob's attack rate lines up with the player's own
	# animation-length-matched cooldown instead of drastically outpacing it —
	# see player3d.gd's _attack_animation_duration().
	var base_cooldown: float = _attack_anim_timer if _attack_anim_timer > 0.0 else attack_cooldown
	attack_timer = base_cooldown * (1.0 + combat_node.get_modifier("attack_speed_slow"))

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
			if target.has_method("_tick_defense_skill"):
				target._tick_defense_skill(result.get("result", ""))
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

func die(award_xp: bool = true, drop_loot: bool = true, credited_peer_id: int = -1) -> void:
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

	# Award XP to whoever's credited with the kill — local player by default
	# (not index 0, see the same note in _physics_process() above), or a
	# specific peer when called via apply_networked_damage() below (a
	# non-host client's kill, resolved on the server). If the credited player
	# is THIS machine's own (single-player, or the host killing something
	# themselves), apply directly; otherwise Global.player_data is this
	# process's own save data — there's no way to reach into a remote peer's
	# save file directly — so relay it via RPC to their own machine instead.
	if award_xp:
		var p: Node = TargetFrame.peer_id_to_player_node(credited_peer_id) if credited_peer_id != -1 else TargetFrame.local_player()
		if is_instance_valid(p):
			if p.is_multiplayer_authority():
				p.grant_xp(xp_gain)
			elif p.has_method("receive_kill_credit"):
				p.receive_kill_credit.rpc_id(p.get_multiplayer_authority(), xp_gain)

	if animation_player and animation_player.has_animation("death"):
		anim_state = "death"  # replicated — see _play_replicated_animation()
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


# ── Networked damage (Phase 3 netcode) ──────────────────────────────────────
# A client-authoritative-damage / server-authoritative-application split:
# the attacking player's own client still computes the real hit/miss/damage
# roll locally (unchanged — see player3d.gd's attack_current_target()), using
# its own accurate local stats, since replicating a full combat stat kit
# (strength/weapon_skill/gear bonuses/etc, not just the current_hp/max_hp
# "bar" values Phase 2 replicated) just to let the server redo that roll
# itself would be a much larger change for a private LAN co-op game where
# trusting the attacker's reported damage is an acceptable trade-off. This
# just makes sure the number actually lands on the monster's REAL (server or
# single-player-local) combat_node instead of a non-authoritative client's
# own cosmetic, replicated-over-anyway copy.
@rpc("any_peer", "call_local", "reliable")
func apply_networked_damage(amount: int, attacker_peer_id: int) -> void:
	if not is_multiplayer_authority() or current_state == State.DEAD:
		return
	combat_node.current_hp = maxi(combat_node.current_hp - amount, 0)
	if not combat_node.is_alive():
		die(true, true, attacker_peer_id)


# Same reasoning/pattern as apply_networked_damage() above, for the
# non-damage side of a spell — debuffs, snares, DoTs, etc. Monsters are
# server-authoritative, so a non-host caster's own local, replicated puppet
# of a monster is not the real one; mutating combat_node.apply_effect()
# directly there (what player3d.gd's _buff_target() used to always do) was a
# no-op from every other peer's perspective, identical in shape to the
# player-to-player heal/buff bug fixed the same day. See player3d.gd's
# _buff_target() for the caller side.
@rpc("any_peer", "call_remote", "reliable")
func apply_networked_effect(effect_name: String, duration: float, modifiers: Dictionary, tick_dmg: int, tick_interval: float) -> void:
	if not is_multiplayer_authority() or current_state == State.DEAD:
		return
	combat_node.apply_effect(effect_name, duration, modifiers, tick_dmg, tick_interval)


# Relays the plain can_attack/attack_timer stagger (stun/mesmerize/confuse's
# shared _apply_disable_effect() fallback, and Improved Disarm) the same way
# as the effect-based relays above. can_attack/attack_timer aren't in this
# scene's SceneReplicationConfig, so a non-host caster's relay only affects
# the SERVER's own decision of whether this monster attacks (what actually
# matters for gameplay) — it won't visually update other clients' copies of
# the flag, which is a cosmetic gap only, not a functional one.
@rpc("any_peer", "call_remote", "reliable")
func apply_networked_disable(duration: float) -> void:
	if not is_multiplayer_authority():
		return
	can_attack = false
	attack_timer = duration


@rpc("any_peer", "call_remote", "reliable")
func apply_networked_fear(duration: float) -> void:
	if not is_multiplayer_authority():
		return
	apply_fear(duration)


# charm_owner is a Node reference and, per this project's own established
# rule (see project_multiplayer_netcode memory), a Node reference is never
# meaningful across machines — so the caster's peer id crosses the wire
# instead, and gets resolved back into a real local Node on whichever
# machine actually authoritative for this monster (the server).
@rpc("any_peer", "call_remote", "reliable")
func apply_networked_charm(duration: float, caster_peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var owner_node: Node = _resolve_peer_to_player(caster_peer_id)
	if not is_instance_valid(owner_node):
		return
	apply_charm(duration, owner_node)


func _resolve_peer_to_player(peer_id: int) -> Node:
	for node in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(node) and node.get_multiplayer_authority() == peer_id:
			return node
	return null


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
