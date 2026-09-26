# player3d.gd - 3D player controller with RPG systems
extends CharacterBody3D
class_name Player3D

#region Movement configuration
const NAMEPLATE_DISTANCE := 20.0  # metres: another player's nameplate shows only within this distance of your own player
const WALK_SPEED: float = 5.0
const RUN_SPEED: float = 8.0
const CROUCH_SPEED: float = 2.5
const JUMP_VELOCITY: float = 6.0
const SPELL_PROJECTILE := preload("res://Scripts/spell_projectile.gd")
const FALL_SAFE_HEIGHT := 6.0          # metres you can drop without getting hurt
const FALL_DAMAGE_PER_METRE := 0.05    # of max health, for every metre past FALL_SAFE_HEIGHT
const FALL_GRACE_MS := 5000            # no fall damage this long after logging in or respawning (being placed on the ground)
const LOW_HEALTH_FRACTION := 0.25      # the heartbeat plays below this much health
const TURN_SPEED: float = PI

const BACKWARD_SPEED_MULT: float = 0.75
const AIR_CONTROL_MULT: float = 0.3
const STUMBLE_DURATION: float = 0.2
#endregion

#region Stamina system (movement — separate from CombatNode stamina)
const MAX_STAMINA: float = 100.0
const STAMINA_DRAIN_RUN: float = 10.0
const STAMINA_DRAIN_JUMP: float = 15.0
const STAMINA_REGEN_STAND: float = 10.0
const STAMINA_REGEN_WALK: float = 5.0
const STAMINA_REGEN_SIT: float = 20.0

var max_stamina: float = MAX_STAMINA
var current_stamina: float = MAX_STAMINA
#endregion

#region RPG stats — sourced from CombatNode
var combat_node: CombatNode
var player_name := "Default Hero"
var player_class := ""
var player_race := ""
var player_sex := "male"
# Dev/staff flag shown as an orange "<Name>" nameplate tag (TargetFrame.
# nameplate_name()). Single-player / host: /gm enable, saved in
# the save file's "is_game_master" key; on a dedicated server /gm enable <password> grants it for the session (gm_commands.gd).
var is_game_master := false:
	set(value):
		is_game_master = value
		if is_inside_tree():
			_refresh_nameplate()   # /gm enable shows "<Name>" in orange at once, on this screen and (replicated) on everyone else's
# Last name, earned with /surname at level 10 (or set by a game master). Replicated; shown on nameplates, the target
# frame and /who (chat and the combat log keep the first name). Saved as Global.player_data["surname"].
var surname := "":
	set(value):
		surname = value
		if is_inside_tree():
			_refresh_nameplate()
# The character's look (Scripts/appearance.gd): body sliders, height, skin / hair / eye colour. Replicated as JSON so
# everyone sees it; saved as Global.player_data["appearance"]. A change (the mirror, a new hair colour) re-applies it.
var appearance_json := "":
	set(value):
		if value == appearance_json:
			return
		appearance_json = value
		if is_inside_tree() and has_node("Character"):
			_apply_appearance()
# What this character holds (HeldGear.encode: "primary_item|offhand_item"), replicated so everyone sees the same weapon and
# shield (test 39). The owner sets it from the equipment; every copy rebuilds the hands when it changes.
var held_gear := "":
	set(value):
		if value == held_gear:
			return
		held_gear = value
		if is_inside_tree() and has_node("Character"):
			HeldGear.apply(get_node("Character"), held_gear)
# The players this one is hostile with right now (lower-case names: a duel or PvP, player_versus.gd), replicated. Two
# players can fight only when each is on the other's list.
var hostile_to := PackedStringArray()
var known_spells: Array = []
var known_skills: Array = []
var known_recipes: Array = []  # tradeskill recipe ids learned from scrolls/quests (innate recipes are always known)
var skill_levels: Dictionary = {}
var regen_bonus: int = 0  # Racial bonus HP added to each regen tick (e.g. Troll regeneration)
var action_bar_slots: Array = []  # Array of {type, name} dicts, 12 elements
var _spell_cache: Dictionary = {}
var _spell_by_name: Dictionary = {}
var _skill_data: Dictionary = {}   # flat skill_name -> description
var _valid_skill_names: Dictionary = {}  # set-like (skill_name -> true) — every real physical/magic/crafting skill, used by _tick_skill() to allow leveling a skill a class wasn't seeded with at creation
var _skill_max: int = 275  # overwritten from player_skills.json's own skill_max once loaded
var _spell_cooldowns: Dictionary = {}
var _active_songs: Dictionary = {}  # spell_name -> true — Troubadour's toggled/playing songs
var _skill_cooldowns: Dictionary = {}
# Set at cast start, consumed once combat_node.is_casting finishes (or cleared
# on interrupt) — see cast_spell()/_resolve_spell_cast()/_check_spell_interrupt()
# below. casting_spell_name is public so cast_bar.gd can read it without
# duplicating the spell-name lookup.
var casting_spell_name: String = ""
# A non-spell timed task shown on the cast bar (gathering, crafting): cast_bar.gd shows it whenever no spell is being
# cast. Set through set_task_progress() / clear_task_progress().
var task_name: String = ""
var task_progress: float = 0.0
var task_seconds_left: float = 0.0
var _athletics_run_time: float = 0.0  # seconds spent sprinting since the last athletics skill roll
var _pending_cast_spell: String = ""
var _spell_skill_category: String = ""  # the spell being resolved right now: which skill it belongs to (evocation, backstab, ...) — feeds Data/skill_effects.json
var _pending_cast_spell_data: Dictionary = {}
var _pending_cast_target: Node = null
var _appraisal_cooldowns: Dictionary = {}  # target instance ID -> remaining seconds
var active_pet: Node = null
var active_pet_frame: Node = null
var _deathly_visage_light: OmniLight3D = null
var _shadowlight_light: OmniLight3D = null
var last_damage_time_ms: int = 0  # Time.get_ticks_msec() of the last hit taken — used to interrupt /camp
var last_attacked_msec: int = 0   # Time.get_ticks_msec() of the last time something SWUNG at you, hit or miss — interrupts camping and crafting, and stands you up
var last_attack_time_ms: int = 0  # Time.get_ticks_msec() of the last attack THIS player actually made — see pet_minion.gd's assist-mode engage check
var current_stance: String = ""

# Pet's own gear, kept separate from Inventory.equipped (the player's 25-slot
# paperdoll) — a reduced weapon+armor set since rings/trinkets/etc. don't make
# sense on a summoned pet. Persists in Global.player_data["pet_equipment"]
# across zoning/exit even while no pet is summoned; re-applied to whatever
# PetMinion instance exists via _apply_pet_gear_bonus().
const PET_EQUIPMENT_SLOTS: Array = ["primary", "offhand", "head", "chest", "arms", "hands", "legs", "feet"]
var pet_equipment: Dictionary = {}

# Computed properties for backward compat (monster3d reads these on current_target)
var current_health: int:
	get: return combat_node.current_hp if combat_node else 0
var max_health: int:
	get: return combat_node.max_hp if combat_node else 100
var current_mana: int:
	get: return combat_node.current_mana if combat_node else 0
var max_mana: int:
	get: return combat_node.max_mana if combat_node else 100

const REGEN_INTERVAL := 6.0  # EQ-style tick
var regen_timer := 0.0

var stats: Dictionary = {}
var faction_standing: Dictionary = {"Villagers of Lumora": 50}
var backpack_scene := preload("res://Scenes/backpack_ui.tscn")
var backpack_instance: Node = null

var caster_classes := [
	"voidknight", "gravecaller", "runecaster", "arcanist", "chaosborn",
	"lightsworn", "lightmender", "spiritweaver", "wildspeaker",
	"woodstalker", "aetherfist", "troubadour"
]
#endregion

#region Vitals system (hunger / thirst)
var satiety: int = 100
var thirst: int = 100

const SATIETY_DECAY_RATE: float = 1.0
const THIRST_DECAY_RATE: float = 2.0
const DECAY_INTERVAL: float = 60.0

var satiety_timer: float = 0.0
var thirst_timer: float = 0.0
#endregion

#region Combat
# dying: true for the whole time the player can't act — both while
# incapacitated (bleeding out) and during the brief window between true death
# and respawn. Freezes movement (_physics_process) and regen/vitals
# (_process) via their existing "if dying: return" gates. See die()/
# _tick_bleedout()/_die_for_real()/_respawn() below.
var dying: bool = false
var is_incapacitated: bool = false
# Death (2026-09-21): at 0 HP you are DOWNED (frozen, bleeding) and monsters stop attacking you; health then drains from 0 to DEATH_HP over
# BLEED_OUT_DURATION and at DEATH_HP you die. A hit that takes you to DEATH_HP or below kills you at once. Health never goes below DEATH_HP.
# An ally's heal that lifts you above 0 gets you up (see _check_bleedout_revival).
const DEATH_HP := -30
const BLEED_OUT_DURATION := 10.0    # seconds from 0 HP to DEATH_HP (was a flat 20 s)
var _bleed_remainder := 0.0
const BLEED_OUT_WARN_INTERVAL := 5.0
const RESPAWN_DELAY := 3.0          # seconds the black respawn screen holds before teleporting
var _bleedout_elapsed: float = 0.0
var _bleedout_warn_timer: float = 0.0
var _last_attacker_desc: String = "an unknown foe"
var _death_flavor: NPCFlavorText = null
var _food_drink_flavor: NPCFlavorText = null
var _death_screen: CanvasLayer = null
var attacking: bool = false
# attack_cooldown now runs for the real swing clip's length each attack (set
# in attack_current_target()/perform_melee_attack() via
# _attack_animation_duration()) instead of a flat constant, so the cooldown
# always matches whatever's actually playing — this still means a new swing
# can start right as the previous one's clip finishes, so each attack stamps
# its own generation here, letting an earlier attack's delayed
# `attacking = false` avoid stomping a newer swing that's still mid-animation.
var _attack_generation: int = 0
var autoattack_enabled: bool = false
var attack_cooldown: float = 0.0
# Casting plays "cast_beneficial" or "cast_detrimental" (see cast_spell(),
# _is_beneficial_cast()) for the clip's length, same decrementing-timer
# pattern monster3d.gd/guard_npc.gd/pet_minion.gd already use for their own
# attack-hold timers (_attack_anim_timer) — chosen over the await-based
# pattern attacking/_attack_generation use above because cast_spell() has
# several early `return`s on invalid targets *after* the animation would
# already be triggered, and a pending await tail would never run to clear
# the state on those paths; a per-frame timer decrement doesn't care how
# cast_spell() exits. Not every model has these clips yet (see
# CHARACTER_MODELS) — _trigger_cast_animation() only sets the timer when the
# currently-loaded library actually has the anim, so races without it just
# keep playing idle/walk as before.
var _current_cast_anim: String = ""
var _cast_anim_timer: float = 0.0
var current_target: Node = null
# Focus (2026-09-21): a second, sticky FRIENDLY target. Beneficial spells go to your current target when it is friendly, otherwise to the focus,
# otherwise to you; detrimental spells still need a hostile current target. Client-side only; survives death and respawn.
var focus_target: Node = null
# Who I am targeting, as a short key ("p:<peer id>", "m:<monster name>", "n:<npc name>"), replicated so everyone can show "target's target".
var target_key: String = ""
var _target_idx: int = -1

# F1-F6 group targeting (EQ/modern-MMO style) — group_members[0] is always
# "yourself". Stored as multiplayer peer ids (not Node references — Nodes
# aren't meaningful across the network), resolved to an actual local Node via
# _peer_id_to_player_node() whenever needed. Pressing the same F-key again
# while already targeting that member switches to their pet instead (and back
# again on a third press) — see _handle_group_target_key() below. Kept in
# sync across a real multiplayer session via Net's invite/roster RPCs — see
# invite_to_group(), _on_group_invite_response(), _on_group_roster_received().
var group_members: Array = []
var group_names: Array = []    # every member's name, in any zone (from the server: world_link.gd); [] = no group
var group_remote: Array = []   # members in other zones: [{name, zone}] (the group frame shows them without bars)
#endregion

#region Movement state
var is_running: bool = true
var is_crouching: bool = false
var is_in_air: bool = false
var _projectile_landing := false       # true while a spell's projectile has arrived and its effect is being applied
var _fall_top_y := 0.0                 # the highest point of the current time in the air (for fall damage)
var _fall_grace_until_ms := 0
var _body_sound_timer := 0.0
var _footsteps_loop: Node = null       # sfx.gd loops, started/stopped by _update_body_sounds()
var _footsteps_kind := ""
var _heartbeat_loop: Node = null
var _was_in_water := false
var stumble_timer: float = 0.0
var movement_direction: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var last_direction: Vector3 = Vector3.FORWARD
var is_sitting: bool = false
var autorun_enabled: bool = false

# /follow — see start_following()/stop_following() and _handle_follow_movement()
# in the "Movement handlers" region below.
var _follow_target: Node3D = null
var _follow_path: Array = []
var _follow_repath_timer: float = 0.0
const FOLLOW_STOP_DISTANCE := 3.0
const FOLLOW_REPATH_INTERVAL := 0.75
const FOLLOW_WAYPOINT_EPSILON := 1.5
#endregion

#region Node references
@onready var camera_rig: Node3D = $CameraRig
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
# Not @onready — the "Character" node itself is built dynamically by
# _build_character_model() (race/sex-dependent), so this is only valid once
# that has run at least once. See CHARACTER_MODELS below.
var animation_player: AnimationPlayer = null
#endregion

# Tab is the target-cycle key, but it is ALSO Godot's built-in "move keyboard focus to the
# next UI control" key — so every press shifted focus around the HUD (pet/group buttons, the
# chat box) while it cycled targets. Once the chat box's LineEdit gets that focus, movement is
# deliberately skipped (see _physics_process()'s chat_focused), which read as "Tab targets the
# next mob but I can't move." The action state is polled elsewhere, so consuming the event
# here only stops the GUI from also acting on it; typing in the chat box is left alone.
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("tab_target") and not (get_viewport().gui_get_focus_owner() is LineEdit):
		get_viewport().set_input_as_handled()


#region Loot interaction
const LOOT_RANGE := 5.0

var _pause_menu_instance: Node = null

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_try_open_shop_or_loot()
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
					_try_click_target(event.position)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not event.ctrl_pressed:
			if not _close_all_windows():
				_toggle_pause_menu()
			return

		if event.is_action_pressed("hail") and not (get_viewport().gui_get_focus_owner() is LineEdit):
			try_hail_nearby_npc()
			return

		# F = assist: target what your current target is targeting (a raw key, like N: it can ship in a patch).
		if event.keycode == KEY_F and not event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed and not event.echo \
				and not (get_viewport().gui_get_focus_owner() is LineEdit):
			assist_target()
			return

		# M opens / closes your map (Cartography; a raw key too).
		if event.keycode == KEY_M and not event.ctrl_pressed and not event.echo and not (get_viewport().gui_get_focus_owner() is LineEdit):
			MapWindow.open_for(self)
			return

		# N shows/hides the compass (a raw key, not an InputMap action, so it can ship in an update patch).
		if event.keycode == KEY_N and not event.ctrl_pressed and not (get_viewport().gui_get_focus_owner() is LineEdit):
			toggle_compass()
			return

		if event.is_action_pressed("appraise") and not (get_viewport().gui_get_focus_owner() is LineEdit):
			try_appraise_target()
			return

		if not (get_viewport().gui_get_focus_owner() is LineEdit):
			for i in range(1, 7):
				if event.is_action_pressed("group_target_%d" % i):
					_handle_group_target_key(i)
					return

		const SLOT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]
		var idx := SLOT_KEYS.find(event.keycode)
		if idx >= 0 and idx < action_bar_slots.size():
			var slot: Dictionary = action_bar_slots[idx]
			match slot.get("type", ""):
				"spell": cast_spell(slot["name"])
				"skill": use_skill(slot["name"])
				"macro": run_macro(str(slot["name"]))


# Runs one of your macros (macros.gd) — through the chat window, which knows every chat command.
func run_macro(ref: String) -> void:
	var win := get_tree().get_first_node_in_group("game_log_window")
	if win != null:
		win.run_macro(ref)


# Shows or hides the compass HUD (needs the Compass item). Also /compass.
func toggle_compass() -> void:
	for node in get_tree().get_nodes_in_group("game_hud"):
		if node is CompassHud:
			GameLog.log_general("[color=#cccccc]%s[/color]" % node.toggle())
			return
	GameLog.log_general("[color=#cccccc]You have no compass.[/color]")


# Closes every open modal window at once (character sheet, backpack, abilities
# book, shop, corpse loot, pet gear, the item-inspect popup, and the pause
# menu itself if up) — anything that isn't part of the persistent HUD group
# (_spawn_hud() / pet_frame below both tag their nodes "game_hud"). Returns
# whether anything was actually closed, so the Escape handler above only
# falls back to opening the pause menu when nothing was open to close.
func _close_all_windows() -> bool:
	var closed_any := false
	for node in get_tree().root.get_children():
		if node is CanvasLayer and not node.is_in_group("game_hud"):
			node.queue_free()
			closed_any = true
	return closed_any


func _toggle_pause_menu() -> void:
	if is_instance_valid(_pause_menu_instance):
		_pause_menu_instance.queue_free()
		_pause_menu_instance = null
		Global.restore_mouse_mode()
		return
	_pause_menu_instance = load("res://Scenes/pause_menu.tscn").instantiate()
	_pause_menu_instance.closed.connect(func():
		_pause_menu_instance = null
		Global.restore_mouse_mode()
	)
	get_tree().root.add_child(_pause_menu_instance)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

var _shop_window_instance: Node = null

# Right-click: opens a vendor's shop only if the cursor is precisely on that
# vendor's model (raycast), otherwise falls through to the existing
# loot-corpse behavior — range-based, was previously "nearest vendor within
# 5m regardless of where you clicked," which meant a vendor standing near a
# corpse always stole the right-click and made that corpse unlootable.
# Raycasting only works with a real screen-space cursor position, so this
# (like _try_click_target()'s left-click targeting) is meant to skip while
# mouselooking, where there's no cursor to aim with.
#
# Gated on Global.mouselook_enabled rather than Input.mouse_mode — bug fixed
# 2026-09-14 (Session 37): camera_controller.gd's _input() handles this same
# right-click press FIRST (every node's _input() runs before
# _unhandled_input(), where this lives) and immediately sets
# Input.mouse_mode to CAPTURED for its own "hold right-click to head-turn"
# feature, completely independent of mouselook. By the time this ran,
# Input.mouse_mode == MOUSE_MODE_VISIBLE was ALWAYS false — every right-click
# looked like it happened in mouselook even when the cursor was genuinely
# visible a moment before, so the raycast never fired and this silently fell
# through to loot-corpse 100% of the time. Global.mouselook_enabled is the
# stable, persistent toggle that head-turn's transient capture never
# touches (see camera_controller.gd: it only captures "if not
# Global.mouselook_enabled" in the first place), so it actually reflects
# whether the player is in normal cursor-visible play.
func _try_open_shop_or_loot() -> void:
	if not Global.mouselook_enabled:
		var mouse_pos := get_viewport().get_mouse_position()
		var hit := _raycast_world_hit(mouse_pos)
		if not (hit is VendorNPC) and not (hit is Player3D and hit != self and hit.dying):
			hit = _vendor_near_mouse(mouse_pos, hit)  # a wall/pet/creature was in the way: pick the NPC by proximity on screen
		if hit is VendorNPC:
			_open_shop(hit)
			return
		if hit is Player3D and hit != self and hit.dying:
			_try_bandage(hit)
			return
		if hit is Player3D and hit != self:
			request_trade(hit)  # right-click another player: ask them to trade (trade_relay.gd)
			return
	if _try_open_campfire():
		return
	if _try_open_crafting_station():
		return
	if _try_gather():
		return
	if _try_ley_line_node():
		return
	if _try_read_world_note():
		return
	if _try_pickup_pouch():
		return
	_try_loot_corpse()


# Ask another player to trade (right-click them, or /trade). With no argument /trade uses the current target.
func request_trade(target: Node) -> void:
	var relay := get_tree().get_first_node_in_group("trade_relay")
	if relay == null:
		GameLog.log_general("You can't trade here.")
		return
	relay.request_trade(target)


func request_trade_by_name(player_name_query: String) -> void:
	var target := _find_player_by_name(player_name_query)
	if target == null:
		GameLog.log_general("No player named '%s' is currently online." % player_name_query)
		return
	request_trade(target)


# Right-click near a pouch on the ground (world_items.gd): pick it up.
func _try_pickup_pouch() -> bool:
	var world_items := get_tree().get_first_node_in_group("world_items")
	if world_items == null:
		return false
	var id: int = world_items.nearest_pouch(global_position)
	if id < 0:
		return false
	world_items.pick_up(id)
	return true


# Right-click near a ley-stone (ley_line_node.gd): a travelling caster attunes to it.
func _try_ley_line_node() -> bool:
	for node in get_tree().get_nodes_in_group("ley_line_node"):
		if is_instance_valid(node) and global_position.distance_to(node.global_position) <= node.USE_RANGE:
			node.interact(self)
			return true
	return false


# Right-click near a readable object in the world (world_note.gd: the note at the wagon wreck): range-based like the campfire.
func _try_read_world_note() -> bool:
	var nearest: Node = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("world_note"):
		if not is_instance_valid(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist <= node.USE_RANGE and dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	if nearest == null:
		return false
	nearest.read(self)
	return true


var _tradeskill_window_instance: Node = null

# Opens the generic crafting window against whichever campfire/cooking
# station is nearest, if one is in range — range-based rather than a raycast
# (see campfire.gd's comment) since these are static decorations with no
# collision body worth hit-testing. Returns whether one was opened, so
# _try_open_shop_or_loot() can fall through to corpse-looting otherwise.
func _try_open_campfire() -> bool:
	var nearest: Node = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("cooking_station"):
		if not is_instance_valid(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist <= node.COOK_RANGE and dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	if nearest == null:
		return false
	_open_tradeskill_window(nearest.STATION_ID, nearest.display_name, "Cook")
	return true


# Right-click near a town crafting station (crafting_station.gd: Forge, Oven, Tannery, ...) opens the crafting window for it.
# Range-based, same as the campfire.
func _try_open_crafting_station() -> bool:
	var nearest: Node = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("crafting_station"):
		if not is_instance_valid(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist <= node.use_range and dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	if nearest == null:
		return false
	_open_tradeskill_window(nearest.station_id, nearest.display_name, "Craft")
	return true


# Right-click near a gathering node (gathering_node.gd: thistle patch, ore vein, tree) starts gathering from it.
func _try_gather() -> bool:
	# One node at a time: right-clicking again mid-gather used to start the next vein too (two mining sounds at once).
	for node in get_tree().get_nodes_in_group("gathering_node"):
		if is_instance_valid(node) and node.get("_gatherer") == self:
			return true
	var nearest: Node = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("gathering_node"):
		if not is_instance_valid(node) or not node.is_available():
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist <= node.USE_RANGE and dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	if nearest == null:
		return false
	nearest.start_gather(self)
	return true


# Shows a gathering/crafting task on the cast bar: name, 0..1 progress, and seconds left.
func set_task_progress(title: String, progress: float, seconds_left: float) -> void:
	task_name = title
	task_progress = clampf(progress, 0.0, 1.0)
	task_seconds_left = maxf(seconds_left, 0.0)


func clear_task_progress() -> void:
	task_name = ""
	task_progress = 0.0
	task_seconds_left = 0.0


# True if the player knows a tradeskill recipe: innate recipes are always known, the rest must be learned
# (recipe scrolls — slot_button.gd's Learn button — or quest rewards, both through learn_recipe()).
func knows_recipe(recipe_id: String, recipe: Dictionary) -> bool:
	return bool(recipe.get("innate", false)) or known_recipes.has(recipe_id)


# Learns a tradeskill recipe and saves it. False if it was already known.
func learn_recipe(recipe_id: String) -> bool:
	if known_recipes.has(recipe_id):
		return false
	known_recipes.append(recipe_id)
	Global.player_data["known_recipes"] = known_recipes
	Global.save_player_data_to_file()
	return true


# Counts a successful craft of `recipe_id` (Global.player_data["crafted_recipes"] = {recipe id: times made}, which the
# recipe book shows). The first time a recipe is made it is "discovered" and says so in the log. True on that first time.
func record_craft(recipe_id: String, item_name: String) -> bool:
	var crafted: Dictionary = Global.player_data.get("crafted_recipes", {})
	var first := not crafted.has(recipe_id)
	crafted[recipe_id] = int(crafted.get(recipe_id, 0)) + 1
	Global.player_data["crafted_recipes"] = crafted
	if first:
		GameLog.log_general("[color=#ffd966]✦ %s has discovered the recipe for [b]%s[/b]![/color] [color=#aaaaaa](Recipe book: L)[/color]" % [player_name, item_name])
	return first


var _charm_control_frame: Node = null

# Reuses pet_frame.gd verbatim for a charmed monster's temporary control
# window, per the user's explicit request (2026-09-17) — that scene only
# needs `pet_name`/`combat_node`/`command` and the cmd_*() methods, all of
# which monster3d.gd's charm support (apply_charm()) now provides, so it has
# no idea the "pet" here isn't a real PetMinion. Tracked separately from
# active_pet_frame so a real summoned pet and a charmed monster can coexist.
func _open_charm_control_window(charmed: Node) -> void:
	if is_instance_valid(_charm_control_frame):
		_charm_control_frame.queue_free()
	var frame: Node = load("res://Scenes/pet_frame.tscn").instantiate()
	frame.add_to_group("game_hud")
	get_tree().root.add_child(frame)
	frame.set_pet(charmed)
	_charm_control_frame = frame


func _open_tradeskill_window(station_id: String, title: String, action_label: String) -> void:
	if is_instance_valid(_tradeskill_window_instance):
		_tradeskill_window_instance.queue_free()
	_tradeskill_window_instance = load("res://Scenes/tradeskill_window.tscn").instantiate()
	get_tree().root.add_child(_tradeskill_window_instance)
	_tradeskill_window_instance.setup(station_id, title, action_label)


func _raycast_world_hit(screen_pos: Vector2) -> Node:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return null
	var space := get_world_3d().direct_space_state
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 100.0)
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	return hit.get("collider") if hit else null


# A forgiving click target for NPCs. The mouse ray only reports the FIRST thing it meets, so a small NPC like
# Kenji is easy to lose to the level's wall/gate collision, another creature, or your own pet standing in the
# line of sight (found by simulating clicks around him: from some sides every click hit the wall instead).
# When the ray hit something that isn't itself an NPC, this returns the nearest VendorNPC whose body centre is
# within NPC_CLICK_RADIUS_PX of the cursor and NPC_CLICK_RANGE of the player; `fallback` (the ray's own hit)
# is returned when there is none.
const NPC_CLICK_RADIUS_PX := 55.0
const NPC_CLICK_RANGE := 12.0

func _vendor_near_mouse(mouse_pos: Vector2, fallback: Node = null) -> Node:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return fallback
	var best: Node = null
	var best_px := NPC_CLICK_RADIUS_PX
	var candidates: Array = get_tree().get_nodes_in_group("npc_vendor")
	candidates.append_array(get_tree().get_nodes_in_group("npc_guard"))  # guards take hand-ins too (see try_offer_item_to_npc_at)
	for node in candidates:
		if not (node is VendorNPC or node is GuardNPC) or not is_instance_valid(node):
			continue
		if global_position.distance_to(node.global_position) > NPC_CLICK_RANGE:
			continue
		var body := node.get_node_or_null("CollisionShape3D") as Node3D
		var centre: Vector3 = body.global_position if body else node.global_position + Vector3(0, 1.0, 0)
		if camera.is_position_behind(centre):
			continue
		var px := camera.unproject_position(centre).distance_to(mouse_pos)
		if px < best_px:
			best_px = px
			best = node
	return best if best != null else fallback


# EverQuest-style hand-over: an item dragged out of the backpack and released on an NPC in the world (slot_button.gd
# calls this when the drop landed on no UI at all). Only NPCs that define receive_item_drop() take part — Kenji.
# Uses the same forgiving pick as right-click. Returns whether an NPC took it.
func try_offer_item_to_npc_at(screen_pos: Vector2, item: Dictionary) -> bool:
	if Global.mouselook_enabled:
		return false
	var target := _raycast_world_hit(screen_pos)
	if not (target is VendorNPC or target is GuardNPC):
		target = _vendor_near_mouse(screen_pos, target)
	if (target is VendorNPC or target is GuardNPC) and target.has_method("receive_item_drop"):
		target.receive_item_drop(item, self)
		return true
	return false


# Right-click a downed ally to bandage them back up — an alternative to
# healing them with a spell, using whichever bandage-type consumable
# (heal_amount > 0, see items.json/slot_button.gd's Use button) is found
# first in inventory. Reuses _heal_target() so the actual heal/revival logic
# (relay to the target's own machine, bleed-out check) is identical to a
# real heal spell landing on them — a bandage is just another heal source.
func _try_bandage(target: Node) -> void:
	var bandage := _find_bandage_in_inventory()
	if bandage.is_empty():
		GameLog.log_general("You don't have a bandage to use.")
		return
	Sfx.play("bandage")
	var heal_amount: int = int(bandage["item"].get("heal_amount", 0))
	heal_amount = int(heal_amount * (1.0 + combat_node.skill_bonus("bandage_heal_pct") / 100.0))
	_tick_skill("bind_wound")
	_heal_target(target, target.combat_node, heal_amount)
	Inventory.consume_one(bandage["slot_type"], bandage["slot_index"], bandage["bag_slot"], bandage["item_index"])
	GameLog.log_general("[color=#88ffaa]You bandage %s's wounds.[/color]" % TargetFrame.display_name(target))


func _find_bandage_in_inventory() -> Dictionary:
	for i in range(Inventory.BASIC_INVENTORY_SIZE):
		var item: Dictionary = Inventory.get_basic_inventory_slot(i)
		if not item.is_empty() and not Inventory.is_bag(item) \
				and item.get("type", "") == "consumable" and int(item.get("heal_amount", 0)) > 0:
			return {"item": item, "slot_type": "basic", "slot_index": i, "bag_slot": -1, "item_index": -1}
	for bag_slot in range(Inventory.BASIC_INVENTORY_SIZE):
		var bag: Dictionary = Inventory.get_basic_inventory_slot(bag_slot)
		if not Inventory.is_bag(bag):
			continue
		var contents: Array = Inventory.get_bag_contents(bag_slot)
		for item_index in range(contents.size()):
			var item: Dictionary = contents[item_index]
			if item.get("type", "") == "consumable" and int(item.get("heal_amount", 0)) > 0:
				return {"item": item, "slot_type": "bag", "slot_index": -1, "bag_slot": bag_slot, "item_index": item_index}
	return {}


func _open_shop(vendor: Node) -> void:
	# NPCs built on VendorNPC that aren't shops (Kenji) supply their own
	# right-click interaction instead of the shop window.
	if vendor.has_method("open_interaction"):
		vendor.open_interaction(self)
		return
	open_shop_window(vendor)


# Opens the shop window against `vendor`. Public because a vendor that runs its own interaction (the traveling merchant only
# trades while he stands still) calls it from its open_interaction() once it has decided the shop may open.
func open_shop_window(vendor: Node) -> void:
	if is_instance_valid(_shop_window_instance):
		_shop_window_instance.queue_free()
	_shop_window_instance = load("res://Scenes/shop_window.tscn").instantiate()
	get_tree().root.add_child(_shop_window_instance)
	_shop_window_instance.setup(vendor)
	if vendor.has_method("greet_player"):
		vendor.greet_player(player_name)


# G: loot every corpse within LOOT_ALL_RANGE at once — for when a crafting station, an NPC or another corpse is in the way.
const LOOT_ALL_RANGE := 10.0

func loot_all_nearby(quiet: bool = false) -> void:
	var corpses := 0
	var taken := 0
	for node in get_tree().get_nodes_in_group("monsters"):
		if node is Monster and (node as Monster).current_state == Monster.State.DEAD \
				and global_position.distance_to((node as Node3D).global_position) <= LOOT_ALL_RANGE:
			corpses += 1
			taken += (node as Monster).loot_everything()
	if quiet and taken == 0:
		return   # auto-loot: says nothing when there's nothing
	if corpses == 0:
		GameLog.log_general("There is nothing to loot within %d m." % int(LOOT_ALL_RANGE))
	elif taken == 0:
		GameLog.log_general("You search %d corpse%s but find nothing more." % [corpses, "" if corpses == 1 else "s"])
	else:
		Sfx.play("pickup")


func _try_loot_corpse() -> void:
	var nearest: Monster = null
	var nearest_dist := LOOT_RANGE

	for node in get_tree().get_nodes_in_group("monsters"):
		if not node is Monster:
			continue
		var m := node as Monster
		if m.current_state != Monster.State.DEAD:
			continue
		var dist := global_position.distance_to(m.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = m

	if nearest == null:
		print("⚠️ No lootable corpse within range.")
		return

	# open_loot_window() now handles "nothing here" itself (personal loot is
	# rolled lazily per-peer, so there's no shared is_lootable flag to check
	# beforehand — see monster3d.gd).
	nearest.open_loot_window()


# A Firewood Bundle's Light button (slot_button.gd): lights a campfire a step in front of you (campfire_relay.gd).
# Returns whether it did (the caller then uses up the bundle).
func light_campfire(item_id: String) -> bool:
	var fires := CampfireRelay.relay(get_tree())
	if fires == null:
		GameLog.log_general("You can't make camp here.")
		return false
	var why := CampfireRelay.refusal(self)
	if why != "":
		GameLog.log_general("[color=#ff8866]%s[/color]" % why)
		return false
	var forward := -global_transform.basis.z
	var at := global_position + Vector3(forward.x, 0.0, forward.z).normalized() * 1.5
	fires.light(item_id, at, player_name)
	return true


const HAIL_RANGE := 5.0
const PET_RANGE := 4.0


# /pet — pet your current target if it is pettable (the cats), otherwise the
# nearest pettable thing within PET_RANGE. The petted node's receive_pet()
# supplies the reply text.
func try_pet_nearby() -> void:
	if is_instance_valid(current_target) and current_target.is_in_group("pettable"):
		if global_position.distance_to(current_target.global_position) > PET_RANGE:
			GameLog.log_general("You are too far away to pet %s." % TargetFrame.display_name(current_target))
			return
		current_target.receive_pet(self)
		return
	var nearest: Node = null
	var nearest_dist := PET_RANGE
	for node in get_tree().get_nodes_in_group("pettable"):
		if not is_instance_valid(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	if nearest == null:
		GameLog.log_general("There is nothing close enough to pet.")
		return
	nearest.receive_pet(self)

func try_hail_nearby_npc() -> void:
	# Your target is another player, or a pet (anyone's, or a charmed monster): greet them out loud (test 38).
	var t := current_target
	if is_instance_valid(t) and t != self and (t.is_in_group("player") or t.is_in_group("pets") or not str(t.get("pet_name") if "pet_name" in t else "").is_empty()):
		send_say("Hail, %s!" % TargetFrame.display_name(t).capitalize() if not t.is_in_group("player") else "Hail, %s!" % str(t.get("player_name")))
		return
	var nearest: Node = null
	var nearest_dist := HAIL_RANGE

	for node in get_tree().get_nodes_in_group("npc_guard") + get_tree().get_nodes_in_group("npc_vendor"):
		if not is_instance_valid(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node

	if nearest == null:
		GameLog.log_general("There's no one nearby to hail.")
		return

	if nearest is VendorNPC and not nearest.has_method("open_interaction"):
		_open_shop(nearest)
	elif nearest.has_method("respond_to_hail"):
		nearest.respond_to_hail()
#endregion

#region Mob Appraisal
const APPRAISAL_COOLDOWN := 10.0

const APPRAISAL_TEXTS := {
	"Trivial": [
		"This creature poses no threat whatsoever.",
		"You could defeat this in your sleep.",
		"A pathetic opponent. You could easily dispatch it quickly.",
		"Not even a warm-up.",
	],
	"Easy": [
		"This appears to be a simple opponent.",
		"You have the advantage here.",
		"A straightforward victory awaits.",
		"Nothing you can't handle.",
		"An easy kill, should you desire it.",
	],
	"Moderate": [
		"A worthy opponent. This could be interesting.",
		"The battle would be evenly matched.",
		"You sense a capable foe before you.",
		"This one fights with skill.",
		"Victory is possible, but not assured.",
	],
	"Hard": [
		"This creature is significantly more powerful.",
		"You sense great danger ahead.",
		"Engaging this foe would be quite risky.",
		"You are outmatched here.",
		"Retreat may be the wisest course.",
	],
	"Deadly": [
		"This being radiates an overwhelming aura of power.",
		"You have no hope against such a force.",
		"Flight is your only option.",
		"Death awaits you here.",
		"Do not engage. You will perish.",
	],
}

const APPRAISAL_FACTION_TEXT := {
	"Ally":    {"prefix": "Your ally appears... ", "suffix": "They seem eager to fight alongside you."},
	"Neutral": {"prefix": "This stranger... ",      "suffix": "Their intentions remain unclear."},
	"Enemy":   {"prefix": "Your enemy... ",         "suffix": "They regard you with clear hostility."},
}

# Monster faction names ("Bandit"/"Dustwalker"/"Lumora"/"None") mostly don't
# match player_faction.json's named factions — alias the ones that do.
# Monster "faction" names -> the standing they use (Data/player_faction.json / factions.json).
const FACTION_STANDING_ALIASES := {"Lumora": "Villagers of Lumora", "Djhanid": "Djhanid Clans"}


func _appraisal_tier(diff: int) -> Dictionary:
	# (test 37: DCs of 15 and 20 against d20 + a +1 bonus meant "you sense nothing unusual" most of the time; the roll now
	# only decides how MUCH you learn, and these are easier)
	if diff <= -5:
		return {"dc": 4, "name": "Trivial"}
	elif diff <= -2:
		return {"dc": 7, "name": "Easy"}
	elif diff <= 1:
		return {"dc": 10, "name": "Moderate"}
	elif diff <= 4:
		return {"dc": 14, "name": "Hard"}
	else:
		return {"dc": 18, "name": "Deadly"}


func _ability_modifier(stat: int) -> int:
	return int(floor((stat - 10) / 2.0))


func _faction_reputation_text(target: Node) -> String:
	# Monsters expose "faction"; NPCs like guards expose "npc_faction" instead.
	var target_faction: String = "None"
	if "faction" in target:
		target_faction = target.get("faction")
	elif "npc_faction" in target:
		target_faction = target.get("npc_faction")
	var mapped: String = standing_name(target_faction)
	if not faction_standing.has(mapped):
		return "Unaligned"
	var standing: int = faction_standing.get(mapped, 0) + race_faction_offset
	var label := "Neutral"
	if standing <= -25:  label = "Hated"
	elif standing < 0:   label = "Disliked"
	elif standing < 20:  label = "Neutral"
	elif standing < 40:  label = "Liked"
	else:                label = "Revered"
	return "%s (%d)" % [label, standing]


func try_appraise_target() -> void:
	if not current_target or not is_instance_valid(current_target):
		GameLog.log_general("You have no target to appraise.")
		return

	var target_id := current_target.get_instance_id()
	var cd: float = _appraisal_cooldowns.get(target_id, 0.0)
	if cd > 0.0:
		GameLog.log_general("You must wait %.1fs before appraising that again." % cd)
		return
	_appraisal_cooldowns[target_id] = APPRAISAL_COOLDOWN

	var target_level := TargetFrame.entity_level(current_target)
	var diff := target_level - combat_node.level
	var tier: Dictionary = _appraisal_tier(diff)
	var faction: String = TargetFrame.faction_status(current_target)
	var target_desc: String = TargetFrame.display_name(current_target)

	var int_mod := _ability_modifier(combat_node.intelligence)
	var wis_mod := _ability_modifier(combat_node.wisdom)
	# Appraising is Perception at work: every appraisal trains it, and each 10 points of it add +1 to the roll. Perception
	# will matter more later (hidden enemies, traps, secrets).
	_tick_skill("perception")
	var perception_bonus := effective_skill("perception") / 10
	var roll := randi_range(1, 20)
	var total := roll + maxi(int_mod, wis_mod) + perception_bonus
	var success: bool = total >= tier["dc"]

	var frames := get_tree().get_nodes_in_group("target_frame")
	var frame: Node = frames[0] if not frames.is_empty() else null

	if roll == 1:
		if frame:
			frame.show_wrong_color(30.0)
		GameLog.log_general("[color=#cc4444]Your senses betray you. %s seems %s than it truly is...[/color]" % [
			target_desc.capitalize(), "weaker" if randf() < 0.5 else "stronger"
		])
		return

	# Always (like EverQuest's /consider): who it is, how dangerous, how it regards you. The roll decides the rest.
	var is_crit: bool = roll == 20
	var flavor_bank: Array = APPRAISAL_TEXTS.get(tier["name"], [])
	var flavor: String = flavor_bank[randi() % flavor_bank.size()] if not flavor_bank.is_empty() else ""
	var faction_text: Dictionary = APPRAISAL_FACTION_TEXT.get(faction, {})

	GameLog.log_general("[color=#ccddff][b]Appraisal: %s[/b] (Lv %d, %s)[/color]" % [target_desc.capitalize(), target_level, tier["name"]])
	if not flavor.is_empty():
		GameLog.log_general(flavor)
	GameLog.log_general("%s%s" % [faction_text.get("prefix", ""), faction_text.get("suffix", "")])
	GameLog.log_general("Estimated threat: %s" % tier["name"])
	GameLog.log_general("Faction Reputation: %s" % _faction_reputation_text(current_target))

	if not success:
		GameLog.log_general("[color=#aaaaaa]You can't make out more than that about %s.[/color]" % target_desc)
		return

	# what it can do: its real abilities (monsters.json "abilities"), with what stops them
	var tricks: Array = current_target.get("abilities") if "abilities" in current_target and current_target.get("abilities") is Array else []
	if not tricks.is_empty():
		var described := []
		for a in tricks:
			var kind := str(a.get("type", ""))
			var note: String = {"nuke": "a spell", "debuff": "a curse", "aoe": "hits everyone near", "heal": "heals itself",
					"summon": "calls for help", "enrage": "frenzies when hurt"}.get(kind, kind)
			if float(a.get("cast", 0.0)) > 0.0 and kind != "enrage":
				note += ", cast: stun or silence to stop it"
			described.append("%s (%s)" % [str(a.get("name", "?")), note])
		GameLog.log_general("[color=#ffcc88]It can: %s[/color]" % "; ".join(described))

	var resistances: Array = current_target.get("resistances") if "resistances" in current_target else []
	var weaknesses: Array = current_target.get("weaknesses") if "weaknesses" in current_target else []
	if not resistances.is_empty():
		GameLog.log_general("Resistances: [%s]" % ", ".join(resistances))
	if not weaknesses.is_empty():
		GameLog.log_general("Weaknesses: [%s]" % ", ".join(weaknesses))

	var special: String = current_target.get("special_ability") if "special_ability" in current_target else ""
	if not special.is_empty():
		GameLog.log_general("Special Ability: %s" % special)

	var quality := "Common"
	if target_level >= 15:   quality = "Epic"
	elif target_level >= 10: quality = "Rare"
	elif target_level >= 5:  quality = "Uncommon"
	GameLog.log_general("Loot Quality: %s" % quality)

	var target_is_boss: bool = current_target.get("is_boss") if "is_boss" in current_target else false
	if target_is_boss:
		GameLog.log_general("[color=#ff44ff]An aura of ancient power surrounds this being.[/color]")

	var corruption: String = current_target.get("corruption") if "corruption" in current_target else ""
	if not corruption.is_empty():
		GameLog.log_general("[color=#aa44ff]This creature is twisted by the Void. (%s)[/color]" % corruption)

	if is_crit:
		var secret: String = current_target.get("secret_note") if "secret_note" in current_target else ""
		if secret.is_empty():
			secret = "You glimpse something the creature is hiding..."
		GameLog.log_general("[color=#ffdd44]%s[/color]" % secret)
#endregion

#region Character sheet
var character_sheet_scene = preload("res://Scenes/character_sheet.tscn")
var character_sheet_instance: Node = null
var abilities_book_instance: Node = null
#endregion

#region Initialization
# The zone scene ships with one pre-placed player (the solo/host character). A
# joiner's zone must not keep it — their own character arrives from the host's
# PlayerSpawner, and a leftover authority-1 copy would show as a phantom "host" that
# never updates — and a dedicated server has no character at all. Freed here, before
# any child's _ready() (camera rig, synchronizer) treats it as the local player.
func _enter_tree() -> void:
	if Net.omit_preplaced_player and get_parent().name != "RemotePlayers":
		queue_free()


func _ready() -> void:
	# Never ride another body (test 38: standing on a player's head, you were carried when they gated or zoned 1,200 m away).
	# There are no moving platforms in the world, so nothing underfoot should move you.
	platform_floor_layers = 0
	_fall_grace_until_ms = Time.get_ticks_msec() + FALL_GRACE_MS  # the game drops you onto the ground when you arrive
	if is_queued_for_deletion():
		return
	# Players pass through each other, as in EverQuest (test 38: two characters arriving on the same spot each climbed on
	# top of the other, 140 m up, then fell to their deaths). Targeting rays still hit them.
	for other in get_tree().get_nodes_in_group("player"):
		if other is PhysicsBody3D and other != self:
			add_collision_exception_with(other)
			other.add_collision_exception_with(self)
	add_to_group("player")
	_build_character_model()

	# Every player gets a combat_node now, puppets included — named "CombatNode"
	# so player3d.tscn's SceneReplicationConfig can target its current_hp/
	# max_hp/current_mana/max_mana/level by NodePath ("CombatNode:current_hp"
	# etc). A puppet's copy is never locally simulated (no regen ticks, no
	# stat recalculation from gear) — it just sits there as a receiver for
	# whatever the authoritative owner's real combat_node replicates out,
	# which is what lets group_frame/target_frame show a remote member's real
	# HP/MP instead of an empty bar or a Nil-property crash on a missing
	# combat_node. See project_multiplayer_netcode memory: this was the
	# single biggest documented netcode gap before this change.
	combat_node = CombatNode.new()
	combat_node.name = "CombatNode"
	add_child(combat_node)
	combat_node.effect_ticked.connect(_on_effect_ticked)
	# Caster travel / gates / binding (player_travel.gd). On puppets too: its RPCs arrive on the caster's copy on every peer.
	var travel := PlayerTravel.new()
	travel.name = "Travel"
	add_child(travel)
	# Duels and PvP (player_versus.gd). On every copy of the player: its RPCs arrive on the victim's own machine.
	var versus := PlayerVersus.new()
	versus.name = "Versus"
	add_child(versus)
	# Cartography (cartography.gd): charts the land as you walk, when you know the skill and carry the kit.
	var cart := Cartography.new()
	cart.name = "Cartography"
	add_child(cart)
	# Perception checks near interesting places (perception_watcher.gd): only acts for the local player.
	var perception := PerceptionWatcher.new()
	perception.name = "Perception"
	add_child(perception)

	# Every peer's own local copy of this player needs to know how to build a
	# replicated pet spawn locally (mirrors multiplayer_player_spawner.gd's
	# spawn_function assignment happening before ITS OWN authority gate) — a
	# puppet representation of another player still needs this so their pet
	# actually appears on my screen too.
	$PetSpawner.spawn_function = _build_pet

	# Multiplayer puppet: every player3d node in the scene whose multiplayer
	# authority isn't this machine (the host's pre-placed node, from a joining
	# client's point of view; another peer's dynamically-spawned node, from
	# anyone else's) — no local save data, no full combat_node simulation, no
	# HUD windows for it. Offline/single-player is unaffected: with no
	# multiplayer peer active, is_multiplayer_authority() is always true. See
	# _physics_process(), _process(), _unhandled_input() for the matching
	# gates, and camera_controller.gd for why its camera/mouselook are
	# disabled too.
	if not is_multiplayer_authority():
		return

	group_members = [get_multiplayer_authority()]
	Net.group_invite_response_received.connect(_on_group_invite_response)
	Net.group_roster_received.connect(_on_group_roster_received)
	Net.group_removed_received.connect(_on_group_removed)

	Inventory.equipment_changed.connect(_on_equipment_changed)

	load_faction_standing()
	_load_spell_cache()
	load_player_data_from_global()
	call_deferred("_restore_pet_if_saved")
	Global.start_playtime_tracking()  # the /played clock starts when you enter the world
	_announce_zone.call_deferred()
	_death_flavor = NPCFlavorText.new("res://Data/player_death_flavor.json")
	_food_drink_flavor = NPCFlavorText.new("res://Data/food_drink_flavor.json")
	_restore_last_position()
	_ensure_bind_point()
	# Hills (test 34): a slightly thicker collision margin and a longer floor snap keep the capsule from slipping into a
	# steep heightmap slope, and slopes up to 50 degrees are walkable (Godot's default is 45).
	safe_margin = 0.04
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)

	# Dictionaries are references in GDScript — aliasing these means every
	# future apply_effect()/remove_effect() (stances, campfire warmth, spell
	# buffs) is automatically reflected in Global.player_data with no
	# per-frame sync needed, so whatever triggers the next
	# save_player_data_to_file() (there are many call sites) always writes
	# current buff state, not a stale snapshot from login.
	Global.player_data["active_effects"] = combat_node.active_effects

	_spawn_hud()
	call_deferred("_announce_world_entry")

	print("[Player3D] ✅ %s initialized | HP: %d/%d | Mana: %d/%d" % [
		player_name, combat_node.current_hp, combat_node.max_hp,
		combat_node.current_mana, combat_node.max_mana
	])


# Tells every other player "X, the 10th season voidknight, enters the world!"
# (multiplayer only — see Net.broadcast_world_announce()). Runs once per world
# entry on the machine that owns this character.
func _announce_world_entry() -> void:
	if is_multiplayer_authority() and not _arrived_by_zone_line:   # zoning isn't entering the world (it's server-wide now)
		Net.broadcast_world_announce("join", player_name, int(combat_node.level), player_class)


# Which race/sex gets which model+animation set. Anything not listed here
# (every race, and Human males) falls back to DEFAULT_CHARACTER_MODEL — the
# original shared Mixamo model every class has always used. Mixamo animations
# are baked into a single shared AnimationLibrary per model (idle/walk/run/
# jump/sit/attack_horizontal/attack_downward/death) rather than kept as
# separate imported scenes, so the game only loads the lightweight keyframe
# data instead of instancing the (much heavier) source meshes just to steal
# their animations.
const CHARACTER_MODELS := {
	"human_female": {
		# Re-rigged again 2026-09-17 ("Version 2" — new outfit/mesh/texture and
		# a full new Mixamo animation set, including a proper "-buff"-suffixed
		# cast clip this model never had before, see
		# [[reference_character_model_pipeline]] point 10). female_animations.res
		# was rebuilt from this folder's source FBX files, same
		# idle/walk/run/jump/sit/attack_horizontal/attack_downward/death/
		# cast_beneficial/cast_detrimental key shape as every other model.
		"scene":   "res://models/Human Female/Human Female Breathing Idle.fbx",
		"library": "res://models/Human Female/female_animations_pack.res",
		# The Mixamo/Blender export chain for these Meshy-sourced models keeps
		# losing the real texture link (the FBX's own material points at a
		# file that only ever existed on the machine it was exported from) —
		# rather than depend on that export step working, apply the known-good
		# texture directly as a Godot material override. See
		# _apply_texture_override().
		"texture_override": "res://models/Human Female/Meshy_AI_tavern_maid_new_outfi_biped_texture_0.png",
	},
	"human_male": {
		"scene":   "res://models/Human Male/Human Male Breathing Idle.fbx",
		"library": "res://models/Human Male/human_male_animations_pack.res",
		"texture_override": "res://models/Human Male/Meshy_AI_fantasy_commoner_rigg_biped_texture_0.png",
	},
	"half_elf_female": {
		# Re-rigged 2026-09-18 ("Version 2" — new mesh/texture/animation set,
		# same pipeline as Human Female's Version 2 — see
		# [[reference_character_model_pipeline]]). Measures the same 1.7m
		# baseline every correctly-exported model does, so no scale correction.
		"scene":   "res://models/Half-Elf Female/Half-Elf Female Breathing Idle.fbx",
		"library": "res://models/Half-Elf Female/half_elf_female_animations_pack.res",
		"texture_override": "res://models/Half-Elf Female/Meshy_AI_female_half_elf_hero__biped_texture_0.png",
	},
	"half_elf_male": {
		"scene":   "res://models/Half-Elf Male/Half-Elf Male Breathing Idle.fbx",
		"library": "res://models/Half-Elf Male/half_elf_male_animations_pack.res",
		"texture_override": "res://models/Half-Elf Male/Meshy_AI_male_half_elf_commone_biped_texture_0.png",
	},
	"troll_female": {
		"scene":   "res://models/Troll Female/Troll Female Breathing Idle.fbx",
		"library": "res://models/Troll Female/troll_female_animations_pack.res",
		"texture_override": "res://models/Troll Female/Meshy_AI_female_troll_commoner_biped_texture_0.png",
	},
	"troll_male": {
		"scene":   "res://models/Troll Male/Troll Male Breathing Idle.fbx",
		"library": "res://models/Troll Male/troll_male_animations_pack.res",
		"texture_override": "res://models/Troll Male/Meshy_AI_troll_commoner_rig_biped_texture_0.png",
	},
	"elf_male": {
		"scene":   "res://models/Elf Male/Elf Male Breathing Idle.fbx",
		"library": "res://models/Elf Male/elf_male_animations_pack.res",
		"texture_override": "res://models/Elf Male/Meshy_AI_Male_Elf_Commoner_Rig_biped_texture_0.png",
	},
	"elf_female": {
		# Re-rigged again 2026-09-18 ("Version 2") — a fresh export at the
		# same standard 1.7m baseline every other correctly-exported model
		# uses, confirmed via a headless AABB measurement (identical to Guard
		# Reyna's own raw mesh height). The old 2026-09-16 mesh needed a huge
		# "scale": 98.0 hack because THAT specific export was badly
		# undersized; this replacement doesn't need it at all — don't carry
		# that value forward if this model is ever re-rigged again without
		# re-measuring first.
		"scene":   "res://models/Elf Female/Elf Female Breathing Idle.fbx",
		"library": "res://models/Elf Female/elf_female_animations_pack.res",
		"texture_override": "res://models/Elf Female/Meshy_AI_female_elf_hero_rig_biped_texture_0.png",
	},
	"dark_elf_male": {
		"scene":   "res://models/Dark Elf Male/Dark Elf Male Breathing Idle.fbx",
		"library": "res://models/Dark Elf Male/dark_elf_male_animations_pack.res",
		"texture_override": "res://models/Dark Elf Male/Meshy_AI_Male_Dark_Elf_Commone_biped_texture_0.png",
	},
	"dark_elf_female": {
		# Re-rigged 2026-09-18 ("Version 2") — same standard 1.7m baseline,
		# no scale correction needed (see elf_female's comment above).
		"scene":   "res://models/Dark Elf Female/Dark Elf Female Breathing Idle.fbx",
		"library": "res://models/Dark Elf Female/dark_elf_female_animations_pack.res",
		"texture_override": "res://models/Dark Elf Female/Meshy_AI_female_dark_elf_hero__biped_texture_0.png",
	},
	# Added 2026-09-18 — first wiring for these 6 races (Dwarf/Gnome/Halfling/
	# Half-Orc/Lizardkin/Ogre), same pipeline as every other model here. See
	# [[reference_character_model_pipeline]].
	"dwarf_female": {
		"scene":   "res://models/Dwarf Female/Dwarf Female Breathing Idle.fbx",
		"library": "res://models/Dwarf Female/dwarf_female_animations_pack.res",
		"texture_override": "res://models/Dwarf Female/Meshy_AI_female_dwarf_commoner_biped_texture_0.png",
	},
	"dwarf_male": {
		"scene":   "res://models/Dwarf Male/Dwarf Male Breathing Idle.fbx",
		"library": "res://models/Dwarf Male/dwarf_male_animations_pack.res",
		"texture_override": "res://models/Dwarf Male/Meshy_AI_male_dwarf_commoner_r_biped_texture_0.png",
	},
	"gnome_female": {
		"scene":   "res://models/Gnome Female/Gnome Female Breathing Idle.fbx",
		"library": "res://models/Gnome Female/gnome_female_animations_pack.res",
		"texture_override": "res://models/Gnome Female/Meshy_AI_female_gnome_commoner_biped_texture_0.png",
	},
	"gnome_male": {
		"scene":   "res://models/Gnome Male/Gnome Male Breathing Idle.fbx",
		"library": "res://models/Gnome Male/gnome_male_animations_pack.res",
		"texture_override": "res://models/Gnome Male/Meshy_AI_male_gnome_commoner_r_biped_texture_0.png",
	},
	"halfling_female": {
		"scene":   "res://models/Halfling Female/Halfling Female Breathing Idle.fbx",
		"library": "res://models/Halfling Female/halfling_female_animations_pack.res",
		"texture_override": "res://models/Halfling Female/Meshy_AI_female_halfling_commo_biped_texture_0.png",
	},
	"halfling_male": {
		"scene":   "res://models/Halfling Male/Halfling Male Breathing Idle.fbx",
		"library": "res://models/Halfling Male/halfling_male_animations_pack.res",
		"texture_override": "res://models/Halfling Male/Meshy_AI_male_halfling_commone_biped_texture_0.png",
	},
	"half_orc_female": {
		"scene":   "res://models/Half-Orc Female/Half-Orc Female Breathing Idle.fbx",
		"library": "res://models/Half-Orc Female/half_orc_female_animations_pack.res",
		"texture_override": "res://models/Half-Orc Female/Meshy_AI_female_half_orc_commo_biped_texture_0.png",
	},
	"half_orc_male": {
		"scene":   "res://models/Half-Orc Male/Half-Orc Male Breathing Idle.fbx",
		"library": "res://models/Half-Orc Male/half_orc_male_animations_pack.res",
		"texture_override": "res://models/Half-Orc Male/Meshy_AI_male_half_orc_commone_biped_texture_0.png",
	},
	"lizardkin_female": {
		"scene":   "res://models/Lizardkin Female/Lizardkin Female Breathing Idle.fbx",
		"library": "res://models/Lizardkin Female/lizardkin_female_animations_pack.res",
		"texture_override": "res://models/Lizardkin Female/Meshy_AI_female_lizardkin_comm_biped_texture_0.png",
	},
	"lizardkin_male": {
		"scene":   "res://models/Lizardkin Male/Lizardkin Male Breathing Idle.fbx",
		"library": "res://models/Lizardkin Male/lizardkin_male_animations_pack.res",
		"texture_override": "res://models/Lizardkin Male/Meshy_AI_male_lizardkin_common_biped_texture_0.png",
	},
	"ogre_female": {
		"scene":   "res://models/Ogre Female/Ogre Female Breathing Idle.fbx",
		"library": "res://models/Ogre Female/ogre_female_animations_pack.res",
		"texture_override": "res://models/Ogre Female/Meshy_AI_female_ogre_commoner__biped_texture_0.png",
	},
	"ogre_male": {
		"scene":   "res://models/Ogre Male/Ogre Male Breathing Idle.fbx",
		"library": "res://models/Ogre Male/ogre_male_animations_pack.res",
		"texture_override": "res://models/Ogre Male/Meshy_AI_male_ogre_commoner_ri_biped_texture_0.png",
	},
}
const DEFAULT_CHARACTER_MODEL := {
	"scene":   "res://models/player/character.fbx",
	"library": "res://models/player/player_animations.res",
}
# Same facing correction player3d.tscn originally hardcoded on its static
# Character node — every Mixamo export shares this convention, so it applies
# equally regardless of which model gets built here.
var CHARACTER_MODEL_TRANSFORM := Transform3D(
	Vector3(-1.0, 0.0, -8.742278e-08),
	Vector3(0.0, 1.0, 0.0),
	Vector3(8.742278e-08, 0.0, -1.0),
	Vector3(0.0, 0.0, 0.0)
)

var _built_character_model_key: String = ""
var _arrived_by_zone_line := false   # came in through a zone line (or a gate / death to another zone): no "enters the world"


func _character_model_key() -> String:
	return "%s_%s" % [player_race.to_lower(), player_sex.to_lower()]


# Builds (or rebuilds) the "Character" child to match player_race/player_sex —
# called once immediately in _ready() with whatever defaults are set at that
# point (so nobody's ever modelless), and again whenever the real values
# become known: locally via load_character_data() for the authoritative
# player, or via replication for a puppet (see _physics_process()'s puppet
# branch, since player_race/player_sex arrive a frame or two after spawn,
# not at _ready() time). A no-op if the resulting model wouldn't change.
func _build_character_model() -> void:
	var key := _character_model_key()
	if key == _built_character_model_key and has_node("Character"):
		return

	if has_node("Character"):
		var old_character := get_node("Character")
		remove_child(old_character)
		old_character.queue_free()

	var model_info: Dictionary = CHARACTER_MODELS.get(key, DEFAULT_CHARACTER_MODEL)
	var character_scene := load(model_info["scene"])
	if not character_scene:
		return
	var character: Node3D = character_scene.instantiate()
	character.name = "Character"
	MeshSmoothing.smooth_model(character)   # the Meshy exports' hard edges made faces look faceted (test 35)
	character.transform = CHARACTER_MODEL_TRANSFORM
	# Per-model scale correction for a source mesh exported at the wrong unit
	# scale (see elf_female's entry above) — most models don't need this and
	# just fall back to 1.0, i.e. no change to CHARACTER_MODEL_TRANSFORM.
	var model_scale: float = model_info.get("scale", 1.0)
	if model_scale != 1.0:
		character.transform = character.transform.scaled(Vector3.ONE * model_scale)
	add_child(character)

	animation_player = character.get_node_or_null("AnimationPlayer")
	if animation_player:
		var lib := load(model_info["library"]) as AnimationLibrary
		if lib:
			# The imported model's AnimationPlayer already owns a "" library
			# (its raw Mixamo export clips) — replace it so idle/walk/jump can
			# be played unprefixed instead of needing a distinct library name.
			if animation_player.has_animation_library(""):
				animation_player.remove_animation_library("")
			animation_player.add_animation_library("", lib)

	if model_info.has("texture_override"):
		_apply_texture_override(character, model_info["texture_override"])
	character.set_meta("base_scale", character.scale)
	_built_character_model_key = key
	_apply_appearance()
	HeldGear.apply(character, held_gear)   # a rebuilt model (race / sex change) gets its weapon back


# Puts this character's look (appearance_json) on the built model.
func _apply_appearance() -> void:
	var character := get_node_or_null("Character") as Node3D
	if character == null:
		return
	var model_info: Dictionary = CHARACTER_MODELS.get(_character_model_key(), DEFAULT_CHARACTER_MODEL)
	var parsed = JSON.parse_string(appearance_json) if not appearance_json.is_empty() else {}
	var a: Dictionary = Appearance.validate(parsed if typeof(parsed) == TYPE_DICTIONARY else {}, player_sex, player_race)
	Appearance.apply(character, str(model_info["scene"]), str(model_info.get("texture_override", "")), a, player_race,
			character.get_meta("base_scale", character.scale))


# Saves a new look (the mirror or the creation screen): the whole thing while it isn't locked yet, afterwards only what
# may still change (Appearance.CHANGEABLE_AFTER_LOCK; the server keeps the rest anyway). Locks it.
func set_appearance(new_look: Dictionary) -> Dictionary:
	var stored = Global.player_data.get("appearance")
	var merged: Dictionary = Appearance.merge(stored, new_look, player_sex, player_race)["appearance"]
	merged["locked"] = true
	Global.player_data["appearance"] = merged
	appearance_json = JSON.stringify(merged)
	Global.save_player_data_to_file()
	return merged


# Overrides every mesh surface under `node` with a fresh StandardMaterial3D
# using `texture_path` as the albedo — bypasses whatever material data (good
# or broken) the FBX itself carries.
func _apply_texture_override(node: Node, texture_path: String) -> void:
	var tex := load(texture_path) as Texture2D
	if not tex:
		push_warning("⚠️ Texture override not found: %s" % texture_path)
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


const ATTACK_ANIMS := ["attack_horizontal", "attack_downward"]
var _current_attack_anim: String = ""

# Which animation clip is currently playing — kept as a plain var (rather than
# reading animation_player.current_animation directly) so it can be listed in
# player3d.tscn's MultiplayerSynchronizer replication config and mirrored to
# other peers' view of this character. See _play_replicated_animation().
var anim_state: String = "idle"

# Picks one of the two melee swings at random for this strike; _update_animation
# keeps playing it every frame while `attacking` is true (called right where
# `attacking` is set true, in attack_current_target() and perform_melee_attack()).
func _trigger_attack_animation() -> void:
	_current_attack_anim = ATTACK_ANIMS[randi() % ATTACK_ANIMS.size()]


# How long `attacking` should stay true so the swing clip can play out fully
# instead of getting cut back to idle/walk/run mid-animation — real melee
# clips run ~2.3-2.4s, well past the old hardcoded 0.3s wait. Falls back to
# 0.3s if the current model's library doesn't have this clip for some reason.
# Mirrors the pattern monster3d.gd/guard_npc.gd already use for their own
# attack timers (animation_player.get_animation(name).length).
# Seconds between melee swings: the equipped weapon's "delay" (tenths of a second, EverQuest style: 28 = 2.8 s), or
# bare-handed UNARMED_DELAY (an Aetherfist's trained fists: AETHERFIST_UNARMED_DELAY), made shorter by haste
# ("attack_speed_bonus": 0.10 = 10% faster — Wind stance, buffs). The swing animation still plays each time; it no
# longer sets the pace (it used to, which made everyone swing every 0.3-1 s).
const UNARMED_DELAY := 3.0
const AETHERFIST_UNARMED_DELAY := 2.0

func attack_interval() -> float:
	var weapon: Dictionary = Inventory.get_equipped_weapon()
	var delay := float(weapon.get("delay", 0)) / 10.0 if int(weapon.get("delay", 0)) > 0 else 0.0
	if delay <= 0.0:
		delay = AETHERFIST_UNARMED_DELAY if player_class == "Aetherfist" else UNARMED_DELAY
	return delay * clampf(1.0 - combat_node.get_modifier("attack_speed_bonus"), 0.4, 2.0)


func _attack_animation_duration() -> float:
	if animation_player and animation_player.has_animation(_current_attack_anim):
		return animation_player.get_animation(_current_attack_anim).length
	return 0.3


# "self"/"group" targets are always cast on a friendly unit (or yourself) —
# clearly beneficial. "enemy"/"pbaoe"/"chain"/"cone"/"line" are always aimed
# at hostiles — clearly detrimental. "corpse"/"none" are genuinely mixed in
# player_spells.json (e.g. "corpse" covers both a healing corpse-consume and
# an offensive corpse-detonate), so fall back to whether the spell actually
# deals damage.
func _is_beneficial_cast(spell: Dictionary) -> bool:
	var t: String = spell.get("target", "enemy")
	if t in ["self", "group"]:
		return true
	if t in ["enemy", "pbaoe", "chain", "cone", "line"]:
		return false
	return int(spell.get("damage", 0)) <= 0


# Only enters the `casting` animation state if the currently-loaded model's
# library actually has the clip — not every CHARACTER_MODELS entry has
# cast_beneficial/cast_detrimental yet (see CHARACTER_MODELS comments), and
# races still on DEFAULT_CHARACTER_MODEL never will until that model gets
# its own casting clips. Silently no-ops rather than playing nothing/erroring.
func _trigger_cast_animation(spell: Dictionary) -> void:
	var anim_name := pick_variant(animation_player, "cast_beneficial" if _is_beneficial_cast(spell) else "cast_detrimental")
	if anim_name.is_empty():
		return
	_current_cast_anim = anim_name
	_cast_anim_timer = animation_player.get_animation(anim_name).length


func _update_animation() -> void:
	if not animation_player or animation_player.get_animation_list().is_empty():
		return
	var anim_name: String
	if attacking and _current_attack_anim != "":
		anim_name = _current_attack_anim
	elif _cast_anim_timer > 0.0 and _current_cast_anim != "":
		anim_name = _current_cast_anim
	elif not is_on_floor():
		anim_name = "jump"
	elif is_sitting:
		anim_name = "sit"
	elif current_speed > WALK_SPEED + 0.5:
		anim_name = "run"
	elif current_speed > 0.1:
		anim_name = "walk"
	else:
		anim_name = "idle"
	anim_state = anim_name  # replicated to other peers via MultiplayerSynchronizer — see _play_replicated_animation()
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, 0.15)


# Remote peers' characters ("puppets" — every player3d node whose multiplayer
# authority isn't this machine's) skip movement/combat entirely and are only
# ever this: play whatever anim_state the MultiplayerSynchronizer just
# replicated from the owning peer, at the position/rotation it also
# replicated. No local physics, no combat_node, no HUD — see _ready().
func _play_replicated_animation() -> void:
	if not animation_player or animation_player.get_animation_list().is_empty():
		return
	if animation_player.current_animation != anim_state:
		animation_player.play(anim_state, 0.15)


func _spawn_hud() -> void:
	for old in get_tree().get_nodes_in_group("game_hud"):
		old.free()  # never two HUDs (a stale one from a dropped session would sit under the new one)
	_spawn_hud_frames()
	GameLog.log_general("Welcome, [b]%s[/b]." % player_name)


const MINI_TARGET_FRAME := preload("res://Scripts/mini_target_frame.gd")
const ENCOUNTER_FRAME := preload("res://Scripts/encounter_frame.gd")
const HUD_FRAME_SCENES := [
	"res://Scenes/player_frame.tscn",
	"res://Scenes/cast_bar.tscn",
	"res://Scenes/target_frame.tscn",
	"res://Scenes/group_frame.tscn",
	"res://Scenes/game_log_window.tscn",
	"res://Scenes/action_bar.tscn",
	"res://Scenes/stance_bar.tscn",
	"res://Scenes/buff_bar.tscn",
	"res://Scenes/compass.tscn",
]

func _spawn_hud_frames() -> void:
	var root = get_tree().root
	for scene_path in HUD_FRAME_SCENES:
		var node: Node = load(scene_path).instantiate()
		node.add_to_group("game_hud")
		root.add_child(node)
	var encounter: Node = ENCOUNTER_FRAME.new()   # who is fighting you right now (encounter_frame.gd)
	encounter.add_to_group("game_hud")
	root.add_child(encounter)
	for frame_kind in ["focus", "tot"]:   # the focus and target-of-target frames (mini_target_frame.gd)
		var mini: Node = MINI_TARGET_FRAME.new()
		mini.kind = frame_kind
		mini.add_to_group("game_hud")
		root.add_child(mini)


# /resetui — for when a panel gets dragged off-screen and there's no way to
# reach it again to drag it back. Clears every saved HUD position and
# respawns the whole HUD fresh via the same _spawn_hud_frames() login already
# uses, so anything off-screen (including the game_log_window this command
# was typed into — queue_free() doesn't actually free until the frame ends,
# so finishing this call first is safe) comes back at its normal default
# spot. pet_frame.tscn isn't in HUD_FRAME_SCENES (it only exists while a pet
# is active) so it's respawned separately here, same as _summon_pet() does.
# One visible side effect: the chat log's on-screen scrollback resets, since
# GameLog itself keeps no history buffer to replay — same as a normal
# relaunch would do.
func reset_ui() -> void:
	Global.player_data["ui_positions"] = {}
	Global.save_player_data_to_file()

	for node in get_tree().get_nodes_in_group("game_hud"):
		node.queue_free()
	active_pet_frame = null

	_spawn_hud_frames()

	if is_instance_valid(active_pet):
		var frame: Node = load("res://Scenes/pet_frame.tscn").instantiate()
		frame.add_to_group("game_hud")
		get_tree().root.add_child(frame)
		frame.set_pet(active_pet)
		active_pet_frame = frame

	GameLog.log_general("[color=#88ccff]UI windows reset to their default positions.[/color]")
#endregion

#region Spell cache
func _load_spell_cache() -> void:
	var file = FileAccess.open("res://Data/player_spells.json", FileAccess.READ)
	if not file:
		push_error("❌ Failed to open player_spells.json")
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_ARRAY:
		push_error("❌ player_spells.json is not an array")
		return
	for spell in data:
		_spell_cache[spell.get("spell_id", -1)] = spell
		_spell_by_name[spell.get("spell_name", "")] = spell
	print("✅ Loaded %d spell definitions" % _spell_cache.size())

	# Load skill descriptions — flatten {category: {name: desc}} into {name: desc}.
	# Restricted to these three category keys specifically (not "every
	# top-level key") — a bare `for category in sd` used to also walk
	# class_skills, whose values are {skill_name: starting_level} dicts, not
	# descriptions, silently stuffing entries like _skill_data["Blademaster"]
	# = {...} into what's supposed to be a flat skill-name-to-description map.
	var sf := FileAccess.open("res://Data/player_skills.json", FileAccess.READ)
	if sf:
		var sd = JSON.parse_string(sf.get_as_text())
		sf.close()
		if typeof(sd) == TYPE_DICTIONARY:
			for category in ["physical", "magic", "crafting"]:
				var cat = sd.get(category, {})
				if typeof(cat) == TYPE_DICTIONARY:
					for skill_name in cat:
						_skill_data[skill_name] = cat[skill_name]
						_valid_skill_names[skill_name] = true
			_skill_max = int(sd.get("skill_max", _skill_max))
#endregion

#region Physics process (movement / stamina / combat)
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_play_replicated_animation()
		# Invisibility is evaluated fresh every tick against the LOCAL viewer's
		# own see-invisible status (not networked — each client independently
		# decides whether it can perceive this puppet), same reasoning as
		# show_name_tags below already being a per-viewer setting, not synced.
		var hidden := TargetFrame.is_hidden_from_local_player(self)
		if has_node("Character"):
			$Character.visible = not hidden
		# player_name arrives a frame or two after spawn (replicated, not set
		# locally like the authoritative path's load_character_data() call) —
		# cheap to just keep the nameplate in sync every tick rather than
		# reacting to a change signal. Recomputed every tick (not just on
		# player_name change) since the invisible/GM/stealth flags it can fold
		# in can change independently of the name itself.
		if has_node("NameLabel"):
			$NameLabel.text = TargetFrame.nameplate_name(self)
			$NameLabel.modulate = TargetFrame.nameplate_color(self)
			var me := TargetFrame.local_player()
			var near := not is_instance_valid(me) or global_position.distance_squared_to(me.global_position) <= NAMEPLATE_DISTANCE * NAMEPLATE_DISTANCE
			$NameLabel.visible = Global.settings.get("show_name_tags", true) and not hidden and near
		# player_race/player_sex replicate in the same delayed way as
		# player_name — rebuild the model once they arrive (a no-op once the
		# key stops changing, see _build_character_model()).
		if _character_model_key() != _built_character_model_key:
			_build_character_model()
		return

	var chat_focused := get_viewport().gui_get_focus_owner() is LineEdit

	if not chat_focused and Input.is_action_just_pressed("toggle_backpack"):
		toggle_backpack()

	_check_under_terrain(delta)

	if dying:
		return

	if stumble_timer > 0.0:
		stumble_timer -= delta
		return

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		_fall_top_y = maxf(_fall_top_y, global_position.y) if is_in_air else global_position.y
		is_in_air = true
	else:
		if is_in_air and velocity.y < -10.0:
			stumble_timer = STUMBLE_DURATION
		if is_in_air:
			_on_landed(_fall_top_y - global_position.y)
		is_in_air = false

	if chat_focused:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED)
		current_speed = 0.0
	elif not is_sitting:
		handle_toggle_run()
		handle_toggle_autorun()
		handle_crouch()
		handle_jump()
		handle_movement(delta)

	if not chat_focused:
		handle_combat()
	update_stamina(delta)
	_tick_cooldowns(delta)
	_tick_active_spell_effects(delta)
	_tick_spell_cast(delta)

	move_and_slide()
	_update_animation()
	_update_body_sounds(delta)


# Landing after `height` metres of drop: past FALL_SAFE_HEIGHT it hurts (FALL_DAMAGE_PER_METRE of max health a metre)
# with the fall-impact sound. Not right after logging in or respawning, when the game itself drops you onto the ground.
func _on_landed(height: float) -> void:
	if height <= FALL_SAFE_HEIGHT or Time.get_ticks_msec() < _fall_grace_until_ms or dying:
		return
	var damage := int(ceil(combat_node.max_hp * FALL_DAMAGE_PER_METRE * (height - FALL_SAFE_HEIGHT)))
	Sfx.play("fall_impact")
	GameLog.log_combat("[color=#ff8866]You fall %d metres and take [b]%d[/b] damage.[/color]" % [int(round(height)), damage])
	_last_attacker_desc = "a long fall"
	take_damage(damage)


# Footsteps (walking or running) while you move on the ground, the swim sound while you're in the sea, and a heartbeat
# while your health is low. Checked a few times a second; each is a loop that starts and stops as things change.
func _update_body_sounds(delta: float) -> void:
	_body_sound_timer -= delta
	if _body_sound_timer > 0.0:
		return
	_body_sound_timer = 0.15
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var wet := _in_water()
	if wet and not _was_in_water:
		Sfx.play("water_splash")  # stepping (or falling) into the sea
	_was_in_water = wet
	var kind := ""
	if not dying and flat_speed > 0.6:
		if wet:
			kind = "swim"
		elif is_on_floor():
			kind = "footsteps_run" if flat_speed > WALK_SPEED + 0.5 else "footsteps_walk"
	if kind != _footsteps_kind:
		Sfx.stop(_footsteps_loop)
		_footsteps_loop = Sfx.start_loop(kind, self) if not kind.is_empty() else null
		_footsteps_kind = kind
	var low := not dying and combat_node.max_hp > 0 and combat_node.current_hp > 0 \
			and float(combat_node.current_hp) / float(combat_node.max_hp) < LOW_HEALTH_FRACTION
	if low and not is_instance_valid(_heartbeat_loop):
		_heartbeat_loop = Sfx.start_loop("heartbeat", self)
	elif not low and is_instance_valid(_heartbeat_loop):
		Sfx.stop(_heartbeat_loop)
		_heartbeat_loop = null


# In the sea: below the water's surface inside the area of the zone's water mesh (ambient_water_sound.gd finds it).
var _water_rects: Array = []
var _water_surface := INF
var _water_looked := false

func _in_water() -> bool:
	if not _water_looked:
		_water_looked = true
		var scene := get_tree().current_scene
		if scene != null:
			for node in scene.find_children("*", "MeshInstance3D", true, false):
				if String(node.name).to_lower().contains("water") and (node as MeshInstance3D).mesh != null:
					var box: AABB = node.global_transform * (node as MeshInstance3D).get_aabb()
					if box.size.x * box.size.z >= 400.0:  # the sea, not a prop's water
						_water_rects.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
						_water_surface = minf(_water_surface, box.position.y + box.size.y)
	if global_position.y > _water_surface - 0.5:
		return false
	for rect in _water_rects:
		if (rect as Rect2).has_point(Vector2(global_position.x, global_position.z)):
			return true
	return false
#endregion

#region Process (regen / vitals / cooldowns)
#region Light source (torch now; lanterns / magic lights later)
# The Light equipment slot holds ONE light item — any item with a "light_source"
# dict in items.json (radius/energy/color, burn_minutes, and the two "fire"
# traits snuffed_by_rain / breaks_stealth; a future magic light just sets those
# false). Using a torch from a bag equips one and lights it. While lit it has a
# "lit_torch" effect on the buff bar whose remaining time IS the burn timer,
# mirrored into the item's burn_remaining so snuffing/unequipping keeps what is
# left. light_item_id is replicated so every peer sees the carried light. The
# light is not "held" (it lives in a slot) — the visual is just a flickering
# point light on the player, no torch model or flame.
const LIGHT_SLOT := "light"
const LIGHT_EFFECT := "lit_torch"
const CARRIED_LIGHT_HEIGHT := 1.6  # metres above the player's feet
const RAIN_SNUFF_INTENSITY := 0.3  # rain this established snuffs fire lights
var light_item_id: String = ""  # REPLICATED: item id of the LIT light ("" = none lit)
var _light_light: OmniLight3D = null
var _light_base_energy: float = 2.0
var _light_shown_id: String = ""
var _light_flicker_t: float = 0.0


func get_light_item() -> Dictionary:
	var it: Variant = Inventory.equipped.get(LIGHT_SLOT, null)
	return it if it is Dictionary else {}


func _light_source_of(item: Dictionary) -> Dictionary:
	var src: Variant = item.get("light_source", {})
	return src if src is Dictionary else {}


func _race_trait(trait_name: String, default: Variant = 0.0) -> Variant:
	var race := player_race.to_lower().replace(" ", "_").replace("-", "_")
	return Global.character_options.get("races", {}).get(race, {}).get("traits", {}).get(trait_name, default)


func _weather_node() -> Node:
	return get_tree().get_first_node_in_group("weather_manager")


# Full burn time for a fresh light, including a race bonus (Human: torch_burn_bonus).
func light_burn_seconds_for(item: Dictionary) -> float:
	var minutes := float(_light_source_of(item).get("burn_minutes", 10.0))
	return minutes * 60.0 * (1.0 + float(_race_trait("torch_burn_bonus", 0.0)))


func is_carrying_lit_light() -> bool:
	return light_item_id != ""


# True while a lit light of a kind that gives away a sneaking player is carried.
func lit_light_breaks_stealth() -> bool:
	var it := get_light_item()
	return bool(it.get("lit", false)) and bool(_light_source_of(it).get("breaks_stealth", false))


# Use a torch (or any light) from a bag: equip ONE into the Light slot and light it.
func light_from_bag(item: Dictionary, slot_type: String, slot_index: int, bag_slot: int, item_index: int) -> void:
	if not get_light_item().is_empty():
		GameLog.log_general("You are already carrying a light. Unequip it first.")
		return
	var src := _light_source_of(item)
	var wm := _weather_node()
	if bool(src.get("snuffed_by_rain", false)) and wm != null and wm.raining:
		GameLog.log_general("It is raining — you can't get your %s to light." % str(item.get("name", "light")).to_lower())
		return
	if Inventory.equip_item(item, slot_type, slot_index, bag_slot, item_index):
		light_equipped_light()


# Light (or, if already lit, leave lit) whatever is in the Light slot.
func light_equipped_light() -> bool:
	var item := get_light_item()
	var src := _light_source_of(item)
	if item.is_empty() or src.is_empty():
		return false
	if item.get("lit", false):
		return true
	var wm := _weather_node()
	if bool(src.get("snuffed_by_rain", false)) and wm != null and wm.raining:
		GameLog.log_general("It is raining — you can't get your %s to light." % str(item.get("name", "light")).to_lower())
		return false
	if not item.has("burn_remaining"):
		item["burn_remaining"] = light_burn_seconds_for(item)
	item["lit"] = true
	combat_node.apply_effect(LIGHT_EFFECT, float(item["burn_remaining"]), {})
	light_item_id = str(item.get("item_id", ""))
	GameLog.log_general("[color=#ffcc66]%s[/color]" % str(src.get("light_message", "You light your %s." % str(item.get("name", "light")).to_lower())))
	if bool(src.get("breaks_stealth", false)) and current_stance == "stealth":
		_drop_stealth_for_light()
	Inventory.sync_to_global()
	Inventory.equipment_changed.emit()
	return true


# Put the equipped light out but keep it (and the burn time left).
func snuff_equipped_light(message: String = "") -> void:
	var item := get_light_item()
	if not item.is_empty():
		item.erase("lit")
	combat_node.remove_effect(LIGHT_EFFECT)
	light_item_id = ""
	if message != "":
		GameLog.log_general(message)
	Inventory.sync_to_global()
	Inventory.equipment_changed.emit()


func _burn_out_light() -> void:
	var item := get_light_item()
	combat_node.remove_effect(LIGHT_EFFECT)
	light_item_id = ""
	Inventory.equipped[LIGHT_SLOT] = null
	GameLog.log_general("[color=#ffcc66]Your %s burns out.[/color]" % str(item.get("name", "light")).to_lower())
	Inventory.sync_to_global()
	Inventory.equipment_changed.emit()
	Inventory.inventory_changed.emit()


func _drop_stealth_for_light() -> void:
	combat_node.remove_effect("stance_stealth")
	current_stance = ""
	GameLog.log_general("[color=#ffcc66]The light gives you away — you come out of hiding.[/color]")
	for hud in get_tree().get_nodes_in_group("game_hud"):
		if hud.has_method("_refresh_highlight"):
			hud._refresh_highlight()


# One line for the character sheet's Light slot.
func light_status_text() -> String:
	var item := get_light_item()
	if item.is_empty():
		return "No light equipped"
	var remaining := float(item.get("burn_remaining", light_burn_seconds_for(item)))
	var eff = combat_node.active_effects.get(LIGHT_EFFECT)
	if item.get("lit", false) and eff != null:
		remaining = float(eff.get("remaining", remaining))
	var mmss := "%d:%02d" % [int(remaining) / 60, int(remaining) % 60]
	return "%s — %s, %s left" % [str(item.get("name", "Light")), "lit" if item.get("lit", false) else "unlit", mmss]


# Authority only, every frame: the timer/rain/stealth rules for the Light slot.
func _update_light_logic() -> void:
	var item := get_light_item()
	# Shadowlight (the Voidknight's spell) is a carried light too, the same as a torch (same radius, brightness, flicker, and visible to
	# everyone through light_item_id) but violet. A lit torch takes over the slot while it burns.
	if item.is_empty() or not item.get("lit", false):
		var spell_light := SHADOWLIGHT_LIGHT_ID if combat_node.has_effect("shadowlight") else ""
		if light_item_id == "" or light_item_id == SHADOWLIGHT_LIGHT_ID:
			if light_item_id != spell_light:
				light_item_id = spell_light
			return
	if item.is_empty() or not item.get("lit", false):
		if light_item_id != "":
			light_item_id = ""
		if combat_node.has_effect(LIGHT_EFFECT):
			combat_node.remove_effect(LIGHT_EFFECT)  # e.g. it was unequipped while lit
		return
	var eff = combat_node.active_effects.get(LIGHT_EFFECT)
	if eff == null:
		# The effect ended: burned all the way down, or cancelled from the buff bar.
		if float(item.get("burn_remaining", 0.0)) <= 2.0:
			_burn_out_light()
		else:
			snuff_equipped_light("You put out your %s." % str(item.get("name", "light")).to_lower())
		return
	item["burn_remaining"] = float(eff.get("remaining", 0.0))
	if light_item_id == "":
		light_item_id = str(item.get("item_id", ""))  # e.g. right after logging in with it lit
	if bool(_light_source_of(item).get("snuffed_by_rain", false)):
		var wm := _weather_node()
		if wm != null and wm.intensity > RAIN_SNUFF_INTENSITY:
			snuff_equipped_light("[color=#9fc5e8]%s[/color]" % str(_light_source_of(item).get("rain_snuff_message", "The rain snuffs out your %s." % str(item.get("name", "light")).to_lower())))


# Every peer: show/hide the carried light to match light_item_id.
func _update_light_visual(delta: float) -> void:
	if light_item_id != _light_shown_id or (light_item_id != "" and not is_instance_valid(_light_light)):
		_clear_light_visual()
		_light_shown_id = light_item_id
		if light_item_id == SHADOWLIGHT_LIGHT_ID:
			_build_light_visual(SHADOWLIGHT_SOURCE)
		elif light_item_id != "":
			_build_light_visual(_light_source_of(Inventory.get_item_definition(light_item_id)))
	if is_instance_valid(_light_light):
		_light_flicker_t += delta
		_light_light.light_energy = _light_base_energy * (0.9 + 0.07 * sin(_light_flicker_t * 17.0) + 0.05 * sin(_light_flicker_t * 41.0))


const SHADOWLIGHT_LIGHT_ID := "spell:shadowlight"   # what light_item_id holds while the spell is up (there is no item)
const SHADOWLIGHT_SOURCE := {"radius": 9.0, "energy": 2.2, "color": [0.62, 0.35, 0.95]}   # a torch's light, in violet


func _clear_light_visual() -> void:
	if is_instance_valid(_light_light):
		_light_light.queue_free()
	_light_light = null


func _build_light_visual(src: Dictionary) -> void:
	var light := OmniLight3D.new()
	light.name = "CarriedLight"
	var c: Array = src.get("color", [1.0, 0.72, 0.35])
	light.light_color = Color(c[0], c[1], c[2])
	light.omni_range = float(src.get("radius", 9.0))
	_light_base_energy = float(src.get("energy", 2.2))
	light.light_energy = _light_base_energy
	light.shadow_enabled = false  # carried lights skip shadows (up to 6 players' worth)
	add_child(light)
	light.position = Vector3(0.0, CARRIED_LIGHT_HEIGHT, 0.0)
	_light_light = light
#endregion


func _process(delta: float) -> void:
	_update_light_visual(delta)  # everyone sees a lit torch (driven by the replicated light_item_id)
	_update_stance_aura()        # and a stance's aura (driven by the replicated current_stance)
	if not is_multiplayer_authority():
		return
	_update_decoys()
	_tick_stance_group(delta)
	_update_light_logic()
	if current_target != null and not is_instance_valid(current_target):
		current_target = null  # it died and was freed while targeted
	var key := TargetFrame.target_key_of(current_target)
	if key != target_key:
		target_key = key
	if combat_node.current_hp < DEATH_HP:
		combat_node.current_hp = DEATH_HP   # simultaneous hits (a raid) can overshoot: health never goes below the death line
	if is_incapacitated:
		_tick_bleedout(delta)
	elif not dying and combat_node.current_hp <= DEATH_HP:
		die()   # went straight past the downed state
	if dying:
		return

	_tick_weapon_poison(delta)

	regen_timer += delta
	if regen_timer >= REGEN_INTERVAL:
		regen_timer = 0.0
		_update_racial_day_night()

		# satiety <= 0 halts HP regen entirely (not just a reduction) — see
		# update_vitals_decay() below. Below 25 but still >0 is just a graduated
		# warning-zone penalty, same as before.
		if combat_node.current_hp < combat_node.max_hp and satiety > 0:
			var regen_h: int = combat_node.get_derived_stat("hp_regen") + regen_bonus + int(combat_node.get_modifier("hp_regen_bonus"))
			if is_sitting:
				regen_h = int(regen_h * 3.0)
			if satiety < 25:
				regen_h = int(regen_h * 0.8)
			if race_in_combat_regen_pct > 0.0 and combat_node.in_combat:
				regen_h += maxi(1, int(combat_node.max_hp * race_in_combat_regen_pct))
			regen_h = _racial_regen("hp", regen_h, race_hp_regen_mult)
			combat_node.current_hp = mini(combat_node.current_hp + regen_h, combat_node.max_hp)

		# thirst <= 0 halts mana regen entirely — mirrors the satiety/HP rule above.
		if combat_node.current_mana < combat_node.max_mana and thirst > 0:
			var regen_m: int = combat_node.get_derived_stat("mana_regen") + int(combat_node.get_modifier("mana_regen_bonus"))
			if is_sitting:
				regen_m = int(regen_m * 3.0)
			# Meditation: each point makes a mana tick MEDITATION_REGEN_PER_POINT bigger while sitting (a quarter of that on your feet).
			regen_m = int(round(regen_m * meditation_regen_multiplier()))
			if thirst < 25:
				regen_m = int(regen_m * 0.8)
			regen_m = _racial_regen("mana", regen_m, race_mana_regen_mult)
			combat_node.current_mana = mini(combat_node.current_mana + regen_m, combat_node.max_mana)

	# Sitting trains meditation on every tick (being attacked stands you up, so sitting always means out of combat), whether or not
	# your mana is full: it used to train only while mana was missing, so a quick sit at full mana never raised it.
	if is_sitting:
		_tick_skill("meditation")

	if attack_cooldown > 0.0:
		attack_cooldown -= delta
	if _cast_anim_timer > 0.0:
		_cast_anim_timer -= delta

	update_vitals_decay(delta)
#endregion

#region Vitals decay system
# Satiety/thirst decay slowly over real time (satiety: ~100 real minutes to
# fully drain from 100; thirst: ~50, roughly twice as fast — matches EQ's
# "water more often than food" convention) and gate regeneration rather than
# dealing chip damage: satiety<=0 halts HP (and movement stamina, see
# update_stamina()) regen entirely, thirst<=0 halts mana regen entirely (see
# the regen block in _process() above). Eating/drinking (consume_food_or_drink,
# triggered from the inventory's right-click "Eat"/"Drink" button) restores
# them; a "Well Fed" buff (_update_well_fed_buff) gives a small regen bonus
# and visible buff-bar feedback while both stay topped up.
# Edge-triggered warning state, one stage per vital: "" (fine) -> "low"
# (<25, warned once) -> "empty" (<=0, warned once). Reset back to "" once the
# vital climbs back above the low threshold, so a future drop warns again.
var _hunger_warn_stage: String = ""
var _thirst_warn_stage: String = ""

func update_vitals_decay(delta: float) -> void:
	satiety_timer += delta
	thirst_timer += delta

	if satiety_timer >= DECAY_INTERVAL:
		satiety_timer = 0.0
		satiety = max(satiety - int(SATIETY_DECAY_RATE), 0)
		if satiety < 25:
			_try_auto_consume("satiety")
		if satiety <= 0 and _hunger_warn_stage != "empty":
			_hunger_warn_stage = "empty"
			GameLog.log_general("[color=#ff8866]You are famished. Your health will no longer recover until you eat something.[/color]")
		elif satiety > 0 and satiety < 25 and _hunger_warn_stage == "":
			_hunger_warn_stage = "low"
			GameLog.log_general("[color=#ffaa66]Your stomach growls. You should find something to eat soon.[/color]")
		elif satiety >= 25:
			_hunger_warn_stage = ""

	if thirst_timer >= DECAY_INTERVAL:
		thirst_timer = 0.0
		thirst = max(thirst - int(THIRST_DECAY_RATE), 0)
		if thirst < 25:
			_try_auto_consume("thirst")
		if thirst <= 0 and _thirst_warn_stage != "empty":
			_thirst_warn_stage = "empty"
			GameLog.log_general("[color=#66aaff]You are parched. Your mana will no longer recover until you drink something.[/color]")
		elif thirst > 0 and thirst < 25 and _thirst_warn_stage == "":
			_thirst_warn_stage = "low"
			GameLog.log_general("[color=#88ccff]Your throat is dry. You should find something to drink soon.[/color]")
		elif thirst >= 25:
			_thirst_warn_stage = ""

	_update_well_fed_buff()


func get_stat_penalty() -> float:
	var penalty := 1.0
	if satiety < 25:
		penalty *= 0.95
	if thirst < 25:
		penalty *= 0.90
	return penalty


const WELL_FED_THRESHOLD := 75
const WELL_FED_MODIFIERS := {
	"hp_regen_bonus": 2,
	"mana_regen_bonus": 2,
	"stamina_regen_bonus": 2,
}

# Re-evaluated every vitals tick rather than run on a fixed timer — toggles on
# the moment satiety/thirst are both topped back up (usually right after
# eating/drinking) and falls off on its own once either drops back below the
# threshold, no separate expiry bookkeeping needed.
func _update_well_fed_buff() -> void:
	if satiety >= WELL_FED_THRESHOLD and thirst >= WELL_FED_THRESHOLD:
		if not combat_node.has_effect("well_fed"):
			combat_node.apply_effect("well_fed", INF, WELL_FED_MODIFIERS)
			GameLog.log_general("[color=#ffdd88]You feel well fed and hydrated.[/color]")
	elif combat_node.has_effect("well_fed"):
		combat_node.remove_effect("well_fed")


# Called from update_vitals_decay() the moment satiety/thirst dips below the
# "low" threshold — eats/drinks the first matching item found anywhere in the
# player's inventory (basic slots, then bags) so the player doesn't have to
# babysit food/water manually. Silently does nothing if no matching item is
# carried, and the normal low/empty warning messages take over from there.
func _try_auto_consume(restores: String) -> bool:
	var found: Dictionary = Inventory.find_first_by_restores(restores)
	if found.is_empty():
		return false
	consume_food_or_drink(found["item"])
	Inventory.consume_one(found["slot_type"], found["slot_index"], found["bag_slot"], found["item_index"])
	return true


# Called from slot_button.gd's inventory right-click "Eat"/"Drink" button.
func consume_food_or_drink(item: Dictionary) -> void:
	var restores: String = item.get("restores", "")
	var amount: int = item.get("restore_amount", 0)
	var item_name: String = item.get("name", "item")
	match restores:
		"satiety":
			Sfx.play("eat")
			satiety = mini(satiety + amount, 100)
			var line: String = _food_drink_flavor.get_line("eat") if _food_drink_flavor else ""
			GameLog.log_general(line % item_name if not line.is_empty() else "You eat %s." % item_name)
		"thirst":
			Sfx.play("drink")
			thirst = mini(thirst + amount, 100)
			var line: String = _food_drink_flavor.get_line("drink") if _food_drink_flavor else ""
			GameLog.log_general(line % item_name if not line.is_empty() else "You drink %s." % item_name)
		_:
			return
	_update_well_fed_buff()
	apply_consumable_effects(item)


# Drinks a crafted potion or elixir (items with type "potion" — Data/items.json). Returns true if it was used up.
func use_potion(item: Dictionary) -> bool:
	Sfx.play("potion")
	GameLog.log_general("You drink %s." % item.get("name", "the potion"))
	apply_consumable_effects(item)
	return true


# The extra effects crafted food, drink and potions carry on top of satiety/thirst (tools/export_crafting.py writes them):
# an instant heal ("heal_amount"), a timed buff ("use_buff": regen bonuses, stat_<name> bonuses, damage_mult, heal over
# time), and "cures_poison" (removes every damage-over-time effect with poison/venom in its name). A new buff from the same
# item replaces the old one rather than stacking.
func apply_consumable_effects(item: Dictionary) -> void:
	var heal: int = int(item.get("heal_amount", 0))
	if heal > 0:
		var healed: int = combat_node.heal(heal)
		if healed > 0:
			GameLog.log_general("[color=#88ffaa]You are healed for [b]%d[/b].[/color]" % healed)
	if bool(item.get("cures_poison", false)):
		var cured := 0
		for effect_name in combat_node.active_effects.keys():
			var lowered: String = str(effect_name).to_lower()
			if ("poison" in lowered or "venom" in lowered) and int(combat_node.active_effects[effect_name].get("tick_dmg", 0)) > 0:
				combat_node.remove_effect(effect_name)
				cured += 1
		GameLog.log_general("[color=#88ffaa]The poison burns away.[/color]" if cured > 0 else "You feel no different.")
	var buff: Variant = item.get("use_buff")
	if typeof(buff) == TYPE_DICTIONARY:
		combat_node.apply_effect(str(buff.get("effect_name", "consumable_buff")), float(buff.get("duration", 600.0)),
				buff.get("modifiers", {}), 0, float(buff.get("tick_interval", 6.0)), int(buff.get("tick_heal", 0)))
#endregion

#region Movement handlers
func handle_toggle_run() -> void:
	if Input.is_action_just_pressed("toggle_run"):
		is_running = not is_running
		GameLog.log_general("You begin to sprint." if is_running else "You return to walking speed.")


func handle_toggle_autorun() -> void:
	if Input.is_action_just_pressed("toggle_autorun"):
		autorun_enabled = not autorun_enabled
		GameLog.log_general("Autorun " + ("enabled." if autorun_enabled else "disabled."))


func handle_crouch() -> void:
	if Input.is_action_pressed("crouch"):
		if not is_crouching:
			is_crouching = true
	else:
		if is_crouching:
			is_crouching = false


func handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if current_stamina <= 0.0:
			return
		current_stamina -= STAMINA_DRAIN_JUMP
		current_stamina = max(current_stamina, 0.0)
		_tick_skill("athletics")
		velocity.y = JUMP_VELOCITY
		Sfx.play("jump")


func handle_movement(delta: float) -> void:
	if _fear_time > 0.0:
		_handle_fear_movement(delta)
		return
	if is_sitting:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED)
		current_speed = 0.0
		return

	if _follow_target != null:
		if not is_instance_valid(_follow_target):
			stop_following("You are no longer following your target.")
		elif Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_backward") \
				or Input.is_action_pressed("strafe_left") or Input.is_action_pressed("strafe_right") \
				or Input.is_action_pressed("turn_left") or Input.is_action_pressed("turn_right") \
				or Input.is_action_just_pressed("jump"):
			stop_following("You stop following %s." % _follow_display_name(_follow_target))
		else:
			_handle_follow_movement(delta)
			return

	if Input.is_action_pressed("turn_left"):
		rotation.y += TURN_SPEED * delta
	if Input.is_action_pressed("turn_right"):
		rotation.y -= TURN_SPEED * delta

	var strafe := 0.0
	if Input.is_action_pressed("strafe_left"):
		strafe -= 1.0
	if Input.is_action_pressed("strafe_right"):
		strafe += 1.0

	var forward := 0.0
	if Input.is_action_pressed("move_forward") or autorun_enabled:
		forward += 1.0
	if Input.is_action_pressed("move_backward"):
		forward -= 1.0
		autorun_enabled = false

	var target_speed: float
	if is_crouching:
		target_speed = CROUCH_SPEED
	elif is_running and current_stamina > 0.0:
		target_speed = RUN_SPEED
	else:
		target_speed = WALK_SPEED
	var hidden_bonus := 0.10 if combat_node.has_passive("improved_stealth") and (combat_node.is_stealthed() or combat_node.is_currently_invisible()) else 0.0
	target_speed *= maxf(0.2, 1.0 + combat_node.get_modifier("move_speed_bonus") + hidden_bonus - combat_node.get_modifier("speed_slow"))  # Swift Step, stances, snares, Improved Stealth

	if forward < 0.0:
		target_speed *= BACKWARD_SPEED_MULT
	if not is_on_floor():
		target_speed *= AIR_CONTROL_MULT
	if combat_node.race_movement_speed_mult != 0.0:
		target_speed *= (1.0 + combat_node.race_movement_speed_mult)

	var forward_dir: Vector3 = -transform.basis.z.normalized()
	var right_dir: Vector3 = transform.basis.x.normalized()
	var world_move: Vector3 = (right_dir * strafe + forward_dir * forward).normalized()

	velocity.x = world_move.x * target_speed
	velocity.z = world_move.z * target_speed
	current_speed = Vector2(velocity.x, velocity.z).length()


# ── Fear, EverQuest-style (test 42, the user: "have it randomly either lower your stats or make you run randomly
# depending on your save roll") ──
# A monster's fear (an ability whose effect is "terrified": Halvek's Grave Command, the mirage's Dread Mirage, the
# Mass Gravesite's Wail) first gets the usual full resist roll (monster3d.gd land_ability). If it lands, you roll a
# fear save: make it and you're only Shaken (the ability's own penalty plus -2 Strength, Dexterity and Wisdom); fail and
# you're Terrified: you lose control and run blindly, a new direction every FEAR_TURN_SECONDS, unable to fight or cast,
# for the effect's duration. Runs on the player's own machine; the movement replicates like any other.
const FEAR_TURN_SECONDS := 1.5
const SHAKEN_STAT_PENALTY := 2
var _fear_time := 0.0
var _fear_dir := Vector3.ZERO
var _fear_turn := 0.0


# The chance to keep your nerve: an even chance at the caster's level, +/-5% a level of difference, +2% a point of Wisdom
# over 10, +5% a point of racial fear save; always between 10% and 90%.
static func fear_save_chance(my_level: int, caster_level: int, wisdom: int, racial_bonus: int) -> float:
	return clampf(0.5 + 0.05 * float(my_level - caster_level) + 0.02 * float(wisdom - 10) + 0.05 * float(racial_bonus), 0.1, 0.9)


func is_feared() -> bool:
	return _fear_time > 0.0


# Returns true when you break and run, false when you keep your nerve (Shaken). `roll` is for the tests (-1 = random).
func receive_fear(duration: float, caster_level: int, caster_desc: String, mods: Dictionary, roll: float = -1.0) -> bool:
	var chance := fear_save_chance(int(combat_node.level), caster_level, int(combat_node.wisdom), race_fear_save_bonus)
	var r := randf() if roll < 0.0 else roll
	if r < chance or combat_node.is_cc_immune("fear"):
		var shaken := mods.duplicate()
		for stat in ["stat_strength", "stat_dexterity", "stat_wisdom"]:
			shaken[stat] = float(shaken.get(stat, 0.0)) - SHAKEN_STAT_PENALTY
		combat_node.apply_effect("shaken", duration, shaken)
		GameLog.log_combat("[color=#ffcc66]You steel yourself against %s's terror, but your hands shake.[/color]" % caster_desc)
		return false
	combat_node.apply_effect("terrified", duration, mods.duplicate())
	_fear_time = maxf(_fear_time, duration)
	_fear_turn = 0.0
	autorun_enabled = false
	is_sitting = false
	stop_following()
	if combat_node.is_casting:
		_stop_all_casting_except_songs()
		GameLog.log_combat("[color=#ff8866]Your spell is interrupted.[/color]")
	GameLog.log_combat("[color=#ff5555]You flee in terror from %s![/color]" % caster_desc)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer():
		Net.broadcast_combat_message("[color=#ffcc66]%s flees in terror![/color]" % player_name, global_position)
	return true


func _handle_fear_movement(delta: float) -> void:
	_fear_time -= delta
	if _fear_time <= 0.0 or _player_down_for_fear() or not combat_node.active_effects.has("terrified"):   # a cure ends it
		_fear_time = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		current_speed = 0.0
		if combat_node.is_alive():
			GameLog.log_combat("[color=#aaddff]You regain control of yourself.[/color]")
		return
	_fear_turn -= delta
	if _fear_turn <= 0.0 or is_on_wall():
		_fear_turn = FEAR_TURN_SECONDS
		var a := randf() * TAU
		_fear_dir = Vector3(cos(a), 0.0, sin(a))
	look_at(global_position + _fear_dir, Vector3.UP)
	var speed := RUN_SPEED * maxf(0.2, 1.0 - combat_node.get_modifier("speed_slow"))
	velocity.x = _fear_dir.x * speed
	velocity.z = _fear_dir.z * speed
	current_speed = speed


func _player_down_for_fear() -> bool:
	return dying or not combat_node.is_alive()


# ── /follow ──────────────────────────────────────────────────────────────────
# Steers the player toward _follow_target using the same self-managed
# NavigationServer3D.query_path() approach guard_npc.gd uses for patrols —
# NavigationAgent3D's get_next_path_position() was found to go stale over
# long distances/after external repositioning during that work, and following
# an NPC across the whole zone (e.g. Sergeant Bryn's patrol) hits exactly that
# case. Canceled by any manual movement input (see handle_movement()), by the
# target going invalid, or by issuing /follow again.
func _follow_display_name(target: Node) -> String:
	if "player_name" in target:
		var pname: String = str(target.get("player_name"))
		if not pname.is_empty():
			return pname
	return TargetFrame.display_name(target)


func start_following(target: Node3D) -> void:
	_follow_target = target
	_follow_path.clear()
	_follow_repath_timer = 0.0
	GameLog.log_general("You begin following [b]%s[/b]." % _follow_display_name(target))


func stop_following(reason: String = "") -> void:
	if _follow_target == null:
		return
	_follow_target = null
	_follow_path.clear()
	if not reason.is_empty():
		GameLog.log_general(reason)


func _handle_follow_movement(delta: float) -> void:
	var target_pos: Vector3 = _follow_target.global_position
	if global_position.distance_to(target_pos) <= FOLLOW_STOP_DISTANCE:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED)
		current_speed = 0.0
		_follow_path.clear()
		return

	_follow_repath_timer -= delta
	if _follow_repath_timer <= 0.0 or _follow_path.is_empty():
		_follow_repath_timer = FOLLOW_REPATH_INTERVAL
		_recompute_follow_path(target_pos)

	while _follow_path.size() > 1 and global_position.distance_to(_follow_path[0]) < FOLLOW_WAYPOINT_EPSILON:
		_follow_path.remove_at(0)

	var next_point: Vector3 = _follow_path[0] if not _follow_path.is_empty() else target_pos
	var look_point := Vector3(next_point.x, global_position.y, next_point.z)
	if look_point.distance_to(global_position) > 0.01:
		look_at(look_point, Vector3.UP)

	var target_speed: float = RUN_SPEED if is_running and current_stamina > 0.0 else WALK_SPEED
	var forward_dir: Vector3 = -transform.basis.z.normalized()
	velocity.x = forward_dir.x * target_speed
	velocity.z = forward_dir.z * target_speed
	current_speed = Vector2(velocity.x, velocity.z).length()


func _recompute_follow_path(target_pos: Vector3) -> void:
	_follow_path.clear()
	if not is_inside_tree():
		return
	var query := NavigationPathQueryParameters3D.new()
	query.map = get_world_3d().navigation_map
	query.start_position = global_position
	query.target_position = target_pos
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	for p in result.path:
		_follow_path.append(p)
	if _follow_path.size() > 1:
		_follow_path.remove_at(0)  # path[0] is just our own current position


# Called from game_log_window.gd's /follow command. query is the name text
# typed after the command; empty means "follow my current target". Searches
# guards, vendors, monsters, and (for future multiplayer) other players by
# name, nearest match wins.
func try_follow(query: String) -> void:
	var target: Node3D = null

	if query.is_empty():
		if current_target != null and is_instance_valid(current_target):
			target = current_target
		else:
			GameLog.log_general("[color=red]You need to target or name someone to follow. Try /follow <name>.[/color]")
			return
	else:
		target = _find_followable_by_name(query)
		if target == null:
			GameLog.log_general("[color=red]No one named '%s' is nearby.[/color]" % query)
			return

	if target == self:
		GameLog.log_general("[color=red]You can't follow yourself.[/color]")
		return

	if _follow_target == target:
		stop_following("You stop following %s." % _follow_display_name(target))
		return

	start_following(target)


func _find_followable_by_name(query: String) -> Node3D:
	var query_lower := query.to_lower()
	var best: Node3D = null
	var best_dist := INF
	var candidates: Array = []
	candidates.append_array(get_tree().get_nodes_in_group("npc_guard"))
	candidates.append_array(get_tree().get_nodes_in_group("npc_vendor"))
	candidates.append_array(get_tree().get_nodes_in_group("monsters"))
	candidates.append_array(get_tree().get_nodes_in_group("player"))

	for node in candidates:
		if node == self or not is_instance_valid(node) or not (node is Node3D):
			continue
		var name_lower := _follow_display_name(node).to_lower()
		if query_lower in name_lower:
			var dist := global_position.distance_to(node.global_position)
			if dist < best_dist:
				best_dist = dist
				best = node

	return best


func update_stamina(delta: float) -> void:
	var is_moving := current_speed > 0.1

	if Input.is_action_just_pressed("sit"):
		is_sitting = not is_sitting
		if is_sitting:
			is_running = false
			is_crouching = false
			GameLog.log_general("You sit down to rest.")
		else:
			GameLog.log_general("You stand up.")

	if is_moving and is_running and is_on_floor():
		current_stamina -= STAMINA_DRAIN_RUN * delta * maxf(0.5, 1.0 - combat_node.skill_bonus("stamina_drain_pct") / 100.0)
		_athletics_run_time += delta
		if _athletics_run_time >= 10.0:  # every 10 s of sprinting is a workout
			_athletics_run_time = 0.0
			_tick_skill("athletics")
	elif is_on_floor() and satiety > 0:  # satiety<=0 halts stamina regen too, see update_vitals_decay()
		var regen_rate: float
		if is_sitting:
			regen_rate = STAMINA_REGEN_SIT
		elif is_moving:
			regen_rate = STAMINA_REGEN_WALK
		else:
			regen_rate = STAMINA_REGEN_STAND
		current_stamina += (regen_rate + combat_node.get_modifier("stamina_regen_bonus") + combat_node.skill_bonus("stamina_regen")) * delta

	current_stamina = clamp(current_stamina, 0.0, max_stamina)
	if current_stamina <= 0.0:
		is_running = false
#endregion

#region Combat system
func handle_combat() -> void:
	if Input.is_action_just_pressed("tab_target"):
		tab_cycle_target()
	if Input.is_action_just_pressed("clear_target"):
		clear_target()
	if Input.is_action_just_pressed("attack_target"):
		autoattack_enabled = !autoattack_enabled
		GameLog.set_autoattack(autoattack_enabled)
		if autoattack_enabled:
			if current_target == null or not is_instance_valid(current_target):
				tab_cycle_target()
			print("⚔️ Autoattack ON")
		else:
			print("⚔️ Autoattack OFF")
	# Ally targets (your own pet, a group member) never resolve attack_cooldown
	# forward once attack_current_target()'s own ally-check bails out early —
	# meaning attack_cooldown <= 0.0 stays true forever, and without this
	# guard autoattack would call attack_current_target() again next frame,
	# spamming "You can't attack an ally." every single frame for as long as
	# an ally stayed targeted (e.g. targeting your own pet to heal it mid-fight
	# while autoattack was still on from the last target).
	if autoattack_enabled and current_target and attack_cooldown <= 0.0 \
			and TargetFrame.faction_status(current_target) != "Ally":
		attack_current_target()
	if Input.is_action_just_pressed("melee_attack") and attack_cooldown <= 0.0:
		perform_melee_attack()
	if Input.is_action_just_pressed("toggle_character_sheet"):
		toggle_character_sheet()
	if Input.is_action_just_pressed("toggle_abilities_book"):
		toggle_abilities_book()
	if Input.is_action_just_pressed("toggle_pet_gear"):
		toggle_pet_gear_window()
	if Input.is_action_just_pressed("toggle_tracking"):
		toggle_tracking_window()
	if Input.is_action_just_pressed("toggle_quest_journal"):
		toggle_quest_journal()
	if Input.is_action_just_pressed("toggle_recipe_book"):
		toggle_recipe_book()
	if Input.is_action_just_pressed("loot_all"):
		loot_all_nearby()
	if is_instance_valid(_deathly_visage_light):
		_deathly_visage_light.visible = combat_node.has_effect("deathly_visage")
	if is_instance_valid(_shadowlight_light):
		_shadowlight_light.visible = combat_node.has_effect("shadowlight")
	if has_node("NameLabel"):
		$NameLabel.visible = Global.settings.get("show_name_tags", true)



# ── Focus target and target-of-target ──
func get_focus() -> Node:
	if focus_target != null and not is_instance_valid(focus_target):
		focus_target = null
	return focus_target


func set_focus(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if TargetFrame.faction_status(node) == "Enemy":
		GameLog.log_general("An enemy can't be your focus: target a friend.")
		return
	focus_target = node
	var who: String = "yourself" if node == self else TargetFrame.display_name(node)
	GameLog.log_general("[color=#88ddaa]Focus: [b]%s[/b]. Your beneficial spells go to them while you target something else.[/color]" % who)


func clear_focus() -> void:
	if focus_target != null:
		focus_target = null
		GameLog.log_general("You clear your focus.")


# /focus  = your current target becomes the focus; /focus clear; /focus <group member's name>; /focus self.
func cmd_focus(arg: String) -> void:
	var text := arg.strip_edges()
	match text.to_lower():
		"":
			if current_target != null and is_instance_valid(current_target):
				set_focus(current_target)
			elif get_focus() != null:
				GameLog.log_general("Your focus is %s. (/focus clear to drop it)" % TargetFrame.display_name(get_focus()))
			else:
				GameLog.log_general("Target a friend and type /focus (Shift-click a group member works too).")
		"clear", "off", "none":
			clear_focus()
		"self", "me":
			set_focus(self)
		_:
			for node in get_tree().get_nodes_in_group("player"):
				if is_instance_valid(node) and node != self and str(node.get("player_name")).to_lower().begins_with(text.to_lower()):
					set_focus(node)
					return
			GameLog.log_general("There is nobody called '%s' nearby." % text)


# /assist: target whatever your current target is targeting (target the tank, /assist: the enemy the tank is fighting).
func assist_target() -> void:
	var t := TargetFrame.target_of(current_target)
	if t == null or not _is_targetable_alive(t):
		GameLog.log_general("Your target has no target to assist with.")
		return
	current_target = t
	_announce_target(t)


func clear_target() -> void:
	if current_target == null:
		return
	current_target = null
	_set_target_frame(null)
	autoattack_enabled = false
	GameLog.set_autoattack(false)
	GameLog.log_general("You clear your target.")


func _is_targetable_alive(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if "current_state" in node:
		return node.get("current_state") != node.State.DEAD
	return true  # e.g. guards, which have no death state


# F1-F6 group targeting. n is 1-based (F1 = group_members[0], ... F6 =
# group_members[5]) — a no-op if that slot doesn't have a real member yet
# (always true past slot 1 until a party system exists). Pressing the same
# F-key again while already targeting that exact member switches to their
# pet instead; pressing it again after that switches back to the member —
# a clean toggle with no extra state needed beyond checking current_target.
func _handle_group_target_key(n: int) -> void:
	if n < 1 or n > group_members.size():
		return
	var member := _peer_id_to_player_node(group_members[n - 1])
	if member == null:
		return

	if current_target == member:
		var pet: Node = member.get("active_pet") if "active_pet" in member else null
		if is_instance_valid(pet):
			current_target = pet
			_announce_target(pet)
		else:
			var who: String = member.player_name if "player_name" in member else "That group member"
			GameLog.log_general("%s has no pet out." % who)
		return

	current_target = member
	_announce_target(member)


const MAX_GROUP_SIZE := 6

# Resolves a group_members entry (a multiplayer peer id) to whatever local
# Node currently represents that peer — the pre-placed host node, a
# RemotePlayers-spawned puppet, or this node itself. Returns null if that
# peer isn't currently in the scene (disconnected, different zone, etc.).
func _peer_id_to_player_node(peer_id: int) -> Node:
	if not is_inside_tree():  # mid scene change — the HUD can outlive this node by a frame
		return null
	for node in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(node) and node.get_multiplayer_authority() == peer_id:
			return node
	return null


func _display_name_for_peer(peer_id: int) -> String:
	var node := _peer_id_to_player_node(peer_id)
	return TargetFrame.display_name(node) if node else "A player"


# /invite (or the Group frame's Invite button) — targets a real other player
# only (not NPCs/pets). Sends a real invite over the network; the target sees
# an Accept/Decline popup (group_invite_popup.gd) rather than being added
# instantly. See _on_group_invite_response() for what happens once they answer.
func invite_to_group(target: Node) -> void:
	if not is_instance_valid(target) or not target.is_in_group("player"):
		GameLog.log_general("You can only invite another player to your group.")
		return
	if target == self:
		GameLog.log_general("You can't invite yourself.")
		return
	var target_id: int = target.get_multiplayer_authority()
	if target_id in group_members:
		GameLog.log_general("%s is already in your group." % TargetFrame.display_name(target))
		return
	if group_members.size() >= MAX_GROUP_SIZE:
		GameLog.log_general("Your group is full (%d/%d)." % [MAX_GROUP_SIZE, MAX_GROUP_SIZE])
		return
	Net.send_group_invite(target_id, player_name)
	GameLog.log_general("[color=#88ccff]You invite %s to your group.[/color]" % TargetFrame.display_name(target))


# Fires on the INVITER's machine once the invited player answers the popup.
# On accept, adds them locally and pushes the new full roster out to every
# member (the new one included) so everyone's local group_members agrees —
# see Net.broadcast_group_roster().
func _on_group_invite_response(responder_id: int, accepted: bool) -> void:
	if not accepted:
		GameLog.log_general("[color=#ffaa66]%s declined your invite.[/color]" % _display_name_for_peer(responder_id))
		return
	if responder_id in group_members:
		return
	if group_members.size() >= MAX_GROUP_SIZE:
		return
	group_members.append(responder_id)
	GameLog.log_general("[color=#88ccff]%s has joined your group.[/color]" % _display_name_for_peer(responder_id))
	Net.broadcast_group_roster(group_members)
	_report_group()


# Fires on every OTHER member's machine (new joiner included) whenever the
# roster changes — replaces their local copy wholesale rather than trying to
# diff it, which is plenty for a group capped at 6.
func _on_group_roster_received(peer_ids: Array) -> void:
	group_members = peer_ids.duplicate()


# Fires when this player specifically has been kicked or the whole group
# they were in got disbanded — resets them back to solo.
func _on_group_removed(reason: String) -> void:
	group_members = [get_multiplayer_authority()]
	GameLog.log_general("[color=#ffaa66]%s[/color]" % reason)


# /disband (or the Group frame's Disband button) — a targeted group member
# (not yourself) is kicked; no target, or targeting yourself, disbands the
# whole group back down to just you. Either way, everyone affected is told
# over the network so their own group_members stays in sync.
func disband_or_kick_from_group(target: Node = null) -> void:
	if is_instance_valid(target) and target != self:
		var target_id: int = target.get_multiplayer_authority()
		if target_id in group_members:
			group_members.erase(target_id)
			GameLog.log_general("[color=#ffaa66]%s has been removed from the group.[/color]" % TargetFrame.display_name(target))
			Net.send_group_removed(target_id, "You have been removed from the group.")
			Net.broadcast_group_roster(group_members)
			_report_group([str(target.get("player_name"))])
			return

	if group_members.size() <= 1:
		GameLog.log_general("You aren't in a group.")
		return
	var old_members := group_members.duplicate()
	group_members = [get_multiplayer_authority()]
	group_remote = []
	GameLog.log_general("[color=#ffaa66]The group has been disbanded.[/color]")
	var link := get_tree().get_first_node_in_group("world_link")
	if Net.remote_character_mode and link != null:
		link.request_group_set([player_name])
	for pid in old_members:
		if pid != get_multiplayer_authority():
			Net.send_group_removed(pid, "The group has been disbanded.")


# Tells the server the group as this machine now has it: the members here plus those in other zones (world_link.gd
# keeps groups by name across every zone). `dropping` = names just removed.
func _report_group(dropping: Array = []) -> void:
	var link := get_tree().get_first_node_in_group("world_link")
	if not (Net.remote_character_mode and link != null):
		return
	var names: Array = []
	for pid in group_members:
		var node := _peer_id_to_player_node(pid)
		if is_instance_valid(node):
			names.append(str(node.get("player_name")))
	for r in group_remote:
		if not names.has(str(r["name"])):
			names.append(str(r["name"]))
	names = names.filter(func(n): return not dropping.has(n))
	link.request_group_set(names)


# The server's word on the group (world_link.gd): everyone's names, the ones in this zone by connection, the rest by
# zone. Keeps a group together across zone lines (test 38).
func apply_group_state(members: Array, local_peers: Array, remote: Array) -> void:
	group_names = members.duplicate()
	var me := get_multiplayer_authority()
	var peers := local_peers.map(func(p): return int(p))
	if not peers.has(me):
		peers.insert(0, me)
	group_members = peers if members.size() > 1 else [me]
	group_remote = remote.duplicate() if members.size() > 1 else []


# Looks up a player by character name instead of by targeting/proximity —
# for /invite <name> and /disband <name>. Only finds players whose node is
# actually in the scene tree (this "player" group), which today means only
# yourself; once networking exists, remote players will register into this
# same group as they come online, so this lookup needs no changes then.
func _find_player_by_name(query: String) -> Node:
	var query_lower := query.strip_edges().to_lower()
	if query_lower.is_empty():
		return null
	for node in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(node):
			continue
		var pname: String = str(node.get("player_name")) if "player_name" in node else ""
		if pname.to_lower() == query_lower:
			return node
	return null


# /invite <name> — resolves a character name (not requiring a target) and
# hands off to the normal invite_to_group() checks.
func invite_to_group_by_name(player_name_query: String) -> void:
	var target := _find_player_by_name(player_name_query)
	if target == null:
		# not in this zone: the server finds them in any zone and sends the invite there (world_link.gd, test 39)
		var link := get_tree().get_first_node_in_group("world_link")
		if Net.remote_character_mode and link != null:
			link.request_invite(player_name_query)
			return
		GameLog.log_general("No player named '%s' is currently online." % player_name_query)
		return
	invite_to_group(target)


# /disband <name> — resolves a character name (not requiring a target) and
# hands off to the normal disband_or_kick_from_group() checks.
func disband_from_group_by_name(player_name_query: String) -> void:
	var target := _find_player_by_name(player_name_query)
	if target == null:
		GameLog.log_general("No player named '%s' is currently online." % player_name_query)
		return
	disband_or_kick_from_group(target)


# /tell <name> <message> — a private, cross-peer whisper. Only makes sense in
# an actual multiplayer session (single-player has no one else to hear it).
func send_tell(target_name: String, message: String) -> void:
	if not Net.is_multiplayer_game:
		GameLog.log_general("[color=red]You're not in a multiplayer session.[/color]")
		return
	var target := _find_player_by_name(target_name)
	if target == null:
		# not in this zone: the server finds them in any zone (world_link.gd); it says whether it arrived
		var link := get_tree().get_first_node_in_group("world_link")
		if Net.remote_character_mode and link != null:
			var clean := ChatChannels.clean(message)
			var l := Languages.speaking()
			link.request_tell(target_name, Languages.encode(l, Languages.pronounce(l, clean)), clean, l)
			return
		GameLog.log_general("[color=red]No player named '%s' is currently online.[/color]" % target_name)
		return
	if target == self:
		GameLog.log_general("[color=red]You can't tell yourself something... or can you?[/color]")
		return
	message = ChatChannels.clean(message)
	var lang := Languages.speaking()
	Net.send_tell(target.get_multiplayer_authority(), player_name, Languages.encode(lang, Languages.pronounce(lang, message)))
	GameLog.log_general(ChatChannels.tell_self(TargetFrame.display_name(target), message, lang))
	_practice_speaking(lang, [target])


# /party <message> — broadcasts to every OTHER real player currently in
# group_members. Once real cross-zone grouping exists this still works
# unchanged, since it addresses peers by id, not by scene proximity.
func send_party_message(message: String) -> void:
	if not Net.is_multiplayer_game:
		GameLog.log_general("[color=red]You're not in a multiplayer session.[/color]")
		return
	var my_id := get_multiplayer_authority()
	var peer_ids: Array = group_members.filter(func(pid): return pid != my_id)
	if peer_ids.is_empty() and group_remote.is_empty():
		GameLog.log_general("[color=red]You aren't in a group.[/color]")
		return
	message = ChatChannels.clean(message)
	var lang := Languages.speaking()
	var link := get_tree().get_first_node_in_group("world_link")
	if Net.remote_character_mode and link != null:
		# through the server: every member hears it, in any zone (world_link.gd)
		link.request_party(Languages.encode(lang, Languages.pronounce(lang, message)))
		GameLog.log_general(ChatChannels.party_self(message, lang))
		_practice_speaking(lang, peer_ids.map(func(pid): return TargetFrame.peer_id_to_player_node(pid)))
		return
	Net.send_party_message(peer_ids, player_name, Languages.encode(lang, Languages.pronounce(lang, message)))
	GameLog.log_general(ChatChannels.party_self(message, lang))
	_practice_speaking(lang, peer_ids.map(func(pid): return TargetFrame.peer_id_to_player_node(pid)))


# /say — heard by players within ChatChannels.SAY_RANGE. The distance is judged here from the
# replicated positions, so a far-away player is never even sent the line. In single-player
# there is nobody else, so it is just echoed to yourself.
func send_say(message: String) -> void:
	message = ChatChannels.clean(message)
	if message.is_empty():
		return
	var lang := Languages.speaking()
	GameLog.log_general(ChatChannels.say_self(message, lang))
	_npcs_hear(message, lang)
	var listeners: Array = []
	for npc in get_tree().get_nodes_in_group("npc_talker") + get_tree().get_nodes_in_group("npc_guard") + get_tree().get_nodes_in_group("npc_vendor"):
		if is_instance_valid(npc) and npc is Node3D and npc.global_position.distance_to(global_position) <= ChatChannels.SAY_RANGE:
			listeners.append(npc)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer():
		var spoken := Languages.encode(lang, Languages.pronounce(lang, message))
		for pid in multiplayer.get_peers():
			var other := TargetFrame.peer_id_to_player_node(pid)
			if is_instance_valid(other) and other.global_position.distance_to(global_position) <= ChatChannels.SAY_RANGE:
				Net.send_say(pid, player_name, spoken)
				listeners.append(other)
	_practice_speaking(lang, listeners)


# Speaking a language you're learning counts as practice only when someone who knows it hears you: a player whose race
# grows up speaking it, or an NPC who speaks it — so there's always a way to practise, even with nobody online.
func _practice_speaking(lang: String, listeners: Array) -> void:
	if Languages.skill(lang) >= 100.0:
		return
	var race_start: Dictionary = Languages.data().get("race_start", {})
	for who in listeners:
		if not is_instance_valid(who) or who == self:
			continue
		var knows := false
		if who.is_in_group("player"):
			knows = float(race_start.get(str(who.get("player_race")).to_lower().replace(" ", "_").replace("-", "_"), {}).get(lang, 0.0)) >= 50.0
		else:
			knows = str(who.get("language") if who.get("language") != null else "common") == lang
		if knows:
			Languages.practice(lang)
			return


# Whatever you say near a talkative NPC (npc_talker group) is heard by it — EverQuest-style keyword conversation, see
# npc_conversation.gd. Answers go only to you, from your own machine's copy of the NPC.
func _npcs_hear(message: String, lang: String = "common") -> void:
	# Only ONE answers: the one you have targeted if it can, otherwise the nearest that has an answer (three guards standing
	# together must not all reply to the same word). An NPC only understands its own languages (Languages.npc_speaks); it
	# answers in the one you used.
	var best: Node = null
	var best_dist := INF
	var puzzled: Node = null
	for npc in get_tree().get_nodes_in_group("npc_talker"):
		if not is_instance_valid(npc) or not npc.has_method("can_answer") or not npc.can_answer(self, message):
			continue
		if not Languages.npc_speaks(npc, lang):
			if npc == current_target or puzzled == null:
				puzzled = npc
			continue
		if npc == current_target:
			best = npc
			break
		var dist: float = global_position.distance_to(npc.global_position)
		if dist < best_dist:
			best_dist = dist
			best = npc
	if best != null:
		best.set_meta("answer_language", lang)
		best.hear_say(self, message)
	elif puzzled != null:
		GameLog.log_general("[color=#cccc88]%s doesn't understand you. (You're speaking %s.)[/color]" % [TargetFrame.display_name(puzzled), Languages.display(lang)])


# /zone — a shout everyone in the zone hears. Echoed to yourself in single-player.
func send_zone(message: String) -> void:
	message = ChatChannels.clean(message)
	if message.is_empty():
		return
	var lang := Languages.speaking()
	GameLog.log_general(ChatChannels.zone_self(message, lang))
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer():
		Net.broadcast_zone_message(player_name, Languages.encode(lang, Languages.pronounce(lang, message)))


func tab_cycle_target() -> void:
	var candidates := get_tree().get_nodes_in_group("monsters") + get_tree().get_nodes_in_group("npc_guard") + get_tree().get_nodes_in_group("npc_vendor") + get_tree().get_nodes_in_group("pets")
	var valid: Array = []
	for m in candidates:
		if _is_targetable_alive(m):
			valid.append(m)

	if valid.is_empty():
		current_target = null
		_set_target_frame(null)
		GameLog.log_general("No targets available.")
		return

	valid.sort_custom(func(a, b):
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	)

	if current_target == null or not is_instance_valid(current_target) or not valid.has(current_target):
		_target_idx = 0
	else:
		_target_idx = (valid.find(current_target) + 1) % valid.size()

	current_target = valid[_target_idx]
	_announce_target(current_target)


func _try_click_target(screen_pos: Vector2) -> void:
	var picked: Node = _pick_target_at(screen_pos)
	if picked == null:
		return
	if Input.is_key_pressed(KEY_SHIFT) and TargetFrame.faction_status(picked) != "Enemy":
		set_focus(picked)   # Shift-click a friend: focus, without changing your target
		return
	if _is_targetable_alive(picked):
		current_target = picked
		_announce_target(current_target)


const TARGET_CLICK_RADIUS_PX := 45.0
const TARGET_CLICK_MAX_RANGE := 40.0

# What the player most plausibly meant by a click. The old version took the FIRST thing under the cursor, so in a fight
# a corpse (they linger ~60 s and can't be targeted), your own pet or a wall in front of the enemy swallowed the click and
# nothing happened. Now the ray passes THROUGH everything in its way and the pick is, in order:
#   1. the nearest LIVE monster on the ray (corpses, walls and your own pet in front no longer matter),
#   2. else the nearest other targetable thing on the ray (guard, vendor, pet, another player),
#   3. else the live monster/NPC whose body centre is nearest the cursor, within TARGET_CLICK_RADIUS_PX (a near miss).
func _pick_target_at(screen_pos: Vector2) -> Node:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return null
	var space := get_world_3d().direct_space_state
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var skip: Array[RID] = [get_rid()]
	var first_other: Node = null
	for _step in 10:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 150.0)
		query.exclude = skip
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Node = hit["collider"]
		skip.append(hit["rid"])
		# A collider still physically exists when its model/nameplate are hidden (an invisible entity) — hidden ones are not targets.
		if collider is Monster:
			if _is_targetable_alive(collider) and not TargetFrame.is_hidden_from_local_player(collider):
				return collider
		elif first_other == null and (collider is GuardNPC or collider is VendorNPC or collider is PetMinion or collider is Player3D):
			if not TargetFrame.is_hidden_from_local_player(collider):
				first_other = collider
	if first_other != null:
		return first_other
	return _nearest_to_cursor(screen_pos, camera)


# Live monsters and vendors whose body centre is within TARGET_CLICK_RADIUS_PX of the cursor (nearest to the cursor wins).
func _nearest_to_cursor(screen_pos: Vector2, camera: Camera3D) -> Node:
	var best: Node = null
	var best_px := TARGET_CLICK_RADIUS_PX
	for node in get_tree().get_nodes_in_group("monsters") + get_tree().get_nodes_in_group("npc_vendor"):
		if not is_instance_valid(node) or not _is_targetable_alive(node) or TargetFrame.is_hidden_from_local_player(node):
			continue
		if global_position.distance_to(node.global_position) > TARGET_CLICK_MAX_RANGE:
			continue
		var body := node.get_node_or_null("CollisionShape3D") as Node3D
		var centre: Vector3 = body.global_position if body else node.global_position + Vector3(0, 1.0, 0)
		if camera.is_position_behind(centre):
			continue
		var px := camera.unproject_position(centre).distance_to(screen_pos)
		if px < best_px:
			best_px = px
			best = node
	return best


func _announce_target(target: Node) -> void:
	_set_target_frame(target)
	var desc: String = TargetFrame.display_name(target)
	var cur_hp: int
	var max_hp: int
	if "combat_node" in target and target.combat_node is CombatNode:
		cur_hp = target.combat_node.current_hp
		max_hp = target.combat_node.max_hp
	else:
		cur_hp = int(target.get("current_health")) if "current_health" in target else 0
		max_hp  = int(target.get("max_health")) if "max_health" in target else 0
	var dist := global_position.distance_to(target.global_position)
	GameLog.log_general("Target: [b]%s[/b] — HP %d/%d (%.1fm away)" % [desc, cur_hp, max_hp, dist])


func attack_current_target() -> void:
	if _fear_time > 0.0:
		return   # running in terror (receive_fear())
	if not current_target or not is_instance_valid(current_target):
		current_target = null
		print("⚔️ No target selected. Press Tab to target.")
		return

	if not _is_targetable_alive(current_target):
		print("⚔️ Target is already dead.")
		current_target = null
		return

	if TargetFrame.faction_status(current_target) == "Ally":
		GameLog.log_general("You can't attack an ally.")
		return

	if attack_cooldown > 0.0:
		return

	if current_target.is_in_group("player"):
		_attack_player(current_target)   # a duel or PvP foe
		return

	var dist := global_position.distance_to(current_target.global_position)
	if dist > 3.0:
		print("⚔️ %s is out of range (%.1fm). Move closer!" % [TargetFrame.display_name(current_target), dist])
		return

	attacking = true
	last_attack_time_ms = Time.get_ticks_msec()
	_trigger_attack_animation()
	var swing_duration := _attack_animation_duration()
	attack_cooldown = attack_interval()  # the weapon's speed, not the animation's length
	_attack_generation += 1
	var my_attack_generation := _attack_generation

	if "combat_node" in current_target and current_target.combat_node is CombatNode:
		var result = _resolve_melee_attack(current_target.combat_node)
		if not combat_node.is_alive():
			die(current_target)
			return

		# Multiplayer: relay the real damage to whoever actually owns this
		# monster's authoritative combat_node (the server) instead of only
		# trusting our own local mutation just above, which is a cosmetic,
		# replicated-over-anyway copy on any non-host client. Single-player
		# and the host attacking their own monster are already correct
		# locally (is_multiplayer_authority() is true there), so no relay
		# needed in either case. See monster3d.gd's apply_networked_damage().
		var target_is_networked_monster: bool = current_target is Monster and not current_target.is_multiplayer_authority()
		if target_is_networked_monster and result.get("damage", 0) > 0:
			current_target.apply_networked_damage.rpc_id(1, result["damage"], multiplayer.get_unique_id())

		if current_target.has_method("add_threat"):
			current_target.add_threat(self, combat_node.generate_threat(result.get("damage", 0)))
		var target_desc: String = _desc_of(current_target)
		var weapon := Inventory.get_equipped_weapon()
		var weapon_name: String = weapon.get("name", "")
		var dmg_type: String = CombatLogFormatter.damage_type_from_item(weapon)
		var msg: String = CombatLogFormatter.player_attack(result, target_desc, weapon_name, dmg_type)
		if not msg.is_empty():
			GameLog.log_combat(msg)
			_broadcast_combat(CombatLogFormatter.player_attack_broadcast(player_name, result, target_desc, weapon_name, dmg_type))
		play_swing_sound(str(result.get("result", "")), weapon, current_target)
		if str(result.get("result", "")) == "HIT":
			_stance_on_hit(current_target, int(result.get("damage", 0)))
		_maybe_extra_swing(current_target, weapon)
		if result["result"] == "HIT":
			var skey: String = _weapon_skill_key(weapon)
			_tick_skill(skey)
			_tick_skill("offense")
			_tick_skill("weapon_mastery")
		# PARRY/DODGE/BLOCK/RIPOSTE here mean the *target* defended against our
		# attack, not that we defended anything — ticking our own defensive
		# skills on these results was crediting us for the monster's save. Our
		# own parry/dodge/block/riposte now tick from _tick_defense_skill(),
		# called when a monster attacks us and we're the one defending.
		if not current_target.combat_node.is_alive():
			var dead := current_target
			combat_node.notify_kill()
			GameLog.log_combat(CombatLogFormatter.death("You", target_desc))
			_broadcast_combat(CombatLogFormatter.death(player_name, target_desc))
			_set_target_frame(null)
			current_target = null
			autoattack_enabled = false
			GameLog.set_autoattack(false)
			# Networked monster's own real death/removal/XP-credit already
			# happens server-side via apply_networked_damage() above once the
			# relayed damage lands — calling die() again here would be a
			# second, wrongly-attributed (to whoever's running this code)
			# kill on top of that.
			if not target_is_networked_monster and dead.has_method("die"):
				dead.die()
	else:
		var penalty := get_stat_penalty()
		var total_damage := int(combat_node.calculate_melee_damage(null, combat_node.roll_crit()) * penalty)
		if current_target.has_method("apply_damage"):
			current_target.apply_damage(total_damage, "physical")
			var target_desc: String = _desc_of(current_target)
			GameLog.log_combat("You hit %s for [b]%d[/b] damage." % [target_desc, total_damage])
			_broadcast_combat("%s hits %s for [b]%d[/b] damage." % [player_name, target_desc, total_damage])
		if not is_instance_valid(current_target) or current_target.current_health <= 0:
			var target_desc: String = _desc_of(current_target)
			GameLog.log_combat("%s has been defeated!" % target_desc.capitalize())
			_broadcast_combat("%s has been defeated!" % target_desc.capitalize())
			_set_target_frame(null)
			current_target = null
			autoattack_enabled = false
			GameLog.set_autoattack(false)

	await get_tree().create_timer(swing_duration).timeout
	if _attack_generation == my_attack_generation:
		attacking = false


func perform_melee_attack() -> void:
	if attacking or dying:
		return

	attacking = true
	last_attack_time_ms = Time.get_ticks_msec()
	_trigger_attack_animation()
	var swing_duration := _attack_animation_duration()
	attack_cooldown = attack_interval()  # the weapon's speed, not the animation's length
	_attack_generation += 1
	var my_attack_generation := _attack_generation

	var attack_range := 3.0
	var target: Node = null

	if current_target and is_instance_valid(current_target):
		if global_position.distance_to(current_target.global_position) <= attack_range:
			target = current_target

	if target == null:
		var monsters := get_tree().get_nodes_in_group("monsters")
		var closest_distance := attack_range
		for monster in monsters:
			if not is_instance_valid(monster):
				continue
			var distance := global_position.distance_to(monster.global_position)
			if distance < closest_distance:
				closest_distance = distance
				target = monster

	if target and TargetFrame.faction_status(target) == "Ally":
		target = null

	if target:
		if "combat_node" in target and target.combat_node is CombatNode:
			var result = _resolve_melee_attack(target.combat_node)
			if not combat_node.is_alive():
				die(target)
				return

			# See attack_current_target()'s identical comment — relays real
			# damage to whoever actually owns this monster's authoritative
			# combat_node instead of only trusting our own local mutation.
			var target_is_networked_monster: bool = target is Monster and not target.is_multiplayer_authority()
			if target_is_networked_monster and result.get("damage", 0) > 0:
				target.apply_networked_damage.rpc_id(1, result["damage"], multiplayer.get_unique_id())

			var target_desc: String = TargetFrame.display_name(target)
			var weapon := Inventory.get_equipped_weapon()
			var weapon_name: String = weapon.get("name", "")
			var dmg_type: String = CombatLogFormatter.damage_type_from_item(weapon)
			var msg: String = CombatLogFormatter.player_attack(result, target_desc, weapon_name, dmg_type)
			if not msg.is_empty():
				GameLog.log_combat(msg)
				_broadcast_combat(CombatLogFormatter.player_attack_broadcast(player_name, result, target_desc, weapon_name, dmg_type))
			play_swing_sound(str(result.get("result", "")), weapon, target)
			if str(result.get("result", "")) == "HIT":
				_stance_on_hit(target, int(result.get("damage", 0)))
			_maybe_extra_swing(target, weapon)
			if result["result"] == "HIT":
				var skey: String = _weapon_skill_key(weapon)
				_tick_skill(skey)
				_tick_skill("offense")
				_tick_skill("weapon_mastery")
			# See attack_current_target()'s identical comment: PARRY/DODGE/
			# BLOCK/RIPOSTE here are the target's own defense, not ours.
			if not target.combat_node.is_alive():
				combat_node.notify_kill()
				GameLog.log_combat(CombatLogFormatter.death("You", target_desc))
				_broadcast_combat(CombatLogFormatter.death(player_name, target_desc))
				if target == current_target:
					_set_target_frame(null)
					current_target = null
				# Same reasoning as attack_current_target(): a networked
				# monster's own death/removal/XP-credit already happens
				# server-side once the relayed damage above lands.
				if not target_is_networked_monster and target.has_method("die"):
					target.die()
		else:
			var penalty := get_stat_penalty()
			var total_damage := int(combat_node.calculate_melee_damage(null, combat_node.roll_crit()) * penalty)
			if target.has_method("apply_damage"):
				target.apply_damage(total_damage, "physical")
				var tname = target.get_monster_name() if target.has_method("get_monster_name") else "enemy"
				GameLog.log_combat("You hit %s for %d damage." % [tname, total_damage])
				_broadcast_combat("%s hits %s for %d damage." % [player_name, tname, total_damage])
	else:
		GameLog.log_combat("No target in range.")

	await get_tree().create_timer(swing_duration).timeout
	if _attack_generation == my_attack_generation:
		attacking = false


func take_damage(amount: int, attacker: Node = null) -> void:
	if dying:
		return
	last_damage_time_ms = Time.get_ticks_msec()
	combat_node.take_damage(amount)
	GameLog.log_combat("💔 You take %d damage. [HP: %d/%d]" % [amount, combat_node.current_hp, combat_node.max_hp])
	_register_attacker(attacker)
	_check_spell_interrupt(attacker)
	if not combat_node.is_alive():
		die(attacker)


func apply_damage(amount: int, attacker: Variant = null) -> void:
	if not is_multiplayer_authority():
		# someone else's player (a duel or PvP foe): the blow goes to their own machine (player_versus.gd)
		var me := TargetFrame.local_player()
		if is_instance_valid(me) and me != self and me.has_node("Versus"):
			me.get_node("Versus").send_hit(self, amount)
		return
	take_damage(amount, attacker if attacker is Node else null)


# A melee swing at another player (a duel or PvP foe, player_versus.gd): rolled here like any swing, landed on their
# machine. Their local copy here isn't touched (their own machine owns their health).
func _attack_player(target: Node) -> void:
	var dist := global_position.distance_to((target as Node3D).global_position)
	if dist > 3.0:
		return
	attacking = true
	last_attack_time_ms = Time.get_ticks_msec()
	_trigger_attack_animation()
	attack_cooldown = attack_interval()
	var tcn: CombatNode = target.combat_node
	var hp_before := tcn.current_hp
	var result: Dictionary = _resolve_melee_attack(tcn)
	tcn.current_hp = hp_before
	var weapon := Inventory.get_equipped_weapon()
	var weapon_name: String = weapon.get("name", "")
	var dmg_type: String = CombatLogFormatter.damage_type_from_item(weapon)
	var desc := TargetFrame.display_name(target)
	var msg: String = CombatLogFormatter.player_attack(result, desc, weapon_name, dmg_type)
	if not msg.is_empty():
		GameLog.log_combat(msg)
		_broadcast_combat(CombatLogFormatter.player_attack_broadcast(player_name, result, desc, weapon_name, dmg_type))
	play_swing_sound(str(result.get("result", "")), weapon, target)
	if str(result.get("result", "")) == "HIT":
		get_node("Versus").send_hit(target, int(result.get("damage", 0)))
		_tick_skill(_weapon_skill_key(weapon))
		_tick_skill("offense")


# Each class's starting weapon (character_creation.gd gives it at creation). A character made before theirs was added
# (test 41: Maedianie, a Wildspeaker from before test 34, had no staff) gets it once, if it isn't already in their bags
# or hands.
const STARTER_WEAPONS := {
	"Blademaster": "rusty_sword", "Voidknight": "rusty_sword", "Lightsworn": "rusty_sword",
	"Shadowblade": "dagger", "Woodstalker": "dagger", "Aetherfist": "worn_hand_wraps",
	"Arcanist": "dagger", "Chaosborn": "dagger", "Gravecaller": "dagger", "Troubadour": "dagger", "Lightmender": "dagger",
	"Wildspeaker": "fir_staff", "Spiritweaver": "fir_staff",
}

func _grant_missing_starter_weapon() -> void:
	if not is_multiplayer_authority() or Global.player_data.get("starter_weapon_checked", false):
		return
	Global.player_data["starter_weapon_checked"] = true
	var weapon := str(STARTER_WEAPONS.get(str(player_class), ""))
	if weapon.is_empty() or ItemHelper.count(weapon) > 0 or Inventory.equipped.values().any(func(it): return typeof(it) == TYPE_DICTIONARY and str(it.get("item_id", "")) == weapon):
		return
	if Inventory.add_item(weapon):
		GameLog.log_general("[color=#ffdd88]You find your %s in your pack.[/color]" % str(Inventory.get_item_definition(weapon).get("name", weapon)))
		Global.save_player_data_to_file()


# How a target is named in the combat log: a monster's description, or a player's name.
func _desc_of(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "something"
	if n.is_in_group("player"):
		return TargetFrame.display_name(n)
	var d = n.get("monster_description")
	if d != null and str(d) != "":
		return str(d)
	return n.get_monster_name() if n.has_method("get_monster_name") else TargetFrame.display_name(n)


# Called instead of take_damage() by anything that already applied its own
# damage via CombatNode.resolve_attack() (which mutates current_hp directly —
# see monster3d.gd's perform_attack()) — calling take_damage() there too would
# double-apply the same hit. Handles only the non-HP side effects.
func on_combat_node_hit(attacker: Node) -> void:
	if dying:
		return
	last_damage_time_ms = Time.get_ticks_msec()
	_register_attacker(attacker)
	_check_spell_interrupt(attacker)
	if not combat_node.is_alive():
		die(attacker)


# Being attacked targets the attacker ONLY when you have no target (or your target is gone/dead): a second attacker never pulls you
# off the one you chose.
func _register_attacker(attacker: Node) -> void:
	if not (attacker and is_instance_valid(attacker)) or current_target == attacker:
		return
	var has_target: bool = is_instance_valid(current_target) and current_target.get("current_state") != 4   # 4 = Monster.State.DEAD
	if has_target and "combat_node" in current_target and current_target.combat_node is CombatNode and not current_target.combat_node.is_alive():
		has_target = false
	if has_target:
		return
	current_target = attacker
	_announce_target(attacker)


# ===== DEATH / INCAPACITATION / RESPAWN =====
# EQ-style: 0 HP doesn't kill outright — it incapacitates (downed, frozen,
# bleeding out). Every monster currently fighting the player disengages
# immediately and heads back to its spawn point (monster3d.gd's
# force_disengage()), and won't re-aggro a downed/dead player
# (can_see_player()'s "dying" check) — so the bleed-out window that follows
# is never interrupted by more combat, it's a pure countdown. If it reaches
# BLEED_OUT_DURATION, true death fires: a red "defeated by X" message, a
# random flavor line, a full black respawn screen, then teleport to the
# player's bind point (wherever they first spawned in, see
# _ensure_bind_point()) at full HP/mana/stamina.

# ── Spell messages (player_spells.json "cast_message") ──
# The line the caster sees when the spell lands, with these variables: $targetname (the target's name: "a sand brigand", "Guard Reyna", or
# "yourself" when you are the target), $Targetname (the same with a capital first letter, for the start of a sentence), $caster (your name)
# and $spell (the spell's name). Example: "The melody makes $targetname feel strangely at ease."
func _format_cast_message(text: String, spell_name: String, target_desc: String) -> String:
	var out := text
	out = out.replace("$Targetname", target_desc.substr(0, 1).to_upper() + target_desc.substr(1))
	out = out.replace("$targetname", target_desc)
	out = out.replace("$caster", player_name)
	out = out.replace("$spell", spell_display_name(spell_name))
	return out


# The flavor line for a spell aimed at someone else (a self-cast shows it through _apply_generic_spell_effect instead).
func _log_cast_flavor(spell_name: String, spell: Dictionary, target_desc: String) -> void:
	var text := str(spell.get("cast_message", ""))
	if not text.is_empty():
		GameLog.log_combat("[color=#e6d9a8]%s[/color]" % _format_cast_message(text, spell_name, target_desc))


# ── Spell range ──
# player_spells.json "range" is text like "15m" ("0m" = self only). A spell aimed at a target cannot be cast at anything farther than that
# (a little slack for the target's body): it used to work at 120 m.
const SPELL_RANGE_SLACK := 1.0
var _range_warn_msec := 0


static func spell_range_m(spell: Dictionary) -> float:
	var text := str(spell.get("range", "15m")).strip_edges().to_lower().trim_suffix("m")
	return text.to_float() if text.is_valid_float() else 15.0


func _target_out_of_range(spell: Dictionary, target: Node) -> bool:
	if target == null or target == self or not (target is Node3D):
		return false
	var reach := spell_range_m(spell)
	return reach > 0.0 and global_position.distance_to((target as Node3D).global_position) > reach + SPELL_RANGE_SLACK


func _stop_all_casting_except_songs() -> void:
	if _pending_cast_spell_data.has("travel"):
		$Travel.on_cast_stopped()
	combat_node.is_casting = false
	combat_node.current_cast_time = 0.0
	_pending_cast_spell = ""
	_pending_cast_spell_data = {}
	_pending_cast_target = null
	casting_spell_name = ""


# Death ends all casting: the spell in progress, and every song that was playing (they used to resume after respawning).
func _stop_all_casting() -> void:
	if not _active_songs.is_empty():
		GameLog.log_combat("[color=#ff8866]Your song ends.[/color]")
	_active_songs.clear()
	if _pending_cast_spell_data.has("travel"):
		$Travel.on_cast_stopped()
	combat_node.is_casting = false
	combat_node.current_cast_time = 0.0
	_pending_cast_spell = ""
	_pending_cast_spell_data = {}
	_pending_cast_target = null
	casting_spell_name = ""


func die(attacker: Node = null) -> void:
	if dying:
		return
	dying = true
	is_incapacitated = true
	_bleedout_elapsed = 0.0
	_bleedout_warn_timer = 0.0
	_bleed_remainder = 0.0
	combat_node.current_hp = clampi(combat_node.current_hp, DEATH_HP, 0)  # keep a real overshoot (a hit to -12 leaves you at -12), never below the death line
	_stop_all_casting()  # a downed bard's song stops, and stays stopped after respawning

	if attacker and is_instance_valid(attacker):
		var desc: String = attacker.get("monster_description") if "monster_description" in attacker else ""
		if attacker.is_in_group("player"):
			desc = TargetFrame.display_name(attacker)   # a PvP foe
			_broadcast_combat("[color=#ff5544]%s has been slain by %s![/color]" % [player_name, desc])
		if desc == "" and attacker.has_method("get_monster_name"):
			desc = attacker.get_monster_name()
		if desc != "":
			_last_attacker_desc = desc

	autoattack_enabled = false
	GameLog.set_autoattack(false)
	if combat_node.current_hp <= DEATH_HP:
		_die_for_real()   # a killing blow: no time spent downed
		return
	GameLog.log_combat("[color=#ff8866]You collapse, bleeding out...[/color]")

	for m in get_tree().get_nodes_in_group("monsters"):
		if is_instance_valid(m) and m.has_method("force_disengage"):
			m.force_disengage()

	var death_anim := pick_variant(animation_player, "death")
	if not death_anim.is_empty():
		animation_player.play(death_anim)


# One of a clip's variants at random: "cast_beneficial", "cast_beneficial_2", ... (the animation pack,
# tools/make_animation_pack.gd, gives every race the other races' casts and deaths). "" if it has none.
static func pick_variant(ap: AnimationPlayer, base: String) -> String:
	if ap == null or not ap.has_animation(base):
		return ""
	var names := [base]
	var i := 2
	while ap.has_animation("%s_%d" % [base, i]):
		names.append("%s_%d" % [base, i])
		i += 1
	return names.pick_random()


func _tick_bleedout(delta: float) -> void:
	_bleedout_elapsed += delta
	_bleed_remainder += float(-DEATH_HP) / BLEED_OUT_DURATION * delta   # health drains toward the death line
	while _bleed_remainder >= 1.0:
		_bleed_remainder -= 1.0
		combat_node.current_hp -= 1
	if combat_node.current_hp <= DEATH_HP or _bleedout_elapsed >= BLEED_OUT_DURATION:
		combat_node.current_hp = DEATH_HP
		_die_for_real()
		return
	_bleedout_warn_timer += delta
	if _bleedout_warn_timer >= BLEED_OUT_WARN_INTERVAL:
		_bleedout_warn_timer = 0.0
		GameLog.log_combat("[color=#aa3333]You are bleeding out...[/color]")


func _die_for_real() -> void:
	is_incapacitated = false
	# Counted for the server's telemetry (deaths per hour by class, what killed you).
	Global.player_data["deaths"] = int(Global.player_data.get("deaths", 0)) + 1
	Global.player_data["last_death_by"] = str(_last_attacker_desc)
	combat_node.current_hp = DEATH_HP
	Sfx.play("death_female" if player_sex.to_lower() == "female" else "death_male")
	GameLog.log_combat("[color=#ff4444]You have been defeated by %s![/color]" % _last_attacker_desc.capitalize())
	if _death_flavor:
		var line := _death_flavor.get_line("death")
		if line != "":
			GameLog.log_general("[color=#999999]%s[/color]" % line)
	_clear_on_death()
	_wipe_aggro()
	_show_death_screen()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	_respawn()


# Death wipes you off every monster's hate list (test 42: Halvek chased Maedianie to her bind point after she died, and the
# tank had to drag him back). Each forgets you on its own machine (the server's, over the network).
const AGGRO_WIPE_RANGE := 300.0

func _wipe_aggro() -> void:
	for m in get_tree().get_nodes_in_group("monsters"):
		if not (is_instance_valid(m) and m is Node3D and m.has_method("forget_attacker")):
			continue
		if (m as Node3D).global_position.distance_to(global_position) > AGGRO_WIPE_RANGE:
			continue
		if m.is_multiplayer_authority():
			m.forget_attacker(get_path())
		elif Net.is_multiplayer_game and multiplayer.has_multiplayer_peer():
			m.forget_attacker.rpc_id(1, get_path())


# Death strips every spell effect, good and bad, and sends your pet away (summon it again; its gear stays with you, it
# isn't lost the way it is when the pet itself is killed). Stances, a lit torch and being fed or hungry aren't spells.
const KEPT_THROUGH_DEATH := ["lit_torch", "well_fed", "starving", "thirsty"]

func _clear_on_death() -> void:
	_fear_time = 0.0   # no running off in terror after you wake
	for effect_name in combat_node.active_effects.keys():
		if str(effect_name).begins_with("stance_") or KEPT_THROUGH_DEATH.has(str(effect_name)):
			continue
		combat_node.remove_effect(str(effect_name))
	combat_node._stats_dirty = true
	if is_instance_valid(active_pet):
		GameLog.log_general("[color=#cccccc]Your pet fades away as you fall. Summon it again when you're back on your feet.[/color]")
		active_pet.dismissed.emit()      # the same bookkeeping as Dismiss: gear kept, "pet_active" saved as false
		active_pet.queue_free()
		active_pet = null
	if is_instance_valid(active_pet_frame):
		active_pet_frame.queue_free()


func _show_death_screen() -> void:
	_death_screen = CanvasLayer.new()
	_death_screen.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen.add_child(bg)
	var lbl := Label.new()
	lbl.text = "Death is upon you! Returning to your bind point......."
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_death_screen.add_child(lbl)
	get_tree().root.add_child(_death_screen)


func _respawn() -> void:
	if is_instance_valid(_death_screen):
		_death_screen.queue_free()
	_death_screen = null

	if bind_is_elsewhere():
		# bound in another zone: wake up there (full health is restored below and saved with the trip)
		combat_node.current_hp = combat_node.max_hp
		combat_node.current_mana = combat_node.max_mana
		dying = false
		Net.zone_travel(str(Global.player_data.get("bind_zone")), "", true)
		return
	global_position = get_bind_point()
	_fall_grace_until_ms = Time.get_ticks_msec() + FALL_GRACE_MS
	combat_node.current_hp = combat_node.max_hp
	combat_node.current_mana = combat_node.max_mana
	current_stamina = max_stamina
	current_target = null
	_set_target_frame(null)
	dying = false
	GameLog.log_general("[color=#88ccff]You awaken at your bind point.[/color]")
	if is_instance_valid(active_pet) and active_pet.has_method("recall_to_owner"):
		active_pet.recall_to_owner()  # the pet appears beside you instead of walking all the way back


# The player's bind point defaults to wherever they first spawned into the
# world (no bind spell/NPC exists yet — this can grow into that later
# without changing anything here, just what sets Global.player_data["bind_point"]).
# Stored as a plain [x,y,z] array since Vector3 isn't JSON-serializable.
func _ensure_bind_point() -> void:
	if not Global.player_data.has("bind_point"):
		Global.player_data["bind_point"] = [global_position.x, global_position.y, global_position.z]
		Global.player_data["bind_zone"] = ZoneInfo.current_id()
		Global.save_player_data_to_file()


# Bound in another zone (Global.player_data "bind_zone"; characters from before zones are bound in the starting zone)?
# Death and gate spells then take you home through Net.zone_travel(), not to these coordinates here.
func bind_is_elsewhere() -> bool:
	var bz := str(Global.player_data.get("bind_zone", ZoneInfo.DEFAULT_ID))
	var here := ZoneInfo.current_id()
	return ZoneInfo.exists(bz) and ZoneInfo.exists(here) and bz != here


# Restores the position saved by Global.save_player_data_to_file() so the
# player logs back in exactly where they logged out, instead of always at the
# zone scene's fixed Player3D spawn transform. No-op for a brand new
# character (no "last_position" saved yet), which just keeps the zone's
# default spawn.
func _restore_last_position() -> void:
	_fall_grace_until_ms = Time.get_ticks_msec() + FALL_GRACE_MS
	# Just came through a zone line (Net.zone_travel()): arrive at its marker in this zone, or at the bind point.
	var zone_in := str(Global.player_data.get("zone_in", ""))
	if not zone_in.is_empty():
		Global.player_data.erase("zone_in")
		_arrived_by_zone_line = true
		if zone_in == "@spawn":   # a game master's /teleport: the zone's arrival point
			global_position = _zone_safe_spot()
			_lift_above_ground.call_deferred()
			return
		var marker: Node3D = null
		if zone_in != "@bind" and get_tree().current_scene != null:
			marker = get_tree().current_scene.get_node_or_null("Markers/" + zone_in) as Node3D
		if zone_in == "@bind" or marker != null:
			global_position = get_bind_point() if marker == null else marker.global_position + Vector3(0, 1.0, 0)
			if marker != null:
				face_into_zone()
			_lift_above_ground.call_deferred()
			return
		push_warning("Zone-in marker '%s' not found in this zone — using the zone's spawn point." % zone_in)
		return
	var arr: Array = Global.player_data.get("last_position", [])
	if arr.size() == 3:
		global_position = Vector3(arr[0], arr[1], arr[2])
		if float(arr[1]) < FALL_RESCUE_Y:
			global_position = _zone_safe_spot()   # logged out while falling out of the world
		_lift_above_ground.call_deferred()


# A poison, disease or burn ticking on you: say so, in the damage-taken colour (only on your own screen).
func _on_effect_ticked(effect_name: String, amount: int) -> void:
	if not is_multiplayer_authority() or dying:
		return
	var spell: Dictionary = _spell_by_name.get(effect_name, {})
	var what := spell_display_name(effect_name) if not spell.is_empty() else effect_name.replace("_", " ").capitalize()
	GameLog.log_combat("[color=#ff7766]You have taken %d point%s of damage from %s.[/color]" % [amount, "" if amount == 1 else "s", what])


# Just through a zone line: turn to face INTO the zone, away from the nearest zone line (test 37: you arrived facing
# back the way you came, and walking forward took you straight back over the line).
func face_into_zone() -> void:
	var here := Vector3(global_position.x, 0.0, global_position.z)
	var nearest: Node3D = null
	var best := INF
	for line in get_tree().get_nodes_in_group("zone_line"):
		var d := here.distance_to(Vector3(line.global_position.x, 0.0, line.global_position.z))
		if d < best:
			best = d
			nearest = line
	if nearest == null:
		return
	# across the line (its thin side, local Z), on our side of it: a wide line's middle can be far off to one side
	var across := nearest.global_transform.basis.z
	across.y = 0.0
	if across.length() < 0.01:
		return
	across = across.normalized()
	var away := here - Vector3(nearest.global_position.x, 0.0, nearest.global_position.z)
	if away.dot(across) < 0.0:
		across = -across
	look_at(global_position + across, Vector3.UP)


# EverQuest style: "You have entered Dustwind Plateaus." on logging in and on every zone change. Waits a moment so the
# chat window (built as the character enters the world) is there to show it.
func _announce_zone() -> void:
	await get_tree().create_timer(0.5).timeout
	if is_inside_tree() and is_multiplayer_authority():
		GameLog.log_general("[color=#ffdd88]You have entered %s.[/color]" % WorldAnnouncer.zone_display_name())


# The ground is a heightmap: there is never anything to stand on UNDER it. If the character ends up more than half a metre
# below the terrain surface where they stand (slipped through a steep slope), put them back on top. Checked 4 times a second.
const UNDER_TERRAIN_MARGIN := 0.5
# Fell out of the world altogether (off an edge, through a gap): below this you're put back at the zone's safe spot.
const FALL_RESCUE_Y := -150.0


# The zone's safe spot: where new characters appear (the zone root's spawn_position).
func _zone_safe_spot() -> Vector3:
	var scene := get_tree().current_scene
	var spot = scene.get("spawn_position") if scene != null else null
	return spot if spot is Vector3 else Vector3(0, 2, 0)


func _rescue_from_fall() -> void:
	global_position = _zone_safe_spot() + Vector3(0, 1.0, 0)
	velocity = Vector3.ZERO
	_fall_grace_until_ms = Time.get_ticks_msec() + FALL_GRACE_MS
	_lift_above_ground.call_deferred()
	GameLog.log_general("[color=#ffdd88]You tumble through the void... and find yourself on solid ground again.[/color]")
	Global.save_player_data_to_file()
var _terrain_check_timer := 0.0
var _terrain_node: Node = null

func _check_under_terrain(delta: float) -> void:
	_terrain_check_timer += delta
	if _terrain_check_timer < 0.25:
		return
	_terrain_check_timer = 0.0
	if global_position.y < FALL_RESCUE_Y:
		_rescue_from_fall()
		return
	if not is_instance_valid(_terrain_node):
		var scene := get_tree().current_scene
		_terrain_node = scene.get_node_or_null("Terrain3D") if scene != null else null
		if _terrain_node == null:
			return
	var data = _terrain_node.get("data")
	if data == null:
		return
	var h: float = data.get_height(global_position)
	if is_nan(h) or h > 10000.0:
		return   # outside the terrain's regions
	if global_position.y < h - UNDER_TERRAIN_MARGIN:
		global_position.y = h + 0.2
		velocity.y = 0.0
		_fall_grace_until_ms = Time.get_ticks_msec() + FALL_GRACE_MS   # no fall damage for being put back


# A saved position from before the ground changed (the flat zone -> the Terrain3D rebuild, or a re-sculpted hill) can now
# be inside the terrain. If there's no ground just under the player, put them on the ground at that spot instead.
func _lift_above_ground() -> void:
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var near := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0), global_position + Vector3(0, -3.0, 0))
	near.exclude = [get_rid()]
	if not Global.ground_ray(space, near).is_empty():
		return
	var high := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 300.0, 0), global_position + Vector3(0, -300.0, 0))
	high.exclude = [get_rid()]
	var hit := Global.ground_ray(space, high)
	if not hit.is_empty():
		global_position = hit["position"] + Vector3(0, 0.2, 0)


# /stuck — for when the world's collision traps you (the mausoleum door, test 33). Moves you STUCK_DISTANCE metres in a
# random direction: up to STUCK_TRIES directions are tried, and the first one with floor under it (found near your own
# height, so never on a roof) and room for your body wins; failing that, the first one with any floor. Not in a fight,
# not while dying, once every STUCK_COOLDOWN_MS.
const STUCK_DISTANCE := 5.0
const STUCK_TRIES := 16
const STUCK_COOLDOWN_MS := 30000
var _last_stuck_msec := -STUCK_COOLDOWN_MS


func cmd_stuck() -> void:
	if dying:
		return
	if Time.get_ticks_msec() - last_attacked_msec < 10000 or combat_node.in_combat:
		GameLog.log_general("[color=#ff8866]You can't do that in the middle of a fight.[/color]")
		return
	var wait := STUCK_COOLDOWN_MS - (Time.get_ticks_msec() - _last_stuck_msec)
	if wait > 0:
		GameLog.log_general("[color=#ff8866]Wait %d more seconds before trying that again.[/color]" % int(ceil(wait / 1000.0)))
		return
	var space := get_world_3d().direct_space_state
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var fallback := Vector3.INF
	var spot := Vector3.INF
	var start_angle := randf() * TAU
	for i in STUCK_TRIES:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, start_angle + TAU * i / STUCK_TRIES)
		var target := global_position + dir * STUCK_DISTANCE
		var down := PhysicsRayQueryParameters3D.create(target + Vector3(0, 2.5, 0), target + Vector3(0, -4.0, 0))
		down.exclude = [get_rid()]
		var hit := Global.ground_ray(space, down)
		if hit.is_empty():
			continue
		var feet: Vector3 = hit["position"] + Vector3(0, 0.1, 0)
		if fallback == Vector3.INF:
			fallback = feet
		if shape_node != null and shape_node.shape != null:
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape_node.shape
			q.transform = Transform3D(shape_node.global_transform.basis, feet + (shape_node.global_position - global_position) + Vector3(0, 0.05, 0))
			q.exclude = [get_rid()]
			if not space.intersect_shape(q, 1).is_empty():
				continue
		spot = feet
		break
	if spot == Vector3.INF:
		spot = fallback
	if spot == Vector3.INF:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, start_angle)
		spot = global_position + dir * STUCK_DISTANCE
		_lift_above_ground.call_deferred()
	_last_stuck_msec = Time.get_ticks_msec()
	velocity = Vector3.ZERO
	global_position = spot
	_fall_grace_until_ms = Time.get_ticks_msec() + FALL_GRACE_MS
	# Your pet comes too (test 34: it stayed trapped).
	if is_instance_valid(active_pet):
		if active_pet.has_method("recall_to_owner"):
			active_pet.recall_to_owner()
		elif active_pet is Node3D:
			active_pet.global_position = spot + Vector3(1.0, 0.2, 1.0)
	GameLog.log_general("[color=#88ccff]You wriggle free.[/color]")


func get_bind_point() -> Vector3:
	var arr: Array = Global.player_data.get("bind_point", [])
	if arr.size() == 3:
		return Vector3(arr[0], arr[1], arr[2])
	return global_position


func _set_target_frame(target: Node) -> void:
	for tf in get_tree().get_nodes_in_group("target_frame"):
		tf.set_target(target)
#endregion

#region Character sheet management
func toggle_character_sheet() -> void:
	Sfx.play("window")
	if character_sheet_instance:
		character_sheet_instance.queue_free()
		character_sheet_instance = null
		Global.restore_mouse_mode()
		print("📋 Character sheet closed")
	else:
		character_sheet_instance = character_sheet_scene.instantiate()
		get_tree().root.add_child(character_sheet_instance)

		if character_sheet_instance.has_method("set_player"):
			character_sheet_instance.set_player(self)

		if character_sheet_instance.has_method("set_character_data"):
			var is_caster = caster_classes.has(player_class.to_lower())
			var sheet_data := {
				"player_name":    player_name,
				"player_class":   Global.player_data.get("player_class", "Unknown"),
				"player_race":    Global.player_data.get("player_race", ""),
				"player_level":   Global.player_data.get("player_level", 1),
				"xp":             Global.player_data.get("xp", 0),
				"xp_next_level":  Global.player_data.get("xp_next_level", 100),
				"stats":          stats,
				# CombatNode-derived values
				"current_hp":      combat_node.current_hp,
				"max_hp":          combat_node.max_hp,
				"current_mana":    combat_node.current_mana,
				"max_mana":        combat_node.max_mana,
				"current_stamina": int(current_stamina),
				"max_stamina":     int(max_stamina),
				"armor_class":     combat_node.get_ac(),
				"crit_chance":     combat_node.get_crit_chance(),
				"attack":          combat_node.get_atk(),
				"max_weight":      combat_node.get_derived_stat("carry_weight"),
				"spell_power":     combat_node.get_arcane_power() if is_caster else 0,
				"resistances": {
					"acid":      combat_node.get_resistance("acid"),
					"cold":      combat_node.get_resistance("cold"),
					"fire":      combat_node.get_resistance("fire"),
					"lightning": combat_node.get_resistance("lightning"),
					"poison":    combat_node.get_resistance("poison"),
					"disease":   combat_node.get_resistance("disease"),
					"magic":     combat_node.get_resistance("magic"),
					"divine":    combat_node.get_resistance("divine"),
					"psychic":   combat_node.get_resistance("psychic"),
					"spirit":    combat_node.get_resistance("spirit"),
				},
				# Pass-through fields
				"satiety":           satiety,
				"thirst":            thirst,
				"equipment":         Global.player_data.get("equipment", {}),
				"character_creation":Global.player_data.get("character_creation", {}),
				"playtime_seconds":  Global.get_total_playtime(),
				"copper":   Global.player_data.get("copper", 0),
				"silver":   Global.player_data.get("silver", 0),
				"gold":     Global.player_data.get("gold", 0),
				"platinum": Global.player_data.get("platinum", 0),
			}
			character_sheet_instance.set_character_data(sheet_data)

		print("📋 Character sheet opened")
#endregion

#region Character data loading
func load_player_data_from_global() -> void:
	if Global.player_data.is_empty():
		# Dev fallback: hardcoded test character for launching scenes directly from the editor
		push_warning("⚠️ No Global.player_data — loading dev defaults")

		# Build starting inventory so items are visible in the backpack
		Inventory.initialize_basic_inventory()
		Inventory._initialize_equipment()
		Inventory.basic_inventory[0] = Inventory.create_item_instance("small_bag")
		Inventory.bag_contents["0"] = [
			Inventory.create_item_instance("faded_note"),
			Inventory.create_item_instance("iron_rations", 20),
			Inventory.create_item_instance("water_flask", 20),
			Inventory.create_item_instance("torch", 5),
		]
		var _dev_gear: Array[String] = ["rusty_sword", "ragged_hood", "ragged_tunic", "ragged_leggings", "torn_boots", "cloth_cape"]
		for _gi in range(_dev_gear.size()):
			Inventory.basic_inventory[_gi + 1] = Inventory.create_item_instance(_dev_gear[_gi])

		Global.set_player_data({
			"player_name":  "Dev",
			"player_class": "Blademaster",
			"player_race":  "Human",
			"player_level": 1,
			"stats": {
				"strength": 14, "constitution": 12, "dexterity": 12,
				"intelligence": 10, "wisdom": 10, "charisma": 10, "luck": 10
			},
			"equipment": {
				"ear1": "", "ear2": "", "neck": "", "face": "", "head": "",
				"finger1": "", "finger2": "", "wrist1": "", "wrist2": "",
				"charm": "", "focus": "", "arms": "", "hands": "", "shoulders": "",
				"chest": "", "back": "", "waist": "", "legs": "", "feet": "",
				"trinket1": "", "trinket2": "", "primary": "", "secondary": "",
				"ranged": "", "ammo": ""
			},
			"known_spells": ["power_strike", "battle_shout"],
			"known_skills": ["1h_slashing", "parry", "dodge", "weapon_mastery"],
			"skill_levels": {"1h_slashing": 10, "parry": 5, "dodge": 5, "weapon_mastery": 5},
			"action_bar_slots": [
				{"type": "spell", "name": "power_strike"},
				{"type": "spell", "name": "battle_shout"},
				{"type": "", "name": ""}, {"type": "", "name": ""},
				{"type": "", "name": ""}, {"type": "", "name": ""},
				{"type": "", "name": ""}, {"type": "", "name": ""},
				{"type": "", "name": ""}, {"type": "", "name": ""},
				{"type": "", "name": ""}, {"type": "", "name": ""}
			],
			"inventory_data": Inventory.save_inventory_data(),
			"copper": 15, "silver": 2, "gold": 0, "platinum": 0,
			"xp": 0, "xp_next_level": int(Global.xp_table.get("2", 100))
		})

	load_character_data(Global.player_data)

	satiety = Global.player_data.get("satiety", 100)
	thirst = Global.player_data.get("thirst", 100)
	current_stamina = Global.player_data.get("current_stamina", MAX_STAMINA)
	max_stamina = Global.player_data.get("max_stamina", MAX_STAMINA)

	var inv_data = Global.player_data.get("inventory_data", {})
	if inv_data.is_empty():
		Inventory.reset_for_new_character()  # a character with no saved inventory starts empty, not with the last one's
	else:
		Inventory.load_inventory_data(inv_data)
		_apply_equipment_from_inventory()
		# The equipped weapon only exists from here on. load_character_data() (above) ran _sync_weapon_skill() BEFORE the
		# inventory was loaded, found nothing wielded, and left the baseline skill in place — so accuracy at login came from
		# the baseline and only jumped to the character's real weapon skill at the first "You've become better at..." message.
		_sync_weapon_skill()
		_apply_baseline_weapon_skill()  # still 0 (e.g. an old save keyed under a different skill name): keep the fallback
		combat_node._stats_dirty = true
		combat_node.recalculate_derived_stats()
		_grant_missing_starter_weapon()


# Starting weapon skill: combat classes begin with a baseline so they can hit. Only a FALLBACK for when the equipped
# weapon's real skill is 0 (or nothing is equipped yet).
func _apply_baseline_weapon_skill() -> void:
	match player_class:
		"Blademaster", "Shadowblade", "Voidknight", "Lightsworn":
			if combat_node.weapon_skill == 0:
				combat_node.weapon_skill = 10
		"Woodstalker", "Aetherfist", "Zenblade":
			if combat_node.weapon_skill == 0:
				combat_node.weapon_skill = 8
		_:
			if combat_node.weapon_skill == 0:
				combat_node.weapon_skill = 4


func _refresh_nameplate() -> void:
	if has_node("NameLabel"):
		$NameLabel.text = TargetFrame.nameplate_name(self)
		$NameLabel.modulate = TargetFrame.nameplate_color(self)


func load_character_data(data: Dictionary) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("❌ Invalid character data type")
		return

	player_name  = data.get("player_name",  "Unnamed Player")
	surname      = str(data.get("surname", ""))
	player_class = data.get("player_class", "Blademaster")
	player_race  = data.get("player_race",  "Human")
	player_sex   = data.get("player_sex",   "male")
	stats        = data.get("stats",        {})
	appearance_json = JSON.stringify(data.get("appearance", {})) if typeof(data.get("appearance")) == TYPE_DICTIONARY else ""
	# On a server the flag is granted per session by the server's password (gm_commands.gd), never restored from the save.
	is_game_master = bool(data.get("is_game_master", false)) and not (Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and not multiplayer.is_server())

	_build_character_model()

	_refresh_nameplate()

	data["resistances"] = data.get("resistances", {
		"acid": 0, "cold": 0, "fire": 0, "magic": 0, "psychic": 0
	})
	data["equipment"] = data.get("equipment", {})

	pet_equipment = data.get("pet_equipment", {})
	Inventory.refresh_item_icons(pet_equipment)
	for slot in PET_EQUIPMENT_SLOTS:
		if not pet_equipment.has(slot):
			pet_equipment[slot] = null

	combat_node.character_name = player_name
	combat_node.set_base_stat("level",        data.get("player_level", 1))
	combat_node.set_class(player_class)
	combat_node.set_base_stat("strength",     int(stats.get("strength",     10)))
	combat_node.set_base_stat("constitution", int(stats.get("constitution", 10)))
	combat_node.set_base_stat("dexterity",    int(stats.get("dexterity",    10)))
	combat_node.set_base_stat("intelligence", int(stats.get("intelligence", 10)))
	combat_node.set_base_stat("wisdom",       int(stats.get("wisdom",       10)))
	combat_node.set_base_stat("charisma",     int(stats.get("charisma",     10)))
	combat_node.set_base_stat("luck",         int(stats.get("luck",         10)))
	combat_node.recalculate_derived_stats()

	# Restore saved resources; default to full for new characters
	var saved_hp = data.get("current_hp", -1)
	combat_node.current_hp = saved_hp if saved_hp >= 0 else combat_node.max_hp
	var saved_mana = data.get("current_mana", -1)
	combat_node.current_mana = saved_mana if saved_mana >= 0 else combat_node.max_mana

	# Restore active buffs/debuffs (stances, campfire warmth, etc.) exactly as
	# they were at save time — active_effects is plain data (no Node
	# references), so it round-trips through JSON as-is. Also restores
	# current_stance so the stance bar highlights the right slot again.
	var saved_effects: Dictionary = data.get("active_effects", {})
	for effect_name in saved_effects:
		combat_node.active_effects[effect_name] = saved_effects[effect_name]
	for effect_name in saved_effects:
		if effect_name.begins_with("stance_"):
			current_stance = effect_name.substr(len("stance_"))
			break

	apply_racial_modifiers(player_race)
	known_spells     = data.get("known_spells", [])
	known_skills     = data.get("known_skills", [])
	known_recipes    = data.get("known_recipes", [])
	if is_multiplayer_authority():
		Languages.ensure_started(player_race.to_lower().replace(" ", "_").replace("-", "_"))  # a character made before languages gets its race's (Data/languages.json)
	# Pickpocket (added 2026-09-23) is innate for the sneaky classes: characters made before it get it here.
	if player_class in ["Shadowblade", "Troubadour", "Woodstalker"] \
			and not known_spells.any(func(k): return SpellInfo.counts_as(str(k)).has("pickpocket")):
		known_spells.append("pickpocket")
	if player_class == "Aetherfist":
		if not known_spells.has("focused_strike"):
			known_spells.append("focused_strike")  # the level-1 self-buff every Aetherfist starts with (added 2026-09-23)
		known_spells.erase("wind_stance")  # retired as an ability: the Aetherfist's Wind Stance is a stance on the stance bar now
	skill_levels     = data.get("skill_levels", {})
	_migrate_legacy_skills()
	combat_node.skills = skill_levels  # Data/skill_effects.json reads the player's skills through the combat node
	action_bar_slots = data.get("action_bar_slots", _default_action_bar_slots())
	_sync_weapon_skill()
	apply_equipment(data.get("equipment", {}))
	_apply_baseline_weapon_skill()
	combat_node._stats_dirty = true
	combat_node.recalculate_derived_stats()

	print("✅ Loaded stats for %s | Class: %s | HP: %d | Mana: %d" % [
		player_name, player_class, combat_node.max_hp, combat_node.max_mana
	])


# Racial bonuses/penalties from character_options.json's traits/penalties —
# per user request (2026-09-18), this covers the "core combat stats" subset
# only (health/mana/damage/resistance/dodge/parry/crit/movement speed/
# all-stats/negative-effect-resist/root-and-blind immunity). Deliberately NOT
# covered here (see [[project_racial_traits]] in memory for the full list and
# why): skill-specific bonuses (blacksmithing, hide, tracking, etc. — a
# dozen+ different skill names, no clean single hook), faction standing
# offsets (a separate system), environmental/conditional traits (Dark Elf's
# daylight regen penalty, Lizardkin's cold penalties, Troll's swamp bonus,
# Elf's "outdoors" qualifier on movement speed — all need zone/time-of-day
# awareness this doesn't have yet), XP-gain-rate bonuses (a leveling-system
# hook, not combat), and Lizardkin's unarmed bite/amphibious (full abilities,
# not passive stats).
func apply_racial_modifiers(race_name: String) -> void:
	match race_name.to_lower():
		"human":
			# health/mana regen bonuses ride on the SAME flat regen_bonus var
			# Troll's trait already uses below, rather than a new field —
			# Human's own bonus is a percentage of a per-tick amount too small
			# to meaningfully separate from Troll's flat approach.
			pass
		"elf":
			combat_node.race_mana_mult = 0.10
			combat_node.race_spell_damage_mult = 0.05
			combat_node.race_immune_to_root = true
			combat_node.race_hp_mult = -0.10
			combat_node.race_cold_resist = 5
			combat_node.race_magic_resist = 5
		"dwarf":
			combat_node.race_hp_mult = 0.15
			combat_node.race_physical_resist = 0.05
			combat_node.race_movement_speed_mult = -0.10
			combat_node.race_mana_mult = -0.10
			combat_node.race_acid_resist = 5
			combat_node.race_cold_resist = 5
			combat_node.race_magic_resist = 5
			combat_node.race_psychic_resist = -5
		"gnome":
			combat_node.race_dodge_bonus = 10
			combat_node.race_spell_crit_chance = 0.05  # spell_critical_chance_bonus (it used to be a melee crit bonus)
			combat_node.race_melee_damage_mult = -0.15
			combat_node.race_magic_resist = 10
			combat_node.race_psychic_resist = 5
		"halfling":
			combat_node.race_negative_effect_resist = 0.10
			combat_node.race_hp_mult = -0.10
			combat_node.race_melee_damage_mult = -0.05
			combat_node.race_magic_resist = 5
			combat_node.race_psychic_resist = 5
		"half_elf":
			combat_node.race_all_stats_mult = 0.05
			combat_node.race_magic_resist = 5
			combat_node.race_psychic_resist = 5
		"ogre":
			combat_node.race_melee_damage_mult = 0.20
			combat_node.race_hp_mult = 0.10
			combat_node.race_physical_resist = 0.05
			combat_node.race_movement_speed_mult = -0.15
			combat_node.race_dodge_bonus = -10
			combat_node.race_mana_mult = -0.20
			combat_node.race_acid_resist = 10
			combat_node.race_magic_resist = -10
			combat_node.race_psychic_resist = -5
		"troll":
			regen_bonus = 4  # Troll regeneration trait: +4 HP per regen tick (stacks with sitting bonus)
			combat_node.race_crit_bonus = 10
			combat_node.race_dodge_bonus = -10
			combat_node.race_parry_bonus = -10
			combat_node.race_acid_resist = 10
			combat_node.race_cold_resist = -5
			combat_node.race_fire_resist = -5
		"dark_elf":
			combat_node.race_immune_to_blind = true
			combat_node.race_fire_resist = -5
			combat_node.race_magic_resist = 10
			combat_node.race_psychic_resist = 10
		"half_orc":
			combat_node.race_melee_damage_mult = 0.15
			combat_node.race_hp_mult = 0.05
			combat_node.race_mana_mult = -0.10
			combat_node.race_spell_damage_mult = -0.05
			combat_node.race_acid_resist = 5
			combat_node.race_magic_resist = -5
		"lizardkin":
			# Natural armour: its own field (gear_ac is recomputed from equipment, which dropped the +2 on the first equip).
			# The charisma penalty is already in racial_stats.json's base 8; it used to be taken off a second time here.
			combat_node.race_ac_bonus = 2
			combat_node.race_acid_resist = 5
			combat_node.race_cold_resist = -10
			combat_node.race_psychic_resist = 5
	apply_racial_traits(race_name)
	combat_node._stats_dirty = true
	combat_node.recalculate_derived_stats()


# The racial traits apply_racial_modifiers() above doesn't cover, read from Data/character_options.json "traits" (the
# list the character creation screen shows). Nothing here is saved: it is worked out again at every login, so existing
# characters get it too. Traits with no game system behind them yet (research, intimidation, swamps,
# knockback — no monster knocks players back) are listed in RACIAL_TRAITS_NOT_YET_USED.
const RACIAL_SKILL_TRAITS := {
	"blacksmithing_skill_bonus": "blacksmithing", "mining_skill_bonus": "prospecting", "engineering_skill_bonus": "tinkering",
	"foraging_skill_bonus": "forage", "fishing_skill_bonus": "fishing", "tracking_skill_bonus": "tracking",
	"divination_skill_bonus": "divination", "hide_skill_bonus": "stealth", "sneak_skill_bonus": "stealth",
	"pick_lock_skill_bonus": "lockpicking", "defense_skill_bonus": "defense",
}
const RACIAL_TRAITS_NOT_YET_USED := ["research_skill_bonus", "intimidation_skill_bonus", "swamp_movement_speed_bonus",
	"swamp_survival_skill_bonus", "swamp_perception_skill_bonus", "immune_to_knockback"]
var race_skill_gain_mult: float = 1.0          # Human +5% (experience_gain_all_skills), Half-Elf -5% (Identity Conflict)
var race_combat_skill_gain_mult: float = 1.0   # Half-Orc +5% on combat (physical) skills
var race_hp_regen_mult: float = 1.0            # Human +5%
var race_mana_regen_mult: float = 1.0          # Human, Half-Elf +5%
var race_in_combat_regen_pct: float = 0.0      # Lizardkin: share of max health regained per tick while fighting
var race_daylight_regen_mult: float = 1.0      # Vol'kyne (Sunlight Weakness): health/mana regen by day
var race_night_attack_penalty: int = 0         # Lizardkin (Sunlight Dependency): accuracy lost at night
var race_fear_save_bonus: int = 0              # Lizardkin: each point is +5% on the fear save (receive_fear())
var race_faction_offset: int = 0               # added to every faction standing (Human +10, Half-Elf +5; shunned races less)
var _regen_carry := {"hp": 0.0, "mana": 0.0}    # fractions of a point kept between ticks so +5% regen isn't lost to rounding
static var _physical_skills: Dictionary = {}


func apply_racial_traits(race_name: String) -> void:
	var race_key := race_name.to_lower()
	var traits: Dictionary = Global.character_options.get("races", {}).get(race_key, {}).get("traits", {})
	var bonus := {}
	for trait_key in RACIAL_SKILL_TRAITS:
		if traits.has(trait_key):
			var skill: String = RACIAL_SKILL_TRAITS[trait_key]
			bonus[skill] = maxi(int(bonus.get(skill, 0)), int(traits[trait_key]))  # hide + sneak both mean stealth: the larger counts
	combat_node.race_skill_bonus = bonus
	combat_node.race_school_damage = {}
	race_skill_gain_mult = 1.0 + float(traits.get("experience_gain_all_skills", 0.0))
	race_combat_skill_gain_mult = 1.0 + float(traits.get("combat_skill_experience_gain_bonus", 0.0))
	race_hp_regen_mult = 1.0 + float(traits.get("health_regeneration_bonus", 0.0))
	race_mana_regen_mult = 1.0 + float(traits.get("mana_regeneration_bonus", 0.0))
	race_fear_save_bonus = int(traits.get("fear_resistance_save_bonus", 0))   # Lizardkin +2: see receive_fear()
	race_faction_offset = int(traits.get("faction_bonus_all", 0)) + int(traits.get("faction_standing_bonus_all", 0))
	race_faction_modifiers = race_standing_modifiers(race_key)
	_refresh_faction_attitudes()   # the racial offset moves every standing
	# Every zone is outdoors so far, so the Elf's outdoor speed always applies (indoor zones will have to switch it off).
	if traits.has("movement_speed_outdoors_bonus"):
		combat_node.race_movement_speed_mult = float(traits["movement_speed_outdoors_bonus"])  # Elf: no other speed modifier
	if traits.has("spell_critical_chance_bonus"):
		combat_node.race_spell_crit_chance = float(traits["spell_critical_chance_bonus"])
	if traits.has("necrotic_spell_damage_bonus"):
		combat_node.race_school_damage["necromancy"] = float(traits["necrotic_spell_damage_bonus"])
	if traits.has("illusion_spell_damage_bonus"):
		combat_node.race_school_damage["illusion"] = float(traits["illusion_spell_damage_bonus"])
	combat_node.race_unarmed_bite = traits.has("unarmed_bite_damage")
	# Troll's in_combat_health_regeneration is the flat regen_bonus above (always on); the Lizardkin's small one is a share of max health.
	if race_key == "lizardkin":
		race_in_combat_regen_pct = float(traits.get("in_combat_health_regeneration", 0.0))
	# The penalties written as notes in character_options.json, given numbers:
	match race_key:
		"half_elf": race_skill_gain_mult -= 0.05          # Identity Conflict: slightly slower skill growth
		"dark_elf":
			race_daylight_regen_mult = 0.5                 # Sunlight Weakness: regeneration severely hampered in daylight
			race_faction_offset -= 10                      # Outcast
		"lizardkin": race_night_attack_penalty = 5        # Sunlight Dependency: accuracy penalty in darkness
		"troll": race_faction_offset -= 10                 # Poor Reputation
		"gnome", "half_orc": race_faction_offset -= 5      # Faction Distrust / Social Stigma


# Racial regen multipliers (Human +5%, Vol'kyne halved by day). Fractions carry over to the next tick.
func _racial_regen(kind: String, amount: int, mult: float) -> int:
	if race_daylight_regen_mult != 1.0 and not NPCConversation.is_night(get_tree()):
		mult *= race_daylight_regen_mult
	if mult == 1.0 or amount <= 0:
		return amount
	var exact: float = amount * mult + float(_regen_carry[kind])
	var whole := int(floor(exact))
	_regen_carry[kind] = exact - whole
	return whole


# Lizardkin lose accuracy at night; checked every regen tick.
func _update_racial_day_night() -> void:
	if race_night_attack_penalty == 0:
		return
	var mod := -race_night_attack_penalty if NPCConversation.is_night(get_tree()) else 0
	if combat_node.race_attack_rating_mod != mod:
		combat_node.race_attack_rating_mod = mod
		combat_node._stats_dirty = true


func _is_physical_skill(skill_name: String) -> bool:
	if _physical_skills.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://Data/player_skills.json"))
		_physical_skills = parsed.get("physical", {}) if typeof(parsed) == TYPE_DICTIONARY else {"_": ""}
	return _physical_skills.has(skill_name)


# A skill as it counts when USED: the trained points plus any racial bonus (Dwarf +15 Blacksmithing...). Skill-ups, caps and
# recipe minimums use the trained points alone.
func effective_skill(skill_name: String) -> int:
	return int(skill_levels.get(skill_name, 0)) + int(combat_node.race_skill_bonus.get(skill_name, 0))


func racial_skill_bonus(skill_name: String) -> int:
	return int(combat_node.race_skill_bonus.get(skill_name, 0))
#endregion

#region Faction
# Starting standings (Data/player_faction.json), then this character's own (saved: "faction_standing").
func load_faction_standing() -> void:
	var file: FileAccess = FileAccess.open("res://Data/player_faction.json", FileAccess.READ)
	if file:
		var json_data = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(json_data) == TYPE_DICTIONARY and json_data.has("factions"):
			for faction in json_data["factions"]:
				if faction.has("name") and faction.has("standing"):
					faction_standing[faction["name"]] = faction["standing"]
	var mine = Global.player_data.get("faction_standing", {})
	if typeof(mine) == TYPE_DICTIONARY:
		for name in mine:
			faction_standing[str(name)] = int(mine[name])
	_load_faction_rules()
	_refresh_faction_attitudes()


# ── Standing that changes (2026-09-25): kills (monsters.json "kill_standing"), later quests and choices ──
const STANDING_MIN := -100
const STANDING_MAX := 100
static var _faction_rules: Dictionary = {}
var race_faction_modifiers: Dictionary = {}   # this race's lean for or against factions (Data/race_faction_affiliations.json)   # standing name -> {hostile_threshold, friendly_threshold} (Data/factions.json)

## Monster factions that attack THIS player on sight / count them as an ally, from their standing. Replicated (the
## server's monsters decide who to attack by it — monster3d.gd can_see_player()).
var kos_factions: PackedStringArray = PackedStringArray()
var ally_factions: PackedStringArray = PackedStringArray()


func _load_faction_rules() -> void:
	if not _faction_rules.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://Data/factions.json")) if FileAccess.file_exists("res://Data/factions.json") else null
	if typeof(parsed) == TYPE_DICTIONARY:
		for f in parsed.get("factions", []):
			if typeof(f) == TYPE_DICTIONARY and f.has("name"):
				_faction_rules[str(f["name"])] = f


# A race's standing modifiers: {"The Moribund Order": 15, ...}. Always added on top of the saved standing, never saved.
static func race_standing_modifiers(race_key: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://Data/race_faction_affiliations.json")) if FileAccess.file_exists("res://Data/race_faction_affiliations.json") else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var key := race_key.to_lower().replace("-", "_").replace(" ", "_")
	return parsed.get("races", {}).get(key, {}).get("standing_modifiers", {})


# The standing a name really uses: a monster faction's (FACTION_STANDING_ALIASES: "Djhanid" -> "Djhanid Clans"), or an
# order's parent (factions.json type "order": Circle of Thorns -> The Verdant Kin), else the name itself.
static func standing_name(faction_name: String) -> String:
	var name: String = FACTION_STANDING_ALIASES.get(faction_name, faction_name)
	if _faction_rules.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://Data/factions.json")) if FileAccess.file_exists("res://Data/factions.json") else null
		if typeof(parsed) == TYPE_DICTIONARY:
			for f in parsed.get("factions", []):
				if typeof(f) == TYPE_DICTIONARY and f.has("name"):
					_faction_rules[str(f["name"])] = f
	var rule: Dictionary = _faction_rules.get(name, {})
	return str(rule.get("parent", name)) if str(rule.get("type", "")) == "order" else name


# Which monster factions hate / befriend this character right now.
func _refresh_faction_attitudes() -> void:
	var kos := PackedStringArray()
	var allies := PackedStringArray()
	for monster_faction in FACTION_STANDING_ALIASES:
		var name: String = FACTION_STANDING_ALIASES[monster_faction]
		var rule: Dictionary = _faction_rules.get(name, {})
		if rule.is_empty() or not faction_standing.has(name):
			continue
		var standing := get_faction_standing(name)
		if standing <= int(rule.get("hostile_threshold", -1000)):
			kos.append(monster_faction)
		elif standing >= int(rule.get("friendly_threshold", 1000)):
			allies.append(monster_faction)
	kos_factions = kos
	ally_factions = allies


# EverQuest style: "Your faction standing with the Djhanid Clans got worse." A change also ripples to that faction's
# friends and enemies (factions.json "relations": killing for the Covenant pleases the Wardens and angers the Order).
func adjust_standing(faction_name: String, delta: int, ripple := true) -> void:
	if delta == 0 or faction_name.is_empty():
		return
	_load_faction_rules()
	faction_name = standing_name(faction_name)   # an order (Circle of Thorns) moves its parent's standing
	var was_kos := kos_factions.duplicate()
	var old := int(faction_standing.get(faction_name, 0))
	var now := clampi(old + delta, STANDING_MIN, STANDING_MAX)
	faction_standing[faction_name] = now
	var saved: Dictionary = Global.player_data.get("faction_standing", {}) if typeof(Global.player_data.get("faction_standing")) == TYPE_DICTIONARY else {}
	saved[faction_name] = now
	Global.player_data["faction_standing"] = saved
	var called := faction_display_name(faction_name)
	if now == old:
		GameLog.log_general("[color=#cccccc]Your faction standing with %s could not possibly get any %s.[/color]" % [called, "better" if delta > 0 else "worse"])
	else:
		GameLog.log_general("[color=%s]Your faction standing with %s got %s.[/color]" % ["#88ccff" if delta > 0 else "#ff8866", called, "better" if delta > 0 else "worse"])
	if ripple:
		var relations: Dictionary = _faction_rules.get(faction_name, {}).get("relations", {})
		for other in relations:
			var share := int(round(delta * float(relations[other])))
			if share != 0:
				adjust_standing(str(other), share, false)
	_refresh_faction_attitudes()
	for monster_faction in kos_factions:
		if not was_kos.has(monster_faction):
			var who := faction_display_name(str(FACTION_STANDING_ALIASES.get(monster_faction, monster_faction)))
			GameLog.log_general("[color=#ff4444]%s will now attack you on sight.[/color]" % (who[0].to_upper() + who.substr(1)))
	if ripple:
		Global.save_player_data_to_file()


# "the Djhanid Clans", "The Moribund Order" (names that carry their own article keep it).
static func faction_display_name(faction_name: String) -> String:
	return faction_name if faction_name.begins_with("The ") else "the " + faction_name


# The server's kill credit carries the killed monster's standing changes ({"Djhanid Clans": -15}): applied on this
# player's own machine, which keeps their standing (sent by the server, or called directly in single-player / on the host).
@rpc("any_peer", "call_remote", "reliable")
func receive_standing_changes(changes_json: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender != 0 and sender != 1) or not is_multiplayer_authority():
		return
	var changes = JSON.parse_string(changes_json)
	if typeof(changes) != TYPE_DICTIONARY:
		return
	for name in changes:
		adjust_standing(str(name), int(changes[name]))


func get_faction_standing(faction_name: String) -> int:
	faction_name = standing_name(faction_name)
	return int(faction_standing.get(faction_name, 0)) + race_faction_offset + int(race_faction_modifiers.get(faction_name, 0))
#endregion

#region Helpers
func get_last_direction() -> Vector3:
	return last_direction
#endregion

# ================================================================================
# ⭐ EQUIPMENT
# ================================================================================

func apply_equipment(equipment: Dictionary) -> void:
	# Applies stats from save-file equipment dict (item_id strings).
	# Only used during initial load to handle old saves that stored equipment
	# as a dict of slot→item_id rather than via Inventory.equipped instances.
	var file := FileAccess.open("res://Data/items.json", FileAccess.READ)
	if not file:
		return
	var items_data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(items_data) != TYPE_DICTIONARY:
		return

	var weapon_dmg := 0
	var bonus_ac   := 0
	var stat_totals: Dictionary = {}

	for slot in equipment:
		var item_key: String = equipment[slot]
		if item_key.is_empty() or not items_data.has(item_key):
			continue
		var item = items_data[item_key]
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if slot == "primary":
			weapon_dmg = item.get("damage", 0)
		else:
			bonus_ac += item.get("armor_class", 0)
		_add_gear_stat_modifiers(item, stat_totals)

	combat_node.weapon_damage = weapon_dmg
	combat_node.gear_ac       = bonus_ac
	_apply_gear_stat_totals(stat_totals)
	combat_node._stats_dirty  = true
	combat_node.recalculate_derived_stats()


# A single equipped item's own "stat_modifiers" (items.json — e.g. a ring's {"dexterity": 1}) folded into `totals`. Shared by
# apply_equipment() (the legacy save path above) and _apply_equipment_from_inventory() (the live one below) so both feed the
# same 7 combat_node.gear_<stat> fields the same way — see their declaration in combatnode.gd for why this exists.
func _add_gear_stat_modifiers(item: Dictionary, totals: Dictionary) -> void:
	# item.get("stat_modifiers", {}) is not enough on its own — most items have the KEY present with a literal JSON `null`
	# (no bonus), and Dictionary.get()'s default only applies when the key is missing entirely, not when it's there but null.
	var raw: Variant = item.get("stat_modifiers")
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var mods: Dictionary = raw
	for stat_name in mods:
		totals[stat_name] = int(totals.get(stat_name, 0)) + int(mods[stat_name])


const GEAR_STAT_FIELDS := {
	"strength": "gear_strength", "constitution": "gear_constitution", "dexterity": "gear_dexterity",
	"intelligence": "gear_intelligence", "wisdom": "gear_wisdom", "charisma": "gear_charisma", "luck": "gear_luck",
}

func _apply_gear_stat_totals(totals: Dictionary) -> void:
	for stat_name in GEAR_STAT_FIELDS:
		combat_node.set(GEAR_STAT_FIELDS[stat_name], int(totals.get(stat_name, 0)))


func _on_equipment_changed() -> void:
	_apply_equipment_from_inventory()
	Global.save_player_data_to_file()


# A caster's Attune Spirit bound you (player_travel.gd). Runs on your own machine: it checks the caster really is a player
# standing next to you, and binds you where you stand (test 39: casters bind anyone, like EverQuest's Bind Affinity).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_bound_by() -> void:
	if not is_multiplayer_authority():
		return
	var caster := TargetFrame.peer_id_to_player_node(multiplayer.get_remote_sender_id())
	if not is_instance_valid(caster) or (caster as Node3D).global_position.distance_to(global_position) > PlayerTravel.BIND_OTHER_RANGE + 5.0:
		return
	PlayerTravel.bind_spirit(global_position, "[color=#ffdd44]%s attunes your spirit to this place. You will return here when you fall.[/color]" % TargetFrame.display_name(caster))


# Learns a skill from a scroll (items.json "teaches_skill", e.g. Cartography). False if you already know it.
func learn_skill(skill_name: String) -> bool:
	if skill_levels.has(skill_name):
		GameLog.log_general("You already know [b]%s[/b]." % skill_name.replace("_", " ").capitalize())
		return false
	skill_levels[skill_name] = 1
	if not known_skills.has(skill_name):
		known_skills.append(skill_name)
	Global.player_data["skill_levels"] = skill_levels
	Global.player_data["known_skills"] = known_skills
	GameLog.log_general("[color=#ffdd44]You have learned [b]%s[/b]![/color]" % skill_name.replace("_", " ").capitalize())
	return true


func _equipped_id(slot: String) -> String:
	var item: Variant = Inventory.equipped.get(slot, null)
	return str(item.get("item_id", "")) if typeof(item) == TYPE_DICTIONARY else ""


# A weapon poison (slot_button.gd's _apply_weapon_poison()) lasts WEAPON_POISON_DEFAULT_SECONDS of play, like a standard buff.
# The time left is stored on the weapon item itself (poison_remaining, saved with it) and only runs down while the weapon is
# equipped. A coating from before poisons expired has no timer: it gets a full one the first time it is seen.
const WEAPON_POISON_DEFAULT_SECONDS := 900.0

func _tick_weapon_poison(delta: float) -> void:
	for slot in ["primary", "secondary"]:
		var weapon: Variant = Inventory.equipped.get(slot, null)
		if typeof(weapon) != TYPE_DICTIONARY or int(weapon.get("poison_bonus_damage", 0)) <= 0:
			continue
		var left: float = float(weapon.get("poison_remaining", WEAPON_POISON_DEFAULT_SECONDS)) - delta
		if left > 0.0:
			weapon["poison_remaining"] = left
			continue
		var poison_name: String = str(weapon.get("poison_name", "The poison"))
		weapon.erase("poison_bonus_damage")
		weapon.erase("poison_name")
		weapon.erase("poison_remaining")
		GameLog.log_general("[color=#88ffaa]%s wears off your %s.[/color]" % [poison_name, weapon.get("name", "weapon")])
		_apply_equipment_from_inventory()


var _complete_sets: Array = []   # armour sets fully worn at the last equipment update (for the "set complete" message)


func _apply_equipment_from_inventory() -> void:
	if is_multiplayer_authority():
		held_gear = HeldGear.encode(_equipped_id("primary"), _equipped_id("offhand"))
	var weapon_dmg := 0
	var bonus_ac   := 0
	var stat_totals: Dictionary = {}

	for slot in Inventory.EQUIPMENT_SLOTS:
		var item: Variant = Inventory.equipped.get(slot, null)
		if item == null or typeof(item) != TYPE_DICTIONARY:
			continue
		if slot == "primary":
			weapon_dmg = item.get("damage", 0) + item.get("poison_bonus_damage", 0)
		else:
			bonus_ac += item.get("armor_class", 0)
		_add_gear_stat_modifiers(item, stat_totals)

	# A complete crafted armour set (ArmorTypes / Data/armor_sets.json) adds its bonus on top.
	var complete := ArmorTypes.complete_sets()
	for set_id in complete:
		var set_def: Dictionary = ArmorTypes.sets().get(set_id, {})
		bonus_ac += int(set_def.get("ac", 0))
		_add_gear_stat_modifiers({"stat_modifiers": set_def.get("stats", {})}, stat_totals)
		if not _complete_sets.has(set_id):
			GameLog.log_general("[color=#ffdd44]Your %s set is complete: %s.[/color]" % [set_def.get("name", set_id), ArmorTypes.bonus_text(set_id)])
	_complete_sets = complete

	_apply_gear_stat_totals(stat_totals)
	combat_node.weapon_damage = weapon_dmg
	combat_node.gear_ac       = bonus_ac
	# Swapping weapons swaps which skill counts (and unarmed uses hand_to_hand) — this used to stay on the old weapon's skill until relog.
	_sync_weapon_skill()
	_apply_baseline_weapon_skill()
	combat_node._stats_dirty  = true
	combat_node.recalculate_derived_stats()


# ================================================================================
# ⭐ PET EQUIPMENT (separate paperdoll from the player's own gear — see
# PET_EQUIPMENT_SLOTS. Equip/unequip happen via slot_button.gd's inspect
# popup buttons, not drag-and-drop, matching the rest of the item UI.)
# ================================================================================

# item comes from slot_button.gd's inspect popup (a basic_inventory or bag
# slot); src_* identify where to put the pet's previously-equipped item back.
func pet_can_equip_slot(equip_slot: String) -> bool:
	return equip_slot in PET_EQUIPMENT_SLOTS


func equip_to_pet(item: Dictionary, src_type: String, src_basic_idx: int = -1, src_bag_slot: int = -1, src_item_idx: int = -1) -> bool:
	var item_slot: String = item.get("slot", "none")
	var pet_slot: String = Inventory.ITEM_SLOT_MAP.get(item_slot, "")
	if pet_slot.is_empty() or pet_slot not in PET_EQUIPMENT_SLOTS:
		GameLog.log_general("[b]%s[/b] can't be equipped on your pet." % item.get("name", "?"))
		return false

	var displaced: Variant = pet_equipment.get(pet_slot, null)

	if src_type == "basic" and src_basic_idx >= 0:
		Inventory.basic_inventory[src_basic_idx] = displaced
	elif src_type == "bag" and src_bag_slot >= 0 and src_item_idx >= 0:
		var key := str(src_bag_slot)
		if Inventory.bag_contents.has(key):
			if displaced != null:
				Inventory.bag_contents[key][src_item_idx] = displaced
			else:
				Inventory.bag_contents[key].remove_at(src_item_idx)

	pet_equipment[pet_slot] = item
	_on_pet_equipment_changed()
	GameLog.log_general("[color=#aa88ff]Your pet is now equipped with %s.[/color]" % item.get("name", "?"))
	return true


func unequip_from_pet(slot: String) -> bool:
	var item: Variant = pet_equipment.get(slot, null)
	if item == null:
		return false
	for i in range(Inventory.BASIC_INVENTORY_SIZE):
		if Inventory.basic_inventory[i] == null:
			Inventory.basic_inventory[i] = item
			pet_equipment[slot] = null
			_on_pet_equipment_changed()
			return true
	GameLog.log_general("[color=#ff8866]Your inventory is full — can't unequip that.[/color]")
	return false


func _on_pet_equipment_changed() -> void:
	Global.player_data["pet_equipment"] = pet_equipment
	Global.save_player_data_to_file()
	Inventory.inventory_changed.emit()
	_apply_pet_gear_bonus()


func _apply_pet_gear_bonus() -> void:
	if not is_instance_valid(active_pet):
		return
	var weapon_dmg := 0
	var bonus_ac   := 0
	for slot in PET_EQUIPMENT_SLOTS:
		var item: Variant = pet_equipment.get(slot, null)
		if item == null or typeof(item) != TYPE_DICTIONARY:
			continue
		if slot == "primary":
			weapon_dmg = item.get("damage", 0)
		else:
			bonus_ac += item.get("armor_class", 0)
	if active_pet.has_method("apply_gear_bonus"):
		active_pet.apply_gear_bonus(weapon_dmg, bonus_ac)
	# and it holds them, for everyone to see (test 41)
	if is_multiplayer_authority() and "held_gear" in active_pet:
		var ids := {}
		for slot in ["primary", "offhand"]:
			var it: Variant = pet_equipment.get(slot, null)
			ids[slot] = str(it.get("item_id", "")) if typeof(it) == TYPE_DICTIONARY else ""
		# a summon that isn't a living creature (the Lightmender's Spiritual Weapon) holds nothing: its gear still counts
		var shows: bool = not (active_pet is SummonedPet and SummonedPet.HOLDS_NO_GEAR.has((active_pet as SummonedPet).kind))
		active_pet.held_gear = HeldGear.encode(ids["primary"], ids["offhand"]) if shows else ""


# ================================================================================
# ⭐ SPELL CASTING
# ================================================================================

# Spells whose in-fiction name isn't derivable from the internal snake_case
# spell_name via the usual replace("_"," ").capitalize() convention.
const SPELL_DISPLAY_NAMES := {
	"shadow_aura": "Aura of the Shadow",
	"siphon_mana": "Siphon Essence",
	"spectral_minion": "Morthan's Call",
	"phantasmal_echo": "Phantasmal Echo",
	"campfire_warmth": "Warmth of the Campfire",
	"kenjis_blessing": "Kenji's Blessing",
	"lit_torch": "Lit Torch",
	"curse_of_weakness": "Curse of Weakness",
	"deaths_echo": "Death's Echo",
	"mountains_challenge": "Mountain's Challenge",
	"focused_strike": "Focused Strike",
	"striking_serpent": "Striking Serpent",
	"dragon_fist": "Dragon Fist",
	"improved_ki_strike": "Ki Strike",          # an "improvement" of a Ki Strike the Aetherfist never had: it IS the strike
	"enhanced_mend_wounds": "Mend Wounds",      # likewise the Aetherfist's group heal itself
	"recall_to_sanctuary": "Recall to Sanctuary",
	"call_of_nature": "Call of Nature",
	"call_of_shadow": "Call of Shadow",
	"deaths_gate": "Death's Gate",
	"oath_of_return": "Oath of Return",
	"song_of_remembrance": "Song of Remembrance",
}

static func spell_display_name(spell_name: String) -> String:
	return SPELL_DISPLAY_NAMES.get(spell_name, spell_name.replace("_", " ").capitalize())


# Troubadour spells are songs, toggled rather than one-shot (2026-09-17,
# per the user's spec) — clicking one starts it "playing," auto-recasting
# itself every time its own cooldown expires (refreshing a buff
# indefinitely, or re-attempting a charm the instant it's allowed to if the
# target broke free early — see monster3d.gd's state_charmed() break-chance)
# until clicked again to stop it. `is_auto_recast` distinguishes a fresh
# user click (which toggles on/off) from the automatic re-trigger
# (_tick_cooldowns() below) so the auto-recast path never toggles itself
# off. Returns whether the cast actually went through, so the auto-recast
# loop can tell a real failure (dead target, out of mana) from "still on
# cooldown" and stop trying rather than spam every frame.
func cast_spell(spell_name: String, is_auto_recast: bool = false) -> bool:
	if _fear_time > 0.0:
		if not is_auto_recast:
			GameLog.log_combat("You are too terrified to do anything but run!")
		return false
	var spell: Dictionary = _spell_by_name.get(spell_name, {})
	if spell.is_empty():
		GameLog.log_general("Unknown spell or ability: [b]%s[/b]." % spell_display_name(spell_name))
		return false
	# Passives ("passive": true in player_spells.json) work just by being known — see CombatNode.has_passive().
	if spell.get("passive", false):
		GameLog.log_general("[b]%s[/b] is passive — it's always working, no need to cast it." % spell_display_name(spell_name))
		return false

	if player_class == "Troubadour" and not is_auto_recast and not spell.has("travel"):  # a gate is not a song
		if _active_songs.has(spell_name):
			_active_songs.erase(spell_name)
			GameLog.log_combat("You stop playing [b]%s[/b]." % spell_display_name(spell_name))
			return false
		# Only one song plays at a time (per user correction 2026-09-17 — the
		# earlier "multiple songs stack independently" design was explicitly
		# wrong): starting a new song stops every other one from
		# auto-recasting. Whatever it replaces isn't ripped away instantly —
		# its already-applied buff just runs out on its own over its
		# remaining duration, same as toggling a song off normally does.
		for other_song in _active_songs.keys():
			GameLog.log_combat("[b]%s[/b] fades as you begin a new song." % spell_display_name(other_song))
		_active_songs.clear()
		_active_songs[spell_name] = true

	# Per-class level requirement, not the flat top-level "level" field — the
	# same spell can require a different level for different classes (e.g.
	# Improved Block is Voidknight:3 but Blademaster:7), and the flat field
	# only ever reflects one of them. Falls back to the flat field only if
	# this class genuinely has no entry for it (shouldn't normally happen —
	# every learnable spell is gated to a class via this same dict already).
	var required_level: int = int(spell.get("class_level_requirements", {}).get(
		player_class, spell.get("level", 1)
	))
	if combat_node.level < required_level:
		GameLog.log_general("You must be level %d to cast [b]%s[/b]." % [required_level, spell_display_name(spell_name)])
		_active_songs.erase(spell_name)
		return false

	var cd_remaining: float = _spell_cooldowns.get(spell_name, 0.0)
	if cd_remaining > 0.0:
		if not is_auto_recast:
			GameLog.log_general("[b]%s[/b] is not ready. (%.1fs remaining)" % [spell_display_name(spell_name), cd_remaining])
		return false

	var cost: int = int(spell.get("mana_cost", 0.0))
	if cost > 0 and combat_node.get_modifier("silenced") > 0.0:   # a silence (a monster's, or a player's) stops spells, not skills
		if not is_auto_recast:
			GameLog.log_general("[color=#8888ff]You can't cast spells while silenced![/color]")
		return false
	if combat_node.current_mana < cost:
		if is_auto_recast:
			GameLog.log_combat("[color=#ff8866]You don't have enough mana to keep playing [b]%s[/b] — the song fades.[/color]" % spell_display_name(spell_name))
			_active_songs.erase(spell_name)
		else:
			GameLog.log_general("Insufficient mana to use [b]%s[/b]!" % spell_display_name(spell_name))
		return false

	if combat_node.is_casting:
		if not is_auto_recast:
			GameLog.log_general("You are already casting a spell.")
		return false

	# Travel spells (player_travel.gd): not in combat, bind cooldown, and a ritual asks where to go first.
	if spell.has("travel") and not $Travel.pre_cast(spell_name, spell):
		return false

	var display_name    := spell_display_name(spell_name)
	var spell_target    := spell.get("target", "enemy") as String
	var target_node: Node = current_target if (current_target and is_instance_valid(current_target)) else null
	# Option "detrimental spells go to my friendly target's target": with a friend (the tank) targeted, an enemy-aimed spell goes to the enemy they are fighting.
	if spell_target in ["enemy", "cone"] and target_node != null and Global.settings.get("detrimental_to_tot", false) \
			and TargetFrame.faction_status(target_node) != "Enemy":
		var their_target := TargetFrame.target_of(target_node)
		if their_target != null and TargetFrame.faction_status(their_target) == "Enemy" and _is_targetable_alive(their_target):
			target_node = their_target

	# Enemy/cone spells need a valid, hostile target to even begin casting —
	# checked again in _resolve_spell_cast() too, since a multi-second cast can
	# outlive the target (it can die, or you can lose target lock, mid-cast).
	if spell_target in ["enemy", "cone"]:
		if target_node == null:
			if not is_auto_recast:
				GameLog.log_general("No target selected for [b]%s[/b]." % display_name)
			return false
		if not _is_targetable_alive(target_node):
			if is_auto_recast:
				GameLog.log_combat("[color=#ff8866]Your target for [b]%s[/b] is gone — the song fades.[/color]" % display_name)
				_active_songs.erase(spell_name)
			else:
				GameLog.log_general("Your target is already dead.")
			return false
		if TargetFrame.faction_status(target_node) == "Ally":
			if not is_auto_recast:
				GameLog.log_general("You can't target an ally with [b]%s[/b]." % display_name)
			return false
		if _target_out_of_range(spell, target_node):
			# A song that plays on keeps trying, so it resumes when the target is back in reach: say so only now and then.
			if not is_auto_recast or Time.get_ticks_msec() - _range_warn_msec > 5000:
				_range_warn_msec = Time.get_ticks_msec()
				GameLog.log_general("[color=#ff8866]Your target is out of range for [b]%s[/b] (%d m).[/color]" % [display_name, int(spell_range_m(spell))])
			if not is_auto_recast:
				_active_songs.erase(spell_name)   # a song that never started is not "playing"
			return false

	# Begin cast message
	GameLog.log_combat(CombatLogFormatter.begin_cast("You"))

	# Commit mana and cooldown
	combat_node.current_mana -= cost
	_spell_cooldowns[spell_name] = float(spell.get("recast_time", 10.0))

	# Tick spell_casting skill
	_tick_skill("spell_casting")
	# Every Troubadour spell is a song, and playing one trains musicianship (nothing did before — it was a skill no
	# action ever raised).
	if player_class == "Troubadour":
		_tick_skill("musicianship")

	# Also tick the spell's own governing skill (e.g. necromancy, evocation,
	# mantis_fist), so schools/classifications level individually, not just
	# the broad spell_casting skill.
	var skill_category: String = spell.get("skill_category", "")
	if not skill_category.is_empty():
		_tick_skill(skill_category)

	_trigger_cast_animation(spell)

	var cast_time: float = float(spell.get("casting_time", 0.0))
	if spell.has("casting_time_max"):  # Chaos Rift: a flickering 5-8 s
		cast_time = randf_range(cast_time, float(spell["casting_time_max"]))
	if cast_time <= 0.0:
		_resolve_spell_cast(spell_name, spell, target_node)
		return true

	_pending_cast_spell = spell_name
	_pending_cast_spell_data = spell
	_pending_cast_target = target_node
	casting_spell_name = display_name
	combat_node.start_spell_cast(cast_time)
	_cast_start_pos = global_position
	if spell.has("travel"):
		$Travel.on_cast_started(spell_name, spell, cast_time)
	return true


# Runs the actual spell effect — either immediately (instant-cast spells) or
# once _tick_spell_cast() finishes counting down a real cast time. target_node
# is whatever was locked in when the cast began, not necessarily current_target
# anymore (see cast_spell() above).
func _resolve_spell_cast(spell_name: String, spell: Dictionary, target_node: Node) -> void:
	if spell.has("travel"):
		$Travel.resolve(spell_name, spell)
		return
	var display_name    := spell_display_name(spell_name)
	# An upgrade (Improved Plague Strike) runs its base spell's special code; its own numbers come from its own data.
	var spell_key := SpellInfo.root_name(spell_name)
	var school: String   = spell.get("spell_school", "magic")
	_spell_skill_category = str(spell.get("skill_category", ""))
	var spell_target    := spell.get("target", "enemy") as String
	var base_damage: int = spell.get("damage", 0)
	if stance_boosts(spell_key):
		base_damage = int(round(base_damage * (1.0 + STANCE_BOOST)))  # the stance's own element: 25% stronger
	var effect_type_raw  = spell.get("effect_type", "")
	var effect_type: String = effect_type_raw if effect_type_raw is String else ""
	# An enemy spell with an "aoe_radius" also hits every other enemy that close to its target: resolved like a cone.
	if spell_target == "enemy" and spell.has("aoe_radius"):
		spell_target = "cone"
	# A bolt or arrow spell cast at an enemy flies there first (spell_projectile.gd) and lands — damage, effects and its
	# sound at the target — when it arrives: this function runs again then, with _projectile_landing set.
	var flies: bool = not _projectile_landing and spell_target in ["enemy", "line"] \
			and target_node is Node3D and SPELL_PROJECTILE.flies(spell)
	if not flies:
		# A spell on someone else sounds from them; one on yourself plays straight in your ears (as a 3D sound at your own
		# feet it could be faint with the camera pulled back).
		var on_other: bool = is_instance_valid(target_node) and target_node != self
		Sfx.play(spell_sound(spell), target_node if on_other else null)

	# Summons with a "pet_kind" and pet buffs ("pet_buff": Beast Bond) don't need a target of their own.
	if spell.has("pet_kind"):
		_summon_from_spell(spell)
		_broadcast_combat(CombatLogFormatter.spell_cast(player_name, spell_name))
		return
	if spell.get("pet_buff", false):
		if not is_instance_valid(active_pet) or not (active_pet.get("combat_node") is CombatNode):
			GameLog.log_general("You have no companion to empower.")
			return
		active_pet.combat_node.apply_effect(spell_name, float(spell.get("duration", 15)), spell.get("modifiers", {}))
		GameLog.log_combat("[color=#88ffcc]%s is empowered.[/color]" % active_pet.pet_name)
		return

	# "reactive" spells (e.g. Improved Parry, Spell Ward) are defensive
	# self-effects by design — some have a mis-authored "enemy" target in the
	# data, so force self-targeting here rather than trusting that field for
	# this spell_type.
	if spell.get("spell_type", "") == "reactive":
		spell_target = "self"

	match spell_target:
		# No target: Shadowstep (behind your target), Swift Step (a dash) and teleports (Blink — see _teleport()).
		"none":
			if spell_name == "shadowstep":
				if target_node == null:
					GameLog.log_general("No target selected for [b]%s[/b]." % display_name)
					return
				if not _is_targetable_alive(target_node):
					GameLog.log_general("Your target is already dead.")
					return
				if TargetFrame.faction_status(target_node) == "Ally":
					GameLog.log_general("You can't target an ally with [b]%s[/b]." % display_name)
					return

				# Godot's forward convention is -Z, so the direction BEHIND a
				# node is its raw (un-negated) +Z basis vector.
				var behind_dir: Vector3 = target_node.global_transform.basis.z
				behind_dir.y = 0.0
				if behind_dir.length() < 0.01:
					behind_dir = Vector3.FORWARD
				behind_dir = behind_dir.normalized()
				var dest: Vector3 = target_node.global_position + behind_dir * 2.0
				dest.y = global_position.y
				global_position = dest

				# Face the target after teleporting, per user request — flattened
				# to horizontal only so a height difference doesn't pitch the
				# player up/down (same reasoning as monster3d.gd's look_at_target()).
				var face_pos: Vector3 = target_node.global_position
				face_pos.y = global_position.y
				look_at(face_pos, Vector3.UP)

				var stealth_duration: float = float(spell.get("duration", 30.0))
				combat_node.apply_effect("invisibility", stealth_duration, {"invisible": 1.0})
				GameLog.log_combat("[color=#8866ff]You vanish into the shadows behind %s.[/color]" % TargetFrame.display_name(target_node))
			elif spell_name == "swift_step":
				# Dash "dash_distance" metres the way you face (stopping at anything solid), then run faster for the duration.
				var ahead := -global_transform.basis.z
				ahead.y = 0.0
				move_and_collide(ahead.normalized() * float(spell.get("dash_distance", 8.0)) * (1.0 + STANCE_BOOST if stance_boosts(spell_key) else 1.0))
				combat_node.apply_effect("swift_step", float(spell.get("duration", 4.0)), spell.get("modifiers", {"move_speed_bonus": 0.15}))
				GameLog.log_combat("[color=#88ffcc]You dash forward, light on your feet.[/color]")
				_broadcast_combat("[color=#88ffcc]%s dashes forward.[/color]" % player_name)
			elif spell.get("spell_type", "") == "teleport":
				_teleport(spell_name, spell)
			else:
				GameLog.log_combat("You use [b]%s[/b]." % display_name)
			return

		"enemy", "corpse", "line":
			if target_node == null:
				GameLog.log_general("No target selected for [b]%s[/b]." % display_name)
				return
			if not _is_targetable_alive(target_node):
				GameLog.log_general("Your target is already dead.")
				return
			if TargetFrame.faction_status(target_node) == "Ally":
				GameLog.log_general("You can't target an ally with [b]%s[/b]." % display_name)
				return
			if not _projectile_landing and _target_out_of_range(spell, target_node):
				GameLog.log_general("[color=#ff8866]Your target moved out of range of [b]%s[/b].[/color]" % display_name)
				return
			if not target_node.has_method("apply_damage"):
				return
			if spell_key == "pickpocket":
				_pickpocket(target_node, spell)
				return
			# Siphon Essence: drains mana from something that has it (a player, a spell-casting monster: "casts_spells");
			# anything else loses life instead (the normal hit below, all of it returned to you by "drain_pct").
			if spell_key == "siphon_mana" and (target_node.is_in_group("player") or target_node.get("casts_spells") == true):
				var essence_cn = target_node.get("combat_node")
				if essence_cn is CombatNode:
					var siphoned := mini(int(essence_cn.current_mana), int(spell.get("effect_amount", 30)))
					essence_cn.current_mana = maxf(0.0, essence_cn.current_mana - siphoned)
					combat_node.current_mana = minf(float(combat_node.max_mana), combat_node.current_mana + siphoned)
					GameLog.log_combat("[color=#8866ff]You siphon %d mana from %s.[/color]" % [siphoned, TargetFrame.display_name(target_node)])
					if target_node.has_method("add_threat"):
						target_node.add_threat(self, combat_node.generate_threat(NO_DAMAGE_THREAT))
				return
			if spell.get("leap", false) and target_node is Node3D:
				# Flying Kick: leap to the target (stopping at anything solid in the way) and land the blow.
				var to_target: Vector3 = (target_node as Node3D).global_position - global_position
				to_target.y = 0.0
				if to_target.length() > 1.6:
					move_and_collide(to_target.normalized() * (to_target.length() - 1.4))
				var face: Vector3 = (target_node as Node3D).global_position
				face.y = global_position.y
				if face.distance_to(global_position) > 0.1:
					look_at(face, Vector3.UP)
			if flies:
				var bolt_target: Node3D = target_node
				SPELL_PROJECTILE.launch(self, bolt_target, spell, func() -> void:
					if not is_instance_valid(self) or not is_instance_valid(bolt_target) or dying:
						return
					_projectile_landing = true
					_resolve_spell_cast(spell_name, spell, bolt_target)
					_projectile_landing = false)
				return

			combat_node.break_invisibility()
			last_attack_time_ms = Time.get_ticks_msec()

			var target_cn = target_node.get("combat_node")
			var target_desc: String = _desc_of(target_node)
			_log_cast_flavor(spell_name, spell, target_desc)

			# Multi-bolt spells (Magic Missile, Arcane Barrage, Unstable
			# Missile, Chaos Barrage) — data-driven via "bolt_count" (and
			# optional "extra_bolt_chance") rather than one hardcoded case
			# per spell, so any future multi-hit spell just needs these two
			# fields. "damage" means PER-BOLT damage here, same as every
			# other spell's "damage" field means "the number this spell
			# actually hits for" — found via a user report that Magic
			# Missile's "damage" had been set to 3 (the bolt COUNT from its
			# own description) instead of 6 (the actual per-bolt damage),
			# the same authoring mix-up on all four of these spells.
			var bolt_count: int = int(spell.get("bolt_count", 1))
			if bolt_count > 1:
				_cast_multi_bolt_spell(spell_name, target_node, target_cn, target_desc,
					base_damage, bolt_count, float(spell.get("extra_bolt_chance", 0.0)), school)
				return

			# Backstab requires actually being behind the target (or stealthed —
			# its own description is "from stealth/behind target", either
			# condition works) — previously it just did its full 100 damage
			# from any angle, same as a plain nuke. Bails out entirely (no
			# damage at all) rather than a reduced "failed backstab" hit, since
			# nothing in the spell's own data describes a fallback amount.
			if spell_name == "backstab" and not (combat_node.is_stealthed() or combat_node.is_currently_invisible()):
				var to_caster: Vector3 = global_position - target_node.global_position
				to_caster.y = 0.0
				var target_forward: Vector3 = -target_node.global_transform.basis.z
				target_forward.y = 0.0
				if to_caster.length() > 0.01 and target_forward.length() > 0.01 \
						and target_forward.normalized().dot(to_caster.normalized()) > -0.5:
					GameLog.log_general("[color=#ff8866]You must be behind %s to backstab![/color]" % target_desc)
					return

			# "bonus_vs": {"undead": 0.25} — stronger against a monster category (monster3d.gd's `category`).
			var bonus_vs: Dictionary = spell.get("bonus_vs", {}) if spell.get("bonus_vs") is Dictionary else {}
			if not bonus_vs.is_empty() and "category" in target_node and bonus_vs.has(str(target_node.category)):
				base_damage = int(round(base_damage * (1.0 + float(bonus_vs[str(target_node.category)]))))
			var final_dmg: int = 0
			if base_damage <= 0:
				pass  # a debuff, snare or crowd-control spell: no hit of its own (spell power used to make every one hit for ~15)
			elif school == "physical":
				# Physical combat abilities scale with STR and are mitigated by AC
				final_dmg = base_damage + int(combat_node.strength / 2.0)
				final_dmg = int(final_dmg * (1.0 + combat_node.skill_bonus("ability_damage_pct", str(spell.get("skill_category", ""))) / 100.0))
				if target_cn is CombatNode:
					final_dmg = combat_node.apply_ac_mitigation(final_dmg, target_cn)
				final_dmg = max(1, final_dmg)
				target_node.apply_damage(final_dmg, "physical")
			else:
				# Magical spells scale with arcane/divine power and are
				# resisted by the specific damage type they deal (school
				# directly IS the resist_type — see calculate_spell_damage()).
				final_dmg = combat_node.calculate_spell_damage(base_damage, school, target_cn, false, str(spell.get("skill_category", "")))
				if combat_node.last_spell_crit:
					GameLog.log_combat("[color=#ffdd44]Your spell strikes with unusual force! (critical)[/color]")
				target_node.apply_damage(final_dmg, "magic")

			# Multiplayer: relay real damage to whoever actually owns this
			# monster's authoritative combat_node — same reasoning as
			# attack_current_target()'s melee relay. No stat-replication
			# needed since the caster's own local stats (used above) are
			# already accurate; only the resulting number needs to land on
			# the real target.
			var target_is_networked_monster: bool = target_node is Monster and not target_node.is_multiplayer_authority()
			if target_is_networked_monster and final_dmg > 0:
				target_node.apply_networked_damage.rpc_id(1, final_dmg, multiplayer.get_unique_id())

			if final_dmg > 0:
				GameLog.log_combat(CombatLogFormatter.spell_damage("You", spell_name, target_desc, final_dmg))
				_broadcast_combat(CombatLogFormatter.spell_damage(player_name, spell_name, target_desc, final_dmg))

			if target_node.has_method("add_threat"):
				target_node.add_threat(self, combat_node.generate_threat(final_dmg if final_dmg > 0 else NO_DAMAGE_THREAT))
			# "drain_pct": the caster heals for that share of the damage dealt (Life Drain, Death Coil, Harmony Blade).
			if spell.has("drain_pct") and final_dmg > 0:
				var drained := combat_node.heal(maxi(1, int(round(final_dmg * float(spell["drain_pct"])))))
				if drained > 0:
					GameLog.log_combat("[color=#66ff99]You drain [b]%d[/b] health.[/color]" % drained)
					_broadcast_combat("[color=#66ff99]%s drains [b]%d[/b] health.[/color]" % [player_name, drained])
			if spell.has("knockback") and final_dmg > 0:
				_knock_back(target_node, float(spell["knockback"]))
			# "self_buff": {"duration", "modifiers"} — a landed hit also buffs the caster (Defensive Strike, Soul Shard).
			if spell.get("self_buff") is Dictionary and final_dmg > 0:
				var self_buff: Dictionary = spell["self_buff"]
				combat_node.apply_effect(spell_name + "_self", float(self_buff.get("duration", 15.0)), self_buff.get("modifiers", {}))
			if spell.get("interrupt", false):
				# Earth Strike: cancel a spell the target is casting and hold back its next attack.
				if target_cn is CombatNode and target_cn.is_casting:
					target_cn.is_casting = false
					target_cn.current_cast_time = 0.0
				_disable_target(target_node, INTERRUPT_DELAY)
				GameLog.log_combat("[color=#ffcc66]%s is interrupted.[/color]" % target_desc.capitalize())

			match spell_key:
				"life_siphon":
					var heal_pct := randf_range(0.30, 0.70)
					var heal_amount := int(final_dmg * heal_pct * (1.0 + combat_node.get_modifier("life_drain_heal_mult")))
					var healed := combat_node.heal(heal_amount)
					if healed > 0:
						GameLog.log_combat("[color=#66ff99]You siphon life, healing yourself for [b]%d[/b].[/color]" % healed)
						_broadcast_combat("[color=#66ff99]%s siphons life, healing themself for [b]%d[/b].[/color]" % [player_name, healed])
						if target_node.has_method("add_threat"):
							target_node.add_threat(self, combat_node.generate_threat(0, healed))
				"necrotic_grasp":
					if target_cn is CombatNode:
						_buff_target(target_node, target_cn, "necrotic_grasp", 6.0, {"speed_slow": 0.15, "attack_speed_slow": 0.15})
						GameLog.log_combat("[color=#8866ff]%s is gripped by necrotic energy, slowing them.[/color]" % target_desc.capitalize())
						_broadcast_combat("[color=#8866ff]%s is gripped by necrotic energy, slowing them.[/color]" % target_desc.capitalize())
				"curse_of_weakness":
					if target_cn is CombatNode:
						_buff_target(target_node, target_cn, "curse_of_weakness", 10.0, {"damage_mult": -0.05})
						GameLog.log_combat("[color=#8866ff]%s is weakened, their attacks feeble.[/color]" % target_desc.capitalize())
						_broadcast_combat("[color=#8866ff]%s is weakened, their attacks feeble.[/color]" % target_desc.capitalize())
				"plague_strike":
					if target_cn is CombatNode:
						var plague_secs := float(spell.get("duration", 8)) if spell.has("effect_amount") else 8.0
						var plague_tick := maxi(1, int(round(float(spell["effect_amount"]) / plague_secs))) if spell.has("effect_amount") else 5
						_buff_target(target_node, target_cn, "plague_strike", plague_secs, {}, plague_tick, 1.0)
						GameLog.log_combat("[color=#77aa44]%s is wracked with plague.[/color]" % target_desc.capitalize())
						_broadcast_combat("[color=#77aa44]%s is wracked with plague.[/color]" % target_desc.capitalize())
				"soul_leech":
					if target_cn is CombatNode:
						var improved_leech := spell_name == "improved_soul_leech"
						var drained := int(target_cn.max_mana * (0.05 if improved_leech else 0.03))
						target_cn.current_mana = maxf(0.0, target_cn.current_mana - drained)
						var healed := combat_node.heal(int(drained * (0.50 if improved_leech else 0.30)))
						if healed > 0:
							GameLog.log_combat("[color=#66ff99]You leech %d mana from %s, healing yourself for [b]%d[/b].[/color]" % [drained, target_desc, healed])
							_broadcast_combat("[color=#66ff99]%s leeches %d mana from %s, healing themself for [b]%d[/b].[/color]" % [player_name, drained, target_desc, healed])
				"improved_disarm":
					if randf() < (0.60 if spell_name == "master_disarm" else 0.40):
						if "attack_timer" in target_node and "attack_cooldown" in target_node:
							_disable_target(target_node, 2.0)
						GameLog.log_combat("[color=#ffcc66]You disarm %s, disrupting their attack![/color]" % target_desc)
						_broadcast_combat("[color=#ffcc66]%s disarms %s, disrupting their attack![/color]" % [player_name, target_desc])
					else:
						GameLog.log_combat("Your disarm attempt on %s fails." % target_desc)
				"taunt", "mountains_challenge":
					if target_node is Monster and not target_node.is_multiplayer_authority():
						target_node.apply_networked_taunt.rpc_id(1, multiplayer.get_unique_id())   # the server owns the threat table
						GameLog.log_combat("[color=#ffcc66]You bellow a challenge — %s's fury turns on you![/color]" % target_desc)
						_broadcast_combat("[color=#ffcc66]%s bellows a challenge — %s's fury turns to them![/color]" % [player_name, target_desc])
					elif target_node.has_method("taunt"):
						target_node.taunt(self, 50.0 if stance_boosts(spell_key) else 1.0)  # Earth Stance: holds it on you harder
						GameLog.log_combat("[color=#ffcc66]You bellow a challenge — %s's fury turns on you![/color]" % target_desc)
						_broadcast_combat("[color=#ffcc66]%s bellows a challenge — %s's fury turns to them![/color]" % [player_name, target_desc])
				_:
					# Generic, data-driven fallback for every other spell (any
					# class) — see _apply_generic_spell_effect().
					if not _apply_generic_spell_effect(effect_type, spell, combat_node, target_cn, target_node, target_desc):
						GameLog.log_combat("You use [b]%s[/b] on %s." % [display_name, target_desc])
						_broadcast_combat("%s uses [b]%s[/b] on %s." % [player_name, display_name, target_desc])

			if not target_node.combat_node.is_alive():
				combat_node.notify_kill()
				GameLog.log_combat(CombatLogFormatter.death("You", target_desc))
				_broadcast_combat(CombatLogFormatter.death(player_name, target_desc))
				_set_target_frame(null)
				current_target = null
				autoattack_enabled = false
				GameLog.set_autoattack(false)
				# Pre-existing bug found while adding the networking relay
				# above: this branch never actually called .die() on a
				# killing blow — no loot roll, no XP, no despawn timer, ever,
				# for a kill via single-target enemy spell damage. Fixed
				# alongside the same "don't double-kill a networked monster
				# server already handles" guard the melee paths use.
				if not target_is_networked_monster and target_node.has_method("die"):
					target_node.die()

		"self":
			# One generic broadcast covers every self-cast spell (buffs,
			# wards, summons) uniformly, rather than duplicating the dozens
			# of flavor-specific "You..." lines below into third-person
			# variants one at a time — other players at least see that the
			# spell was cast; the effect-specific messages inside
			# _apply_generic_spell_effect (for spells that fall through to
			# it) broadcast their own detail on top of this.
			_broadcast_combat(CombatLogFormatter.spell_cast(player_name, spell_name))
			match spell_key:
				"shadow_aura":
					combat_node.apply_effect("shadow_aura", 900.0, {})
					GameLog.log_combat("[color=#8888ff]Shadows coil around you, throwing off nearby enemies' aim.[/color]")
				"death_pact":
					# The "oh no" button: sacrifice a living pet close by to restore 35% of your health.
					if not is_instance_valid(active_pet) or not (active_pet.get("combat_node") is CombatNode) \
							or not active_pet.combat_node.is_alive() or global_position.distance_to(active_pet.global_position) > DEATH_PACT_RANGE:
						GameLog.log_general("Your pet must be alive and within %d m to make a Death Pact." % int(DEATH_PACT_RANGE))
						return
					var sacrificed: String = active_pet.pet_name
					active_pet.die()
					var pact_healed := combat_node.heal(int(combat_node.max_hp * float(spell.get("heal_pct_max_hp", 0.35))))
					GameLog.log_combat("[color=#aa66ff]You sacrifice %s, and its life floods into you: [b]%d[/b] health.[/color]" % [sacrificed, pact_healed])
				"blood_ritual":
					var cost_hp: int = maxi(1, int(combat_node.max_hp * 0.10))
					combat_node.current_hp = maxi(1, combat_node.current_hp - cost_hp)
					combat_node.apply_effect("blood_ritual", float(spell.get("duration", 30)), {"damage_mult": 0.10})
					GameLog.log_combat("[color=#ff4444]You sacrifice %d health, empowering your attacks![/color]" % cost_hp)
				"shadowlight":
					combat_node.apply_effect("shadowlight", 900.0, {})   # 15 minutes, like every non-combat buff (test 39)
					_enable_shadowlight()
					GameLog.log_combat("[color=#8855cc]A dim violet light kindles across your weapon.[/color]")
				"spectral_minion":
					_summon_spectral_minion()
				"raise_skeleton":
					_summon_raised_skeleton()
				"phantasmal_echo":
					_summon_phantasmal_echo()
				"summon_spirit_of_the_woods":
					_summon_spirit_of_the_woods()
				"dark_pact":
					var mana_cost_extra: int = int(combat_node.max_mana * 0.05)
					combat_node.current_mana = maxf(0.0, combat_node.current_mana - mana_cost_extra)
					combat_node.apply_effect("dark_pact", 30.0, {"magic_resist_bonus": 10.0})
					GameLog.log_combat("[color=#8866ff]You forge a dark pact, warding your mind against magic.[/color]")
				"enhanced_riposte":
					combat_node.apply_effect("enhanced_riposte", 30.0, {"riposte_bonus_damage": 10.0})
					GameLog.log_combat("[color=#8888ff]Your riposte crackles with necrotic energy.[/color]")
				"shadow_ward":
					combat_node.apply_effect("shadow_ward", 8.0, {})
					combat_node.active_effects["shadow_ward"]["absorb_remaining"] = 100
					GameLog.log_combat("[color=#8866ff]A ward of shadow surrounds you, absorbing damage.[/color]")
				"blood_aegis":
					combat_node.apply_effect("blood_aegis", 6.0, {"damage_drain_pct": 0.20})
					GameLog.log_combat("[color=#ff4444]Your blood aegis stirs, ready to drink the pain you take.[/color]")
				"deaths_echo":
					combat_node.apply_effect("deaths_echo", float(spell.get("duration", 900)), {})
					GameLog.log_combat("[color=#aa88ff]Death's Echo lingers, ready to answer your next kill.[/color]")
				"deathly_visage":
					combat_node.apply_effect("deathly_visage", 900.0, {"see_invisible": 1.0})
					_enable_deathly_visage_light()
					GameLog.log_combat("[color=#88bbcc]A pale, deathly light fills your eyes — the unseen becomes visible.[/color]")
				"invisibility":
					combat_node.apply_effect("invisibility", float(spell.get("duration", 900)), {"invisible": 1.0})
					GameLog.log_combat("[color=#aaaaaa]You fade from sight...[/color]")
				_:
					if not _apply_generic_spell_effect(effect_type, spell, combat_node, combat_node, self, "yourself"):
						GameLog.log_combat("You use [b]%s[/b] on yourself." % display_name)

		# "cone" (Gravechill) — no real directional cone geometry in this codebase yet,
		# so approximated as the primary target plus any other hostile monster within
		# 4m of it (a small cleave), which reads close enough to a cone hit for testing.
		"cone":
			if target_node == null:
				GameLog.log_general("No target selected for [b]%s[/b]." % display_name)
				return
			if not _is_targetable_alive(target_node):
				GameLog.log_general("Your target is already dead.")
				return
			if TargetFrame.faction_status(target_node) == "Ally":
				GameLog.log_general("You can't target an ally with [b]%s[/b]." % display_name)
				return

			combat_node.break_invisibility()
			last_attack_time_ms = Time.get_ticks_msec()

			var cone_targets: Array = [target_node]
			for monster in get_tree().get_nodes_in_group("monsters"):
				if monster == target_node or not is_instance_valid(monster):
					continue
				if TargetFrame.faction_status(monster) == "Ally":
					continue
				if monster.global_position.distance_to(target_node.global_position) <= _aoe_radius(spell, 4.0):
					cone_targets.append(monster)

			for hit_target in cone_targets:
				if not hit_target.has_method("apply_damage"):
					continue
				var hit_cn = hit_target.get("combat_node")
				var hit_desc: String = _desc_of(hit_target)
				# Magic cones used to be computed as physical blows (strength, armour, never halved like other spells).
				var cone_dmg: int = _compute_spell_damage(base_damage, school, hit_cn) if base_damage > 0 else 0

				# Same networking relay as the "enemy" branch above — each
				# cone target needs its own check/relay since they're
				# independent monsters.
				var hit_is_networked_monster: bool = hit_target is Monster and not hit_target.is_multiplayer_authority()
				if cone_dmg > 0:
					hit_target.apply_damage(cone_dmg, "physical" if school == "physical" else "magic")
					if hit_is_networked_monster:
						hit_target.apply_networked_damage.rpc_id(1, cone_dmg, multiplayer.get_unique_id())
					GameLog.log_combat(CombatLogFormatter.spell_damage("You", spell_name, hit_desc, cone_dmg))
					_broadcast_combat(CombatLogFormatter.spell_damage(player_name, spell_name, hit_desc, cone_dmg))
				if hit_target.has_method("add_threat"):
					hit_target.add_threat(self, combat_node.generate_threat(cone_dmg if cone_dmg > 0 else NO_DAMAGE_THREAT))
				if spell.has("knockback") and cone_dmg > 0:
					_knock_back(hit_target, float(spell["knockback"]))
				if hit_cn is CombatNode:
					# Data-driven per the spell's own effect_type — was
					# previously hardcoded to always apply Gravechill's slow
					# to every cone spell regardless of caster's class/spell.
					_apply_generic_spell_effect(effect_type, spell, combat_node, hit_cn, hit_target, hit_desc)
					if not hit_cn.is_alive():
						combat_node.notify_kill()
						GameLog.log_combat(CombatLogFormatter.death("You", hit_desc))
						_broadcast_combat(CombatLogFormatter.death(player_name, hit_desc))
						if hit_target == current_target:
							_set_target_frame(null)
							current_target = null
							autoattack_enabled = false
							GameLog.set_autoattack(false)
						# Same pre-existing missing-.die() bug as the "enemy"
						# branch, fixed here too.
						if not hit_is_networked_monster and hit_target.has_method("die"):
							hit_target.die()

		# "group" is used for both single-ally heals/buffs (Spirit Mend,
		# Ancestral Guidance) and true small-radius group buffs (Earth Totem) —
		# the JSON doesn't distinguish these, so it's handled per spell_name
		# below. Ally resolution deliberately allows ANY non-Enemy target (a
		# guard, a vendor, your own pet), not just other players/party members —
		# there's no real party system yet, and letting healers test on any
		# friendly NPC is the point until one exists.
		"group":
			# All Troubadour songs are true area-effect (per user request
			# 2026-09-17: "All Troubadour buff spells are area of effect
			# spells") — every one of their "group"-targeted songs already
			# says so in its own description ("allies in 8m", "grants
			# party", etc.), unlike every OTHER class's "group"-targeted
			# spells below (Spiritweaver's spirit_mend/ancestral_guidance,
			# and 150+ single-ally heals across Lightmender/Lightsworn/
			# Blademaster/etc.), which really do mean "cast on whichever one
			# ally you have selected" despite sharing the same `target`
			# value — that's why this is gated on player_class rather than
			# changing the generic fallback everyone else also falls
			# through below.
			# Troubadour songs, and any group spell with an "aoe_radius" (group heals such as Holy Light or Meditation), reach
			# every ally that close to the caster instead of one.
			if player_class == "Troubadour" or spell.has("aoe_radius"):
				_cast_troubadour_group_song(spell_name, spell, effect_type, base_damage, display_name)
				return

			var ally_target: Node = self
			if target_node != null and is_instance_valid(target_node) and TargetFrame.faction_status(target_node) != "Enemy":
				ally_target = target_node   # an explicitly targeted friend always wins
			elif get_focus() != null:
				ally_target = get_focus()   # otherwise the focus: you are targeting an enemy (or nothing) and healing the tank
			if ally_target != self:
				if _target_out_of_range(spell, ally_target):
					GameLog.log_general("[color=#ff8866]%s is out of range of [b]%s[/b] (%d m).[/color]" % [TargetFrame.display_name(ally_target), display_name, int(spell_range_m(spell))])
					return
			var ally_cn = ally_target.get("combat_node")
			var ally_desc: String = "yourself" if ally_target == self else TargetFrame.display_name(ally_target)
			if ally_target != self:
				_log_cast_flavor(spell_name, spell, ally_desc)
			# Same "yourself" swap as _apply_generic_spell_effect's bcast_desc
			# — an ally-target broadcast naming this caster's real name when
			# the target is themself, otherwise the same name every observer
			# already sees.
			var ally_bcast_desc: String = player_name if ally_target == self else ally_desc

			match spell_key:
				"spirit_mend":
					if ally_cn is CombatNode:
						var healed: int = _heal_target(ally_target, ally_cn, base_damage)
						GameLog.log_combat("[color=#66ff99]You mend %s, restoring [b]%d[/b] health.[/color]" % [ally_desc, healed])
						_broadcast_combat(CombatLogFormatter.spell_heal(player_name, spell_name, ally_bcast_desc, healed))
				"ancestral_guidance":
					if ally_cn is CombatNode:
						_buff_target(ally_target, ally_cn, "ancestral_guidance", 8.0, {"damage_mult": 0.05})
						GameLog.log_combat("[color=#88ffcc]Ancestral spirits quicken %s.[/color]" % ally_desc)
						_broadcast_combat("[color=#88ffcc]Ancestral spirits quicken %s.[/color]" % ally_bcast_desc)
				"earth_totem":
					# True small-radius group buff: caster + any non-Enemy within 8m.
					# Other PLAYERS were missing from this scan (only pets/guards/vendors), so the totem never warded a group
					# member. A remote player owns their own combat_node, so the effect is relayed to them (_buff_target).
					var protected: Array = [self]
					for node in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("pets") + get_tree().get_nodes_in_group("npc_guard") + get_tree().get_nodes_in_group("npc_vendor"):
						if is_instance_valid(node) and node != self and global_position.distance_to(node.global_position) <= 8.0:
							protected.append(node)
					for node in protected:
						var cn = node.get("combat_node")
						if cn is CombatNode:
							if node.is_in_group("player"):
								_buff_target(node, cn, "earth_totem", 15.0, {"damage_taken_mult": 0.05})
							else:
								cn.apply_effect("earth_totem", 15.0, {"damage_taken_mult": 0.05})
					GameLog.log_combat("[color=#88cc66]You plant an Earth Totem, warding %d nearby allies.[/color]" % protected.size())
					_broadcast_combat("[color=#88cc66]%s plants an Earth Totem, warding %d nearby allies.[/color]" % [player_name, protected.size()])
				_:
					if not _apply_generic_spell_effect(effect_type, spell, combat_node, ally_cn, ally_target, ally_desc):
						GameLog.log_combat("[color=#ffdd88]You use [b]%s[/b]! Your battle cry fills the air.[/color]" % display_name)
						_broadcast_combat("[color=#ffdd88]%s uses [b]%s[/b]! Their battle cry fills the air.[/color]" % [player_name, display_name])

		# Point-blank AoE centered on the caster (e.g. Arcane Explosion) —
		# hits every hostile monster within radius, generic damage + effect.
		"pbaoe":
			combat_node.break_invisibility()
			last_attack_time_ms = Time.get_ticks_msec()
			var pbaoe_targets: Array = []
			for monster in get_tree().get_nodes_in_group("monsters"):
				if not is_instance_valid(monster):
					continue
				if TargetFrame.faction_status(monster) == "Ally":
					continue
				if global_position.distance_to(monster.global_position) <= _aoe_radius(spell, 8.0):
					pbaoe_targets.append(monster)
			# "ally_heal": the burst also heals you and every ally in the same radius (Radiant Burst).
			if spell.has("ally_heal"):
				var healed_count := 0
				var mended: Array = [self]
				for node in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("pets"):
					if is_instance_valid(node) and not mended.has(node) and global_position.distance_to(node.global_position) <= _aoe_radius(spell, 8.0):
						mended.append(node)
				for node in mended:
					var ally_cn = node.get("combat_node")
					if ally_cn is CombatNode and ally_cn.is_alive() and _heal_target(node, ally_cn, int(spell["ally_heal"])) > 0:
						healed_count += 1
				if healed_count > 0:
					GameLog.log_combat("[color=#66ff99]Radiant light mends %d %s.[/color]" % [healed_count, "ally" if healed_count == 1 else "allies"])
			if pbaoe_targets.is_empty():
				GameLog.log_general("Nothing is close enough to hit with [b]%s[/b]." % display_name)
				return
			for hit_target in pbaoe_targets:
				if not hit_target.has_method("apply_damage"):
					continue
				var hit_cn = hit_target.get("combat_node")
				var hit_desc: String = _desc_of(hit_target)
				var pbaoe_dmg: int = _compute_spell_damage(base_damage, school, hit_cn) if base_damage > 0 else 0
				var hit_is_networked_monster: bool = hit_target is Monster and not hit_target.is_multiplayer_authority()
				if pbaoe_dmg > 0:
					hit_target.apply_damage(pbaoe_dmg, "physical" if school == "physical" else "magic")
					if hit_is_networked_monster:
						hit_target.apply_networked_damage.rpc_id(1, pbaoe_dmg, multiplayer.get_unique_id())
					GameLog.log_combat(CombatLogFormatter.spell_damage("You", spell_name, hit_desc, pbaoe_dmg))
					_broadcast_combat(CombatLogFormatter.spell_damage(player_name, spell_name, hit_desc, pbaoe_dmg))
				if hit_target.has_method("add_threat"):
					hit_target.add_threat(self, combat_node.generate_threat(pbaoe_dmg if pbaoe_dmg > 0 else NO_DAMAGE_THREAT))
				if spell.has("knockback") and pbaoe_dmg > 0:
					_knock_back(hit_target, float(spell["knockback"]))
				if hit_cn is CombatNode:
					_apply_generic_spell_effect(effect_type, spell, combat_node, hit_cn, hit_target, hit_desc)
					if not hit_cn.is_alive():
						combat_node.notify_kill()
						GameLog.log_combat(CombatLogFormatter.death("You", hit_desc))
						_broadcast_combat(CombatLogFormatter.death(player_name, hit_desc))
						if hit_target == current_target:
							_set_target_frame(null)
							current_target = null
							autoattack_enabled = false
							GameLog.set_autoattack(false)
						if not hit_is_networked_monster and hit_target.has_method("die"):
							hit_target.die()

		# Chain spells (e.g. Chain Lightning) — primary target plus up to 2
		# nearby hostiles, each successive jump doing less damage.
		"chain":
			if target_node == null:
				GameLog.log_general("No target selected for [b]%s[/b]." % display_name)
				return
			if not _is_targetable_alive(target_node):
				GameLog.log_general("Your target is already dead.")
				return
			if TargetFrame.faction_status(target_node) == "Ally":
				GameLog.log_general("You can't target an ally with [b]%s[/b]." % display_name)
				return

			combat_node.break_invisibility()
			last_attack_time_ms = Time.get_ticks_msec()

			var chain_targets: Array = [target_node]
			for monster in get_tree().get_nodes_in_group("monsters"):
				if chain_targets.size() >= 3:
					break
				if monster in chain_targets or not is_instance_valid(monster):
					continue
				if TargetFrame.faction_status(monster) == "Ally":
					continue
				if monster.global_position.distance_to(target_node.global_position) <= 10.0:
					chain_targets.append(monster)

			var falloff: float = 1.0
			for hit_target in chain_targets:
				if not hit_target.has_method("apply_damage"):
					continue
				var hit_cn = hit_target.get("combat_node")
				var hit_desc: String = _desc_of(hit_target)
				var chain_dmg: int = max(1, int(_compute_spell_damage(base_damage, school, hit_cn) * falloff))
				hit_target.apply_damage(chain_dmg, "physical" if school == "physical" else "magic")
				var hit_is_networked_monster: bool = hit_target is Monster and not hit_target.is_multiplayer_authority()
				if hit_is_networked_monster and chain_dmg > 0:
					hit_target.apply_networked_damage.rpc_id(1, chain_dmg, multiplayer.get_unique_id())
				GameLog.log_combat(CombatLogFormatter.spell_damage("You", spell_name, hit_desc, chain_dmg))
				_broadcast_combat(CombatLogFormatter.spell_damage(player_name, spell_name, hit_desc, chain_dmg))
				if hit_target.has_method("add_threat"):
					hit_target.add_threat(self, combat_node.generate_threat(chain_dmg))
				if hit_cn is CombatNode:
					_apply_generic_spell_effect(effect_type, spell, combat_node, hit_cn, hit_target, hit_desc)
					if not hit_cn.is_alive():
						combat_node.notify_kill()
						GameLog.log_combat(CombatLogFormatter.death("You", hit_desc))
						_broadcast_combat(CombatLogFormatter.death(player_name, hit_desc))
						if hit_target == current_target:
							_set_target_frame(null)
							current_target = null
							autoattack_enabled = false
							GameLog.set_autoattack(false)
						if not hit_is_networked_monster and hit_target.has_method("die"):
							hit_target.die()
				falloff *= 0.7


# Shared physical/magic damage math, factored out of the "enemy" branch above
# so the newer "pbaoe"/"chain" branches don't duplicate it a third/fourth time.
# Troubadour's real "group" behavior: every song hits the caster plus every
# non-Enemy within radius (default 8m, matching most songs' own description
# text — tune per-spell via an "aoe_radius" field, same spirit as
# "cast_message", for the couple of songs whose description states a
# different number, e.g. Master Anthem's "affects 15m"). Mirrors
# earth_totem's existing radius-scan exactly, just generalized to run
# through _apply_generic_spell_effect() per recipient instead of one
# hardcoded modifier.
# Pickpocket (Shadowblade, Troubadour, Woodstalker; improved/master versions raise the odds): steals one thing the target
# would drop — a roll of its own loot table — or a few coins from a humanoid/undead with an empty roll. The chance is
# "pick_chance", "pick_hidden_chance" while you are hidden, and certain from behind the target, even mid-fight. A failed
# attempt reveals you and turns the target on you. Each enemy can be picked once per player.
func _pickpocket(target: Node, spell: Dictionary) -> void:
	var desc: String = TargetFrame.display_name(target)
	var picked_key := "picked_by_%d" % (multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1)
	if target.has_meta(picked_key):
		GameLog.log_general("You've already emptied %s's pockets." % desc)
		return
	var hidden: bool = combat_node.is_stealthed() or combat_node.is_currently_invisible()
	var chance := float(spell.get("pick_hidden_chance" if hidden else "pick_chance", 0.4))
	if _is_behind(target):
		chance = 1.0
	if randf() >= chance:
		GameLog.log_combat("[color=#ff8866]You fumble at %s's pockets — it notices you![/color]" % desc)
		combat_node.break_invisibility()
		if target is Monster and not target.is_multiplayer_authority():
			target.apply_networked_taunt.rpc_id(1, multiplayer.get_unique_id())
		elif target.has_method("taunt"):
			target.taunt(self, 1.0)
		return
	target.set_meta(picked_key, true)
	var coin_bonus := float(spell.get("pick_coin_bonus", 0.0))
	var times := 2 if randf() < float(spell.get("pick_twice_chance", 0.0)) else 1
	for i in times:
		var drops: Array = target.roll_loot() if target.has_method("roll_loot") else []
		if drops.is_empty():
			if str(target.get("category")) in ["humanoid", "undead"]:
				drops = [{"item": "copper_coin", "quantity": randi_range(2, 6) * maxi(1, int(target.get("level")))}]
			else:
				GameLog.log_general("You find nothing worth stealing on %s." % desc)
				return
		var drop: Dictionary = drops.pick_random()
		var item_id := str(drop["item"])
		var qty := int(drop.get("quantity", 1))
		if Monster.CURRENCY_MAP.has(item_id):
			qty = maxi(1, int(round(qty * (1.0 + coin_bonus))))
			Global.grant_currency(Monster.CURRENCY_MAP[item_id], qty)
			Global.play_coin_sound()
			GameLog.log_general("[color=#ffd966]You lift %d %s from %s.[/color]" % [qty, str(Monster.CURRENCY_MAP[item_id]).capitalize(), desc])
		elif Inventory.add_item(item_id, qty):
			var item_name := str(Inventory.get_item_definition(item_id).get("name", item_id.replace("_", " ").capitalize()))
			GameLog.log_general("[color=#ffd966]You lift %s from %s.[/color]" % [item_name, desc])
		else:
			GameLog.log_general("You find something on %s, but your bags are full." % desc)


# True when this player stands behind `target` (outside a 120° arc in front of it) — Backstab's rule.
func _is_behind(target: Node) -> bool:
	if not (target is Node3D):
		return false
	var to_me: Vector3 = global_position - (target as Node3D).global_position
	to_me.y = 0.0
	var facing: Vector3 = -(target as Node3D).global_transform.basis.z
	facing.y = 0.0
	return to_me.length() > 0.01 and facing.length() > 0.01 and facing.normalized().dot(to_me.normalized()) <= -0.5


# Pushes a monster `distance` metres straight away from this player (monster3d.gd knockback()); the server moves it.
func _knock_back(target: Node, distance: float) -> void:
	if not (target is Monster) or not is_instance_valid(target):
		return
	if target.is_multiplayer_authority():
		target.knockback(global_position, distance)
	else:
		target.apply_networked_knockback.rpc_id(1, global_position, distance)


# A spell's "aoe_radius" ("5m" or 5) in metres, else `fallback`.
static func _aoe_radius(spell: Dictionary, fallback: float) -> float:
	var text := str(spell.get("aoe_radius", "")).strip_edges().to_lower().trim_suffix("m")
	return text.to_float() if text.is_valid_float() else fallback


# Learns a spell (from a scroll). An upgrade ("upgrades" in player_spells.json: Improved Flurry -> Flurry of Blows) REPLACES
# the spell it improves: in the spell book, and on every action bar slot that held it. It can only be learned once you
# are the level to cast it (the base would otherwise be gone before the upgrade works). Returns whether it was learned.
func learn_spell(spell_name: String) -> bool:
	var info: Dictionary = _spell_by_name.get(spell_name, {})
	var shown := spell_display_name(spell_name)
	if known_spells.has(spell_name):
		GameLog.log_general("You already know [b]%s[/b]." % shown)
		return false
	for known in known_spells:
		if SpellInfo.counts_as(str(known)).has(spell_name):
			GameLog.log_general("You already know [b]%s[/b], which is stronger." % spell_display_name(str(known)))
			return false
	var replaces: Array = known_spells.filter(func(k): return SpellInfo.counts_as(spell_name).has(k))
	var needed := SpellInfo.required_level(info, player_class)
	var level := int(Global.player_data.get("player_level", 1))
	if not replaces.is_empty() and level < needed:
		GameLog.log_general("You must be level %d to learn [b]%s[/b] (it replaces %s)." % [needed, shown, spell_display_name(str(replaces[0]))])
		return false
	for old in replaces:
		known_spells.erase(old)
		_spell_cooldowns.erase(old)
		for slot in action_bar_slots:
			if slot is Dictionary and slot.get("type", "") == "spell" and slot.get("name", "") == old:
				slot["name"] = spell_name
	known_spells.append(spell_name)
	Global.player_data["known_spells"] = known_spells
	Global.player_data["action_bar_slots"] = action_bar_slots
	combat_node._stats_dirty = true  # passive upgrades change derived stats (block, crit)
	Global.save_player_data_to_file()
	if replaces.is_empty():
		GameLog.log_general("[color=#ffdd44]You have learned [b]%s[/b]![/color]" % shown)
	else:
		GameLog.log_general("[color=#ffdd44]You have learned [b]%s[/b]! It replaces %s.[/color]" % [shown, spell_display_name(str(replaces[0]))])
	for bar in get_tree().root.find_children("*", "ActionBar", true, false):
		bar._refresh_slots()
	return true


# Blink-style teleports: "range" metres the way you face, stopping at anything solid. (Chaos Rift used to be one of these, an
# 8 m random hop; it is now the Chaosborn's group travel ritual — player_travel.gd.)
func _teleport(_spell_name: String, spell: Dictionary) -> void:
	var distance: float = spell_range_m(spell)
	var direction := -global_transform.basis.z
	direction.y = 0.0
	move_and_collide(direction.normalized() * distance)
	GameLog.log_combat("[color=#8888ff]You blink away in a flash.[/color]")
	_broadcast_combat("[color=#8888ff]%s blinks away in a flash.[/color]" % player_name)


func _cast_troubadour_group_song(spell_name: String, spell: Dictionary, effect_type: String, base_damage: int, display_name: String) -> void:
	var radius: float = _aoe_radius(spell, 8.0)
	var recipients: Array = [self]
	for node in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("pets") + get_tree().get_nodes_in_group("npc_guard"):
		if is_instance_valid(node) and node != self and global_position.distance_to(node.global_position) <= radius:
			recipients.append(node)

	var applied_any := false
	for recipient in recipients:
		var recipient_cn = recipient.get("combat_node")
		if not (recipient_cn is CombatNode):
			continue
		var recipient_desc: String = "yourself" if recipient == self else TargetFrame.display_name(recipient)
		# "self_modifiers": the caster gets different modifiers from the rest (Commanding Presence: the group sheds threat,
		# the Blademaster draws more).
		var effect_spell := spell
		if recipient == self and spell.get("self_modifiers") is Dictionary:
			effect_spell = spell.duplicate()
			effect_spell["modifiers"] = spell["self_modifiers"]
		if _apply_generic_spell_effect(effect_type, effect_spell, combat_node, recipient_cn, recipient, recipient_desc):
			applied_any = true
	# "caster_buff": {"duration", "modifiers"} — an extra effect on the caster alone (Rallying Cry's armor).
	if spell.get("caster_buff") is Dictionary:
		var caster_buff: Dictionary = spell["caster_buff"]
		combat_node.apply_effect(spell_name + "_self", float(caster_buff.get("duration", 15.0)), caster_buff.get("modifiers", {}))
		applied_any = true

	if not applied_any:
		GameLog.log_combat("[color=#ffdd88]You use [b]%s[/b]! Your battle cry fills the air.[/color]" % display_name)
	# One cast announcement for observers regardless of how many allies were
	# actually in range — each recipient's own "you feel..." message (see
	# _apply_generic_spell_effect's self_cast_message) already covers their
	# own screen; this just tells everyone else a song was played at all.
	_broadcast_combat(CombatLogFormatter.spell_cast(player_name, spell_name))


# Fires `bolt_count` separate damage instances at one target (plus a chance
# at one more, for spells like Unstable Missile/Chaos Barrage) — each bolt
# rolls its own resist/mitigation via _compute_spell_damage() (called fresh
# per bolt, same as a real multi-hit spell should), gets its own combat log
# line/threat/relay, and the loop stops the instant the target dies so a
# lucky early bolt doesn't also log damage against a corpse.
func _cast_multi_bolt_spell(spell_name: String, target_node: Node, target_cn, target_desc: String,
		per_bolt_damage: int, bolt_count: int, extra_bolt_chance: float, school: String) -> void:
	combat_node.break_invisibility()
	last_attack_time_ms = Time.get_ticks_msec()
	var target_is_networked_monster: bool = target_node is Monster and not target_node.is_multiplayer_authority()

	var bolts := bolt_count
	if extra_bolt_chance > 0.0 and randf() < extra_bolt_chance:
		bolts += 1

	for i in range(bolts):
		if not _is_targetable_alive(target_node):
			return
		var bolt_dmg: int = _compute_spell_damage(per_bolt_damage, school, target_cn)
		target_node.apply_damage(bolt_dmg, "physical" if school == "physical" else "magic")
		if target_is_networked_monster and bolt_dmg > 0:
			target_node.apply_networked_damage.rpc_id(1, bolt_dmg, multiplayer.get_unique_id())
		GameLog.log_combat(CombatLogFormatter.spell_damage("You", spell_name, target_desc, bolt_dmg))
		_broadcast_combat(CombatLogFormatter.spell_damage(player_name, spell_name, target_desc, bolt_dmg))
		if target_node.has_method("add_threat"):
			target_node.add_threat(self, combat_node.generate_threat(bolt_dmg))

		if not target_cn.is_alive():
			combat_node.notify_kill()
			GameLog.log_combat(CombatLogFormatter.death("You", target_desc))
			_broadcast_combat(CombatLogFormatter.death(player_name, target_desc))
			_set_target_frame(null)
			current_target = null
			autoattack_enabled = false
			GameLog.set_autoattack(false)
			if not target_is_networked_monster and target_node.has_method("die"):
				target_node.die()
			return


func _compute_spell_damage(base_damage: int, school: String, target_cn) -> int:
	if school == "physical":
		var dmg: int = base_damage + int(combat_node.strength / 2.0)
		dmg = int(dmg * (1.0 + combat_node.skill_bonus("ability_damage_pct", _spell_skill_category) / 100.0))
		if target_cn is CombatNode:
			dmg = combat_node.apply_ac_mitigation(dmg, target_cn)
		return max(1, dmg)
	var dmg := combat_node.calculate_spell_damage(base_damage, school, target_cn, false, _spell_skill_category)
	if combat_node.last_spell_crit:
		GameLog.log_combat("[color=#ffdd44]Your spell strikes with unusual force! (critical)[/color]")
	return dmg


# Generic, data-driven fallback for any spell whose effect_type isn't covered
# by one of the per-spell-name special cases in _resolve_spell_cast() above.
# This is what makes a newly-added class's spells (or any future one) do
# something sensible immediately, instead of being a silent damage-only/no-op
# until someone hand-writes bespoke code for it — named special cases above
# always take priority and are untouched by this. Returns true if it
# recognized and applied the effect_type, false if the caller should fall
# back to a generic flavor-text message.
# The generic effect lines are written about a target ("Target is empowered."); cast on yourself they read "You are
# empowered." rather than "Yourself is empowered.".
func _log_effect(text: String) -> void:
	for pair in [["Yourself is ", "You are "], ["Yourself begins ", "You begin "], ["Yourself healed ", "You are healed "], ["Yourself resists ", "You resist "], ["Yourself flees ", "You flee "]]:
		text = text.replace(pair[0], pair[1])
	GameLog.log_combat(text)


func _apply_generic_spell_effect(effect_type: String, spell: Dictionary, caster_cn: CombatNode, target_cn, target_node: Node, target_desc: String) -> bool:
	if not (target_cn is CombatNode):
		return false

	var effect_name: String = spell.get("spell_name", "spell_effect")
	var duration_raw = spell.get("duration", 0)
	var duration: float = 0.0 if duration_raw is String else float(duration_raw)
	# "effect_amount" (optional) is the effect's own size when it differs from the hit's "damage" (Fire Strike: a 60-damage
	# hit plus a 25-damage burn); "heal_pct_max_hp" makes a heal a share of the target's max health (Inner Focus: 0.15).
	var magnitude: int = int(spell.get("effect_amount", spell.get("damage", 0)))
	if spell.has("heal_pct_max_hp") and target_cn is CombatNode:
		magnitude = int(round(float(target_cn.max_hp) * float(spell["heal_pct_max_hp"])))
	# "modifiers" (optional): what a buff / debuff / snare actually changes (e.g. {"dodge_bonus": 10}); without it the
	# old defaults apply (+/-5% damage, 15% slow).
	var spell_mods: Dictionary = spell.get("modifiers", {}) if spell.get("modifiers") is Dictionary else {}
	if effect_type == "heal" or effect_type == "hot":
		magnitude = int(magnitude * (1.0 + combat_node.skill_bonus("spell_potency_pct", str(spell.get("skill_category", ""))) / 100.0))

	# Racial resistance/immunity to harmful effects (Halfling's general
	# negative_effect_resist chance, Elf's root immunity, Dark Elf's blind
	# immunity) — checked against whichever entity is ON THE RECEIVING END
	# (target_cn), before any of it actually applies. "heal"/"hot"/"buff"/
	# "cure"/"absorb" are beneficial-or-neutral and never resistable this way.
	const NEGATIVE_EFFECT_TYPES := ["debuff", "dot", "snare", "stun", "fear",
		"charm", "mesmerize", "confuse", "root", "blind", "silence"]
	# "affects_only": "undead" — the effect only takes hold on that monster category (Turn Undead).
	if spell.has("affects_only") and target_node != self and str(target_node.get("category")) != str(spell["affects_only"]):
		_log_effect("[color=#88ccff]%s is unaffected.[/color]" % target_desc.capitalize())
		return false
	# "effect_chance": 0.1 — the effect only takes hold that often (Smite's blind, Entropic Blast's stun). A miss is quiet.
	if spell.has("effect_chance") and target_node != self and randf() >= float(spell["effect_chance"]):
		return true
	if effect_type in NEGATIVE_EFFECT_TYPES:
		if effect_type in ["stun", "fear", "charm", "mesmerize", "confuse", "root", "snare", "blind", "silence"] and target_cn.is_cc_immune(effect_type):
			_log_effect("[color=#88ccff]%s is immune.[/color]" % target_desc.capitalize())
			return false
		if effect_type == "root" and target_cn.race_immune_to_root:
			_log_effect("[color=#88ccff]%s is immune to being rooted.[/color]" % target_desc.capitalize())
			return false
		if effect_type == "blind" and target_cn.race_immune_to_blind:
			_log_effect("[color=#88ccff]%s is immune to blindness.[/color]" % target_desc.capitalize())
			return false
		if target_cn.rolls_resist_negative_effect():
			_log_effect("[color=#88ccff]%s resists the effect![/color]" % target_desc.capitalize())
			return false

	# These messages are all target-referential ("Target is empowered.") with
	# no "You"/"your" anywhere, so they're already safe to broadcast verbatim
	# to other players — except when target_desc is the caster's own local
	# "yourself" placeholder (self-cast spells), which would read as nonsense
	# ("Yourself is empowered.") on someone else's screen. bcast_desc swaps
	# that one case for this caster's real name; every other target already
	# names itself correctly for a third-person observer.
	var bcast_desc: String = player_name if target_desc == "yourself" else target_desc

	# Optional per-spell override for the SELF-cast case specifically (see
	# player_spells.json's "cast_message" field, e.g. Song of Courage's "You
	# feel courageous."). Written in 2nd person, so it only ever makes
	# grammatical sense on the actual recipient's own screen — only used when
	# target_desc=="yourself" (the caster IS the recipient here, so "you" is
	# correct); every other recipient in a multi-target cast, and every
	# broadcast to third-party observers, still uses the existing 3rd-person
	# "Target is empowered."-style text instead, since 2nd person wouldn't
	# make sense describing what happened to someone else.
	var self_cast_message: String = _format_cast_message(str(spell.get("cast_message", "")), str(spell.get("spell_name", "")), "yourself") if target_desc == "yourself" else ""

	match effect_type:
		"heal":
			var heal_name := spell_display_name(str(spell.get("spell_name", "")))
			_heal_spell_name = heal_name
			var healed: int = _heal_target(target_node, target_cn, magnitude)
			_heal_spell_name = ""
			if healed <= 0:
				return false
			# "You heal Zozuur for 100 with Regrowth." here; "Maedianie heals you for 100 with Regrowth." on theirs (test 42)
			var heal_msg: String = self_cast_message if not self_cast_message.is_empty() \
				else "[color=#66ff99]You heal %s for [b]%d[/b] with %s.[/color]" % [target_desc, healed, heal_name]
			_log_effect(heal_msg)
			_broadcast_combat("[color=#66ff99]%s heals %s for [b]%d[/b] with %s.[/color]" % [player_name, bcast_desc if target_desc != "yourself" else ("herself" if player_sex.to_lower() == "female" else "himself"), healed, heal_name])
			return true
		"hot":
			if duration <= 0.0:
				return false
			var ticks := maxi(1, int(round(duration)))
			var per_tick := maxi(1, int(round(float(magnitude) / ticks)))
			_buff_target(target_node, target_cn, effect_name, duration, {}, 0, 1.0, per_tick)
			var hot_msg: String = self_cast_message if not self_cast_message.is_empty() \
				else "[color=#66ff99]%s begins regenerating health.[/color]" % target_desc.capitalize()
			_log_effect(hot_msg)
			_broadcast_combat("[color=#66ff99]%s begins regenerating health.[/color]" % bcast_desc.capitalize())
			return true
		"dot":
			if duration <= 0.0:
				return false
			if str(spell.get("spell_school", "")) == "poison" and caster_cn.has_passive("enhanced_poison_making"):
				duration *= 1.25
				magnitude = int(round(magnitude * 1.25 * 1.05))  # the same damage per second for longer, plus 5%
			var ticks := maxi(1, int(round(duration)))
			var per_tick := maxi(1, int(round(float(magnitude) / ticks)))
			# "stacks": N lets the same DoT land up to N times at once (Striking Serpent's venom); each stack is its own effect.
			var stacks := int(spell.get("stacks", 1))
			if stacks > 1:
				var slot := 1
				for i in range(1, stacks + 1):
					if not target_cn.active_effects.has("%s_%d" % [effect_name, i]):
						slot = i
						break
				effect_name = "%s_%d" % [effect_name, slot]
			_buff_target(target_node, target_cn, effect_name, duration, {}, per_tick, 1.0)
			_log_effect("[color=#77aa44]%s is afflicted with a lingering effect.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#77aa44]%s is afflicted with a lingering effect.[/color]" % bcast_desc.capitalize())
			return true
		"buff":
			if duration <= 0.0:
				return false
			_buff_target(target_node, target_cn, effect_name, duration, spell_mods if not spell_mods.is_empty() else {"damage_mult": 0.05})
			var buff_msg: String = self_cast_message if not self_cast_message.is_empty() \
				else "[color=#88ffcc]%s is empowered.[/color]" % target_desc.capitalize()
			_log_effect(buff_msg)
			_broadcast_combat("[color=#88ffcc]%s is empowered.[/color]" % bcast_desc.capitalize())
			return true
		"debuff":
			if duration <= 0.0:
				return false
			_buff_target(target_node, target_cn, effect_name, duration, spell_mods if not spell_mods.is_empty() else {"damage_mult": -0.05})
			_log_effect("[color=#8866ff]%s is weakened.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#8866ff]%s is weakened.[/color]" % bcast_desc.capitalize())
			return true
		"snare":
			if duration <= 0.0:
				return false
			_buff_target(target_node, target_cn, effect_name, duration, spell_mods if not spell_mods.is_empty() else {"speed_slow": 0.15, "attack_speed_slow": 0.15})
			_log_effect("[color=#8866ff]%s is slowed.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#8866ff]%s is slowed.[/color]" % bcast_desc.capitalize())
			return true
		"stun":
			var stunned := _apply_disable_effect(duration, target_node, target_desc, "is stunned!")
			if stunned:
				_broadcast_combat("%s is stunned!" % bcast_desc.capitalize())
			return stunned
		"fear":
			if duration <= 0.0:
				return false
			if target_node.has_method("apply_fear"):
				_fear_target(target_node, duration)
				_log_effect("[color=#ffcc66]%s flees in terror![/color]" % target_desc.capitalize())
				_broadcast_combat("[color=#ffcc66]%s flees in terror![/color]" % bcast_desc.capitalize())
				return true
			var feared := _apply_disable_effect(duration, target_node, target_desc, "flees in terror!")
			if feared:
				_broadcast_combat("%s flees in terror!" % bcast_desc.capitalize())
			return feared
		"charm":
			if duration <= 0.0:
				return false
			if target_node.has_method("apply_charm"):
				_charm_target(target_node, duration)
				_open_charm_control_window(target_node)
				_log_effect("[color=#ffcc66]%s is charmed![/color]" % target_desc.capitalize())
				_broadcast_combat("[color=#ffcc66]%s is charmed![/color]" % bcast_desc.capitalize())
				return true
			var charmed := _apply_disable_effect(duration, target_node, target_desc, "is charmed!")
			if charmed:
				_broadcast_combat("%s is charmed!" % bcast_desc.capitalize())
			return charmed
		"mesmerize":
			var mesmerized := _apply_disable_effect(duration, target_node, target_desc, "is mesmerized!")
			if mesmerized:
				_broadcast_combat("%s is mesmerized!" % bcast_desc.capitalize())
			return mesmerized
		"confuse":
			var confused := _apply_disable_effect(duration, target_node, target_desc, "is confused!")
			if confused:
				_broadcast_combat("%s is confused!" % bcast_desc.capitalize())
			return confused
		"root":
			if duration <= 0.0:
				return false
			_buff_target(target_node, target_cn, effect_name, duration, {"speed_slow": 1.0})
			_log_effect("[color=#8866ff]%s is rooted in place.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#8866ff]%s is rooted in place.[/color]" % bcast_desc.capitalize())
			return true
		"blind":
			if duration <= 0.0:
				return false
			_buff_target(target_node, target_cn, effect_name, duration, {"hit_chance": -25.0})
			_log_effect("[color=#8866ff]%s is blinded.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#8866ff]%s is blinded.[/color]" % bcast_desc.capitalize())
			return true
		"silence":
			if duration <= 0.0:
				return false
			# "silenced" is a modifier flag only, same pattern as "stealthed"/
			# "see_invisible" elsewhere — no monster spellcasting exists yet
			# to consult it, but any future caster (monster or class) that
			# checks it before casting will work with zero extra wiring here.
			_buff_target(target_node, target_cn, effect_name, duration, {"silenced": 1.0})
			_log_effect("[color=#8888ff]%s is silenced.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#8888ff]%s is silenced.[/color]" % bcast_desc.capitalize())
			return true
		"cure":
			var to_remove: String = _find_debuff_to_cure(target_cn)
			if to_remove.is_empty():
				return false
			_remove_effect_from_target(target_node, target_cn, to_remove)
			_log_effect("[color=#88ffaa]%s is cleansed of %s.[/color]" % [
				target_desc.capitalize(), spell_display_name(to_remove)
			])
			_broadcast_combat("[color=#88ffaa]%s is cleansed of %s.[/color]" % [
				bcast_desc.capitalize(), spell_display_name(to_remove)
			])
			return true
		"absorb":
			if duration <= 0.0:
				return false
			# Flat damage-absorption shield, same mechanic as the hardcoded
			# Shadow Ward case above — consumed via absorb_incoming_damage().
			# Only ever self-targeted in current data (arcane_armor/ki_barrier/
			# wholeness_of_body), so no remote-player relay case exists yet;
			# the absorb_remaining pool write below would need its own RPC
			# field if a group-target absorb spell is ever added.
			var shield_mods := spell_mods.duplicate()
			shield_mods["absorb_amount"] = magnitude  # plus whatever else the shield does (reflect, slow attackers...)
			_buff_target(target_node, target_cn, effect_name, duration, shield_mods)  # reaches a remote group member too
			_log_effect("[color=#8866ff]%s is shielded, absorbing damage.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#8866ff]%s is shielded, absorbing damage.[/color]" % bcast_desc.capitalize())
			return true
	return false


# Mirrors a just-logged local combat/spell message into every other connected
# peer's own combat log via Net's RPC relay (net.gd) — GameLog itself is
# purely local, so without this a second player never sees the first
# player's attacks/spells/buffs at all. Tagged with this caster's own
# position so the receiver's existing 10m combat-visibility range
# (game_log_window.gd) applies the same as it already does for distant NPC
# fights. Callers pass an already-third-person string (actor named by
# player_name, not "You") — see CombatLogFormatter's *_broadcast/spell_cast*
# variants and _apply_generic_spell_effect's target-referential messages,
# which need no rewording since they never say "You" to begin with.
func _broadcast_combat(text: String) -> void:
	if not Net.is_multiplayer_game or text.is_empty():
		return
	Net.broadcast_combat_message(text, global_position)


# Heals/buffs targeting a REMOTE player need to land on THAT player's own
# authoritative combat_node — each player owns their own (unlike monsters,
# which are server-authoritative and relay to peer 1 via
# apply_networked_damage()). Previously this just mutated the caster's local,
# replicated *copy* of the target's combat_node, which looked right on the
# healer's own screen for a moment and then got silently overwritten by the
# next replication update from the target's real, unchanged state — the
# healed/buffed player never actually saw anything happen. Self and monster
# targets (no apply_networked_heal/_buff method) fall through to the direct
# path unchanged, so this is a no-op behavior change for every existing case.
# Known limitation, same as the damage relay: no server-side re-verification,
# and for a remote target the caster's own log line reports the requested
# amount rather than the real post-clamp result (which arrives async).
var _heal_spell_name := ""   # the heal being cast right now (its name reaches the target: "X heals you ... with Regrowth")

func _heal_target(target_node: Node, target_cn, amount: int) -> int:
	if not (target_cn is CombatNode):
		return 0
	if target_node == self or target_node.is_multiplayer_authority() \
			or not target_node.has_method("apply_networked_heal"):
		var healed: int = target_cn.heal(amount)
		if target_node.has_method("_check_bleedout_revival"):
			target_node._check_bleedout_revival()
		return healed
	target_node.apply_networked_heal.rpc_id(target_node.get_multiplayer_authority(), amount, _heal_spell_name)
	return amount


func _buff_target(target_node: Node, target_cn, effect_name: String, duration: float,
		modifiers: Dictionary, tick_dmg: int = 0, tick_interval: float = 1.0, tick_heal: int = 0) -> void:
	if not (target_cn is CombatNode):
		return
	if target_node == self or target_node.is_multiplayer_authority():
		target_cn.apply_effect(effect_name, duration, modifiers, tick_dmg, tick_interval, tick_heal)
		target_cn.effect_casters[effect_name] = player_name
		return
	if target_node.has_method("apply_networked_buff"):
		# A remote PLAYER — each player is self-authoritative, so relay to
		# their own peer specifically.
		target_node.apply_networked_buff.rpc_id(
			target_node.get_multiplayer_authority(), effect_name, duration, modifiers, tick_dmg, tick_interval, tick_heal
		)
	elif target_node.has_method("apply_networked_effect"):
		# A server-authoritative MONSTER — relay to the server (peer 1)
		# regardless of who's casting. tick_heal has no monster equivalent
		# today (no spell pairs a HoT with an enemy target), so it's dropped
		# here rather than plumbed through a signature nothing uses yet.
		target_node.apply_networked_effect.rpc_id(1, effect_name, duration, modifiers, tick_dmg, tick_interval)
	else:
		target_cn.apply_effect(effect_name, duration, modifiers, tick_dmg, tick_interval, tick_heal)


# fear/charm use their own dedicated apply_fear()/apply_charm() methods on
# Monster (not the generic apply_effect() apply_networked_buff()/
# apply_networked_effect() route) — same relay reasoning, own RPCs
# (monster3d.gd's apply_networked_fear()/apply_networked_charm()).
func _fear_target(target_node: Node, duration: float) -> void:
	if target_node.is_multiplayer_authority() or not target_node.has_method("apply_networked_fear"):
		target_node.apply_fear(duration)
		return
	target_node.apply_networked_fear.rpc_id(1, duration)


# apply_charm() takes an owner Node, which (per this project's own rule —
# a Node reference means nothing across machines) can't cross the wire as-is,
# so the RPC carries this caster's own peer id instead and the server
# resolves it back to a real local player Node — see
# monster3d.gd's apply_networked_charm()/_resolve_peer_to_player().
func _charm_target(target_node: Node, duration: float) -> void:
	if target_node.is_multiplayer_authority() or not target_node.has_method("apply_networked_charm"):
		target_node.apply_charm(duration, self)
		return
	target_node.apply_networked_charm.rpc_id(1, duration, multiplayer.get_unique_id())


# Spirit Link: `amount` of a blow this linked player took is spread over the rest of the group within SPIRIT_LINK_RANGE
# (on each member's own machine). With nobody close enough, it lands on this player after all.
const SPIRIT_LINK_RANGE := 30.0

func share_damage_with_group(amount: int) -> void:
	var others: Array = []
	for peer in group_members:
		var member := _peer_id_to_player_node(peer)
		if is_instance_valid(member) and member != self and (member as Node3D).global_position.distance_to(global_position) <= SPIRIT_LINK_RANGE:
			others.append(member)
	if others.is_empty():
		combat_node.current_hp -= amount
		return
	var each := maxi(1, int(ceil(float(amount) / others.size())))
	for member in others:
		if member.is_multiplayer_authority():
			member.receive_shared_damage(each, player_name)
		else:
			member.apply_networked_shared_damage.rpc_id(member.get_multiplayer_authority(), each, player_name)
	GameLog.log_combat("[color=#88ccff]The spirit link spreads %d of the blow across your group.[/color]" % amount)


func receive_shared_damage(amount: int, from_name: String) -> void:
	if dying:
		return
	combat_node.current_hp -= amount
	GameLog.log_combat("[color=#88ccff]You take %d damage through the spirit link to %s.[/color]" % [amount, from_name])
	if not combat_node.is_alive():
		die(null)


@rpc("any_peer", "call_remote", "reliable")
func apply_networked_shared_damage(amount: int, from_name: String) -> void:
	if is_multiplayer_authority():
		receive_shared_damage(amount, from_name)


@rpc("any_peer", "call_remote", "reliable")
func apply_networked_heal(amount: int, spell_name: String = "") -> void:
	if not is_multiplayer_authority():
		return
	var healed := combat_node.heal(amount)
	if healed > 0:
		var healer := TargetFrame.peer_id_to_player_node(multiplayer.get_remote_sender_id())
		var who := TargetFrame.display_name(healer) if is_instance_valid(healer) else "Someone"
		if spell_name.is_empty():
			GameLog.log_combat("[color=#66ff99]%s heals you for [b]%d[/b].[/color]" % [who, healed])
		else:
			GameLog.log_combat("[color=#66ff99]%s heals you for [b]%d[/b] with %s.[/color]" % [who, healed, spell_name])
	_check_bleedout_revival()


# Per user request (2026-09-17): another player healing (spell or bandage) a
# downed ally should be able to bring them back before their bleed-out timer
# expires, not just watch it run out. Only ever meaningful here — a
# single-player game has no one else to heal you, and a player can't act
# (including casting a heal on themselves) while dying is true, so this is
# only ever reached via someone ELSE'S heal landing, whether relayed here via
# apply_networked_heal() or applied directly in _heal_target() (single
# authority/testing edge case).
func _check_bleedout_revival() -> void:
	if not dying or combat_node.current_hp <= 0:
		return
	dying = false
	is_incapacitated = false
	if animation_player and str(animation_player.current_animation).begins_with("death") and animation_player.is_playing():
		animation_player.stop()
	var msg := "[color=#88ff88][b]%s[/b] comes back to life![/color]" % player_name
	GameLog.log_combat(msg)
	_broadcast_combat(msg)


# "cure"/dispel spells (Remove Curse, Purify) — previously effect_type: null
# in the data, so they were pure flavor text with no actual behavior at all,
# even single-player. Picks the first active_effects entry whose *originating
# spell* was enemy-targeted (same "target says whether it's harmful" signal
# buff_bar.gd's debuff-highlight uses) rather than trying to name specific
# curse effects — works for any current or future debuff without per-spell
# wiring, matching this whole engine's approach.
func _find_debuff_to_cure(target_cn) -> String:
	if not (target_cn is CombatNode):
		return ""
	for effect_name in target_cn.active_effects.keys():
		var spell: Dictionary = _spell_by_name.get(effect_name, {})
		if (not spell.is_empty() and spell.get("target", "") == "enemy") or MONSTER_AILMENTS.has(effect_name):
			return effect_name
	return ""


# Harmful effects monsters leave on players (monsters.json "on_hit_effect") that cure spells remove.
const MONSTER_AILMENTS := ["weak_poison", "disease", "strong_poison", "weakening_venom", "sundered_armor", "crippled", "blinded",
		"dazed", "withering_touch", "bleeding", "grave_miasma", "ensnared", "silenced", "cursed", "burning", "chilled", "terrified", "shaken"]


func _remove_effect_from_target(target_node: Node, target_cn, effect_name: String) -> void:
	if not (target_cn is CombatNode):
		return
	if target_node == self or target_node.is_multiplayer_authority():
		target_cn.remove_effect(effect_name)
		return
	if target_node.has_method("apply_networked_remove_effect"):
		target_node.apply_networked_remove_effect.rpc_id(target_node.get_multiplayer_authority(), effect_name)


@rpc("any_peer", "call_remote", "reliable")
func apply_networked_remove_effect(effect_name: String) -> void:
	if not is_multiplayer_authority():
		return
	combat_node.remove_effect(effect_name)


@rpc("any_peer", "call_remote", "reliable")
func apply_networked_buff(effect_name: String, duration: float, modifiers: Dictionary,
		tick_dmg: int, tick_interval: float, tick_heal: int) -> void:
	if not is_multiplayer_authority():
		return
	combat_node.apply_effect(effect_name, duration, modifiers, tick_dmg, tick_interval, tick_heal)
	var caster := TargetFrame.peer_id_to_player_node(multiplayer.get_remote_sender_id())
	if is_instance_valid(caster):
		combat_node.effect_casters[effect_name] = str(caster.get("player_name"))   # who sent it: the tooltip's "Caster:"


# stun/fear/charm/mesmerize/confuse are mechanically distinct in a full CC
# system (fear should make the target flee rather than just freeze, charm
# should temporarily flip its allegiance, mesmerize should break on damage,
# confuse should randomize its actions) — none of that machinery exists yet,
# so all five share this one honest approximation for now: the target simply
# can't attack for the duration, same mechanism as the existing Improved
# Disarm stagger. Flavor text still differs per effect_type so it reads
# correctly in the log even though the underlying behavior is identical.
# Upgrade candidate once real CC-specific behavior is worth building.
func _apply_disable_effect(duration: float, target_node: Node, target_desc: String, verb: String) -> bool:
	if duration <= 0.0 or not ("can_attack" in target_node and "attack_timer" in target_node):
		return false
	_disable_target(target_node, duration)
	GameLog.log_general("[color=#ffcc66]%s %s[/color]" % [target_desc.capitalize(), verb])
	return true


func _disable_target(target_node: Node, duration: float) -> void:
	var cn = target_node.get("combat_node") if "combat_node" in target_node else null
	if cn is CombatNode and cn.is_cc_immune():
		return  # CC immunity (a monster buff, or a player's Zen Focus)
	if target_node.is_multiplayer_authority() or not target_node.has_method("apply_networked_disable"):
		target_node.can_attack = false
		target_node.attack_timer = duration
		if target_node.has_method("interrupt_cast"):
			target_node.interrupt_cast(duration)   # a stun or bash breaks a monster's spell
		return
	target_node.apply_networked_disable.rpc_id(1, duration)


# Actual point light (not just a "see invisible" flag) so it doubles as real
# night vision — 10m range, matching the spell's stated radius. Left attached
# and just toggled invisible/visible off the "deathly_visage" active_effect
# rather than freed on expiry, so recasting doesn't need to recreate it.
func _enable_deathly_visage_light() -> void:
	if not is_instance_valid(_deathly_visage_light):
		_deathly_visage_light = OmniLight3D.new()
		_deathly_visage_light.light_color = Color(0.65, 0.85, 1.0)
		_deathly_visage_light.light_energy = 1.2
		_deathly_visage_light.omni_range = 10.0
		_deathly_visage_light.position = Vector3(0, 1.5, 0)
		add_child(_deathly_visage_light)
	_deathly_visage_light.visible = true


# Same "real light, toggled off the active_effect rather than freed on
# expiry" pattern as _enable_deathly_visage_light() above — dimmer and
# shorter-range, matching shadowlight's own flavor ("a dim violet light...
# on your weapon or hand") rather than deathly_visage's room-illuminating
# night vision.
func _enable_shadowlight() -> void:
	pass  # the light itself is the shared carried light (see _update_light_logic): same as a torch, in violet


# pet_type keys into PET_SCENES and is saved to Global.player_data so
# _restore_pet_if_saved() knows which scene to bring back on next login —
# before phantasmal_echo, only one pet type ever existed so this field didn't
# need to exist yet.
const PET_SCENES := {
	"spectral_minion": "res://Scenes/pet_minion.tscn",
	"raised_skeleton": "res://Scenes/pet_minion.tscn",
	"phantasmal_echo": "res://Scenes/phantasmal_echo_pet.tscn",
	"spirit_of_the_woods": "res://Scenes/wildspeaker_pet.tscn",
	"summoned": "res://Scenes/summoned_pet.tscn",  # every other summon: a borrowed monster model (summoned_pet.gd)
}

# Gravecaller's raise_skeleton spell is explicitly the same skeleton thrall
# as Voidknight's spectral_minion (same scene/model/voice — see PET_SCENES
# above), just tankier per its own spell description ("80% caster's
# health" vs. spectral_minion's base PetMinion default of 40% — see
# pet_minion.gd's hp_percent_of_caster). Applied in _build_pet() before
# setup() runs, since setup() is what actually reads the percentage.
const PET_HP_PERCENT_OVERRIDES := {
	"raised_skeleton": 0.8,
}

# Spawns through $PetSpawner (a MultiplayerSpawner) instead of directly
# instantiating, so every connected peer gets an identical, replicated copy
# of the pet — previously a remote player's pet was invisible to everyone
# else. _build_pet() below (the spawn_function) does the actual node
# construction, running on every peer alike.
func _summon_pet(pet_type: String, preset_name: String = "", extra: Dictionary = {}) -> void:
	if is_instance_valid(active_pet):
		active_pet.queue_free()
	if is_instance_valid(active_pet_frame):
		active_pet_frame.queue_free()

	var data := {"pet_type": pet_type, "preset_name": preset_name}
	data.merge(extra)
	$PetSpawner.spawn(data)


# A summon spell with a "pet_kind" (Summon Ghoul, Call Companion, Summon Wraith...): see summoned_pet.gd.
func _summon_from_spell(spell: Dictionary) -> void:
	_summon_pet("summoned", "", {
		"kind": str(spell.get("pet_kind", "wolf")),
		"hp_pct": float(spell.get("pet_hp_pct", 0.4)),
		"duration": float(spell.get("pet_duration", 0.0)),
		"damage_mult": float(spell.get("pet_damage_mult", 1.0)),
		"crit_bonus": float(spell.get("pet_crit_bonus", 0.0)),
	})


func _summon_spectral_minion(preset_name: String = "") -> void:
	_summon_pet("spectral_minion", preset_name)


func _summon_raised_skeleton(preset_name: String = "") -> void:
	_summon_pet("raised_skeleton", preset_name)


func _summon_phantasmal_echo(preset_name: String = "") -> void:
	_summon_pet("phantasmal_echo", preset_name)


func _summon_spirit_of_the_woods(preset_name: String = "") -> void:
	_summon_pet("spirit_of_the_woods", preset_name)


# Runs on every peer as part of $PetSpawner's replication (mirrors
# multiplayer_player_spawner.gd's _spawn_player()) — builds an identical
# local pet node everywhere. Authority matches the OWNING PLAYER's own peer
# id (every peer independently sets the same value here, the same way
# _spawn_player() does for players) rather than always the server like
# monsters — a pet belongs to a specific player, not the world. HUD frame /
# save data / the "You..." flavor message only happen for the owner's own
# client (is_multiplayer_authority()) — other peers get the replicated pet
# itself (visible, fighting, healing) but not the owner-only UI/state.
func _build_pet(data: Dictionary) -> Node:
	var pet_type: String = str(data.get("pet_type", ""))
	var preset_name: String = str(data.get("preset_name", ""))

	var pet: Node = load(PET_SCENES[pet_type]).instantiate()
	pet.set_multiplayer_authority(get_multiplayer_authority())
	if PET_HP_PERCENT_OVERRIDES.has(pet_type):
		pet.hp_percent_of_caster = PET_HP_PERCENT_OVERRIDES[pet_type]
	if pet is SummonedPet:
		pet.configure(data)
	pet.setup(self, preset_name)
	active_pet = pet
	pet.dismissed.connect(_on_pet_gone)
	pet.died.connect(_on_pet_gone)
	pet.died.connect(_on_pet_died)

	if is_multiplayer_authority():
		_apply_pet_gear_bonus()

		# A timed summon (a 20-second wolf) isn't brought back at the next login; a lasting one is, with its spawn data.
		var timed: bool = pet is SummonedPet and pet.is_timed()
		Global.player_data["pet_active"] = not timed
		Global.player_data["pet_type"] = pet_type
		Global.player_data["pet_name"] = pet.pet_name
		var spawn_extra := data.duplicate()
		spawn_extra.erase("pet_type")
		spawn_extra.erase("preset_name")
		Global.player_data["pet_spawn"] = spawn_extra
		Global.save_player_data_to_file()
		_apply_saved_pet_mode(pet)

		var frame: Node = load("res://Scenes/pet_frame.tscn").instantiate()
		frame.add_to_group("game_hud")
		get_tree().root.add_child(frame)
		frame.set_pet(pet)
		active_pet_frame = frame

		match pet_type:
			"phantasmal_echo":
				GameLog.log_general("[color=#aa88ff]You call forth a Phantasmal Echo — %s drifts to your side, ready to mend and strike.[/color]" % pet.pet_name)
			"raised_skeleton":
				GameLog.log_general("[color=#aa88ff]You tear %s from the grave to fight at your side.[/color]" % pet.pet_name)
			"summoned":
				GameLog.log_general("[color=#aa88ff]%s answers your call.[/color]" % pet.pet_name)
			_:
				GameLog.log_general("[color=#aa88ff]You invoke Morthan's Call — %s rises to fight at your side.[/color]" % pet.pet_name)

	return pet


# Re-applies whichever of Follow/Guard/Assist/Sit was last commanded (see
# pet_minion.gd's _persist_mode()) on every fresh summon, not just the
# restore-on-login case below — so dismissing a Guard-mode pet and recasting
# the spell doesn't silently reset it back to Follow. PetState.ATTACK is
# never actually persisted (see _persist_mode()), so it's covered by the
# same default-to-Follow branch as an unset value.
func _apply_saved_pet_mode(pet: Node) -> void:
	# int(): a mode read back from the save file is a float (JSON has only one kind of number), and a float never matches these int cases,
	# so every login used to put the pet back in Follow whatever it was in when you logged out.
	match int(Global.player_data.get("pet_mode", 0)):
		2: pet.cmd_sit()
		3: pet.cmd_guard()
		4: pet.cmd_assist()
		_: pet.cmd_follow()


# Fires on death (pet_minion.gd's died signal) and on Dismiss (dismissed
# signal) alike — either way the pet is gone voluntarily/in combat, so it
# shouldn't come back on next login. Deliberately NOT tied to tree_exited:
# that also fires when the whole zone (pet included) is freed during a scene
# change (/camp, /exit, Save & Exit), which was overwriting a correct
# "pet is still alive" save with "gone" right after logging out with a live
# pet — the exact bug this signal split fixes.
func _on_pet_gone() -> void:
	Global.player_data["pet_active"] = false
	Global.save_player_data_to_file()


# Only on an actual death (not Dismiss, not logging out with a pet out) —
# whatever gear was equipped on the pet is lost with it, same idea as the
# pet's own HP being at risk.
func _on_pet_died() -> void:
	var had_gear := false
	for slot in PET_EQUIPMENT_SLOTS:
		if pet_equipment.get(slot, null) != null:
			had_gear = true
		pet_equipment[slot] = null
	if had_gear:
		GameLog.log_general("[color=#ff6666]Your pet's equipment is lost along with it.[/color]")
	Global.player_data["pet_equipment"] = pet_equipment
	Global.save_player_data_to_file()


# Called once from _ready() after load_player_data_from_global() — brings the
# pet back on login instead of it just being gone, keeping its saved name so
# it reads as the same pet rather than a freshly re-rolled one. Full HP, not
# whatever it was at logout — pets aren't saved mid-fight, only "had one out."
func _restore_pet_if_saved() -> void:
	if Global.player_data.get("pet_active", false):
		_summon_pet(Global.player_data.get("pet_type", "spectral_minion"), Global.player_data.get("pet_name", ""), Global.player_data.get("pet_spawn", {}))


func _default_action_bar_slots() -> Array:
	var slots: Array = []
	for s in known_spells:
		slots.append({"type": "spell", "name": s})
	while slots.size() < 12:
		slots.append({"type": "", "name": ""})
	return slots


func use_skill(skill_name: String) -> void:
	if not _skill_data.has(skill_name):
		GameLog.log_general("Unknown skill: %s" % skill_name)
		return
	var cd: float = _skill_cooldowns.get(skill_name, 0.0)
	if cd > 0.0:
		GameLog.log_general("[b]%s[/b] not ready (%.1fs)" % [skill_name.replace("_", " ").capitalize(), cd])
		return
	# Placeholder — active effects implemented per-skill later
	_skill_cooldowns[skill_name] = 6.0
	GameLog.log_combat("You use [b]%s[/b]!" % skill_name.replace("_", " ").capitalize())


# Advances the real cast-time delay started by cast_spell() below. Runs every
# physics frame rather than a signal/timer node so cast_bar.gd can just read
# combat_node.is_casting/current_cast_time/total_cast_time directly, same
# pattern as every other HUD bar polling player state.
func _tick_spell_cast(delta: float) -> void:
	if not combat_node.is_casting:
		return
	# Moving breaks a cast (walking, being knocked back, falling) — except for a Troubadour, whose songs are sung on the move.
	if (player_class != "Troubadour" or _pending_cast_spell_data.has("travel")) and Vector2(global_position.x - _cast_start_pos.x, global_position.z - _cast_start_pos.z).length() > CAST_MOVE_TOLERANCE:
		GameLog.log_general("[color=#ff8866]You moved, and your spell fizzles.[/color]")
		Sfx.play("spell_fizzle")
		_stop_all_casting_except_songs()
		return
	combat_node.current_cast_time += delta
	if combat_node.current_cast_time < combat_node.total_cast_time:
		return
	combat_node.is_casting = false
	var spell_name := _pending_cast_spell
	var spell: Dictionary = _pending_cast_spell_data
	# The target (a pet, a monster) can die/be freed during the cast — passing
	# a freed object into _resolve_spell_cast()'s typed Node parameter crashes
	# outright ("previously freed" error) rather than failing gracefully, so
	# it has to be caught here, before the call, not inside it.
	var target_node: Node = _pending_cast_target if is_instance_valid(_pending_cast_target) else null
	_pending_cast_spell = ""
	_pending_cast_spell_data = {}
	_pending_cast_target = null
	casting_spell_name = ""
	_resolve_spell_cast(spell_name, spell, target_node)


# Called from take_damage()/on_combat_node_hit() whenever this player is hit
# while mid-cast. Reuses combat_node.interrupt_spell()'s concentration-check
# scaffolding (previously wired up nowhere) rather than inventing a second
# interrupt system.
func _check_spell_interrupt(attacker: Node) -> void:
	if not combat_node.is_casting:
		return
	var mana_cost: int = int(_pending_cast_spell_data.get("mana_cost", 0.0))
	var attacker_cn: CombatNode = attacker.get("combat_node") if (attacker and is_instance_valid(attacker)) else null
	var result: Dictionary = combat_node.interrupt_spell(attacker_cn, mana_cost)
	match result.get("result", ""):
		"CONCENTRATION_SUCCESS":
			GameLog.log_general("[color=#88ccff]%s[/color]" % result.get("message", ""))
			_tick_skill("concentration")  # keeping your focus under fire is what trains it
			_tick_skill("channeling")
		"CONCENTRATION_FAILURE":
			GameLog.log_general("[color=#ff8866]%s[/color]" % result.get("message", ""))
			Sfx.play("spell_fizzle")
			if _pending_cast_spell_data.has("travel"):
				$Travel.on_cast_stopped()
			_pending_cast_spell = ""
			_pending_cast_spell_data = {}
			_pending_cast_target = null
			casting_spell_name = ""


func _tick_cooldowns(delta: float) -> void:
	for spell_name in _spell_cooldowns.keys():
		_spell_cooldowns[spell_name] = maxf(_spell_cooldowns[spell_name] - delta, 0.0)
	for skill_name in _skill_cooldowns.keys():
		_skill_cooldowns[skill_name] = maxf(_skill_cooldowns[skill_name] - delta, 0.0)
	for target_id in _appraisal_cooldowns.keys():
		_appraisal_cooldowns[target_id] = maxf(_appraisal_cooldowns[target_id] - delta, 0.0)

	if not _active_songs.is_empty():
		_tick_active_songs()


# Auto-recasts any toggled-on song the instant its own cooldown clears —
# checked every frame (not edge-triggered) so a transient failure (still
# mid-cast-animation from a just-fired recast) naturally retries next frame
# instead of getting stuck forever; a genuine failure (dead target, no mana)
# removes the spell from _active_songs inside cast_spell() itself, so this
# loop stops retrying on its own once that happens.
func _tick_active_songs() -> void:
	for spell_name in _active_songs.keys().duplicate():
		if _spell_cooldowns.get(spell_name, 0.0) <= 0.0:
			cast_spell(spell_name, true)


func _tick_active_spell_effects(_delta: float) -> void:
	# shadow_aura: continuously debuff accuracy of nearby monsters while active
	if combat_node.has_effect("shadow_aura"):
		for monster in get_tree().get_nodes_in_group("monsters"):
			if monster.get("current_state") == monster.State.DEAD:
				continue
			if global_position.distance_to(monster.global_position) <= 10.0:
				var mob_cn = monster.get("combat_node")
				if mob_cn is CombatNode:
					_buff_target(monster, mob_cn, "shadow_aura_debuff", 1.5, {"hit_chance": -5.0, "damage_mult": -0.05} if combat_node.has_passive("improved_shadow_aura") else {"hit_chance": -5.0})


# How far a skill can be trained at the character's current level (Data/combat_balance.json: skill_cap_per_level,
# 4 = level 1 caps at 4 points, level 10 at 40), never above the absolute _skill_max and never BELOW what the skill
# already is (starting skills above the cap wait for the level to catch up; nothing is ever lowered).
const MEDITATION_REGEN_PER_POINT := 0.05   # +5% mana per tick per point of meditation while sitting (skill 16 = +80%)


func meditation_regen_multiplier() -> float:
	var points := int(skill_levels.get("meditation", 0))
	return 1.0 + points * MEDITATION_REGEN_PER_POINT * (1.0 if is_sitting else 0.25)


func skill_cap_for(current: int) -> int:
	var per_level := int(CombatBalance.num("skill_cap_per_level"))
	if per_level <= 0:
		return _skill_max
	return mini(_skill_max, maxi(int(combat_node.level) * per_level, current))


# A weapon in the primary hand AND a weapon in the off hand (a shield is not a weapon). Dual wield only trains with both.
func is_dual_wielding() -> bool:
	var main: Variant = Inventory.equipped.get("primary", null)
	var off: Variant = Inventory.equipped.get("offhand", null)
	return typeof(main) == TYPE_DICTIONARY and str(main.get("type", "")) == "weapon" \
			and typeof(off) == TYPE_DICTIONARY and str(off.get("type", "")) == "weapon"


# gain_mult scales the skill-up chance: tradeskills pass 1.0 for a success, 0.25 for a failed craft (Crafting.xlsx Rules).
func _tick_skill(skill_name: String, gain_mult: float = 1.0) -> void:
	if skill_name.is_empty() or skill_name == "none":
		return
	if skill_name == "dual_wield" and not is_dual_wielding():
		return   # it used to rise from casting Blade Dance with nothing in your hands
	# Previously required the skill to already be in skill_levels — meaning a
	# class could only ever level the handful of skills it happened to start
	# with (build_starting_skill_levels()), so e.g. a Blademaster who picked
	# up a 2h weapon their class never started with would stay stuck at 0
	# skill in it forever, regardless of how much they used it. Any
	# recognized physical/magic/crafting skill (see _valid_skill_names,
	# loaded from player_skills.json) can now start accruing from 0 the first
	# time it's actually used, same as real EQ-style "use it to raise it."
	if not skill_levels.has(skill_name):
		if not _valid_skill_names.get(skill_name, false):
			return
		skill_levels[skill_name] = 0
		if not known_skills.has(skill_name):
			known_skills.append(skill_name)  # so abilities_book.gd's skill list actually shows it
	var current: int = skill_levels[skill_name]
	var cap: int = skill_cap_for(current)
	if current >= cap:
		return
	var chance: float = 0.15 * (1.0 - float(current) / float(cap)) * gain_mult * race_skill_gain_mult
	if race_combat_skill_gain_mult != 1.0 and _is_physical_skill(skill_name):
		chance *= race_combat_skill_gain_mult
	if randf() < chance:
		skill_levels[skill_name] += 1
		GameLog.log_general("You've become better at [b]%s[/b]! (%d)" % [
			skill_name.replace("_", " ").capitalize(), skill_levels[skill_name]
		])
		_sync_weapon_skill()
		combat_node.skills = skill_levels
		combat_node._stats_dirty = true  # dodge/parry/crit/... are derived from skills now
		Global.player_data["skill_levels"] = skill_levels


# Dispatches to Aetherfist's multi-attack flurry (resolve_aetherfist_attack())
# instead of a plain resolve_attack() for that class specifically, and
# normalizes its differently-shaped "AETHERFIST_FLURRY" result (total_damage/
# attack_count instead of a single damage) back into an ordinary HIT-shaped
# dict so every caller downstream (weapon-skill tick, damage relay, threat,
# kill check, combat log) keeps working unchanged for every class. Was
# previously fully dead code — Aetherfist got a single plain swing like every
# other melee class and never got its Double/Triple Attack at level 10+/15+.
func _resolve_melee_attack(target_cn: CombatNode) -> Dictionary:
	if player_class != "Aetherfist":
		return combat_node.resolve_attack(target_cn)

	var result: Dictionary = combat_node.resolve_aetherfist_attack(target_cn)
	if result["result"] != "AETHERFIST_FLURRY":
		return result  # MISS/PARRY/DODGE/BLOCK/RIPOSTE — same shape as normal

	if result["attack_count"] > 1:
		GameLog.log_combat("[color=#ffdd88]%s[/color]" % result["message"])
		_tick_skill("double_attack")
		if result["attack_count"] > 2:
			_tick_skill("triple_attack")
	return {
		"result": "HIT",
		"damage": result["total_damage"],
		"is_crit": false,
		"message": "You strike for " + str(result["total_damage"]) + " damage!",
	}


# Called when a monster's attack against us resolves to PARRY/DODGE/BLOCK/
# RIPOSTE — i.e. when *we* successfully defended, as opposed to the ticks in
# attack_current_target()/perform_melee_attack() which are about a monster
# defending against our own swing.
# Called by a monster every time it swings at you (hit, miss, dodge, parry...): an attack is an attack even when it does no damage.
# It stands you up (you cannot rest through a fight) and interrupts camping and crafting (they watch last_attacked_msec).
# ── Stances (class_stances.json): procs, boosts, group benefit, aura ──
# The current stance's data, the extras a class_stances.json stance can carry beyond its modifiers (the Aetherfist's
# elemental stances): procs on auto-attack hits, abilities it boosts, a benefit for nearby group members and a visible aura.
const INTERRUPT_DELAY := 1.5      # seconds an interrupting blow holds back the target's next attack
const STANCE_BOOST := 0.25          # an ability of the stance's own element is this much stronger
const NO_DAMAGE_THREAT := 10
const DEATH_PACT_RANGE := 15.0      # the pet must be this close to be sacrificed
const CAST_MOVE_TOLERANCE := 0.25   # metres a caster may drift (a nudge, a slope) before a cast in progress breaks
var _cast_start_pos := Vector3.ZERO        # threat from a spell that lands without a hit (a slow, a stun, a curse)
const PROC_STUN_IMMUNE_MS := 15000  # a monster stunned by a proc can't be proc-stunned again for this long
const STANCE_GROUP_RANGE := 10.0    # group members this close get the stance's group benefit
const STANCE_GROUP_TICK := 2.0
static var _stance_cache := {}      # class -> {stance_id: stance dict}
var _stance_group_timer := 0.0
var _stance_aura: Node3D = null
var _stance_aura_for := ""


func _stance_data(stance_id: String = current_stance) -> Dictionary:
	if stance_id.is_empty():
		return {}
	if not _stance_cache.has(player_class):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://Data/class_stances.json"))
		var list: Array = parsed.get(player_class, []) if typeof(parsed) == TYPE_DICTIONARY and parsed.get(player_class) is Array else []
		var by_id := {}
		for st in list:
			by_id[str(st.get("stance_id", ""))] = st
		_stance_cache[player_class] = by_id
	return _stance_cache[player_class].get(stance_id, {})


func stance_boosts(ability: String) -> bool:
	return ability in _stance_data().get("boosts", [])


# An auto-attack landed: the stance's procs (never from abilities).
func _stance_on_hit(target: Node, damage: int) -> void:
	_tank_stance_procs(target)
	var weaken: float = combat_node.get_modifier("weaken_on_hit")  # Dragon Fist
	if weaken > 0.0 and is_instance_valid(target) and "combat_node" in target:
		_buff_target(target, target.combat_node, "dragon_fist_weaken", 5.0, {"damage_mult": -weaken})
	var procs: Dictionary = _stance_data().get("procs", {})
	if procs.is_empty() or not is_instance_valid(target) or not ("combat_node" in target):
		return
	var target_cn = target.combat_node
	var desc := TargetFrame.display_name(target)
	if procs.has("stun") and randf() < float(procs["stun"].get("chance", 0.0)):
		_proc_stun(target, desc, float(procs["stun"].get("min", 3.0)), float(procs["stun"].get("max", 5.0)))
	if procs.has("lifesteal") and damage > 0 and randf() < float(procs["lifesteal"].get("chance", 0.0)):
		var healed: int = combat_node.heal(maxi(1, int(round(damage * float(procs["lifesteal"].get("pct", 0.3))))))
		if healed > 0:
			GameLog.log_combat("[color=#66ccff]The tide flows back into you: [b]+%d[/b] health.[/color]" % healed)
	if procs.has("burn") and randf() < float(procs["burn"].get("chance", 0.0)):
		var burn: Dictionary = procs["burn"]
		var stacks := int(burn.get("stacks", 3))
		var slot := 1
		for i in range(1, stacks + 1):  # the first free stack, else refresh the first one
			if not target_cn.active_effects.has("ember_burn_%d" % i):
				slot = i
				break
		_buff_target(target, target_cn, "ember_burn_%d" % slot, float(burn.get("seconds", 4.0)), {}, int(burn.get("dps", 3)), 1.0)
		GameLog.log_combat("[color=#ff8844]%s is set burning.[/color]" % desc.capitalize())
	if procs.has("void") and randf() < float(procs["void"].get("chance", 0.0)):
		match randi() % 5:
			0:
				_buff_target(target, target_cn, "void_weaken", 6.0, {"damage_mult": -0.10})
				GameLog.log_combat("[color=#aa77ff]The void saps %s's strength.[/color]" % desc)
			1:
				_buff_target(target, target_cn, "void_blind", 6.0, {"hit_chance": -25.0})
				GameLog.log_combat("[color=#aa77ff]The void blinds %s.[/color]" % desc)
			2:
				_buff_target(target, target_cn, "void_silence", 4.0, {"silenced": 1.0})
				GameLog.log_combat("[color=#aa77ff]The void silences %s.[/color]" % desc)
			3:
				var drained := int(minf(target_cn.current_mana, 10.0 + combat_node.level * 2.0))
				target_cn.current_mana = maxf(0.0, target_cn.current_mana - drained)
				combat_node.current_mana = minf(combat_node.max_mana, combat_node.current_mana + drained)
				GameLog.log_combat("[color=#aa77ff]The void drains %d mana from %s.[/color]" % [drained, desc])
			_:
				_proc_stun(target, desc, 3.0, 5.0)


# Tank stance group benefits that trigger on a landed melee hit — on the tank themself and on group members within 10 m
# (stance "group" modifiers): Aegis of Dawn heals the striker for 5% of their health; Necrotic Bastion lifetaps the
# target (magic damage, half of it back as health).
const STANCE_HEAL_PCT := 0.05
const LIFETAP_BASE := 8
const LIFETAP_PER_LEVEL := 2

func _tank_stance_procs(target: Node) -> void:
	var heal_chance: float = combat_node.get_modifier("melee_heal_chance")
	if heal_chance > 0.0 and randf() < heal_chance:
		var healed := combat_node.heal(maxi(1, int(combat_node.max_hp * STANCE_HEAL_PCT)))
		if healed > 0:
			GameLog.log_combat("[color=#ffe08a]The light of dawn mends you: [b]+%d[/b] health.[/color]" % healed)
	var tap_chance: float = combat_node.get_modifier("melee_lifetap_chance")
	if tap_chance > 0.0 and is_instance_valid(target) and target.has_method("apply_damage") and randf() < tap_chance:
		var target_cn = target.get("combat_node")
		var dmg := LIFETAP_BASE + LIFETAP_PER_LEVEL * int(combat_node.level)
		if target_cn is CombatNode:
			dmg = combat_node.calculate_spell_damage(dmg, "spirit", target_cn)
		if target is Monster and not target.is_multiplayer_authority():
			target.apply_networked_damage.rpc_id(1, dmg, multiplayer.get_unique_id())
		else:
			target.apply_damage(dmg, "magic")
		var drained := combat_node.heal(maxi(1, dmg / 2))
		GameLog.log_combat("[color=#99dd77]Necrotic energy tears the life from %s: [b]%d[/b] damage, [b]+%d[/b] health.[/color]" % [TargetFrame.display_name(target), dmg, drained])


func _proc_stun(target: Node, desc: String, min_s: float, max_s: float) -> void:
	var now := Time.get_ticks_msec()
	if int(target.get_meta("proc_stun_immune_until", 0)) > now:
		return
	target.set_meta("proc_stun_immune_until", now + PROC_STUN_IMMUNE_MS)
	_apply_disable_effect(randf_range(min_s, max_s), target, desc, "is stunned!")


# Every STANCE_GROUP_TICK seconds: the stance's group benefit to group members within STANCE_GROUP_RANGE (a short effect
# that keeps being refreshed). Named by stance, so two monks in the same stance don't stack, and in different ones do.
func _tick_stance_group(delta: float) -> void:
	_stance_group_timer -= delta
	if _stance_group_timer > 0.0:
		return
	_stance_group_timer = STANCE_GROUP_TICK
	var mods: Dictionary = _stance_data().get("group", {})
	if mods.is_empty():
		return
	for peer in group_members:
		var member := _peer_id_to_player_node(peer)
		if not is_instance_valid(member) or member == self or not ("combat_node" in member):
			continue
		if (member as Node3D).global_position.distance_to(global_position) <= STANCE_GROUP_RANGE:
			_buff_target(member, member.combat_node, "group_stance_%s" % current_stance, STANCE_GROUP_TICK + 1.0, mods)


# The stance's aura: a soft glow and rising motes in its colour, on every peer (current_stance is replicated).
func _update_stance_aura() -> void:
	if current_stance == _stance_aura_for:
		return
	_stance_aura_for = current_stance
	if is_instance_valid(_stance_aura):
		_stance_aura.queue_free()
	_stance_aura = null
	var colour_list: Array = _stance_data().get("aura", [])
	if colour_list.size() != 3:
		return
	var colour := Color(float(colour_list[0]), float(colour_list[1]), float(colour_list[2]))
	var aura := Node3D.new()
	aura.name = "StanceAura"
	add_child(aura)
	# Each tank shows what it is (show, don't tell): the Voidknight visibly drains, the Lightsworn radiates, the
	# Blademaster throws sparks. The Aetherfist keeps the original rising motes.
	match str(_stance_data().get("aura_style", "rise")):
		"drain":
			_aura_drain(aura, colour)
		"radiant":
			_aura_radiant(aura, colour)
		"sparks":
			_aura_sparks(aura, colour)
		_:
			_aura_rise(aura, colour)
	_stance_aura = aura


static func _aura_material(colour: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(colour, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # so a particle's colour ramp can fade it in and out
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mat.vertex_color_use_as_albedo = true
	return mat


static func _fade_curve() -> Curve:
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(1, 0))
	return fade


static func _aura_light(aura: Node3D, colour: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = energy
	light.omni_range = reach
	light.position = Vector3(0, 1.0, 0)
	aura.add_child(light)


# Aetherfist: a soft glow and motes rising from a ring at the feet.
static func _aura_rise(aura: Node3D, colour: Color) -> void:
	_aura_light(aura, colour, 0.8, 2.5)
	var motes := CPUParticles3D.new()
	motes.amount = 28
	motes.lifetime = 1.4
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = 0.55
	motes.emission_ring_inner_radius = 0.3
	motes.emission_ring_height = 0.1
	motes.direction = Vector3.UP
	motes.spread = 12.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.5
	motes.initial_velocity_max = 1.0
	motes.scale_amount_min = 0.6
	motes.scale_amount_max = 1.0
	motes.scale_amount_curve = _fade_curve()
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	dot.material = _aura_material(colour, 2.0)
	motes.mesh = dot
	motes.position = Vector3(0, 0.15, 0)
	aura.add_child(motes)


# Colour over a particle's life: from `from` (alpha a0) to `to` (alpha a1).
static func _ramp(from: Color, a0: float, to: Color, a1: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(from, a0))
	g.set_color(1, Color(to, a1))
	return g


# Voidknight: the life of everything around is pulled IN — thin streaks, dark and faint where they start ~1.8 m out,
# brightening as they rush to the knight's chest, pointing the way they fly; cold wisps sink at the feet. A dim, sickly light. Evil that feeds, shown rather than told.
static func _aura_drain(aura: Node3D, colour: Color) -> void:
	_aura_light(aura, colour, 0.6, 2.2)
	var pull := CPUParticles3D.new()
	pull.amount = 56
	pull.lifetime = 1.3
	pull.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	pull.emission_sphere_radius = 1.8
	pull.gravity = Vector3.ZERO
	pull.initial_velocity_min = 0.0
	pull.initial_velocity_max = 0.1
	pull.radial_accel_min = -3.2   # drawn inward, toward the knight
	pull.radial_accel_max = -2.4
	pull.particle_flag_align_y = true
	pull.color_ramp = _ramp(colour.darkened(0.7), 0.15, colour.lightened(0.25), 1.0)
	var fade_in := Curve.new()
	fade_in.add_point(Vector2(0, 0.4))
	fade_in.add_point(Vector2(0.85, 1.0))
	fade_in.add_point(Vector2(1, 0))
	pull.scale_amount_curve = fade_in
	var streak := BoxMesh.new()
	streak.size = Vector3(0.025, 0.28, 0.025)
	streak.material = _aura_material(colour, 2.5, 1.0)
	pull.mesh = streak
	pull.position = Vector3(0, 1.1, 0)
	aura.add_child(pull)
	var wisps := CPUParticles3D.new()
	wisps.amount = 20
	wisps.lifetime = 2.2
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	wisps.emission_ring_axis = Vector3.UP
	wisps.emission_ring_radius = 0.55
	wisps.emission_ring_inner_radius = 0.2
	wisps.emission_ring_height = 0.1
	wisps.direction = Vector3.DOWN
	wisps.spread = 25.0
	wisps.gravity = Vector3(0, -0.35, 0)
	wisps.initial_velocity_min = 0.05
	wisps.initial_velocity_max = 0.2
	wisps.scale_amount_min = 1.5
	wisps.scale_amount_max = 2.5
	wisps.scale_amount_curve = _fade_curve()
	wisps.color_ramp = _ramp(colour.darkened(0.4), 0.6, colour.darkened(0.85), 0.0)
	var puff := SphereMesh.new()
	puff.radius = 0.07
	puff.height = 0.14
	puff.material = _aura_material(colour.darkened(0.5), 0.8, 0.6)
	wisps.mesh = puff
	wisps.position = Vector3(0, 0.7, 0)
	aura.add_child(wisps)


# Lightsworn: a warm glow, bright motes rising slowly all around, and soft shafts of light lifting through them —
# calm and heroic.
static func _aura_radiant(aura: Node3D, colour: Color) -> void:
	_aura_light(aura, colour, 1.6, 3.4)
	var motes := CPUParticles3D.new()
	motes.amount = 50
	motes.lifetime = 2.4
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = 0.8
	motes.emission_ring_inner_radius = 0.2
	motes.emission_ring_height = 0.2
	motes.direction = Vector3.UP
	motes.spread = 6.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.35
	motes.initial_velocity_max = 0.6
	motes.scale_amount_min = 0.7
	motes.scale_amount_max = 1.3
	var twinkle := Curve.new()
	twinkle.add_point(Vector2(0, 0))
	twinkle.add_point(Vector2(0.2, 1))
	twinkle.add_point(Vector2(1, 0))
	motes.scale_amount_curve = twinkle
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	dot.material = _aura_material(colour.lightened(0.3), 4.0)
	motes.mesh = dot
	motes.position = Vector3(0, 0.1, 0)
	aura.add_child(motes)
	var shafts := CPUParticles3D.new()
	shafts.amount = 8
	shafts.lifetime = 2.8
	shafts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	shafts.emission_ring_axis = Vector3.UP
	shafts.emission_ring_radius = 0.7
	shafts.emission_ring_inner_radius = 0.5
	shafts.emission_ring_height = 0.1
	shafts.direction = Vector3.UP
	shafts.spread = 0.0
	shafts.gravity = Vector3.ZERO
	shafts.initial_velocity_min = 0.2
	shafts.initial_velocity_max = 0.3
	shafts.color_ramp = _ramp(colour, 0.0, colour, 0.0)
	shafts.color_ramp.add_point(0.4, Color(colour, 0.3))
	var beam := BoxMesh.new()
	beam.size = Vector3(0.03, 1.0, 0.03)
	beam.material = _aura_material(colour.lightened(0.4), 2.0, 1.0)
	shafts.mesh = beam
	shafts.position = Vector3(0, 0.7, 0)
	aura.add_child(shafts)


# Blademaster: bursts of sparks flicking out and falling, like steel on a grindstone — a working fighter.
static func _aura_sparks(aura: Node3D, colour: Color) -> void:
	_aura_light(aura, colour, 0.8, 2.4)
	var sparks := CPUParticles3D.new()
	sparks.amount = 44
	sparks.lifetime = 0.55
	sparks.explosiveness = 0.45
	sparks.randomness = 0.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.45
	sparks.direction = Vector3.UP
	sparks.spread = 75.0
	sparks.gravity = Vector3(0, -7.0, 0)
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 3.6
	sparks.particle_flag_align_y = true   # streaks point the way they fly
	sparks.scale_amount_min = 0.8
	sparks.scale_amount_max = 1.2
	sparks.scale_amount_curve = _fade_curve()
	sparks.color_ramp = _ramp(colour.lightened(0.6), 1.0, colour, 0.8)
	var streak := BoxMesh.new()
	streak.size = Vector3(0.03, 0.22, 0.03)
	streak.material = _aura_material(colour.lightened(0.35), 5.0)
	sparks.mesh = streak
	sparks.position = Vector3(0, 1.0, 0)
	aura.add_child(sparks)


# Windfury ("extra_attack_chance"): a chance for an auto-attack to be followed at once by a second full swing.
func _maybe_extra_swing(target: Node, weapon: Dictionary) -> void:
	var chance: float = combat_node.get_modifier("extra_attack_chance")
	if chance <= 0.0 or randf() >= chance or not is_instance_valid(target) or not ("combat_node" in target) \
			or not target.combat_node.is_alive():
		return
	var result: Dictionary = combat_node.resolve_attack(target.combat_node)
	if target is Monster and not target.is_multiplayer_authority() and int(result.get("damage", 0)) > 0:
		target.apply_networked_damage.rpc_id(1, int(result["damage"]), multiplayer.get_unique_id())
	if target.has_method("add_threat"):
		target.add_threat(self, combat_node.generate_threat(int(result.get("damage", 0))))
	var desc := TargetFrame.display_name(target)
	if str(result.get("result", "")) == "HIT":
		GameLog.log_combat("[color=#aaddff]Windfury! You strike %s again for [b]%d[/b].[/color]" % [desc, int(result["damage"])])
		_stance_on_hit(target, int(result["damage"]))
	play_swing_sound(str(result.get("result", "")), weapon, target)


# Illusions (Mirror Image, Arcane Mirage, Illusory Double): a see-through copy of your character standing beside you for
# each one left, on your own screen. They vanish one by one as blows land on them (combatnode.gd use_decoy()).
var _decoys: Array = []

func _update_decoys() -> void:
	var want: int = mini(combat_node.decoys_left(), 3)
	if want == _decoys.size():
		return
	for decoy in _decoys:
		if is_instance_valid(decoy):
			decoy.queue_free()
	_decoys.clear()
	var model := get_node_or_null("Character") as Node3D
	if model == null:
		return
	for i in want:
		var copy := model.duplicate() as Node3D
		for mesh in copy.find_children("*", "MeshInstance3D", true, false):
			var ghost := StandardMaterial3D.new()
			ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost.albedo_color = Color(0.7, 0.75, 1.0, 0.35)
			ghost.emission_enabled = true
			ghost.emission = Color(0.4, 0.45, 0.9)
			(mesh as MeshInstance3D).material_override = ghost
		add_child(copy)
		copy.position = model.position + Vector3([-1.2, 1.2, 0.0][i], 0, [0.3, 0.3, 1.1][i])
		_decoys.append(copy)


# ── Combat sounds ──
# Which sound a spell makes when it goes off (Data/sounds.json ids), from its player_spells.json fields: stealth,
# summons, healing / cures / dispels, weapon and archery skills, everything helpful as a buff, and harmful spells by
# school (frost, lightning, holy, fire/poison/disease, other magic).
static func spell_sound(spell: Dictionary) -> String:
	var category := str(spell.get("skill_category", ""))
	var effect := str(spell.get("effect_type", "")) if spell.get("effect_type") is String else ""
	var kind := str(spell.get("spell_type", ""))
	var school := str(spell.get("spell_school", ""))
	var spell_name := str(spell.get("spell_name", "")).to_lower()
	if category == "stealth" or spell_name.contains("invis") or spell_name.contains("stealth"):
		return "spell_stealth"
	if kind == "summon" or effect == "summon":
		return "spell_summon"
	if effect in ["heal", "hot", "cure"] or kind == "dispel":
		return "spell_heal"
	if category == "archery":
		return "arrow_shot"
	if category == "mantis_fist":
		return "unarmed_hit"
	if category in ["slashing_weapons", "piercing_weapons", "blunt_weapons", "offense"]:
		return "weapon_hit"
	if kind in ["beneficial", "self-beneficial", "reactive"] or effect in ["buff", "absorb", "light"]:
		return "spell_buff"
	match school:
		"cold":
			return "spell_frost"
		"lightning":
			return "spell_lightning"
		"divine":
			return "spell_holy"
		"fire", "poison", "disease":
			return "spell_elemental"
	return "spell_damage"


# Our own swing: a hit (weapon, or fists for an unarmed swing / an Aetherfist), a miss or dodge (a whoosh), or the
# target's block / parry / riposte.
func play_swing_sound(result: String, weapon: Dictionary, target: Node) -> void:
	match result:
		"HIT":
			var unarmed := weapon.is_empty() or player_class == "Aetherfist"
			Sfx.play("unarmed_hit" if unarmed else "weapon_hit", target)
		"MISS", "DODGE":
			Sfx.play("miss", target)
		"BLOCK":
			Sfx.play("block", target)
		"PARRY", "RIPOSTE":
			Sfx.play("parry", target)


# A monster's swing at us (monster3d.gd, on this player's own machine): hurt when it lands, otherwise how we avoided it.
func play_swung_at_sound(result: String, damage: int, attacker: Node) -> void:
	match result:
		"MISS", "DODGE":
			Sfx.play("miss", attacker)
		"BLOCK":
			Sfx.play("block", self)
		"PARRY", "RIPOSTE":
			Sfx.play("parry", self)
		_:
			if damage > 0:
				Sfx.play("hurt_female" if player_sex.to_lower() == "female" else "hurt_male")


func on_attacked(_attacker: Node) -> void:
	last_attacked_msec = Time.get_ticks_msec()
	if is_sitting:
		is_sitting = false
		GameLog.log_general("[color=#ff8866]You are attacked and jump to your feet![/color]")


func _tick_defense_skill(result: String) -> void:
	if not result.is_empty():
		_tick_skill("defense")  # "raised by being attacked in melee" — hit or miss
	match result:
		"PARRY":
			_tick_skill("parry")
		"DODGE":
			_tick_skill("dodge")
		"BLOCK":
			_tick_skill("block")
		"RIPOSTE":
			_tick_skill("riposte")


# Skill names older saves used, mapped to the current names in Data/player_skills.json.
const LEGACY_SKILL_NAMES := {
	"1h_slashing": "slashing_weapons", "2h_slashing": "slashing_weapons",
	"1h_piercing": "piercing_weapons", "2h_piercing": "piercing_weapons",
	"1h_blunt": "blunt_weapons", "2h_blunt": "blunt_weapons",
}


func _canonical_skill_name(raw: String) -> String:
	var key := raw.to_lower().replace(" ", "_")
	return LEGACY_SKILL_NAMES.get(key, key)


# The skill a weapon uses AND trains. Taken from the item's CURRENT definition: a saved item is a full copy from the day
# it was picked up and can carry a stale name (a saved rusty sword still said "1h slashing" while the game and the
# class starting skills say slashing_weapons), which made the weapon look like skill 0 and accuracy fall back to a baseline.
func _weapon_skill_key(weapon: Dictionary) -> String:
	if weapon.is_empty():
		return "hand_to_hand"  # bare hands
	var definition := Inventory.get_item_definition(str(weapon.get("item_id", "")))
	return _canonical_skill_name(str(definition.get("skill", weapon.get("skill", ""))))


# Carries skills saved under a legacy name over to the current name (keeping the higher value) so old characters
# don't lose the skill they earned.
func _migrate_legacy_skills() -> void:
	for old_name in LEGACY_SKILL_NAMES:
		if skill_levels.has(old_name):
			var new_name: String = LEGACY_SKILL_NAMES[old_name]
			skill_levels[new_name] = maxi(int(skill_levels.get(new_name, 0)), int(skill_levels[old_name]))
			skill_levels.erase(old_name)
	for i in known_skills.size():
		known_skills[i] = _canonical_skill_name(str(known_skills[i]))


func _sync_weapon_skill() -> void:
	var skey: String = _weapon_skill_key(Inventory.get_equipped_weapon())
	# A weapon with no skill of its own (or an unknown one) counts as 0 — _apply_baseline_weapon_skill() then supplies the fallback.
	combat_node.weapon_skill = 0 if (skey.is_empty() or skey == "none") else int(skill_levels.get(skey, 0))
	combat_node.is_unarmed = skey == "hand_to_hand"
	combat_node._stats_dirty = true


func on_level_up(new_level: int) -> void:
	Sfx.play("level_up")
	combat_node.set_base_stat("level", new_level)
	combat_node.recalculate_derived_stats()
	combat_node.current_hp   = combat_node.max_hp
	combat_node.current_mana = combat_node.max_mana
	Global.player_data["player_level"] = new_level


# Only ever meaningful when called on/for the LOCAL machine's own player —
# Global.player_data is this one process's own save data, there's no way to
# reach into a remote peer's save file directly. monster3d.gd's die() calls
# this directly when the credited killer IS this machine (single-player, or
# the host killing something themselves); for a remote peer's kill, it calls
# receive_kill_credit.rpc_id() instead, which lands here on THEIR machine.
func grant_xp(amount: int) -> void:
	var cur_xp: int = Global.player_data.get("xp", 0)
	var xp_next: int = Global.player_data.get("xp_next_level", 100)
	var new_xp: int = cur_xp + amount
	Global.player_data["xp"] = new_xp
	GameLog.log_general("You gain [b]%d[/b] experience points. (%d / %d)" % [amount, new_xp, xp_next])

	# Level-up loop (handles multiple level-ups from one kill)
	while Global.player_data.get("xp", 0) >= Global.player_data.get("xp_next_level", 999999):
		var cur_lvl: int = Global.player_data.get("player_level", 1)
		if cur_lvl >= Global.xp_table.get("max_level", 20):
			break
		var new_lvl: int = cur_lvl + 1
		var next_thresh: int = int(Global.xp_table.get(str(new_lvl + 1), 0))
		Global.player_data["player_level"]  = new_lvl
		Global.player_data["xp_next_level"] = next_thresh if next_thresh > 0 else 999999
		GameLog.log_general("[color=#ffdd44][b]Fortune smiles upon you; your adventures have made you stronger! You are now level %d.[/b][/color]" % new_lvl)
		on_level_up(new_lvl)

	Global.save_player_data_to_file()


# any_peer: the SERVER calls this targeting the credited player's own peer id
# via .rpc_id() — it is never that player's own authority doing the calling
# (monster3d.gd's die() already takes the direct grant_xp() path when it is),
# so "authority"-mode (sender must own this node) would wrongly block it.
# /surname. By yourself: level 10 and no surname yet (a game master can change or clear one). Returns what to tell the player.
func set_own_surname(raw: String) -> String:
	var wanted := raw.strip_edges()
	if not Net.valid_surname(wanted):
		return "[color=#ff8866]A surname is one word: letters (an apostrophe or hyphen inside is fine), 2 to 20.[/color]"
	if not is_game_master:
		if int(combat_node.level) < 10:
			return "[color=#ff8866]You can choose a surname at level 10.[/color]"
		if not surname.is_empty():
			return "[color=#ff8866]You are already %s %s. Only a game master can change a surname.[/color]" % [player_name, surname]
	_apply_surname(Net.format_surname(wanted))
	return "[color=#ffdd44]You are now known as [b]%s %s[/b].[/color]" % [player_name, surname]


func _apply_surname(value: String) -> void:
	surname = value
	Global.player_data["surname"] = value
	Global.save_player_data_to_file()


# A game master's /kill of this player (or of themselves): run on the player's own machine, which owns the character.
# Direct call on the host / single-player; from anyone but the server it's ignored.
@rpc("any_peer", "call_remote", "reliable")
func gm_kill() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender != 0 and sender != 1) or not is_multiplayer_authority() or dying:
		return
	_last_attacker_desc = "a game master"
	combat_node.current_hp = DEATH_HP
	die(null)


# A game master's /give: the item lands in this player's bags (their own machine keeps their inventory).
@rpc("any_peer", "call_remote", "reliable")
func gm_receive_item(item_id: String, count: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if (sender != 0 and sender != 1) or not is_multiplayer_authority():
		return
	var def := Inventory.get_item_definition(item_id)
	if def.is_empty():
		return
	if Inventory.add_item(item_id, clampi(count, 1, 1000)):
		GameLog.log_general("[color=#88ccff]You receive %s%s.[/color]" % [str(def.get("name", item_id)), " x%d" % Inventory.last_added_count if Inventory.last_added_count > 1 else ""])
		Global.save_player_data_to_file()
	else:
		GameLog.log_general("[color=#ff8866]No room in your bags for %s.[/color]" % str(def.get("name", item_id)))


# A game master set (or cleared) this player's surname; sent by the server to the player's own machine.
@rpc("any_peer", "call_remote", "reliable")
func receive_surname(value: String) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority():
		return
	_apply_surname(value)
	GameLog.log_general("[color=#ffdd44]A game master has %s.[/color]" % ("set your surname: you are now [b]%s %s[/b]" % [player_name, value] if not value.is_empty() else "removed your surname"))


@rpc("any_peer", "call_remote", "reliable")
func receive_kill_credit(xp_gain: int) -> void:
	grant_xp(xp_gain)


func toggle_pet_gear_window() -> void:
	var existing := get_tree().root.get_node_or_null("PetGearWindow")
	if existing:
		existing.queue_free()
		return
	var window: Node = load("res://Scenes/pet_gear_window.tscn").instantiate()
	get_tree().root.add_child(window)
	window.set_player(self)


# Tracking (T key) — granted by race (Elf, Half-Elf) or class (Woodstalker,
# Wildspeaker, Troubadour), not something you learn/cast, so it's a plain
# race/class check rather than a known_spells/known_skills entry.
#
# Real bug, found 2026-09-18 while chasing an unrelated animation-library
# issue: player_race is saved/loaded as character_options.json's raw lowercase
# key ("half_elf", "dark_elf", "elf" — see character_creation.gd's
# `"player_race": selected_race`, which is never .capitalize()'d the way
# player_class explicitly is before saving). This list was originally written
# with the CAPITALIZED DISPLAY names ("Elf", "Half-Elf") instead, so it never
# actually matched anything — race-based tracking silently never worked for
# any race. Class-based tracking (TRACKING_CLASSES) was unaffected since
# player_class genuinely is capitalized before saving.
const TRACKING_RACES := ["elf", "half_elf"]
const TRACKING_CLASSES := ["Woodstalker", "Wildspeaker", "Troubadour"]

func has_tracking_skill() -> bool:
	return player_race in TRACKING_RACES or player_class in TRACKING_CLASSES


func toggle_tracking_window() -> void:
	var existing := get_tree().root.get_node_or_null("TrackingWindow")
	if existing:
		existing.queue_free()
		return
	if not has_tracking_skill():
		GameLog.log_general("You haven't learned to track.")
		return
	var window: Node = load("res://Scenes/tracking_window.tscn").instantiate()
	window.name = "TrackingWindow"
	get_tree().root.add_child(window)
	window.set_player(self)


# J — the quest journal (quest_journal.gd): every quest you've been given, Pending / Completed.
func toggle_quest_journal() -> void:
	var existing := get_tree().root.get_node_or_null("QuestJournal")
	if existing:
		existing.queue_free()
		return
	var journal := QuestJournal.new()
	journal.name = "QuestJournal"
	get_tree().root.add_child(journal)


# L — the recipe book (recipe_book.gd): every tradeskill recipe you know, with its ingredients.
func toggle_recipe_book() -> void:
	var existing := get_tree().root.get_node_or_null("RecipeBook")
	if existing:
		existing.queue_free()
		return
	var book := RecipeBook.new()
	book.name = "RecipeBook"
	get_tree().root.add_child(book)
	book.set_player(self)


func toggle_abilities_book() -> void:
	Sfx.play("window")
	if abilities_book_instance:
		abilities_book_instance.queue_free()
		abilities_book_instance = null
	else:
		abilities_book_instance = load("res://Scenes/abilities_book.tscn").instantiate()
		get_tree().root.add_child(abilities_book_instance)
		if abilities_book_instance.has_method("set_player"):
			abilities_book_instance.set_player(self)


# /macro: opens the abilities book on one tab (or brings it to that tab if it is open).
func toggle_abilities_book_tab(tab_name: String) -> void:
	if not is_instance_valid(abilities_book_instance):
		abilities_book_instance = null
		toggle_abilities_book()
	if abilities_book_instance != null and abilities_book_instance.has_method("show_tab"):
		abilities_book_instance.show_tab(tab_name)


func toggle_backpack() -> void:
	Sfx.play("bag_open")
	if backpack_instance:
		backpack_instance.queue_free()
		backpack_instance = null
		Global.restore_mouse_mode()
		print("🎒 Backpack closed")
	else:
		backpack_instance = backpack_scene.instantiate()
		get_tree().root.add_child(backpack_instance)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		print("🎒 Backpack opened")
