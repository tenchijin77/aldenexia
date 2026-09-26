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
const HUMANOID_MOB_TYPES: Array = ["bandit", "skeleton", "goblin", "goblin_scout", "goblin_warrior", "ghost", "mummy", "sunmaddened_wanderer"]
const ATTACK_ANIMS := ["attack_horizontal", "attack_downward"]

# Per-species dedicated models (added 2026-09-16) — mirrors player3d.gd's
# CHARACTER_MODELS/DEFAULT_CHARACTER_MODEL pattern. Anything in
# HUMANOID_MOB_TYPES but not listed here falls back to
# DEFAULT_HUMANOID_MOB_MODEL.
const MOB_MODELS := {
	# STAND-IN until a Meshy model exists: the human male race model, tinted a faded, sun-bleached colour so a Hollowed wanderer
	# doesn't read as a player (optional "tint" multiplies the texture).
	"sunmaddened_wanderer": {
		"scene":   "res://models/Human Male/Human Male Breathing Idle.fbx",
		"library": "res://models/Human Male/human_male_animations.res",
		"texture_override": "res://models/Human Male/Meshy_AI_fantasy_commoner_rigg_biped_texture_0.png",
		"tint": Color(0.68, 0.62, 0.5),
	},
	"skeleton": {
		"scene":   "res://models/mobs/fallen scout skeleton/Meshy_AI_Fallen_Scout_Skeleton_biped_Character_output.fbx",
		"library": "res://models/mobs/fallen scout skeleton/skeleton_animations.res",
		"texture_override": "res://models/mobs/fallen scout skeleton/Meshy_AI_Fallen_Scout_Skeleton_biped_texture_0.png",
	},
	"goblin_warrior": {
		# Swapped to the dedicated 2026-09-18 "desert goblin warrior" model —
		# the old "desert goblin" folder (still used by plain "goblin" below)
		# was only ever a placeholder shared between the two.
		"scene":   "res://models/mobs/desert goblin warrior/Meshy_AI_desert_goblin_warrior_biped_Character_output.fbx",
		"library": "res://models/mobs/desert goblin warrior/desert_goblin_warrior_animations.res",
		"texture_override": "res://models/mobs/desert goblin warrior/Meshy_AI_desert_goblin_warrior_biped_texture_0.png",
	},
	"bandit": {
		"scene":   "res://models/mobs/sand brigand/Meshy_AI_sand_brigand_v2_biped_Character_output.fbx",
		"library": "res://models/mobs/sand brigand/sand_brigand_animations.res",
		"texture_override": "res://models/mobs/sand brigand/Meshy_AI_sand_brigand_v2_biped_texture_0.png",
	},
	# Added 2026-09-19 — Reanimated Tomb Mummy (1.70m, same 24-bone Meshy/Mixamo
	# skeleton as the other humanoid mobs; Mutant Walking + Meshy run + Mixamo
	# idle/death/melee, both attack slots share the one melee clip).
	"mummy": {
		"scene":   "res://models/mobs/reanimated tomb mummy/Meshy_AI_mummy_tomb_guardian_r_biped_Character_output.fbx",
		"library": "res://models/mobs/reanimated tomb mummy/reanimated_tomb_mummy_animations.res",
		"texture_override": "res://models/mobs/reanimated tomb mummy/Meshy_AI_mummy_tomb_guardian_r_biped_texture_0.png",
	},
	"ghost": {
		"scene":   "res://models/mobs/tormented spirit/Meshy_AI_tormented_spirit_rig_biped_Character_output.fbx",
		"library": "res://models/mobs/tormented spirit/tormented_spirit_animations.res",
		"texture_override": "res://models/mobs/tormented spirit/Meshy_AI_tormented_spirit_rig_biped_texture_0.png",
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
	# Added 2026-09-18 — these 5 ship with albedo/roughness/metallic maps only
	# (no separate normal map), unlike rat/spiderling above; "normal" is left
	# out of each entry rather than pointed at a nonexistent file (see
	# _apply_critter_material()'s model_info.get("normal", "") — a missing key
	# just skips the normal map, which is the correct behavior here).
	"slime": {
		"scene": "res://models/mobs/acidic slime/Meshy_AI_acidic_slime_remesh_0919003424_texture.fbx",
		"albedo": "res://models/mobs/acidic slime/Meshy_AI_acidic_slime_remesh_0919003424_texture.png",
		"roughness": "res://models/mobs/acidic slime/Meshy_AI_acidic_slime_remesh_0919003424_texture_roughness.png",
		"metallic": "res://models/mobs/acidic slime/Meshy_AI_acidic_slime_remesh_0919003424_texture_metallic.png",
	},
	"bat": {
		"scene": "res://models/mobs/dusk bat/Meshy_AI_dusk_bat_remesh_0919003344_texture.fbx",
		"albedo": "res://models/mobs/dusk bat/Meshy_AI_dusk_bat_remesh_0919003344_texture.png",
		"roughness": "res://models/mobs/dusk bat/Meshy_AI_dusk_bat_remesh_0919003344_texture_roughness.png",
		"metallic": "res://models/mobs/dusk bat/Meshy_AI_dusk_bat_remesh_0919003344_texture_metallic.png",
	},
	"spider": {
		"scene": "res://models/mobs/giant desert spider/Meshy_AI_giant_desert_spider_r_0919003352_texture.fbx",
		"albedo": "res://models/mobs/giant desert spider/Meshy_AI_giant_desert_spider_r_0919003352_texture.png",
		"roughness": "res://models/mobs/giant desert spider/Meshy_AI_giant_desert_spider_r_0919003352_texture_roughness.png",
		"metallic": "res://models/mobs/giant desert spider/Meshy_AI_giant_desert_spider_r_0919003352_texture_metallic.png",
	},
	"snake": {
		"scene": "res://models/mobs/sand viper/Meshy_AI_sand_viper_remesh_0919003420_texture.fbx",
		"albedo": "res://models/mobs/sand viper/Meshy_AI_sand_viper_remesh_0919003420_texture.png",
		"roughness": "res://models/mobs/sand viper/Meshy_AI_sand_viper_remesh_0919003420_texture_roughness.png",
		"metallic": "res://models/mobs/sand viper/Meshy_AI_sand_viper_remesh_0919003420_texture_metallic.png",
	},
	"dune_scarab": {
		"scene": "res://models/mobs/dune scarab/Meshy_AI_dune_scarab_remesh_0919003047_texture.fbx",
		"albedo": "res://models/mobs/dune scarab/Meshy_AI_dune_scarab_remesh_0919003047_texture.png",
		"roughness": "res://models/mobs/dune scarab/Meshy_AI_dune_scarab_remesh_0919003047_texture_roughness.png",
		"metallic": "res://models/mobs/dune scarab/Meshy_AI_dune_scarab_remesh_0919003047_texture_metallic.png",
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
# Printed to the combat log on death when non-empty (user-authored per
# monster in monsters.json — the field exists on every monster now but
# starts blank; added 2026-09-19, see die() for where it's used).
@export var death_text: String = ""

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
# Low-health flight (2026-09-21): a monster that is not undead turns and runs once its health drops to LOW_HEALTH_FLEE_FRACTION, for
# LOW_HEALTH_FLEE_SECONDS, away from whoever it was fighting, then comes back and fights on (it flees once per fight: no rubber-banding).
# monsters.json "flees": false opts a type out. Undead never flee: they do not fear death.
const LOW_HEALTH_FLEE_FRACTION := 0.10
const LOW_HEALTH_FLEE_SECONDS := 7.0
const LOW_HEALTH_FLEE_SPEED := 0.6   # badly hurt and trying to get away: a limp, not a sprint (was 1.5x)
var _has_fled: bool = false
var _flee_from: Node3D = null      # set while running away from a threat (otherwise fear flees in random directions)
var flees_at_low_health: bool = true
var target_key: String = ""        # who this monster is fighting, replicated for "target's target" (TargetFrame.target_key_of)

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

# Break-early chance (2026-09-17, per the user's spec for Troubadour's
# toggled/repeated charm song): rolled periodically rather than once, so a
# charm that's re-cast every recast_time (10s for Charm Melody) genuinely
# risks not making it to the next refresh, not just to its own 30s cap.
# Values are a starting placeholder — tune once played.
const CHARM_BREAK_CHECK_INTERVAL := 5.0
const CHARM_BREAK_CHANCE := 0.15
var _charm_break_timer: float = 0.0
# Set alongside every animation_player.play() call below, replicated (see
# monster_template.tscn's MultiplayerSynchronizer) so a non-authoritative
# client just mirrors whatever animation the server/single-player simulation
# decided, instead of running its own (removed) AI to decide independently.
var anim_state: String = ""

# Kept for backward compat — always mirrors combat_node.current_hp
var monster_description: String = ""
## Set by GateRaidManager: while this is set the monster marches straight there (a brisk walk) instead of wandering, and it
## clears itself on arrival, after which the monster mills about that spot. Anything that sees a player still chases first.
var march_target: Vector3 = Vector3.INF
var _nameplate_timer := 0.0
const MARCH_SPEED_MULTIPLIER: float = 1.6
var model_from: String = ""        # monsters.json "model_from": borrow this type's model (see the stats block in _ready)
var model_scale: float = 1.0
var model_tint: Color = Color.WHITE
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
const NAMEPLATE_DISTANCE := 20.0  # metres: a mob's nameplate shows only within this distance of your own player
const NAMEPLATE_REFRESH := 0.2   # seconds between nameplate/visibility refreshes on a client
const DORMANT_DISTANCE := 120.0  # metres from the nearest player beyond which an idle/patrolling monster stops running its AI
var _regen_timer: float = 0.0
# Personal/instanced loot (2026-09-17) — each player gets their own
# independently-rolled loot from the same corpse, rather than one shared
# roll everyone fights over. Keyed by peer id so re-opening the window shows
# the same roll rather than re-rolling every click, and so one player
# emptying their own loot has zero effect on anyone else's.
# `_drop_loot_allowed` is set once from die()'s own `drop_loot` param — false
# for e.g. a guard's kill (guard_npc.gd calls die(false, false)), meaning
# nobody gets loot from this corpse at all, not just "nothing rolled yet."
var _drop_loot_allowed: bool = true
var _personal_loot: Dictionary = {}  # peer_id (int) -> Array of that peer's remaining drops
var loot_window: Node = null
# Corpse lifetime (2026-09-21): a corpse waits until everyone who fought it (each has their own loot roll) has looted it, then goes 2 s
# later; a corpse nobody empties (ignored, or loot left in it) goes after 5 minutes. Server side; the looters report in by RPC.
var corpse_loot_timeout: float = 300.0
var corpse_looted_linger: float = 2.0
var _loot_eligible: Dictionary = {}   # peer id -> true: the players who fought it
var _looted_peers: Dictionary = {}    # peer id -> true: has emptied (or found nothing in) their own loot

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
# The CombatNode exists from construction, not from _ready(): a client builds a spawned monster and applies the server's
# spawn state (CombatNode:current_hp, max_hp) BEFORE _ready runs — it used to fail with "Node 'CombatNode:current_hp' not
# found" for every monster that appeared, and the monster's starting health was lost (test 29 log).
func _init() -> void:
	combat_node = CombatNode.new()
	combat_node.name = "CombatNode"
	add_child(combat_node)


func _ready() -> void:
	# Never ride another body (test 38: standing on a player's head, you were carried when they gated or zoned 1,200 m away).
	# There are no moving platforms in the world, so nothing underfoot should move you.
	platform_floor_layers = 0
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
		# Varying levels per the Zone Spawn Sheet's per-mob Level range (e.g.
		# "a spider" = 2-4) — picks a random level within [level_min,
		# level_max] each spawn, same mob otherwise reading identically from
		# an appraisal/spawn-table standpoint every time. Falls back to the
		# flat "level" above for any monster without a range defined yet
		# (currently: everything outside Lumora Outskirts, not live yet).
		# Deliberately does NOT scale health/damage/armor_class by the rolled
		# level — those stay the flat values tuned for this monster; level's
		# existing effect on to-hit/resist chance (calculate_hit_chance()'s
		# level_modifier) already differentiates a level-4 spawn from a
		# level-2 one of the same mob.
		var base_level: int = level
		if stats.has("level_min") and stats.has("level_max"):
			level = randi_range(int(stats["level_min"]), int(stats["level_max"]))
		# Level scaling (Data/combat_balance.json): each level above the monster's base level in monsters.json adds
		# monster_hp_per_level / monster_damage_per_level (below the base level it removes them). Neutral = no scaling,
		# which is how it worked before — level then only changed attack and armor.
		var lvl_delta: int = level - base_level
		var scale_min: float = CombatBalance.num("monster_scale_min")
		var scale_max: float = CombatBalance.num("monster_scale_max")
		var hp_scale: float = clampf(1.0 + lvl_delta * CombatBalance.num("monster_hp_per_level"), scale_min, scale_max)
		max_health = int(round(max_health * hp_scale * CombatBalance.num("monster_hp_mult")))
		_balance_damage_scale = clampf(1.0 + lvl_delta * CombatBalance.num("monster_damage_per_level"), scale_min, scale_max)
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
		death_text      = stats.get("death_text", death_text)
		flees_at_low_health = bool(stats.get("flees", true)) and category != "undead"
		# A variant (a named mob, a blighted spider) reuses another type's model: "model_from" is that type, "model_scale" makes it
		# bigger or smaller, "tint" ([r, g, b], multiplied into the texture) recolours it. No new art needed.
		model_from      = str(stats.get("model_from", ""))
		loot_from       = str(stats.get("loot_from", ""))
		kill_standing   = stats.get("kill_standing", {}) if stats.get("kill_standing") is Dictionary else {}
		knockback_immune = bool(stats.get("knockback_immune", false))
		wary = bool(stats.get("wary", false))
		_load_abilities(stats)
		on_hit_effect = stats.get("on_hit_effect", {}) if stats.get("on_hit_effect") is Dictionary else {}
		attack_verbs = stats.get("attack_verbs", []) if stats.get("attack_verbs") is Array else []
		model_scale     = float(stats.get("model_scale", 1.0))
		var tint_arr = stats.get("tint", null)
		if typeof(tint_arr) == TYPE_ARRAY and tint_arr.size() >= 3:
			model_tint = Color(float(tint_arr[0]), float(tint_arr[1]), float(tint_arr[2]))

	var visual_key := model_from if not model_from.is_empty() else monster_name
	if visual_key in HUMANOID_MOB_TYPES:
		_setup_humanoid_visual(visual_key)
	elif visual_key in CRITTER_MODELS:
		_setup_critter_visual(visual_key)

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

func _setup_humanoid_visual(visual_key: String) -> void:
	mesh_instance.visible = false

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35 * model_scale
	capsule.height = 1.8 * model_scale
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0, 0.9 * model_scale, 0)

	var model_info: Dictionary = MOB_MODELS.get(visual_key, DEFAULT_HUMANOID_MOB_MODEL)
	var character_scene := load(model_info["scene"])
	var character: Node3D = character_scene.instantiate()
	character.name = "Character"
	MeshSmoothing.smooth_model(character)   # smooth shading (mesh_smoothing.gd)
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)  # same 180°-Y facing fix baked into player3d.tscn/guard_npc.tscn's Character node
	character.scale = Vector3.ONE * model_scale
	add_child(character)

	animation_player = character.get_node("AnimationPlayer")
	var lib := load(model_info["library"]) as AnimationLibrary
	if lib and animation_player:
		# Some libraries (the reanimated mummy's) were saved with EVERY clip set to play once, idle/walk/run included,
		# so they stopped after one cycle and got restarted with a visible pop. Movement clips must loop.
		for looping_clip in ["idle", "walk", "run"]:
			if lib.has_animation(looping_clip) and lib.get_animation(looping_clip).loop_mode == Animation.LOOP_NONE:
				lib.get_animation(looping_clip).loop_mode = Animation.LOOP_LINEAR
		if animation_player.has_animation_library(""):
			animation_player.remove_animation_library("")
		animation_player.add_animation_library("", lib)

	if model_info.has("texture_override"):
		_apply_texture_override(character, model_info["texture_override"], model_info.get("tint", Color.WHITE) * model_tint)
	elif model_tint != Color.WHITE:
		push_warning("%s has a tint but its model has no texture_override to tint" % monster_name)


# Meshy-sourced FBX exports never carry their real texture through to Godot
# reliably (confirmed recurring bug across every model built this way), so
# apply it as a runtime material override instead of trusting the FBX's own
# material.
func _apply_texture_override(node: Node, texture_path: String, tint: Color = Color.WHITE) -> void:
	var tex := load(texture_path) as Texture2D
	if not tex:
		push_warning("⚠️ Mob texture override not found: %s" % texture_path)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = tint
	_apply_material_recursive(node, mat)


# Non-humanoid critter with a real but unrigged model (single static mesh,
# no AnimationPlayer) — same shape as wildspeaker_pet.gd's model handling.
# No animation swapping needed since there's nothing to swap; _update_animation()
# below already no-ops harmlessly when animation_player is null.
func _setup_critter_visual(visual_key: String) -> void:
	mesh_instance.visible = false

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4 * model_scale
	capsule.height = 1.0 * model_scale
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0, 0.5 * model_scale, 0)

	var model_info: Dictionary = CRITTER_MODELS[visual_key]
	var character_scene := load(model_info["scene"])
	if not character_scene:
		return
	var character: Node3D = character_scene.instantiate()
	character.name = "Character"
	# Same 180°-Y facing fix every Meshy/Mixamo model in this codebase needs.
	# Every one of these critter meshes has its pivot sitting somewhere above
	# its actual lowest geometry (clipped through the floor at
	# Transform3D.IDENTITY) by a different, model-specific amount — measured
	# precisely 2026-09-19 via world-space AABB (mesh bottom vs. character
	# root position) after a "sunk into the ground" report on the 2026-09-18
	# critters; Juvenile Spider was the only one already correct at 0.
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)
	const GROUND_OFFSET := {
		"rat": 0.4,
		"snake": 0.22,
		"spider": 0.38,
		"spiderling": 0.34,  # added 2026-09-19 — measured 0.342m below the floor; it was rendering half-buried
		"bat": 0.9,
		"slime": 0.95,
		"dune_scarab": 0.46,
	}
	if GROUND_OFFSET.has(visual_key):
		character.position.y += GROUND_OFFSET[visual_key] * model_scale
	character.scale = Vector3.ONE * model_scale
	add_child(character)

	_apply_critter_material(character, model_info)


# Same texture-never-survives-FBX-export issue as every other Meshy model
# here — applied as a runtime material override using all of this asset
# type's real PBR maps (normal/roughness/metallic), same as
# phantasmal_echo_pet.gd's _apply_spirit_pet_material().
# How each unrigged critter moves (Shaders/critter_motion.gdshader, test 41): the body type (mode), which of its mesh's
# axes the body lies along (0 x, 1 y; Z is up in these meshes) and which end is the tail. Measured from the meshes.
const CRITTER_MOTION := {
	"rat": {"mode": 0, "axis": 1, "tail": 1.0},
	"spider": {"mode": 1, "axis": 0, "tail": 1.0},
	"spiderling": {"mode": 1, "axis": 0, "tail": 1.0},
	"dune_scarab": {"mode": 1, "axis": 1, "tail": -1.0},
	"snake": {"mode": 2, "axis": 0, "tail": 1.0},
	"bat": {"mode": 3, "axis": 0, "tail": 1.0},
	"slime": {"mode": 4, "axis": 0, "tail": 1.0},
}
const CRITTER_SHADER := "res://Shaders/critter_motion.gdshader"
var _critter_meshes: Array = []
var _critter_time := 0.0
var _critter_attack := 0.0
var _critter_speed := 0.0
var _critter_last_pos := Vector3.INF
var _critter_seen_state := ""


func _apply_critter_material(node: Node, model_info: Dictionary) -> void:
	var albedo_path: String = model_info.get("albedo", "")
	var albedo := (load(albedo_path) as Texture2D) if not albedo_path.is_empty() else null
	if not albedo:
		push_warning("⚠️ Critter texture override not found for %s" % monster_name)
		return
	var motion: Dictionary = CRITTER_MOTION.get(visual_key_of(), {})
	if not motion.is_empty() and ResourceLoader.exists(CRITTER_SHADER):
		_apply_critter_motion(node, model_info, albedo, motion)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo
	mat.albedo_color = model_tint

	# Not every critter ships a normal/roughness/metallic map (e.g. the 2026-
	# 09-18 desert critters have only albedo/roughness/metallic) — an empty
	# key is left out of model_info entirely rather than pointed at a
	# nonexistent file, since load("") logs a scary-looking (but otherwise
	# harmless) engine error instead of just returning null.
	var normal_path: String = model_info.get("normal", "")
	var normal := (load(normal_path) as Texture2D) if not normal_path.is_empty() else null
	if normal:
		mat.normal_enabled = true
		mat.normal_texture = normal

	var roughness_path: String = model_info.get("roughness", "")
	var roughness := (load(roughness_path) as Texture2D) if not roughness_path.is_empty() else null
	if roughness:
		mat.roughness_texture = roughness

	var metallic_path: String = model_info.get("metallic", "")
	var metallic := (load(metallic_path) as Texture2D) if not metallic_path.is_empty() else null
	if metallic:
		mat.metallic_texture = metallic
		mat.metallic = 1.0  # metallic_texture modulates this scalar — 1.0 lets the map through unscaled

	_apply_material_recursive(node, mat)


# The motion shader on every mesh of the critter, each told its own box (so the shader knows head, tail, legs, wings).
func _apply_critter_motion(node: Node, model_info: Dictionary, albedo: Texture2D, motion: Dictionary) -> void:
	_critter_meshes.clear()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var box := m.get_aabb()
		var mat := ShaderMaterial.new()
		mat.shader = load(CRITTER_SHADER)
		mat.set_shader_parameter("mode", int(motion["mode"]))
		mat.set_shader_parameter("body_axis", int(motion["axis"]))
		mat.set_shader_parameter("tail_sign", float(motion["tail"]))
		mat.set_shader_parameter("box_center", box.get_center())
		mat.set_shader_parameter("box_half", box.size * 0.5)
		mat.set_shader_parameter("tint", model_tint)
		mat.set_shader_parameter("albedo_tex", albedo)
		for key in ["normal", "roughness", "metallic"]:
			var path := str(model_info.get(key, ""))
			var tex := load(path) as Texture2D if not path.is_empty() else null
			if tex:
				mat.set_shader_parameter(key + "_tex", tex)
				if key != "roughness":
					mat.set_shader_parameter("use_" + key, true)
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, mat)
		# the shader moves vertices past the mesh's own box (a wing beat, a tail swish): don't cull it early
		m.extra_cull_margin = maxf(box.size.x, maxf(box.size.y, box.size.z)) * 0.6
		_critter_meshes.append(m)
	_critter_time = randf() * 10.0   # no two rats in step


func visual_key_of() -> String:
	for key in CRITTER_MODELS:
		if get_node_or_null("Character") != null and str(CRITTER_MODELS[key]["scene"]) == str(get_node("Character").scene_file_path):
			return key
	return ""


# Every frame on every screen: how fast it's really moving (from its position, so a copy on a player's screen moves too),
# its clock (running faster at speed), and the attack pulse (a critter's "attack" state, replicated, sets it off).
func _update_critter_motion(delta: float) -> void:
	var p := global_position
	var step := 0.0 if _critter_last_pos == Vector3.INF else Vector2(p.x - _critter_last_pos.x, p.z - _critter_last_pos.z).length() / maxf(delta, 0.001)
	_critter_last_pos = p
	_critter_speed = lerpf(_critter_speed, minf(step, 12.0), 0.15)
	var mv := clampf(_critter_speed / 3.0, 0.0, 1.5)
	_critter_time += delta * (0.5 + 1.2 * mv)
	if anim_state == "attack" and _critter_seen_state != "attack":
		_critter_attack = 1.0
	_critter_seen_state = anim_state
	_critter_attack = maxf(0.0, _critter_attack - delta / 0.35)
	if is_multiplayer_authority() and anim_state == "attack" and _critter_attack < 0.3:
		anim_state = "idle"   # the lunge is over (replicated)
	if Net.is_dedicated_server:
		return
	for m in _critter_meshes:
		if is_instance_valid(m):
			m.set_instance_shader_parameter("anim_time", _critter_time)
			m.set_instance_shader_parameter("move", mv)
			m.set_instance_shader_parameter("attack", sin(_critter_attack * PI) if _critter_attack > 0.0 else 0.0)


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
# A one-shot clip (death, an attack swing) that has FINISHED leaves current_animation empty, which used to read as "not
# playing the replicated state yet" and restarted it every frame — the reanimated mummy's death animation played over
# and over. Now a one-shot state is played once per state change; it can only play again after the state has changed.
var _one_shot_played: String = ""

func _play_replicated_animation() -> void:
	if not animation_player or animation_player.get_animation_list().is_empty():
		return
	if not animation_player.has_animation(anim_state) or animation_player.current_animation == anim_state:
		return
	if animation_player.get_animation(anim_state).loop_mode == Animation.LOOP_NONE:
		if _one_shot_played == anim_state:
			return
		_one_shot_played = anim_state
	else:
		_one_shot_played = ""
	animation_player.play(anim_state, 0.15)


func _play_attack_animation() -> void:
	if not _critter_meshes.is_empty() and (not animation_player or animation_player.get_animation_list().is_empty()):
		anim_state = "attack"   # a critter's lunge (critter_motion.gdshader), replicated
		_critter_attack = 1.0
		_critter_seen_state = "attack"
		return
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
var _balance_damage_scale: float = 1.0  # from the rolled level, see _ready()

func _configure_combat_node() -> void:
	combat_node.level = level
	combat_node.weapon_damage = damage
	combat_node.balance_damage_scale = _balance_damage_scale

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
# Every AI state used to set nav_agent.target_position EVERY physics frame, and NavigationAgent3D re-plans the whole path on
# every assignment even when the point hasn't changed — 60 mobs doing a full path search each frame. Cheap on the old flat
# zone's 391-polygon navmesh, the main source of lag on the Terrain3D zone's ~7,000 (test 17). Now the target only changes
# when it has moved more than NAV_RETARGET_DISTANCE, so a fixed patrol point is planned once and a chased player about
# every metre they move.
const NAV_RETARGET_DISTANCE := 1.0

func _set_nav_target(pos: Vector3) -> void:
	if nav_agent.target_position.distance_to(pos) > NAV_RETARGET_DISTANCE:
		nav_agent.target_position = pos


func _physics_process(delta: float) -> void:
	if not _critter_meshes.is_empty():
		_update_critter_motion(delta)
	if not Net.is_dedicated_server:
		_watch_for_auto_loot()
	# Per-viewer, not networked — see TargetFrame.is_hidden_from_local_player().
	# No monster data actually grants invisibility yet (nothing calls
	# apply_effect("invisibility", ...) on a monster's own combat_node), so
	# this is a no-op today; it's here so a future invisible-mob ability just
	# works without touching rendering code again. Runs regardless of
	# authority/DEAD state — even a corpse should respect see-invisible.
	# Nameplate above the mob's head, same pattern as player3d.gd's own
	# $NameLabel — reuses TargetFrame.nameplate_name() so stealth/invisibility
	# text formatting ("(a shadowy figure)") stays in one place instead of
	# being duplicated per entity type. A dedicated server shows nothing, so it
	# skips all of this; a client refreshes it a few times a second and only
	# shows a nameplate within NAMEPLATE_DISTANCE of its own player.
	if not Net.is_dedicated_server:
		_nameplate_timer -= delta
		if _nameplate_timer <= 0.0:
			_nameplate_timer = NAMEPLATE_REFRESH
			_refresh_nameplate()

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


	# Knocked back: slide away from the blow (walls stop it), nothing else happens meanwhile.
	if _knockback_time > 0.0:
		_knockback_time -= delta
		velocity.x = _knockback_velocity.x
		velocity.z = _knockback_velocity.z
		velocity.y = 0.0 if is_on_floor() else velocity.y - KNOCKBACK_GRAVITY * delta
		move_and_slide()
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

	# Re-resolved every frame to the NEAREST real player, not a single fixed
	# one. This used to be `TargetFrame.local_player()` — correct for a HUD
	# script (which wants "my own" player) but wrong here: monster AI only
	# ever runs on the server (see the is_multiplayer_authority() gate
	# above), where "the local player" means the HOST's own character, so a
	# monster would only ever notice/attack the host and never so much as
	# glance at any other connected player (2026-09-17 bug report: "monsters
	# don't seem to attack her; they run right to the host's player"). Once
	# aggro_table has real entries (from actual damage — see
	# apply_networked_damage()'s add_threat() call), get_current_target()
	# already correctly picks the highest-threat attacker over this default;
	# this only governs who gets noticed/chased before that.
	player = _nearest_player()
	if not is_instance_valid(player):
		if current_state == State.CHASE or current_state == State.ATTACK:
			force_disengage()   # everyone nearby is down or dead: give up the fight
		if target_key != "":
			target_key = ""
		return
	var fighting := TargetFrame.target_key_of(get_current_target()) if (current_state == State.CHASE or current_state == State.ATTACK) else ""
	if fighting != target_key:
		target_key = fighting

	# Dormant while no player is anywhere near: an idle/wandering monster far from every player skips its AI, pathing and
	# physics entirely (it can only notice someone within MAX_AGGRO_DISTANCE anyway). With one player online every monster
	# on the map used to wander and path each frame — ~10 ms of server physics for 64 mobs, enough on a slow VM to pile up
	# into the "Long frame: 0.5 s" stalls. Raiders marching on the gate keep marching; anything in a fight keeps fighting.
	if (current_state == State.IDLE or current_state == State.PATROL) and march_target == Vector3.INF and is_on_floor() \
			and global_position.distance_squared_to(player.global_position) > DORMANT_DISTANCE * DORMANT_DISTANCE:
		if current_state == State.PATROL:
			change_state(State.IDLE)
		velocity = Vector3.ZERO
		_update_animation()
		return


	if not _has_fled and flees_at_low_health and (current_state == State.CHASE or current_state == State.ATTACK) \
			and combat_node.current_hp > 0 and combat_node.current_hp <= int(combat_node.max_hp * LOW_HEALTH_FLEE_FRACTION):
		_start_low_health_flee()

	if _stun_hold > 0.0:
		_stun_hold -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 20.0 * delta
			move_and_slide()
		_update_animation()
		return
	# A spell being cast: it stands still and doesn't swing until it's done (or broken)
	if _tick_abilities(delta):
		if not is_on_floor():
			velocity.y -= 20.0 * delta
			move_and_slide()
		_update_animation()
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
	elif is_on_floor() and velocity.is_zero_approx():
		pass  # standing still on the ground: nothing to slide (move_and_slide() on the terrain is the costliest part of a mob's frame)
	else:
		# Always apply gravity so monsters don't float when idle or attacking
		if not is_on_floor():
			velocity.y -= 20.0 * delta
		else:
			velocity.y = 0.0
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
	_threat_target = attacker   # a taunt takes it outright (the switch margin below is for threat drifting past)
	if current_state == State.IDLE or current_state == State.PATROL:
		change_state(State.CHASE)

# Who it's fighting sticks: another attacker has to get THREAT_SWITCH_MARGIN times its current target's threat to pull it
# off (test 42, "rats seem to be moving back and forth facing away and towards the player in combat in an endless loop":
# a player and an assisting pet trading the top spot blow by blow turned it round and round between them).
const THREAT_SWITCH_MARGIN := 1.1
var _threat_target: Node = null

func get_current_target() -> Node:
	if aggro_table.is_empty():
		return player
	var best: Node = player
	var best_threat: float = aggro_table.get(player, 0.0)
	if is_instance_valid(player) and player.is_in_group("player") and _player_is_down(player):
		best_threat = -1.0   # its first target is down: anyone else still fighting it comes first
	for attacker in aggro_table:
		if not is_instance_valid(attacker) or (attacker.is_in_group("player") and _player_is_down(attacker)):
			continue
		if aggro_table[attacker] > best_threat:
			best_threat = aggro_table[attacker]
			best = attacker
	if not is_instance_valid(_threat_target):
		_threat_target = null   # gone (a pet dismissed, a player logged out): nothing to stick to
	var cur: Node = _threat_target
	if best != cur and cur != null and aggro_table.has(cur) and not (cur.is_in_group("player") and _player_is_down(cur)) \
			and best_threat < aggro_table[cur] * THREAT_SWITCH_MARGIN:
		best = cur
	_threat_target = best
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

	# Arrival is measured on the ground plane and must be FARTHER than the nav agent's own stopping distance
	# (target_desired_distance = 1.5 m). It used to be 1.0 m in 3D: the agent stopped at 1.5 m, called itself
	# finished, and the monster stood there forever because it never got within 1.0 m — measured: most
	# wandering monsters never moved after their first leg. After a leg the monster pauses (IDLE), then
	# wanders again, so it strolls in bursts instead of walking non-stop.
	var flat_to_target: float = Vector2(global_position.x - patrol_target.x, global_position.z - patrol_target.z).length()
	if flat_to_target <= PATROL_ARRIVE_DISTANCE:
		if march_target != Vector3.INF:
			march_target = Vector3.INF   # arrived: from now on it wanders around here
			spawn_position = global_position
		change_state(State.IDLE)
		return
	# Watchdog: no real progress toward the point for a while (blocked, wedged) -> give up on it, pause, pick another.
	if flat_to_target < _patrol_best_distance - 0.5:
		_patrol_best_distance = flat_to_target
		_patrol_stall_timer = 0.0
	else:
		_patrol_stall_timer += delta
		if _patrol_stall_timer >= PATROL_STALL_SECONDS:
			change_state(State.IDLE)
			return

	if is_inside_tree() and nav_agent:
		_set_nav_target(patrol_target)

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
		if nav_agent.is_navigation_finished():
			nav_agent.target_position = target.global_position  # "arrived" at an old spot but the target is out of reach: re-aim
		else:
			_set_nav_target(target.global_position)

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
func _start_low_health_flee() -> void:
	_has_fled = true
	var threat := get_current_target()
	_flee_from = threat as Node3D
	_pre_flee_state = current_state
	_flee_time_remaining = LOW_HEALTH_FLEE_SECONDS
	_flee_direction_timer = 0.0
	var desc: String = monster_description if monster_description != "" else get_monster_name()
	var text := "[color=#ffcc66]%s turns to flee![/color]" % desc.capitalize()
	GameLog.log_combat(text, global_position)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer():
		Net.broadcast_combat_message(text, global_position)
	change_state(State.FLEEING)


func apply_fear(duration: float) -> void:
	if current_state == State.DEAD:
		return
	if current_state != State.FLEEING:
		_pre_flee_state = current_state
	_flee_from = null   # a fear spell: it runs blindly, not from anyone in particular
	_flee_time_remaining = duration
	_flee_direction_timer = 0.0  # forces an immediate direction pick this frame
	change_state(State.FLEEING)


func state_fleeing(delta: float) -> void:
	_flee_time_remaining -= delta
	if _flee_time_remaining <= 0.0:
		_flee_from = null
		change_state(State.CHASE if not aggro_table.is_empty() else _pre_flee_state)
		return

	_flee_direction_timer -= delta
	if _flee_direction_timer <= 0.0:
		_flee_direction_timer = FLEE_DIRECTION_INTERVAL
		var angle := randf() * TAU
		_flee_direction = Vector3(cos(angle), 0, sin(angle))
		if is_instance_valid(_flee_from):
			# Running for its life: straight away from the threat (a little off-line so it does not look ruled), not a random heading.
			var away := global_position - _flee_from.global_position
			away.y = 0.0
			if away.length() > 0.01:
				_flee_direction = away.normalized().rotated(Vector3.UP, randf_range(-0.5, 0.5))

	# Direct movement, not nav_agent pathing — fleeing has no destination, just
	# a heading, and doesn't need to be graceful about it (same reasoning
	# guard_npc.gd's/pet_minion.gd's "stuck" direct-fallback movement uses:
	# straight-line movement plus a short obstacle check is good enough when
	# real pathing isn't the point).
	if _flee_direction != Vector3.ZERO:
		look_at_target(global_position + _flee_direction)
		var speed_3d: float = (speed / 10.0) * (1.0 - combat_node.get_modifier("speed_slow"))
		if is_instance_valid(_flee_from):
			speed_3d *= LOW_HEALTH_FLEE_SPEED
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
	_charm_break_timer = 0.0
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

	_charm_break_timer += delta
	if _charm_break_timer >= CHARM_BREAK_CHECK_INTERVAL:
		_charm_break_timer = 0.0
		if randf() < CHARM_BREAK_CHANCE:
			GameLog.log_general("[color=#ffcc66]%s breaks free of the charm early![/color]" % pet_name.capitalize())
			_end_charm()
			return

	match command:
		0:  # FOLLOW
			if nav_agent:
				_set_nav_target(charm_owner.global_position)
		1:  # ATTACK
			_charm_pursue_and_attack(charm_attack_target, delta)
		2:  # SIT
			if nav_agent:
				_set_nav_target(global_position)
		3:  # GUARD
			if not (is_instance_valid(charm_attack_target) and _target_alive_generic(charm_attack_target)):
				charm_attack_target = _find_nearest_hostile_to(charm_owner, CHARM_GUARD_SCAN_RADIUS)
			if is_instance_valid(charm_attack_target):
				_charm_pursue_and_attack(charm_attack_target, delta)
			elif nav_agent:
				_set_nav_target(guard_position)
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
			_set_nav_target(global_position)
		look_at_target(target.global_position)
		if can_attack:
			_perform_charmed_attack(target)
	elif nav_agent:
		_set_nav_target(target.global_position)


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
		# Credits the charm owner, not whoever happens to be running this code
		# (the server, per state_charmed()'s authority-gated call chain) —
		# same fix apply_networked_damage() already needed for ordinary kills.
		var credited_peer_id: int = charm_owner.get_multiplayer_authority() if is_instance_valid(charm_owner) else -1
		target.die(true, true, credited_peer_id)
		charm_attack_target = null


# ── Commands (pet_frame.gd's exact interface — see PetMinion's cmd_*()) ────
#
# Fixed 2026-09-17: these used to just mutate fields directly, which only
# actually controlled the monster's real behavior when the caster WAS the
# authoritative machine (the server) — a non-host player's charm would take
# (see apply_networked_charm() above), but their Follow/Attack/Sit/Guard
# clicks silently did nothing to the monster's real, server-simulated
# behavior; only the host's own clicks worked. Each cmd_*() now applies
# LOCALLY first (so the caster's own pet_frame.gd ring-highlight updates
# instantly regardless of who's authoritative — command/charm_attack_target
# aren't replicated fields, so this optimistic local update is the only
# thing that makes the control window feel responsive for a non-host caster)
# and ALSO relays to the server via RPC when this machine isn't the real
# authority, so the actual behavior change takes effect for everyone.

func cmd_attack(target: Node) -> void:
	if not is_instance_valid(target):
		GameLog.log_general("%s has no target to attack." % pet_name.capitalize())
		return
	_apply_charm_command("attack", target)


func cmd_follow() -> void:
	_apply_charm_command("follow", null)


func cmd_sit() -> void:
	_apply_charm_command("sit", null)


func cmd_guard() -> void:
	_apply_charm_command("guard", null)


func cmd_assist() -> void:
	_apply_charm_command("assist", null)


func cmd_back() -> void:
	_apply_charm_command("back", null)


func cmd_dismiss() -> void:
	_apply_charm_command("dismiss", null)


func _apply_charm_command(cmd: String, target: Node) -> void:
	match cmd:
		"attack":
			charm_attack_target = target
			command = 1
		"follow":
			charm_attack_target = null
			command = 0
		"sit":
			charm_attack_target = null
			command = 2
		"guard":
			charm_attack_target = null
			guard_position = global_position
			command = 3
		"assist":
			charm_attack_target = null
			command = 4
		"back":
			charm_attack_target = null
			command = 0
		"dismiss":
			GameLog.log_general("[color=#ffcc66]You release %s from your charm.[/color]" % pet_name.capitalize())
			_end_charm()

	if not is_multiplayer_authority():
		var target_path: String = str(target.get_path()) if is_instance_valid(target) else ""
		apply_networked_charm_command.rpc_id(1, cmd, target_path)


# Node references mean nothing across machines (same rule as apply_charm()'s
# owner param above), so cmd_attack's target crosses the wire as a NodePath
# string instead — safe here since both the hand-placed zone monsters and
# MultiplayerSpawner-spawned ones replicate matching node identities/paths
# across every peer already (the whole system depends on that being true).
@rpc("any_peer", "call_remote", "reliable")
func apply_networked_charm_command(cmd: String, target_path: String) -> void:
	if not is_multiplayer_authority():
		return
	var target: Node = get_node_or_null(NodePath(target_path)) if not target_path.is_empty() else null
	_apply_charm_command(cmd, target)


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

	var direction := Vector3.ZERO
	if not nav_agent.is_navigation_finished():
		var next_position: Vector3 = nav_agent.get_next_path_position()
		var to_next: Vector3 = next_position - global_position
		var flat_dir: Vector3 = Vector3(to_next.x, 0, to_next.z)
		if flat_dir.length() >= 0.1:
			direction = flat_dir.normalized()
	# Chasing but navigation has nothing to follow (it thinks it has arrived at a stale point, or this patch of ground
	# has no navmesh path) while the target is still out of reach: go straight at it — walls still stop it. Without this a
	# monster froze just out of range and never swung (the "rats never fight back" of tests 26 and 29, seen live: a
	# rat in CHASE at 2.09 m with a 2.0 m reach, not moving at all; another frozen 19 m away).
	if direction == Vector3.ZERO and current_state == State.CHASE:
		var chased: Node = get_current_target()
		if chased is Node3D:
			var gap := Vector3((chased as Node3D).global_position.x - global_position.x, 0, (chased as Node3D).global_position.z - global_position.z)
			if gap.length() > attack_range * 0.8:
				direction = gap.normalized()

	if direction != Vector3.ZERO:
		look_at_target(global_position + direction)
		var speed_3d = speed / 10.0
		if current_state == State.PATROL and march_target != Vector3.INF:
			speed_3d *= MARCH_SPEED_MULTIPLIER
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

	# A player or pet owned by ANOTHER peer: its real stats, HP and defensive skills
	# live only on its owner's machine — this (server) copy is a stat-less puppet, and
	# HP replicates owner -> everyone, never back. Resolving the swing here used to
	# dent only the server's puppet, so a remote player never lost any life. Ask the
	# owner to roll the defender side against its real character instead.
	if Net.is_multiplayer_game and target.is_inside_tree() and not target.is_multiplayer_authority():
		_rpc_resolve_attack_on_owner.rpc_id(target.get_multiplayer_authority(), target.get_path())
		return

	_resolve_attack_on(target)


# Runs on the peer that owns `target` (see perform_attack()), against that peer's
# replicated copy of this monster. Only the monster's attack stats matter here, and
# those are static per monster type, so every peer's copy agrees on them.
@rpc("authority", "call_remote", "reliable")
func _rpc_resolve_attack_on_owner(target_path: NodePath) -> void:
	var target := get_node_or_null(target_path)
	if not is_instance_valid(target) or not target.is_multiplayer_authority():
		return
	if current_state == State.DEAD:
		return
	_resolve_attack_on(target, true)


# The swing itself. `relayed` = we are the target's owner acting for the server:
# this machine's copy of the monster is only a puppet, so anything that would change
# the MONSTER (a riposte's damage) must go back to the real one instead.
# A player who is downed (0 HP or below, bleeding out) or dead is not a target. The player's own machine knows this via `dying`, but
# the SERVER's monsters (which are the ones fighting) only see the replicated fields, hence the health check too: without it a raid kept
# pounding a fallen player on a dedicated server (health -165/164).
static func _player_is_down(node: Node) -> bool:
	if "dying" in node and node.dying:
		return true
	var cn = node.get("combat_node") if "combat_node" in node else null
	return cn is CombatNode and cn.current_hp <= 0


func _resolve_attack_on(target: Node, relayed: bool = false) -> void:
	if target.is_in_group("player") and _player_is_down(target):
		return
	if "combat_node" in target and target.combat_node is CombatNode:
		var monster_hp_before: int = combat_node.current_hp
		var result = combat_node.resolve_attack(target.combat_node)
		if relayed:
			# resolve_attack() applied a riposte to OUR puppet copy of the monster — undo it
			# and hand the damage to the server, which owns the real one.
			combat_node.current_hp = monster_hp_before
			if result.get("result", "") == "RIPOSTE":
				apply_networked_damage.rpc_id(1, int(result.get("damage", 0)), multiplayer.get_unique_id())
			elif int(result.get("reflected", 0)) > 0:
				apply_networked_damage.rpc_id(1, int(result["reflected"]), multiplayer.get_unique_id())  # Improved Parry
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
		if target.is_in_group("player"):
			var msg: String = CombatLogFormatter.monster_attack(result, desc, attack_verb_type())
			if not msg.is_empty():
				GameLog.log_combat(msg)
			# Everyone else nearby reads the same swing with the victim's real name.
			if Net.is_multiplayer_game:
				var named: String = _attack_text_on_other(result, desc, str(target.get("player_name")))
				if not named.is_empty():
					Net.broadcast_combat_message(named, global_position)
			if target.has_method("on_attacked"):
				target.on_attacked(self)
			if target.has_method("_tick_defense_skill"):
				target._tick_defense_skill(result.get("result", ""))
			if int(result.get("reflected", 0)) > 0:
				var how := "You parry and strike back at" if result.get("result", "") == "PARRY" else "Your shield strikes back at"
				GameLog.log_combat("[color=#ffdd88]%s %s for [b]%d[/b] damage.[/color]" % [how, desc, int(result["reflected"])])
			if result.get("decoy", false):
				GameLog.log_combat("[color=#bb99ff]%s strikes one of your illusions, which shatters.[/color]" % desc.capitalize())
			if int(result.get("shared", 0)) > 0 and target.has_method("share_damage_with_group"):
				target.share_damage_with_group(int(result["shared"]))
			if result.get("result", "") == "HIT":
				_on_hit_defender_effects(target)
			if target.has_method("play_swung_at_sound"):
				target.play_swung_at_sound(str(result.get("result", "")), int(result.get("damage", 0)), self)
			if str(result.get("result", "")) == "HIT" and monster_name.contains("spider"):
				Sfx.play("spider_attack", self)
			if result.get("damage", 0) > 0 and target.has_method("on_combat_node_hit"):
				target.on_combat_node_hit(self)
		else:
			var target_name: String = "your ally"
			if "pet_name" in target:
				target_name = target.get("pet_name")
			elif "npc_name" in target:
				target_name = target.get("npc_name")  # e.g. Oni fighting a rat
			_log_attack_on_other(result, desc, target_name)
			if not target.combat_node.is_alive() and target.has_method("die"):
				target.die()
	elif target.has_method("take_damage"):
		target.take_damage(damage)
		if target.is_in_group("player"):
			var desc: String = monster_description if monster_description != "" else get_monster_name()
			GameLog.log_combat("%s hits you for [b]%d[/b] damage!" % [desc.capitalize(), damage])

	if is_social:
		call_nearby_allies()


func _log_attack_on_other(result: Dictionary, attacker_desc: String, target_name: String) -> void:
	var text := _attack_text_on_other(result, attacker_desc, target_name)
	if not text.is_empty():
		GameLog.log_combat(text, global_position)


func _attack_text_on_other(result: Dictionary, attacker_desc: String, target_name: String) -> String:
	var cap := attacker_desc.capitalize()
	match result.get("result", ""):
		"MISS":
			return "%s misses %s!" % [cap, target_name]
		"PARRY":
			return "%s's attack on %s is parried!" % [cap, target_name]
		"BLOCK":
			return "%s's attack on %s is blocked!" % [cap, target_name]
		"DODGE":
			return "%s's attack on %s is dodged!" % [cap, target_name]
		"RIPOSTE":
			return "%s is riposted by %s for [b]%d[/b] damage!" % [cap, target_name, result.get("damage", 0)]
		"HIT":
			var crit: String = " [color=#ffaa00]Critical![/color]" if result.get("is_crit", false) else ""
			var verb := attack_verb_type()
			return "%s %s %s for [b]%d[/b] damage!%s" % [cap, verb.substr(5) if verb.begins_with("verb:") else "hits", target_name, result.get("damage", 0), crit]
	return ""


func apply_damage(amount: int, damage_type: String = "physical") -> void:
	if current_state == State.DEAD:
		return

	# Allow child classes to apply resistances/weaknesses before CombatNode takes over
	var modified_damage = modify_damage(amount, damage_type)
	combat_node.take_damage(modified_damage)

	print("DEBUG: %s hit for %d, HP: %d/%d" %
		[get_monster_name(), modified_damage, combat_node.current_hp, combat_node.max_hp])

	# On a joined client this monster is a puppet: the hit above only nudges its local copy of the health (the server's real number
	# replicates over it). The kill itself belongs to the server, which the caller has already told (apply_networked_damage). Running
	# die() here as well played the death animation a second time and paid the kill's XP twice ("goblins run their death animation
	# multiple times" and double XP on spell kills).
	if not is_multiplayer_authority():
		return

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

# Creatures have no weapons: what the combat log says they do to you ("A sand viper bites you for 5 damage!").
# monsters.json "attack_verbs": ["stings", ...] overrides the category's; humanoids and undead keep their weapon verbs.
const NATURAL_ATTACK_VERBS := {
	"animal": ["bites", "claws", "scratches"],
	"reptile": ["bites"],
	"insect": ["bites", "pinches"],
}
var attack_verbs: Array = []

func attack_verb_type() -> String:
	var verbs: Array = attack_verbs if not attack_verbs.is_empty() else NATURAL_ATTACK_VERBS.get(category, [])
	return ("verb:" + str(verbs[randi() % verbs.size()])) if not verbs.is_empty() else get_damage_type()


func get_damage_type() -> String:
	match category:
		"humanoid": return "slashing"
		"animal":   return "blunt"
		"insect":   return "piercing"
		"reptile":  return "piercing"
		"undead":   return "blunt"
		_:          return "generic"

const DEATH_LINE_PATH := "res://Data/humanoid_death_lines.json"

var _death_handled := false
signal died

# Auto-Loot on Kill (Options; test 42: "a check box that will automatically loot the area when a monster is killed"): on each
# player's own machine, when a monster that was in a fight (it had a target) or that they had targeted dies within Loot
# All's reach, their player loots everything in reach, as the G key does. Loot is personal, so it only ever takes theirs.
var _seen_dead := false
var _was_fighting := false

func _watch_for_auto_loot() -> void:
	if current_state != State.DEAD:
		if target_key != "":
			_was_fighting = true
		return
	if _seen_dead:
		return
	_seen_dead = true
	if not Global.settings.get("auto_loot", false):
		return
	var me := TargetFrame.local_player()
	if not is_instance_valid(me) or not me.has_method("loot_all_nearby") or Monster._player_is_down(me):
		return
	if not (_was_fighting or me.get("current_target") == self):
		return
	if me.global_position.distance_to(global_position) > me.LOOT_ALL_RANGE:
		return
	me.loot_all_nearby(true)

func die(award_xp: bool = true, drop_loot: bool = true, credited_peer_id: int = -1) -> void:
	# Once only. Every hit that lands on a body (a second attacker, a damage-over-time tick, a guard's or pet's swing a moment
	# later) used to reach here again: the death animation restarted from the top each time ("goblins run their death animation
	# several times") and the kill's XP and loot rights were handed out again.
	if _death_handled:
		return
	_death_handled = true
	died.emit()   # mob_spawner3d.gd starts this spawn point's respawn timer
	_cancel_cast()
	_dismiss_summons()
	change_state(State.DEAD)
	target_key = ""
	print("💀 %s died! (XP: %d, Coins: %.2f, Category: %s)" % [monster_name, xp_gain, coin_modifier, category])

	if category == "humanoid":
		var line := NPCFlavorText.new(DEATH_LINE_PATH).get_line("death")
		if line != "":
			var desc: String = monster_description if monster_description != "" else get_monster_name()
			var spoken := Languages.npc_line(Languages.of_monster(monster_name, category), line)
			GameLog.log_general("[color=#cc8888]%s says%s, \"%s\"[/color]" % [desc.capitalize(), spoken[0], spoken[1]])

	# User-authored per-monster flavor line from monsters.json's "death_text"
	# (blank on every monster until filled in — nothing prints then).
	if death_text != "":
		GameLog.log_combat(death_text, global_position)

	# No shared roll here anymore — each player who actually right-clicks the
	# corpse gets their own independent roll, lazily, in open_loot_window().
	# _drop_loot_allowed just gates whether that's allowed to happen at all
	# (false for e.g. a guard's kill).
	_drop_loot_allowed = drop_loot

	# Award XP to whoever's credited with the kill — local player by default
	# (not index 0, see the same note in _physics_process() above), or a
	# specific peer when called via apply_networked_damage() below (a
	# non-host client's kill, resolved on the server). If the credited player
	# is THIS machine's own (single-player, or the host killing something
	# themselves), apply directly; otherwise Global.player_data is this
	# process's own save data — there's no way to reach into a remote peer's
	# save file directly — so relay it via RPC to their own machine instead.
	_loot_eligible.clear()
	for attacker in aggro_table:
		if is_instance_valid(attacker) and attacker.is_in_group("player"):
			_loot_eligible[attacker.get_multiplayer_authority()] = true
	if credited_peer_id != -1:
		_loot_eligible[credited_peer_id] = true
	else:
		var killer := TargetFrame.local_player()
		if is_instance_valid(killer):
			_loot_eligible[killer.get_multiplayer_authority()] = true

	if award_xp:
		var p: Node = TargetFrame.peer_id_to_player_node(credited_peer_id) if credited_peer_id != -1 else TargetFrame.local_player()
		if is_instance_valid(p):
			# The whole group shares the kill (test 41: a healer standing back got nothing unless she hit it herself):
			# everyone grouped with the killer, in this zone and within XP_SHARE_RANGE, splits it, with a bonus per member.
			var recipients := xp_recipients(p)
			var share := group_xp_share(xp_gain, recipients.size())
			for r in recipients:
				# Resting by a player's campfire (campfire_relay.gd) adds its tier's bonus: worked out here, where the server records the XP
				var got := share
				var fire_bonus := CampfireRelay.xp_bonus_at(get_tree(), (r as Node3D).global_position)
				if fire_bonus > 0.0:
					got = int(round(share * (1.0 + fire_bonus)))
				# The server's own record of the XP it awarded (server trust checks saves against it; telemetry logs it).
				Net.note_kill(r.get_multiplayer_authority(), got, str(monster_description if monster_description != "" else get_monster_name()), int(combat_node.level) if combat_node else 0)
				if r.is_multiplayer_authority():
					r.grant_xp(got)
				elif r.has_method("receive_kill_credit"):
					r.receive_kill_credit.rpc_id(r.get_multiplayer_authority(), got)
				# Faction: killing a Djhanid costs standing with the clans; killing the Dustwalkers who ruin their name earns some.
				if not kill_standing.is_empty() and r.has_method("receive_standing_changes"):
					if r.is_multiplayer_authority():
						r.receive_standing_changes(JSON.stringify(kill_standing))
					else:
						r.receive_standing_changes.rpc_id(r.get_multiplayer_authority(), JSON.stringify(kill_standing))

	if animation_player and animation_player.has_animation("death"):
		anim_state = "death"  # replicated — see _play_replicated_animation()
		animation_player.play("death")

	if not drop_loot:
		queue_free()
		return

	var deadline := Time.get_ticks_msec() + int(corpse_loot_timeout * 1000.0)
	while is_inside_tree() and Time.get_ticks_msec() < deadline and not _everyone_looted():
		await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	if _everyone_looted():
		await get_tree().create_timer(corpse_looted_linger).timeout
		if not is_inside_tree():
			return
	if is_instance_valid(loot_window):
		loot_window.queue_free()
	queue_free()


# Has everyone who is entitled to loot this corpse looted it? Nobody has yet -> keep waiting (up to the timeout). A player who
# fought it but has left the game does not hold it up. Nobody credited at all: the first person to loot it is enough.
func _everyone_looted() -> bool:
	if _looted_peers.is_empty():
		return false
	if _loot_eligible.is_empty():
		return true
	var connected: Array = Array(multiplayer.get_peers()) if multiplayer.has_multiplayer_peer() else []
	for peer in _loot_eligible:
		if _looted_peers.has(peer):
			continue
		if peer == multiplayer.get_unique_id() or connected.has(peer):
			return false
	return true


# This peer has emptied its own loot (or found there was none): tell the server, whose timer decides when the body goes.
func _report_looted() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_looted_peers[multiplayer.get_unique_id()] = true
	else:
		_rpc_looted.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_looted() -> void:
	if multiplayer.is_server():
		_looted_peers[multiplayer.get_remote_sender_id()] = true


# A body that is removed (by the server, for everyone) takes this peer's open loot window with it.
func _exit_tree() -> void:
	if is_instance_valid(loot_window):
		loot_window.queue_free()



const XP_SHARE_RANGE := 100.0        # metres from the kill a group member must be to share it
const GROUP_XP_BONUS := 0.1          # the group earns 10% more per extra member, split evenly


# Who shares this kill's XP: the killer and everyone grouped with them who's in this zone and near. Groups live on the
# world link on a server (world_link.gd, by name); in a one-machine game, on the killer's own group_members.
func xp_recipients(killer: Node) -> Array:
	var out: Array = [killer]
	var near := func(n: Node) -> bool:
		return is_instance_valid(n) and n != killer and not out.has(n) and (n as Node3D).global_position.distance_to(global_position) <= XP_SHARE_RANGE
	var link := get_tree().get_first_node_in_group("world_link")
	var names: Array = []
	if link != null and link.get("groups") is Dictionary and not (link.groups as Dictionary).is_empty():
		var g: String = link._group_of(str(killer.get("player_name")))
		if not g.is_empty():
			names = link.groups[g]["members"]
	if not names.is_empty():
		for n in get_tree().get_nodes_in_group("player"):
			if names.any(func(m): return str(m).to_lower() == str(n.get("player_name")).to_lower()) and near.call(n):
				out.append(n)
	elif killer.get("group_members") is Array:
		for pid in killer.group_members:
			var n: Node = TargetFrame.peer_id_to_player_node(int(pid))
			if near.call(n):
				out.append(n)
	return out


static func group_xp_share(xp: int, members: int) -> int:
	if members <= 1:
		return xp
	return maxi(1, int(round(xp * (1.0 + GROUP_XP_BONUS * (members - 1)) / members)))


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
	# Threat registration was missing entirely for every non-host attacker —
	# player3d.gd's own add_threat() call (right next to this RPC on the
	# caller's side) only ever mutates that CALLER's own non-authoritative
	# puppet copy of this monster when they're not the host, so the real
	# (server-side) aggro_table never learned about their damage at all. That
	# combined with _nearest_player() replacing a host-only player reference
	# is the other half of the 2026-09-17 "she never gets attacked" report —
	# without this, even a monster that finally notices/chases a non-host
	# player would still credit all the actual fight to the host and keep
	# switching back to them, since threat never really updates on the real
	# monster. Uses the plain damage amount rather than
	# attacker.combat_node.generate_threat(amount) — active_effects (stance
	# threat_mult) isn't a replicated field, so the server's copy of a remote
	# player's combat_node can't compute that bonus accurately; this is the
	# same "trust the attacker's own reported number" trade-off the damage
	# amount itself already makes.
	var attacker: Node = _resolve_peer_to_player(attacker_peer_id)
	if attacker:
		add_threat(attacker, float(amount))
	if not combat_node.is_alive():
		die(true, true, attacker_peer_id)


# Knockback (Power Strike, Earth Strike, Titan's Strike: "knockback" metres in player_spells.json): pushes the monster
# straight away from `from` over KNOCKBACK_TIME. Only the authority moves it; a client's puppet asks the server
# (apply_networked_knockback). monsters.json "knockback_immune": true opts a monster out.
const KNOCKBACK_TIME := 0.25
const KNOCKBACK_GRAVITY := 20.0
var knockback_immune := false
# monsters.json "on_hit_effect": {"name", "chance", "tick_damage", "tick_interval", "duration", "modifiers"} — a landed hit may leave it on
# (modifiers: {"speed_slow": 0.35} a snare, {"hit_chance": -20} blindness, {"damage_mult": -0.15} weakness,
# {"armor_bonus": -4} sundered armour; the ailment names and texts are in buff_bar.gd / player3d.gd MONSTER_AILMENTS)
# the player (snakes and spiders: Weak Poison). Applied on the player's own machine, where their health lives.
var on_hit_effect: Dictionary = {}
var loot_from := ""   # monsters.json "loot_from": use this monster's loot table while this one has none of its own
var wary := false   # monsters.json "wary": never attacks first unless the player's standing makes it hate them
var kill_standing: Dictionary = {}   # monsters.json "kill_standing": {"Djhanid Clans": -15} applied to whoever gets the kill
var _knockback_time := 0.0
var _knockback_velocity := Vector3.ZERO

func knockback(from: Vector3, distance: float) -> void:
	if not is_multiplayer_authority() or current_state == State.DEAD or knockback_immune or distance <= 0.0:
		return
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.01:
		away = global_transform.basis.z
		away.y = 0.0
	_knockback_velocity = away.normalized() * (distance / KNOCKBACK_TIME)
	_knockback_time = KNOCKBACK_TIME
	if combat_node and combat_node.is_casting:
		combat_node.is_casting = false  # being moved breaks a cast (monsters don't cast yet; this is the rule for when they do)
		combat_node.current_cast_time = 0.0


@rpc("any_peer", "call_remote", "reliable")
func apply_networked_knockback(from: Vector3, distance: float) -> void:
	knockback(from, clampf(distance, 0.0, 10.0))


# A non-host player's Taunt: threat lives only in the server's aggro_table, so the caster's own puppet copy of the monster cannot be
# taunted — the request goes to the server, which sets the caster's threat just above the highest (see taunt()).
@rpc("any_peer", "call_remote", "reliable")
func apply_networked_taunt(attacker_peer_id: int) -> void:
	if not is_multiplayer_authority() or current_state == State.DEAD:
		return
	var attacker: Node = _resolve_peer_to_player(attacker_peer_id)
	if attacker:
		taunt(attacker)


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
	interrupt_cast(duration)


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


# Called locally by whichever player right-clicks this corpse
# (player3d.gd's _try_loot_corpse(), never an RPC) — everything here reads/
# writes only THIS calling peer's own view of the shared Monster node's
# script fields, which Godot never replicates unless explicitly listed in a
# SceneReplicationConfig (loot_window/_personal_loot aren't), so this is
# implicitly already per-peer with no extra plumbing needed. Rolls this
# peer's own personal loot the first time they open it; reopening shows the
# same roll (rather than re-rolling) until it's fully looted or the corpse
# despawns.
func open_loot_window() -> void:
	if is_instance_valid(loot_window):
		return

	var peer_id: int = multiplayer.get_unique_id()
	if not _personal_loot.has(peer_id):
		_personal_loot[peer_id] = _auto_process_loot(roll_loot()) if _drop_loot_allowed else []

	var my_loot: Array = _personal_loot[peer_id]
	if my_loot.is_empty():
		GameLog.log_general("You search the corpse but find nothing upon it.")
		_report_looted()
		return

	loot_window = load("res://Scenes/corpse_loot_window.tscn").instantiate()
	get_tree().root.add_child(loot_window)
	loot_window.setup(monster_name.capitalize(), my_loot)
	loot_window.all_looted.connect(_on_fully_looted)


# The Loot All key (G, player3d.gd loot_all_nearby()): takes this peer's whole loot from the corpse without opening the
# window — the same as the window's "Loot All" (coins, preferences; anything that doesn't fit stays on the corpse).
# Returns how many drops were taken.
func loot_everything() -> int:
	var peer_id: int = multiplayer.get_unique_id()
	if not _personal_loot.has(peer_id):
		_personal_loot[peer_id] = _auto_process_loot(roll_loot()) if _drop_loot_allowed else []
	var my_loot: Array = _personal_loot[peer_id]
	var taken := 0
	if not my_loot.is_empty():
		var looter = load("res://Scripts/corpse_loot_window.gd").new()  # only for its _apply_drop()
		for drop in my_loot.duplicate():
			if looter._apply_drop(drop):
				my_loot.erase(drop)
				taken += 1
		looter.free()
	if my_loot.is_empty():
		if is_instance_valid(loot_window):
			loot_window.queue_free()
		_report_looted()
	elif is_instance_valid(loot_window):
		loot_window.setup(monster_name.capitalize(), my_loot)
	return taken


# Only closes THIS peer's own loot window — the corpse itself is never freed
# here anymore (that used to run unconditionally, so the first player to
# finish looting despawned the corpse out from under everyone else's
# personal loot). The corpse's actual lifecycle is solely die()'s own
# lifetime rules now (see corpse_loot_timeout above), giving every player in the group the same fair
# window to loot their own roll. Closes immediately rather than after a
# delay — per user feedback (2026-09-18) a 5s grace period just read as "it
# doesn't auto-close at all" since they'd already moved on by the time it
# fired.
func _on_fully_looted() -> void:
	if is_instance_valid(loot_window):
		loot_window.queue_free()
	_report_looted()

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
	# No table of its own yet: monsters.json "loot_from" borrows another monster's (a Plateau Spider drops what a spider does).
	if not loot_from.is_empty() and loot_from != mob_name:
		for zone in loot_data.get("zone_loot_tables", {}).values():
			if zone.has(loot_from):
				return zone[loot_from]
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
			# Only the chased player should read "attacks you" — this runs on the server,
			# where `player` is merely the NEAREST player, so a monster going for a remote
			# player used to announce itself on the host's screen instead.
			var chased: Node = get_current_target()
			if chased != null and chased.is_in_group("player"):
				if chased.is_multiplayer_authority():
					_log_aggro_on_me()
				elif Net.is_multiplayer_game and chased.is_inside_tree():
					_rpc_notify_aggro.rpc_id(chased.get_multiplayer_authority(), chased.get_path())
		State.ATTACK:
			velocity = Vector3.ZERO

func _log_aggro_on_me() -> void:
	var desc: String = monster_description if monster_description != "" else get_monster_name()
	GameLog.log_combat("[color=orange]%s attacks you![/color]" % desc.capitalize())


# Sent by the server to the peer that owns the player this monster just started chasing.
@rpc("authority", "call_remote", "reliable")
func _rpc_notify_aggro(target_path: NodePath) -> void:
	var target := get_node_or_null(target_path)
	if is_instance_valid(target) and target.is_multiplayer_authority():
		_log_aggro_on_me()


# Called on every monster when the player is incapacitated/dies (see
# player3d.gd's die()) — clears aggro and heads straight back to spawn_position
# instead of picking a random nearby patrol point, so it reads as "giving up
# and walking home" rather than just wandering off. can_see_player() (below)
# separately makes sure a monster won't re-aggro the same downed player while
# they're still incapacitated/dead-pending-respawn.
# A pet recalled to its owner (the owner died and respawned — PetMinion.recall_to_owner()) drops out of this monster's
# threat; with nobody left on it, the monster goes home instead of chasing the pet across the map to the bind point.
@rpc("any_peer", "call_remote", "reliable")
func forget_attacker(attacker_path: NodePath) -> void:
	if not is_multiplayer_authority():
		return
	var attacker := get_node_or_null(attacker_path)
	if attacker != null:
		aggro_table.erase(attacker)
	if aggro_table.is_empty() and current_state in [State.CHASE, State.ATTACK]:
		force_disengage()


func force_disengage() -> void:
	if current_state == State.DEAD:
		return
	aggro_table.clear()
	if current_state in [State.CHASE, State.ATTACK]:
		change_state(State.PATROL)
		patrol_target = spawn_position


# Multiplayer-aware replacement for "the one player this client happens to
# be" — scans every real player in the "player" group (both the host's own
# character and every connected peer's puppet exist there identically on the
# server) and returns whichever is physically closest, ignoring anyone
# currently bled-out/dead (same as the old can_see_player() dying check).
# Hides the model from a viewer who can't see it (stealth/invisibility, see TargetFrame.is_hidden_from_local_player()) and
# shows the nameplate only while this client's player is within NAMEPLATE_DISTANCE (the target frame still names a mob
# further away).
func _refresh_nameplate() -> void:
	var hidden := TargetFrame.is_hidden_from_local_player(self)
	var character := get_node_or_null("Character") as Node3D
	if character:
		character.visible = not hidden
	var label := get_node_or_null("NameLabel") as Label3D
	if label == null:
		return
	var me := TargetFrame.local_player()
	var near := is_instance_valid(me) and global_position.distance_squared_to(me.global_position) <= NAMEPLATE_DISTANCE * NAMEPLATE_DISTANCE
	label.visible = near and not hidden
	if label.visible:
		label.text = TargetFrame.nameplate_name(self) + ("\n(casting %s)" % casting if not casting.is_empty() else "")


func _nearest_player() -> Node:
	var best: Node = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(node):
			continue
		if _player_is_down(node):
			continue
		var dist: float = global_position.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	return best


## Whether this monster notices a hidden (stealthed) player at all: only one that sees invisible, so far. Appraisal tells
## the player what they think (player3d.gd try_appraise_target).
func sees_hidden(_hidden: Node) -> bool:
	return combat_node != null and combat_node.get_modifier("see_invisible") > 0.0


func can_see_player() -> bool:
	if not player:
		return false
	if _player_is_down(player):
		return false  # incapacitated or dead-pending-respawn — ignore, per force_disengage() above

	var distance: float = global_position.distance_to(player.global_position)
	var effective_range: float = minf(aggro_range / AGGRO_RANGE_SCALE, MAX_AGGRO_DISTANCE)

	# Faction standing (player3d.gd kos_factions / ally_factions, replicated): a faction that hates this player attacks on
	# sight whatever its usual temper (the Djhanid after you've killed their people); one that counts them an ally never
	# starts a fight with them.
	if faction != "None" and not faction.is_empty():
		var hated_by = player.get("kos_factions")
		if hated_by is PackedStringArray and (hated_by as PackedStringArray).has(faction):
			return distance <= minf(maxf(aggro_range, 150.0) / AGGRO_RANGE_SCALE, MAX_AGGRO_DISTANCE)
		var liked_by = player.get("ally_factions")
		if liked_by is PackedStringArray and (liked_by as PackedStringArray).has(faction):
			return false
	if wary:
		return false   # wary folk (the Djhanid) watch you but never start it — unless you're hated (above)
	# Hidden (Stealth, Shadowstep, invisibility: Player3D.stealthed, replicated): not noticed by sight (test 44: "stealth
	# didn't seem to be working" — monsters never checked). A monster that sees invisible still does. Attacking reveals you.
	if player.get("stealthed") == true and not sees_hidden(player):
		return false

	match behavior_type:
		"passive":
			return distance <= (effective_range / 3.0)
		"neutral":
			return distance <= (effective_range / 2.0)
		_:  # aggressive, skitter, etc.
			return distance <= effective_range

const PATROL_ARRIVE_DISTANCE: float = 2.0   # ground-plane distance that counts as "arrived" (must exceed the nav agent's 1.5 m stopping distance)
const PATROL_STALL_SECONDS: float = 6.0     # no progress toward the wander point for this long -> pick another
var _patrol_best_distance: float = INF
var _patrol_stall_timer: float = 0.0
const PATROL_MIN_DISTANCE: float = 5.0   # avoid trivially-short legs that don't read as movement
const PATROL_MAX_DISTANCE: float = 18.0  # was a flat 10.0 with no minimum — too tight a bubble to look like real wandering

# The zone's no-monster rectangles (Data/lumora_outskirts_spawns.json "no_monster_zones": the town and the gate front):
# monsters don't spawn there (mob_spawner3d.gd) or wander there on their own.
static var _no_monster_zones: Array = []
static var _zones_loaded_for := ""

static func in_no_monster_zone(pos: Vector3) -> bool:
	var zone_id := ZoneInfo.current_id()
	if _zones_loaded_for != zone_id:
		_zones_loaded_for = zone_id
		_no_monster_zones = []
		var path := ZoneInfo.spawns_path(zone_id)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if typeof(parsed) == TYPE_DICTIONARY:
			_no_monster_zones = parsed.get("no_monster_zones", [])
	for zone in _no_monster_zones:
		var lo: Array = zone.get("min", [0, 0])
		var hi: Array = zone.get("max", [0, 0])
		if pos.x >= float(lo[0]) and pos.x <= float(hi[0]) and pos.z >= float(lo[1]) and pos.z <= float(hi[1]):
			return true
	return false


func pick_new_patrol_point() -> void:
	_patrol_best_distance = INF
	_patrol_stall_timer = 0.0
	if march_target != Vector3.INF:
		var march_map: RID = get_world_3d().navigation_map if is_inside_tree() else RID()
		patrol_target = NavigationServer3D.map_get_closest_point(march_map, march_target) if march_map.is_valid() else march_target
		return
	# Try a few random spots and keep the first that is actually on the navmesh (not inside a wall, rock or water) —
	# the point is snapped onto the mesh so the arrival check above can really be met.
	var map: RID = get_world_3d().navigation_map if is_inside_tree() else RID()
	for attempt in 6:
		var random_angle: float = randf() * TAU
		var random_distance: float = randf_range(PATROL_MIN_DISTANCE, PATROL_MAX_DISTANCE)
		var candidate: Vector3 = spawn_position + Vector3(cos(random_angle) * random_distance, 0, sin(random_angle) * random_distance)
		if in_no_monster_zone(candidate):
			continue  # never wander into town on its own
		if not map.is_valid():
			patrol_target = candidate
			return
		var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, candidate)
		if Vector2(on_mesh.x - candidate.x, on_mesh.z - candidate.z).length() <= 2.0:
			patrol_target = on_mesh
			return
	patrol_target = global_position  # nowhere sensible nearby: stay put this round

func look_at_target(target_pos: Vector3) -> void:
	var look_pos: Vector3 = target_pos
	look_pos.y = global_position.y
	if global_position.distance_squared_to(look_pos) > 0.0001:
		look_at(look_pos, Vector3.UP)


# A defender's shield that hits back at whoever strikes it (runs on the defender's machine): Ice Barrier slows the
# attacker ("slow_attackers"), Chaos Shield has a chance to lay a random debuff on it ("attacker_debuff_chance").
func _on_hit_defender_effects(target: Node) -> void:
	var cn = target.get("combat_node") if "combat_node" in target else null
	if not (cn is CombatNode):
		return
	if not on_hit_effect.is_empty() and randf() < float(on_hit_effect.get("chance", 0.0)):
		var effect_name := str(on_hit_effect.get("name", "poison"))
		var fresh: bool = not cn.active_effects.has(effect_name)
		var mods: Dictionary = on_hit_effect.get("modifiers", {}) if on_hit_effect.get("modifiers") is Dictionary else {}
		cn.apply_effect(effect_name, float(on_hit_effect.get("duration", 60.0)), mods.duplicate(), int(on_hit_effect.get("tick_damage", 0)), float(on_hit_effect.get("tick_interval", 6.0)))
		if fresh:
			var who := (monster_description if monster_description != "" else get_monster_name()).capitalize()
			GameLog.log_combat("[color=#77cc44]%s[/color]" % (str(on_hit_effect.get("message", "%s afflicts you!")) % who))
	var slow: float = cn.get_modifier("slow_attackers")
	if slow > 0.0:
		_apply_effect_here_or_server("shield_chill", 4.0, {"speed_slow": slow, "attack_speed_slow": slow})
	var chance: float = cn.get_modifier("attacker_debuff_chance")
	if chance > 0.0 and randf() < chance:
		var picks := [["chaos_slow", {"speed_slow": 0.3, "attack_speed_slow": 0.3}], ["chaos_silence", {"silenced": 1.0}], ["chaos_blind", {"hit_chance": -25.0}]]
		var pick: Array = picks[randi() % picks.size()]
		_apply_effect_here_or_server(pick[0], 5.0, pick[1])
		GameLog.log_combat("[color=#bb99ff]Your chaos shield lashes out at %s.[/color]" % (monster_description if monster_description != "" else get_monster_name()))


func _apply_effect_here_or_server(effect_name: String, duration: float, mods: Dictionary) -> void:
	if is_multiplayer_authority():
		combat_node.apply_effect(effect_name, duration, mods)
	else:
		apply_networked_effect.rpc_id(1, effect_name, duration, mods, 0, 1.0)


# ── Abilities (2026-09-25): monsters.json "abilities" — named monsters cast, curse, heal, call for help and enrage ──
# Each entry: {name, type, cast (seconds, 0 = instant), cooldown, first (seconds into a fight before its first use;
# default 5, or 0 for one with hp_below),
# hp_below (only under that share of health), once, range (m), radius (aoe, m), damage (at the monster's listed level,
# scaled like its swings), school (the resist the target rolls: fire, cold, magic, poison, disease, spirit...),
# effect {name, duration, modifiers, tick_damage, tick_interval} (a MONSTER_AILMENTS name, so cures and the buff bar know
# it), heal (share of max health), summon (monster id) + count, enrage {damage_mult, attack_speed}, message ("%s" = the
# monster's name)}. Types: nuke / debuff (the current target), aoe (every player within radius), heal, summon, enrage.
# The server runs them. A spell with a cast time shows on the target window and nameplate ("casting ...") and is broken
# by a stun, bash or silence; skills (cast 0) are not. Hits reach a player on their own machine (_rpc_ability_on_owner),
# like swings do.
const ABILITY_TYPES := ["nuke", "debuff", "aoe", "heal", "summon", "enrage"]
var abilities: Array = []
var casting := ""                     # replicated: the ability being cast ("" = none)
var _ability_ready_at: Array = []     # fight seconds when each can next be used
var _ability_used: Array = []         # once-only ones spent this fight
var _fight_time := 0.0
var _cast_left := 0.0
var _cast_index := -1
var _cast_target: Node = null
var _stunned_left := 0.0
# A stun (mesmerize, confuse) holds a monster where it stands, not facing anyone (test 44: a Shadowblade "will need some
# kind of skill to stun the mob so they can get behind it and backstab"; a stunned monster used to keep turning to face
# its target). Only a stagger with a length does this.
var _stun_hold := 0.0
var _summons: Array = []              # adds this monster called (they go when it dies or gives up)


func _load_abilities(stats: Dictionary) -> void:
	abilities = []
	for a in stats.get("abilities", []):
		if typeof(a) == TYPE_DICTIONARY and ABILITY_TYPES.has(str(a.get("type", ""))):
			abilities.append(a)
	_reset_abilities()


func _reset_abilities() -> void:
	_fight_time = 0.0
	_ability_ready_at = []
	_ability_used = []
	for a in abilities:
		_ability_ready_at.append(float(a.get("first", 0.0 if a.has("hp_below") else 5.0)))   # a low-health one: as soon as it's low
		_ability_used.append(false)
	_cancel_cast()
	if combat_node and combat_node.active_effects.has("enraged"):
		combat_node.remove_effect("enraged")


func _cancel_cast() -> void:
	_cast_index = -1
	_cast_left = 0.0
	_cast_target = null
	casting = ""


# A stun, bash or knock-down breaks a spell being cast (skills are instant), and nothing is used while it lasts.
# Called by the disable paths with the stun's length.
func interrupt_cast(stun_seconds := 0.0) -> void:
	_stunned_left = maxf(_stunned_left, stun_seconds)
	_stun_hold = maxf(_stun_hold, stun_seconds)
	if _cast_index < 0:
		return
	var a: Dictionary = abilities[_cast_index]
	_ability_ready_at[_cast_index] = _fight_time + 3.0   # it tries again soon
	_cancel_cast()
	_say("%s's %s is interrupted!" % [_desc().capitalize(), str(a.get("name", "spell"))])


func _desc() -> String:
	return monster_description if monster_description != "" else get_monster_name()


# Everyone near hears it: the server tells the players around; a host or single player logs it too.
func _say(text: String, color := "#ffcc66") -> void:
	if text.is_empty():
		return
	var line := "[color=%s]%s[/color]" % [color, text]
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		Net.broadcast_combat_message(line, global_position)
	if not Net.is_dedicated_server:
		GameLog.log_combat(line, global_position)


# Server, every physics frame while fighting. Returns true while casting (the monster stands and doesn't swing).
func _tick_abilities(delta: float) -> bool:
	if abilities.is_empty():
		return false
	var fighting := current_state == State.CHASE or current_state == State.ATTACK
	if not fighting:
		if _fight_time > 0.0:
			_reset_abilities()
			_dismiss_summons()
		return false
	_fight_time += delta
	for i in abilities.size():   # a frenzy isn't an action: it comes the moment health drops, even mid-cast
		var e: Dictionary = abilities[i]
		if str(e["type"]) == "enrage" and not _ability_used[i] and combat_node.current_hp <= int(combat_node.max_hp * float(e.get("hp_below", 0.25))):
			_ability_used[i] = true
			_use_ability(i, null)
	if _cast_index >= 0:
		if combat_node.get_modifier("silenced") > 0.0:
			interrupt_cast()
			return false
		_cast_left -= delta
		if is_instance_valid(_cast_target):
			look_at_target(_cast_target.global_position)
		if _cast_left <= 0.0:
			var i := _cast_index
			var target := _cast_target
			_cancel_cast()
			_use_ability(i, target)
		return _cast_index >= 0 or _cast_left > 0.0
	if _stunned_left > 0.0:
		_stunned_left -= delta
		return false   # stunned: no abilities either
	var target := get_current_target()
	for i in abilities.size():
		var a: Dictionary = abilities[i]
		if str(a["type"]) == "enrage" or _fight_time < float(_ability_ready_at[i]) or (bool(a.get("once", false)) and _ability_used[i]):
			continue
		if a.has("hp_below") and combat_node.current_hp > int(combat_node.max_hp * float(a["hp_below"])):
			continue
		var cast := float(a.get("cast", 0.0))
		if cast > 0.0 and combat_node.get_modifier("silenced") > 0.0:
			continue
		var kind := str(a["type"])
		if kind in ["nuke", "debuff"]:
			if not is_instance_valid(target) or global_position.distance_to(target.global_position) > float(a.get("range", 20.0)):
				continue
		elif kind == "aoe" and _players_within(float(a.get("radius", 6.0))).is_empty():
			continue
		elif kind == "heal" and combat_node.current_hp >= combat_node.max_hp:
			continue
		_ability_ready_at[i] = _fight_time + float(a.get("cooldown", 20.0))
		_ability_used[i] = true
		if cast > 0.0:
			_cast_index = i
			_cast_left = cast
			_cast_target = target
			casting = str(a.get("name", "a spell"))
			velocity.x = 0.0
			velocity.z = 0.0
			_say("%s begins to cast %s." % [_desc().capitalize(), casting])
			return true
		_use_ability(i, target)
		return false
	return false


func _players_within(radius: float) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(node) and not _player_is_down(node) and global_position.distance_to(node.global_position) <= radius:
			out.append(node)
	return out


func _use_ability(i: int, target: Node) -> void:
	if current_state == State.DEAD:
		return
	var a: Dictionary = abilities[i]
	var who := _desc().capitalize()
	match str(a["type"]):
		"nuke", "debuff":
			if is_instance_valid(target) and global_position.distance_to(target.global_position) <= float(a.get("range", 20.0)) + 5.0:
				_ability_hit(target, i)
		"aoe":
			if a.has("say"):
				_say(str(a["say"]) % who, "#ff9966")
			for p in _players_within(float(a.get("radius", 6.0))):
				_ability_hit(p, i)
		"heal":
			combat_node.heal(int(combat_node.max_hp * float(a.get("heal", 0.15))))
			_say(str(a.get("message", "%s is bathed in healing light.")) % who, "#88ff88")
		"summon":
			_summon(str(a.get("summon", "")), int(a.get("count", 1)))
			_say(str(a.get("message", "%s calls for help!")) % who, "#ff9966")
		"enrage":
			var e: Dictionary = a.get("enrage", {})
			combat_node.apply_effect("enraged", 3600.0, {"damage_mult": float(e.get("damage_mult", 0.5)),
					"attack_speed_slow": -float(e.get("attack_speed", 0.3))})
			_say(str(a.get("message", "%s goes into a frenzy!")) % who, "#ff4444")


# Hands one ability hit to whoever owns the target (a remote player's own machine), or lands it here.
func _ability_hit(target: Node, i: int) -> void:
	var amount := int(round(float(abilities[i].get("damage", 0)) * _balance_damage_scale))
	if Net.is_multiplayer_game and target.is_inside_tree() and not target.is_multiplayer_authority():
		_rpc_ability_on_owner.rpc_id(target.get_multiplayer_authority(), target.get_path(), i, amount)
		return
	land_ability(target, i, amount)


@rpc("authority", "call_remote", "reliable")
func _rpc_ability_on_owner(target_path: NodePath, i: int, amount: int) -> void:
	var target := get_node_or_null(target_path)
	if is_instance_valid(target) and target.is_multiplayer_authority() and i >= 0 and i < abilities.size():
		land_ability(target, i, amount)


# On the target's own machine: the resist roll, the damage, the ailment, the message.
func land_ability(target: Node, i: int, amount: int) -> void:
	var cn = target.get("combat_node") if "combat_node" in target else null
	if not (cn is CombatNode) or (target.is_in_group("player") and _player_is_down(target)):
		return
	var a: Dictionary = abilities[i]
	var who := _desc().capitalize()
	var spell := str(a.get("name", "a spell"))
	var is_player := target.is_in_group("player")
	if ability_resisted(cn, str(a.get("school", "")), level):
		if is_player:
			GameLog.log_combat("[color=#aaddff]You resist %s's %s![/color]" % [who, spell])
		return
	var taken := 0
	if amount > 0:
		taken = cn.take_damage(amount)
	var effect: Dictionary = a.get("effect", {})
	var afflicted := false
	if not effect.is_empty() and not cn.rolls_resist_negative_effect():
		var mods: Dictionary = effect.get("modifiers", {}) if effect.get("modifiers") is Dictionary else {}
		if str(effect.get("name", "")) == "terrified" and target.has_method("receive_fear"):
			# fear on a player: a save decides whether they're Shaken or break and run (player3d.gd receive_fear())
			target.receive_fear(float(effect.get("duration", 10.0)), level, who, mods.duplicate())
			if target.has_method("on_attacked"):
				target.on_attacked(self)
			if taken > 0:
				GameLog.log_combat("[color=#ff7766]%s's %s hurts you. (%d damage)[/color]" % [who, spell, taken])
			return
		cn.apply_effect(str(effect.get("name", "cursed")), float(effect.get("duration", 20.0)), mods.duplicate(),
				int(effect.get("tick_damage", 0)), float(effect.get("tick_interval", 6.0)))
		afflicted = true
	if is_player:
		var line := str(a.get("message", "%s's " + spell + " strikes you!"))
		line = line % who if line.contains("%s") else line
		if taken > 0:
			line += " (%d damage)" % taken
		GameLog.log_combat("[color=%s]%s[/color]" % ["#ff7766" if taken > 0 else "#cc88ff", line])
		if afflicted and target.has_method("on_attacked"):
			target.on_attacked(self)
	elif not cn.is_alive() and target.has_method("die"):
		target.die()


# The target's resist against a monster's spell: a full resist, EverQuest style — the resist stat against the caster's
# level. No school (a skill, a thrown net) = never resisted.
static func ability_resisted(cn: CombatNode, school: String, caster_level: int) -> bool:
	if school.is_empty() or school == "physical":
		return false
	var resist := float(cn.get_derived_stat(school + "_resist"))
	var chance := clampf(resist / (resist + 10.0 * float(caster_level) + 50.0), 0.02, 0.75)
	return randf() < chance


# Adds the monster calls: spawned by its zone's MobSpawner like any monster (so every player sees them), outside the
# spawn counts; they go when it dies or gives up the fight.
func _summon(mob_type: String, count: int) -> void:
	if mob_type.is_empty():
		return
	var spawner_node := get_parent().get_parent() if get_parent() else null
	for n in count:
		var at := global_position + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
		var add: Node = null
		if spawner_node and spawner_node.has_method("spawn_extra"):
			add = spawner_node.spawn_extra(mob_type, at)
		else:
			add = load("res://Scenes/monster_template.tscn").instantiate()
			add.monster_name = mob_type
			add.position = at
			get_parent().add_child(add)
		if add:
			_summons.append(add)
			var t := get_current_target()
			if is_instance_valid(t) and add.has_method("add_threat"):
				add.call_deferred("add_threat", t, 1.0)
				add.call_deferred("change_state", State.CHASE)


func _dismiss_summons() -> void:
	for add in _summons:
		if is_instance_valid(add) and add.current_state != State.DEAD:
			add.queue_free()
	_summons.clear()
