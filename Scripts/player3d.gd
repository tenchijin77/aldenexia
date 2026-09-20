# player3d.gd - 3D player controller with RPG systems
extends CharacterBody3D
class_name Player3D

#region Movement configuration
const WALK_SPEED: float = 5.0
const RUN_SPEED: float = 8.0
const CROUCH_SPEED: float = 2.5
const JUMP_VELOCITY: float = 6.0
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
# Dev/staff flag shown as a "<game master>" nameplate tag (TargetFrame.
# nameplate_name()) — no in-game way to grant this yet, it's set by editing
# the save file's "is_game_master" key directly.
var is_game_master := false
var known_spells: Array = []
var known_skills: Array = []
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
var _pending_cast_spell: String = ""
var _pending_cast_spell_data: Dictionary = {}
var _pending_cast_target: Node = null
var _appraisal_cooldowns: Dictionary = {}  # target instance ID -> remaining seconds
var active_pet: Node = null
var active_pet_frame: Node = null
var _deathly_visage_light: OmniLight3D = null
var _shadowlight_light: OmniLight3D = null
var last_damage_time_ms: int = 0  # Time.get_ticks_msec() of the last hit taken — used to interrupt /camp
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
const BLEED_OUT_DURATION := 20.0    # seconds at 0 HP before true death
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
#endregion

#region Movement state
var is_running: bool = true
var is_crouching: bool = false
var is_in_air: bool = false
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
		var hit := _raycast_world_hit(get_viewport().get_mouse_position())
		if hit is VendorNPC:
			_open_shop(hit)
			return
		if hit is Player3D and hit != self and hit.dying:
			_try_bandage(hit)
			return
	if _try_open_campfire():
		return
	_try_loot_corpse()


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
	var heal_amount: int = int(bandage["item"].get("heal_amount", 0))
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
	if is_instance_valid(_shop_window_instance):
		_shop_window_instance.queue_free()
	_shop_window_instance = load("res://Scenes/shop_window.tscn").instantiate()
	get_tree().root.add_child(_shop_window_instance)
	_shop_window_instance.setup(vendor)
	if vendor.has_method("greet_player"):
		vendor.greet_player(player_name)


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


const HAIL_RANGE := 5.0

func try_hail_nearby_npc() -> void:
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
const FACTION_STANDING_ALIASES := {"Lumora": "Villagers of Lumora"}


func _appraisal_tier(diff: int) -> Dictionary:
	if diff <= -5:
		return {"dc": 5, "name": "Trivial"}
	elif diff <= -2:
		return {"dc": 10, "name": "Easy"}
	elif diff <= 1:
		return {"dc": 15, "name": "Moderate"}
	elif diff <= 4:
		return {"dc": 20, "name": "Hard"}
	else:
		return {"dc": 25, "name": "Deadly"}


func _ability_modifier(stat: int) -> int:
	return int(floor((stat - 10) / 2.0))


func _faction_reputation_text(target: Node) -> String:
	# Monsters expose "faction"; NPCs like guards expose "npc_faction" instead.
	var target_faction: String = "None"
	if "faction" in target:
		target_faction = target.get("faction")
	elif "npc_faction" in target:
		target_faction = target.get("npc_faction")
	var mapped: String = FACTION_STANDING_ALIASES.get(target_faction, target_faction)
	if not faction_standing.has(mapped):
		return "Unaligned"
	var standing: int = faction_standing.get(mapped, 0)
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
	var roll := randi_range(1, 20)
	var total := roll + maxi(int_mod, wis_mod)
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

	if not success:
		if frame:
			frame.show_wrong_color(10.0)
		GameLog.log_general("You sense nothing unusual about %s." % target_desc)
		return

	var is_crit: bool = roll == 20
	var flavor_bank: Array = APPRAISAL_TEXTS.get(tier["name"], [])
	var flavor: String = flavor_bank[randi() % flavor_bank.size()] if not flavor_bank.is_empty() else ""
	var faction_text: Dictionary = APPRAISAL_FACTION_TEXT.get(faction, {})

	GameLog.log_general("[color=#ccddff][b]Appraisal: %s[/b] (Lv %d, %s)[/color]" % [target_desc.capitalize(), target_level, tier["name"]])
	if not flavor.is_empty():
		GameLog.log_general(flavor)
	GameLog.log_general("%s%s" % [faction_text.get("prefix", ""), faction_text.get("suffix", "")])
	GameLog.log_general("Estimated threat: %s" % tier["name"])

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

	GameLog.log_general("Faction Reputation: %s" % _faction_reputation_text(current_target))

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
func _ready() -> void:
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
	_death_flavor = NPCFlavorText.new("res://Data/player_death_flavor.json")
	_food_drink_flavor = NPCFlavorText.new("res://Data/food_drink_flavor.json")
	_restore_last_position()
	_ensure_bind_point()

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
	if is_multiplayer_authority():
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
		"library": "res://models/Human Female/female_animations.res",
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
		"library": "res://models/Human Male/human_male_animations.res",
		"texture_override": "res://models/Human Male/Meshy_AI_fantasy_commoner_rigg_biped_texture_0.png",
	},
	"half_elf_female": {
		# Re-rigged 2026-09-18 ("Version 2" — new mesh/texture/animation set,
		# same pipeline as Human Female's Version 2 — see
		# [[reference_character_model_pipeline]]). Measures the same 1.7m
		# baseline every correctly-exported model does, so no scale correction.
		"scene":   "res://models/Half-Elf Female/Half-Elf Female Breathing Idle.fbx",
		"library": "res://models/Half-Elf Female/half_elf_female_animations.res",
		"texture_override": "res://models/Half-Elf Female/Meshy_AI_female_half_elf_hero__biped_texture_0.png",
	},
	"half_elf_male": {
		"scene":   "res://models/Half-Elf Male/Half-Elf Male Breathing Idle.fbx",
		"library": "res://models/Half-Elf Male/half_elf_male_animations.res",
		"texture_override": "res://models/Half-Elf Male/Meshy_AI_male_half_elf_commone_biped_texture_0.png",
	},
	"troll_female": {
		"scene":   "res://models/Troll Female/Troll Female Breathing Idle.fbx",
		"library": "res://models/Troll Female/troll_female_animations.res",
		"texture_override": "res://models/Troll Female/Meshy_AI_female_troll_commoner_biped_texture_0.png",
	},
	"troll_male": {
		"scene":   "res://models/Troll Male/Troll Male Breathing Idle.fbx",
		"library": "res://models/Troll Male/troll_male_animations.res",
		"texture_override": "res://models/Troll Male/Meshy_AI_troll_commoner_rig_biped_texture_0.png",
	},
	"elf_male": {
		"scene":   "res://models/Elf Male/Elf Male Breathing Idle.fbx",
		"library": "res://models/Elf Male/elf_male_animations.res",
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
		"library": "res://models/Elf Female/elf_female_animations.res",
		"texture_override": "res://models/Elf Female/Meshy_AI_female_elf_hero_rig_biped_texture_0.png",
	},
	"dark_elf_male": {
		"scene":   "res://models/Dark Elf Male/Dark Elf Male Breathing Idle.fbx",
		"library": "res://models/Dark Elf Male/dark_elf_male_animations.res",
		"texture_override": "res://models/Dark Elf Male/Meshy_AI_Male_Dark_Elf_Commone_biped_texture_0.png",
	},
	"dark_elf_female": {
		# Re-rigged 2026-09-18 ("Version 2") — same standard 1.7m baseline,
		# no scale correction needed (see elf_female's comment above).
		"scene":   "res://models/Dark Elf Female/Dark Elf Female Breathing Idle.fbx",
		"library": "res://models/Dark Elf Female/dark_elf_female_animations.res",
		"texture_override": "res://models/Dark Elf Female/Meshy_AI_female_dark_elf_hero__biped_texture_0.png",
	},
	# Added 2026-09-18 — first wiring for these 6 races (Dwarf/Gnome/Halfling/
	# Half-Orc/Lizardkin/Ogre), same pipeline as every other model here. See
	# [[reference_character_model_pipeline]].
	"dwarf_female": {
		"scene":   "res://models/Dwarf Female/Dwarf Female Breathing Idle.fbx",
		"library": "res://models/Dwarf Female/dwarf_female_animations.res",
		"texture_override": "res://models/Dwarf Female/Meshy_AI_female_dwarf_commoner_biped_texture_0.png",
	},
	"dwarf_male": {
		"scene":   "res://models/Dwarf Male/Dwarf Male Breathing Idle.fbx",
		"library": "res://models/Dwarf Male/dwarf_male_animations.res",
		"texture_override": "res://models/Dwarf Male/Meshy_AI_male_dwarf_commoner_r_biped_texture_0.png",
	},
	"gnome_female": {
		"scene":   "res://models/Gnome Female/Gnome Female Breathing Idle.fbx",
		"library": "res://models/Gnome Female/gnome_female_animations.res",
		"texture_override": "res://models/Gnome Female/Meshy_AI_female_gnome_commoner_biped_texture_0.png",
	},
	"gnome_male": {
		"scene":   "res://models/Gnome Male/Gnome Male Breathing Idle.fbx",
		"library": "res://models/Gnome Male/gnome_male_animations.res",
		"texture_override": "res://models/Gnome Male/Meshy_AI_male_gnome_commoner_r_biped_texture_0.png",
	},
	"halfling_female": {
		"scene":   "res://models/Halfling Female/Halfling Female Breathing Idle.fbx",
		"library": "res://models/Halfling Female/halfling_female_animations.res",
		"texture_override": "res://models/Halfling Female/Meshy_AI_female_halfling_commo_biped_texture_0.png",
	},
	"halfling_male": {
		"scene":   "res://models/Halfling Male/Halfling Male Breathing Idle.fbx",
		"library": "res://models/Halfling Male/halfling_male_animations.res",
		"texture_override": "res://models/Halfling Male/Meshy_AI_male_halfling_commone_biped_texture_0.png",
	},
	"half_orc_female": {
		"scene":   "res://models/Half-Orc Female/Half-Orc Female Breathing Idle.fbx",
		"library": "res://models/Half-Orc Female/half_orc_female_animations.res",
		"texture_override": "res://models/Half-Orc Female/Meshy_AI_female_half_orc_commo_biped_texture_0.png",
	},
	"half_orc_male": {
		"scene":   "res://models/Half-Orc Male/Half-Orc Male Breathing Idle.fbx",
		"library": "res://models/Half-Orc Male/half_orc_male_animations.res",
		"texture_override": "res://models/Half-Orc Male/Meshy_AI_male_half_orc_commone_biped_texture_0.png",
	},
	"lizardkin_female": {
		"scene":   "res://models/Lizardkin Female/Lizardkin Female Breathing Idle.fbx",
		"library": "res://models/Lizardkin Female/lizardkin_female_animations.res",
		"texture_override": "res://models/Lizardkin Female/Meshy_AI_female_lizardkin_comm_biped_texture_0.png",
	},
	"lizardkin_male": {
		"scene":   "res://models/Lizardkin Male/Lizardkin Male Breathing Idle.fbx",
		"library": "res://models/Lizardkin Male/lizardkin_male_animations.res",
		"texture_override": "res://models/Lizardkin Male/Meshy_AI_male_lizardkin_common_biped_texture_0.png",
	},
	"ogre_female": {
		"scene":   "res://models/Ogre Female/Ogre Female Breathing Idle.fbx",
		"library": "res://models/Ogre Female/ogre_female_animations.res",
		"texture_override": "res://models/Ogre Female/Meshy_AI_female_ogre_commoner__biped_texture_0.png",
	},
	"ogre_male": {
		"scene":   "res://models/Ogre Male/Ogre Male Breathing Idle.fbx",
		"library": "res://models/Ogre Male/ogre_male_animations.res",
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

	_built_character_model_key = key


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
	var anim_name := "cast_beneficial" if _is_beneficial_cast(spell) else "cast_detrimental"
	if not animation_player or not animation_player.has_animation(anim_name):
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
	_spawn_hud_frames()
	GameLog.log_general("Welcome, [b]%s[/b]." % player_name)


const HUD_FRAME_SCENES := [
	"res://Scenes/player_frame.tscn",
	"res://Scenes/cast_bar.tscn",
	"res://Scenes/target_frame.tscn",
	"res://Scenes/group_frame.tscn",
	"res://Scenes/game_log_window.tscn",
	"res://Scenes/action_bar.tscn",
	"res://Scenes/stance_bar.tscn",
	"res://Scenes/buff_bar.tscn",
]

func _spawn_hud_frames() -> void:
	var root = get_tree().root
	for scene_path in HUD_FRAME_SCENES:
		var node: Node = load(scene_path).instantiate()
		node.add_to_group("game_hud")
		root.add_child(node)


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
			$NameLabel.visible = Global.settings.get("show_name_tags", true) and not hidden
		# player_race/player_sex replicate in the same delayed way as
		# player_name — rebuild the model once they arrive (a no-op once the
		# key stops changing, see _build_character_model()).
		if _character_model_key() != _built_character_model_key:
			_build_character_model()
		return

	var chat_focused := get_viewport().gui_get_focus_owner() is LineEdit

	if not chat_focused and Input.is_action_just_pressed("toggle_backpack"):
		toggle_backpack()

	if dying:
		return

	if stumble_timer > 0.0:
		stumble_timer -= delta
		return

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		is_in_air = true
	else:
		if is_in_air and velocity.y < -10.0:
			stumble_timer = STUMBLE_DURATION
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
#endregion

#region Process (regen / vitals / cooldowns)
func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if is_incapacitated:
		_tick_bleedout(delta)
	if dying:
		return

	regen_timer += delta
	if regen_timer >= REGEN_INTERVAL:
		regen_timer = 0.0

		# satiety <= 0 halts HP regen entirely (not just a reduction) — see
		# update_vitals_decay() below. Below 25 but still >0 is just a graduated
		# warning-zone penalty, same as before.
		if combat_node.current_hp < combat_node.max_hp and satiety > 0:
			var regen_h: int = combat_node.get_derived_stat("hp_regen") + regen_bonus + int(combat_node.get_modifier("hp_regen_bonus"))
			if is_sitting:
				regen_h = int(regen_h * 3.0)
			if satiety < 25:
				regen_h = int(regen_h * 0.8)
			combat_node.current_hp = mini(combat_node.current_hp + regen_h, combat_node.max_hp)

		# thirst <= 0 halts mana regen entirely — mirrors the satiety/HP rule above.
		if combat_node.current_mana < combat_node.max_mana and thirst > 0:
			var regen_m: int = combat_node.get_derived_stat("mana_regen") + int(combat_node.get_modifier("mana_regen_bonus"))
			if is_sitting:
				regen_m = int(regen_m * 3.0)
			if thirst < 25:
				regen_m = int(regen_m * 0.8)
			combat_node.current_mana = mini(combat_node.current_mana + regen_m, combat_node.max_mana)

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
			satiety = mini(satiety + amount, 100)
			var line: String = _food_drink_flavor.get_line("eat") if _food_drink_flavor else ""
			GameLog.log_general(line % item_name if not line.is_empty() else "You eat %s." % item_name)
		"thirst":
			thirst = mini(thirst + amount, 100)
			var line: String = _food_drink_flavor.get_line("drink") if _food_drink_flavor else ""
			GameLog.log_general(line % item_name if not line.is_empty() else "You drink %s." % item_name)
		_:
			return
	_update_well_fed_buff()
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
		velocity.y = JUMP_VELOCITY


func handle_movement(delta: float) -> void:
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
		current_stamina -= STAMINA_DRAIN_RUN * delta
	elif is_on_floor() and satiety > 0:  # satiety<=0 halts stamina regen too, see update_vitals_decay()
		var regen_rate: float
		if is_sitting:
			regen_rate = STAMINA_REGEN_SIT
		elif is_moving:
			regen_rate = STAMINA_REGEN_WALK
		else:
			regen_rate = STAMINA_REGEN_STAND
		current_stamina += (regen_rate + combat_node.get_modifier("stamina_regen_bonus")) * delta

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
	if is_instance_valid(_deathly_visage_light):
		_deathly_visage_light.visible = combat_node.has_effect("deathly_visage")
	if is_instance_valid(_shadowlight_light):
		_shadowlight_light.visible = combat_node.has_effect("shadowlight")
	if has_node("NameLabel"):
		$NameLabel.visible = Global.settings.get("show_name_tags", true)



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
			return

	if group_members.size() <= 1:
		GameLog.log_general("You aren't in a group.")
		return
	var old_members := group_members.duplicate()
	group_members = [get_multiplayer_authority()]
	GameLog.log_general("[color=#ffaa66]The group has been disbanded.[/color]")
	for pid in old_members:
		if pid != get_multiplayer_authority():
			Net.send_group_removed(pid, "The group has been disbanded.")


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
		GameLog.log_general("[color=red]No player named '%s' is currently online.[/color]" % target_name)
		return
	if target == self:
		GameLog.log_general("[color=red]You can't tell yourself something... or can you?[/color]")
		return
	Net.send_tell(target.get_multiplayer_authority(), player_name, message)
	GameLog.log_general("[color=#cc88ff]You tell %s, '%s'[/color]" % [TargetFrame.display_name(target), message])


# /party <message> — broadcasts to every OTHER real player currently in
# group_members. Once real cross-zone grouping exists this still works
# unchanged, since it addresses peers by id, not by scene proximity.
func send_party_message(message: String) -> void:
	if not Net.is_multiplayer_game:
		GameLog.log_general("[color=red]You're not in a multiplayer session.[/color]")
		return
	var my_id := get_multiplayer_authority()
	var peer_ids: Array = group_members.filter(func(pid): return pid != my_id)
	if peer_ids.is_empty():
		GameLog.log_general("[color=red]You aren't in a group.[/color]")
		return
	Net.send_party_message(peer_ids, player_name, message)
	GameLog.log_general("[color=#88ccff][Party] You: %s[/color]" % message)


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
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var space := get_world_3d().direct_space_state
	var origin    := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 150.0)
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	if hit and (hit.collider is Monster or hit.collider is GuardNPC or hit.collider is VendorNPC or hit.collider is PetMinion or hit.collider is Player3D):
		var m: Node = hit.collider
		# Its collider still physically exists (that's how the raycast found
		# it at all) even though its model/nameplate are hidden — this is what
		# actually makes an invisible entity untargetable rather than just
		# invisible-looking.
		if TargetFrame.is_hidden_from_local_player(m):
			return
		if _is_targetable_alive(m):
			current_target = m
			_announce_target(current_target)


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

	var dist := global_position.distance_to(current_target.global_position)
	if dist > 3.0:
		print("⚔️ %s is out of range (%.1fm). Move closer!" % [TargetFrame.display_name(current_target), dist])
		return

	attacking = true
	last_attack_time_ms = Time.get_ticks_msec()
	_trigger_attack_animation()
	var swing_duration := _attack_animation_duration()
	attack_cooldown = swing_duration
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
		var target_desc: String = current_target.get("monster_description") if current_target.get("monster_description") != "" else current_target.get_monster_name()
		var weapon := Inventory.get_equipped_weapon()
		var weapon_name: String = weapon.get("name", "")
		var dmg_type: String = CombatLogFormatter.damage_type_from_item(weapon)
		var msg: String = CombatLogFormatter.player_attack(result, target_desc, weapon_name, dmg_type)
		if not msg.is_empty():
			GameLog.log_combat(msg)
			_broadcast_combat(CombatLogFormatter.player_attack_broadcast(player_name, result, target_desc, weapon_name, dmg_type))
		if result["result"] == "HIT":
			var skey: String = weapon.get("skill", "").to_lower().replace(" ", "_")
			_tick_skill(skey)
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
			var target_desc: String = current_target.get("monster_description") if current_target.get("monster_description") != "" else current_target.get_monster_name()
			GameLog.log_combat("You hit %s for [b]%d[/b] damage." % [target_desc, total_damage])
			_broadcast_combat("%s hits %s for [b]%d[/b] damage." % [player_name, target_desc, total_damage])
		if not is_instance_valid(current_target) or current_target.current_health <= 0:
			var target_desc: String = current_target.get("monster_description") if current_target.get("monster_description") != "" else current_target.get_monster_name()
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
	attack_cooldown = swing_duration
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
			if result["result"] == "HIT":
				var skey: String = weapon.get("skill", "").to_lower().replace(" ", "_")
				_tick_skill(skey)
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


func apply_damage(amount: int, attacker: Node = null) -> void:
	take_damage(amount, attacker)


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


func _register_attacker(attacker: Node) -> void:
	if attacker and is_instance_valid(attacker) and current_target != attacker:
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

func die(attacker: Node = null) -> void:
	if dying:
		return
	dying = true
	is_incapacitated = true
	_bleedout_elapsed = 0.0
	_bleedout_warn_timer = 0.0
	combat_node.current_hp = 0  # clamp — resolve_attack() can overshoot well below 0 on a single big hit

	if attacker and is_instance_valid(attacker):
		var desc: String = attacker.get("monster_description") if "monster_description" in attacker else ""
		if desc == "" and attacker.has_method("get_monster_name"):
			desc = attacker.get_monster_name()
		if desc != "":
			_last_attacker_desc = desc

	GameLog.log_combat("[color=#ff8866]You collapse, bleeding out...[/color]")
	autoattack_enabled = false
	GameLog.set_autoattack(false)

	for m in get_tree().get_nodes_in_group("monsters"):
		if is_instance_valid(m) and m.has_method("force_disengage"):
			m.force_disengage()

	if animation_player and animation_player.has_animation("death"):
		animation_player.play("death")


func _tick_bleedout(delta: float) -> void:
	_bleedout_elapsed += delta
	if _bleedout_elapsed >= BLEED_OUT_DURATION:
		_die_for_real()
		return
	_bleedout_warn_timer += delta
	if _bleedout_warn_timer >= BLEED_OUT_WARN_INTERVAL:
		_bleedout_warn_timer = 0.0
		GameLog.log_combat("[color=#aa3333]You are bleeding out...[/color]")


func _die_for_real() -> void:
	is_incapacitated = false
	GameLog.log_combat("[color=#ff4444]You have been defeated by %s![/color]" % _last_attacker_desc.capitalize())
	if _death_flavor:
		var line := _death_flavor.get_line("death")
		if line != "":
			GameLog.log_general("[color=#999999]%s[/color]" % line)
	_show_death_screen()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	_respawn()


func _show_death_screen() -> void:
	_death_screen = CanvasLayer.new()
	_death_screen.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen.add_child(bg)
	var lbl := Label.new()
	lbl.text = "RETURNING TO YOUR BIND POINT..."
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

	global_position = get_bind_point()
	combat_node.current_hp = combat_node.max_hp
	combat_node.current_mana = combat_node.max_mana
	current_stamina = max_stamina
	current_target = null
	_set_target_frame(null)
	dying = false
	GameLog.log_general("[color=#88ccff]You awaken at your bind point.[/color]")


# The player's bind point defaults to wherever they first spawned into the
# world (no bind spell/NPC exists yet — this can grow into that later
# without changing anything here, just what sets Global.player_data["bind_point"]).
# Stored as a plain [x,y,z] array since Vector3 isn't JSON-serializable.
func _ensure_bind_point() -> void:
	if not Global.player_data.has("bind_point"):
		Global.player_data["bind_point"] = [global_position.x, global_position.y, global_position.z]
		Global.save_player_data_to_file()


# Restores the position saved by Global.save_player_data_to_file() so the
# player logs back in exactly where they logged out, instead of always at the
# zone scene's fixed Player3D spawn transform. No-op for a brand new
# character (no "last_position" saved yet), which just keeps the zone's
# default spawn.
func _restore_last_position() -> void:
	var arr: Array = Global.player_data.get("last_position", [])
	if arr.size() == 3:
		global_position = Vector3(arr[0], arr[1], arr[2])


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
			"xp": 0, "xp_next_level": 100
		})

	load_character_data(Global.player_data)

	satiety = Global.player_data.get("satiety", 100)
	thirst = Global.player_data.get("thirst", 100)
	current_stamina = Global.player_data.get("current_stamina", MAX_STAMINA)
	max_stamina = Global.player_data.get("max_stamina", MAX_STAMINA)

	var inv_data = Global.player_data.get("inventory_data", {})
	if not inv_data.is_empty():
		Inventory.load_inventory_data(inv_data)
		_apply_equipment_from_inventory()


func load_character_data(data: Dictionary) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("❌ Invalid character data type")
		return

	player_name  = data.get("player_name",  "Unnamed Player")
	player_class = data.get("player_class", "Blademaster")
	player_race  = data.get("player_race",  "Human")
	player_sex   = data.get("player_sex",   "male")
	stats        = data.get("stats",        {})
	is_game_master = data.get("is_game_master", false)

	_build_character_model()

	if has_node("NameLabel"):
		$NameLabel.text = player_name

	data["resistances"] = data.get("resistances", {
		"acid": 0, "cold": 0, "fire": 0, "magic": 0, "psychic": 0
	})
	data["equipment"] = data.get("equipment", {})

	pet_equipment = data.get("pet_equipment", {})
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
	skill_levels     = data.get("skill_levels", {})
	action_bar_slots = data.get("action_bar_slots", _default_action_bar_slots())
	_sync_weapon_skill()
	apply_equipment(data.get("equipment", {}))

	# Starting weapon skill: combat classes begin with a baseline so they can hit
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
			combat_node.race_crit_bonus = 5
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
			combat_node.gear_ac += 2
			combat_node.set_base_stat("charisma", maxi(1, combat_node.charisma - 2))
			combat_node.race_acid_resist = 5
			combat_node.race_cold_resist = -10
			combat_node.race_psychic_resist = 5
	combat_node._stats_dirty = true
	combat_node.recalculate_derived_stats()
#endregion

#region Faction
func load_faction_standing() -> void:
	var file: FileAccess = FileAccess.open("res://Data/player_faction.json", FileAccess.READ)
	if file:
		var json_data = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(json_data) == TYPE_DICTIONARY and json_data.has("factions"):
			for faction in json_data["factions"]:
				if faction.has("name") and faction.has("standing"):
					faction_standing[faction["name"]] = faction["standing"]
		print("✅ Loaded faction standing")
	else:
		print("⚠️ player_faction.json not found (optional)")


func get_faction_standing(faction_name: String) -> int:
	return faction_standing.get(faction_name, 0)
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

	combat_node.weapon_damage = weapon_dmg
	combat_node.gear_ac       = bonus_ac
	combat_node._stats_dirty  = true
	combat_node.recalculate_derived_stats()


func _on_equipment_changed() -> void:
	_apply_equipment_from_inventory()
	Global.save_player_data_to_file()


func _apply_equipment_from_inventory() -> void:
	var weapon_dmg := 0
	var bonus_ac   := 0

	for slot in Inventory.EQUIPMENT_SLOTS:
		var item: Variant = Inventory.equipped.get(slot, null)
		if item == null or typeof(item) != TYPE_DICTIONARY:
			continue
		if slot == "primary":
			weapon_dmg = item.get("damage", 0) + item.get("poison_bonus_damage", 0)
		else:
			bonus_ac += item.get("armor_class", 0)

	combat_node.weapon_damage = weapon_dmg
	combat_node.gear_ac       = bonus_ac
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


# ================================================================================
# ⭐ SPELL CASTING
# ================================================================================

# Spells whose in-fiction name isn't derivable from the internal snake_case
# spell_name via the usual replace("_"," ").capitalize() convention.
const SPELL_DISPLAY_NAMES := {
	"shadow_aura": "Aura of the Shadow",
	"spectral_minion": "Morthan's Call",
	"phantasmal_echo": "Phantasmal Echo",
	"campfire_warmth": "Warmth of the Campfire",
	"kenjis_blessing": "Kenji's Blessing",
	"curse_of_weakness": "Curse of Weakness",
	"deaths_echo": "Death's Echo",
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
	if spell_name == "improved_block":
		GameLog.log_general("[b]Improved Block[/b] is passive — no need to cast it.")
		return false

	var spell: Dictionary = _spell_by_name.get(spell_name, {})
	if spell.is_empty():
		GameLog.log_general("Unknown spell or ability: [b]%s[/b]." % spell_display_name(spell_name))
		return false

	if player_class == "Troubadour" and not is_auto_recast:
		if _active_songs.has(spell_name):
			_active_songs.erase(spell_name)
			GameLog.log_general("You stop playing [b]%s[/b]." % spell_display_name(spell_name))
			return false
		# Only one song plays at a time (per user correction 2026-09-17 — the
		# earlier "multiple songs stack independently" design was explicitly
		# wrong): starting a new song stops every other one from
		# auto-recasting. Whatever it replaces isn't ripped away instantly —
		# its already-applied buff just runs out on its own over its
		# remaining duration, same as toggling a song off normally does.
		for other_song in _active_songs.keys():
			GameLog.log_general("[b]%s[/b] fades as you begin a new song." % spell_display_name(other_song))
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
	if combat_node.current_mana < cost:
		if is_auto_recast:
			GameLog.log_general("[color=#ff8866]You don't have enough mana to keep playing [b]%s[/b] — the song fades.[/color]" % spell_display_name(spell_name))
			_active_songs.erase(spell_name)
		else:
			GameLog.log_general("Insufficient mana to use [b]%s[/b]!" % spell_display_name(spell_name))
		return false

	if combat_node.is_casting:
		if not is_auto_recast:
			GameLog.log_general("You are already casting a spell.")
		return false

	var display_name    := spell_display_name(spell_name)
	var spell_target    := spell.get("target", "enemy") as String
	var target_node: Node = current_target if (current_target and is_instance_valid(current_target)) else null

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
				GameLog.log_general("[color=#ff8866]Your target for [b]%s[/b] is gone — the song fades.[/color]" % display_name)
				_active_songs.erase(spell_name)
			else:
				GameLog.log_general("Your target is already dead.")
			return false
		if TargetFrame.faction_status(target_node) == "Ally":
			if not is_auto_recast:
				GameLog.log_general("You can't target an ally with [b]%s[/b]." % display_name)
			return false

	# Begin cast message
	GameLog.log_general(CombatLogFormatter.begin_cast("You"))

	# Commit mana and cooldown
	combat_node.current_mana -= cost
	_spell_cooldowns[spell_name] = float(spell.get("recast_time", 10.0))

	# Tick spell_casting skill
	_tick_skill("spell_casting")

	# Also tick the spell's own governing skill (e.g. necromancy, evocation,
	# mantis_fist), so schools/classifications level individually, not just
	# the broad spell_casting skill.
	var skill_category: String = spell.get("skill_category", "")
	if not skill_category.is_empty():
		_tick_skill(skill_category)

	_trigger_cast_animation(spell)

	var cast_time: float = float(spell.get("casting_time", 0.0))
	if cast_time <= 0.0:
		_resolve_spell_cast(spell_name, spell, target_node)
		return true

	_pending_cast_spell = spell_name
	_pending_cast_spell_data = spell
	_pending_cast_target = target_node
	casting_spell_name = display_name
	combat_node.start_spell_cast(cast_time)
	return true


# Runs the actual spell effect — either immediately (instant-cast spells) or
# once _tick_spell_cast() finishes counting down a real cast time. target_node
# is whatever was locked in when the cast began, not necessarily current_target
# anymore (see cast_spell() above).
func _resolve_spell_cast(spell_name: String, spell: Dictionary, target_node: Node) -> void:
	var display_name    := spell_display_name(spell_name)
	var school: String   = spell.get("spell_school", "magic")
	var spell_target    := spell.get("target", "enemy") as String
	var base_damage: int = spell.get("damage", 0)
	var effect_type_raw  = spell.get("effect_type", "")
	var effect_type: String = effect_type_raw if effect_type_raw is String else ""

	# "reactive" spells (e.g. Improved Parry, Spell Ward) are defensive
	# self-effects by design — some have a mis-authored "enemy" target in the
	# data, so force self-targeting here rather than trusting that field for
	# this spell_type.
	if spell.get("spell_type", "") == "reactive":
		spell_target = "self"

	match spell_target:
		# Teleport-style spells with no real target field wired up yet —
		# swift_step/wind_dash (Aetherfist), blink (Arcanist), chaos_rift
		# (Chaosborn) all share this "none" target and are still unbuilt
		# (casting them currently just spends mana/cooldown and does
		# nothing, same bug Shadowstep had); only Shadowstep is implemented
		# so far, per the user's specific request.
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
				GameLog.log_general("[color=#8866ff]You vanish into the shadows behind %s.[/color]" % TargetFrame.display_name(target_node))
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
			if not target_node.has_method("apply_damage"):
				return

			combat_node.break_invisibility()
			last_attack_time_ms = Time.get_ticks_msec()

			var target_cn = target_node.get("combat_node")
			var target_desc: String = target_node.get("monster_description") \
				if target_node.get("monster_description") != "" else target_node.get_monster_name()

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

			var final_dmg: int
			if school == "physical":
				# Physical combat abilities scale with STR and are mitigated by AC
				final_dmg = base_damage + int(combat_node.strength / 2.0)
				if target_cn is CombatNode:
					final_dmg = combat_node.apply_ac_mitigation(final_dmg, target_cn)
				final_dmg = max(1, final_dmg)
				target_node.apply_damage(final_dmg, "physical")
			else:
				# Magical spells scale with arcane/divine power and are
				# resisted by the specific damage type they deal (school
				# directly IS the resist_type — see calculate_spell_damage()).
				final_dmg = combat_node.calculate_spell_damage(base_damage, school, target_cn)
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

			GameLog.log_combat(CombatLogFormatter.spell_damage("You", spell_name, target_desc, final_dmg))
			_broadcast_combat(CombatLogFormatter.spell_damage(player_name, spell_name, target_desc, final_dmg))

			if target_node.has_method("add_threat"):
				target_node.add_threat(self, combat_node.generate_threat(final_dmg))

			match spell_name:
				"life_siphon":
					var heal_pct := randf_range(0.30, 0.70)
					var heal_amount := int(final_dmg * heal_pct * (1.0 + combat_node.get_modifier("life_drain_heal_mult")))
					var healed := combat_node.heal(heal_amount)
					if healed > 0:
						GameLog.log_general("[color=#66ff99]You siphon life, healing yourself for [b]%d[/b].[/color]" % healed)
						_broadcast_combat("[color=#66ff99]%s siphons life, healing themself for [b]%d[/b].[/color]" % [player_name, healed])
						if target_node.has_method("add_threat"):
							target_node.add_threat(self, combat_node.generate_threat(0, healed))
				"necrotic_grasp":
					if target_cn is CombatNode:
						_buff_target(target_node, target_cn, "necrotic_grasp", 6.0, {"speed_slow": 0.15, "attack_speed_slow": 0.15})
						GameLog.log_general("[color=#8866ff]%s is gripped by necrotic energy, slowing them.[/color]" % target_desc.capitalize())
						_broadcast_combat("[color=#8866ff]%s is gripped by necrotic energy, slowing them.[/color]" % target_desc.capitalize())
				"curse_of_weakness":
					if target_cn is CombatNode:
						_buff_target(target_node, target_cn, "curse_of_weakness", 10.0, {"damage_mult": -0.05})
						GameLog.log_general("[color=#8866ff]%s is weakened, their attacks feeble.[/color]" % target_desc.capitalize())
						_broadcast_combat("[color=#8866ff]%s is weakened, their attacks feeble.[/color]" % target_desc.capitalize())
				"plague_strike":
					if target_cn is CombatNode:
						_buff_target(target_node, target_cn, "plague_strike", 8.0, {}, 5, 1.0)
						GameLog.log_general("[color=#77aa44]%s is wracked with plague.[/color]" % target_desc.capitalize())
						_broadcast_combat("[color=#77aa44]%s is wracked with plague.[/color]" % target_desc.capitalize())
				"soul_leech":
					if target_cn is CombatNode:
						var drained := int(target_cn.max_mana * 0.03)
						target_cn.current_mana = maxf(0.0, target_cn.current_mana - drained)
						var healed := combat_node.heal(int(drained * 0.30))
						if healed > 0:
							GameLog.log_general("[color=#66ff99]You leech %d mana from %s, healing yourself for [b]%d[/b].[/color]" % [drained, target_desc, healed])
							_broadcast_combat("[color=#66ff99]%s leeches %d mana from %s, healing themself for [b]%d[/b].[/color]" % [player_name, drained, target_desc, healed])
				"improved_disarm":
					if randf() < 0.40:
						if "attack_timer" in target_node and "attack_cooldown" in target_node:
							_disable_target(target_node, 2.0)
						GameLog.log_general("[color=#ffcc66]You disarm %s, disrupting their attack![/color]" % target_desc)
						_broadcast_combat("[color=#ffcc66]%s disarms %s, disrupting their attack![/color]" % [player_name, target_desc])
					else:
						GameLog.log_general("Your disarm attempt on %s fails." % target_desc)
				"taunt":
					if target_node.has_method("taunt"):
						target_node.taunt(self)
						GameLog.log_general("[color=#ffcc66]You bellow a challenge — %s's fury turns on you![/color]" % target_desc)
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
			match spell_name:
				"shadow_aura":
					combat_node.apply_effect("shadow_aura", 900.0, {})
					GameLog.log_combat("[color=#8888ff]Shadows coil around you, throwing off nearby enemies' aim.[/color]")
				"blood_ritual":
					var cost_hp: int = maxi(1, int(combat_node.max_hp * 0.10))
					combat_node.current_hp = maxi(1, combat_node.current_hp - cost_hp)
					combat_node.apply_effect("blood_ritual", 8.0, {"damage_mult": 0.10})
					GameLog.log_combat("[color=#ff4444]You sacrifice %d health, empowering your attacks![/color]" % cost_hp)
				"shadowlight":
					combat_node.apply_effect("shadowlight", 3600.0, {})
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
					combat_node.apply_effect("deaths_echo", 30.0, {})
					GameLog.log_combat("[color=#aa88ff]Death's Echo lingers, ready to answer your next kill.[/color]")
				"deathly_visage":
					combat_node.apply_effect("deathly_visage", 900.0, {"see_invisible": 1.0})
					_enable_deathly_visage_light()
					GameLog.log_combat("[color=#88bbcc]A pale, deathly light fills your eyes — the unseen becomes visible.[/color]")
				"invisibility":
					combat_node.apply_effect("invisibility", 8.0, {"invisible": 1.0})
					GameLog.log_general("[color=#aaaaaa]You fade from sight...[/color]")
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
				if monster.global_position.distance_to(target_node.global_position) <= 4.0:
					cone_targets.append(monster)

			for hit_target in cone_targets:
				if not hit_target.has_method("apply_damage"):
					continue
				var hit_cn = hit_target.get("combat_node")
				var hit_desc: String = hit_target.get("monster_description") \
					if hit_target.get("monster_description") != "" else hit_target.get_monster_name()
				var cone_dmg: int = base_damage + int(combat_node.strength / 2.0)
				if hit_cn is CombatNode:
					cone_dmg = combat_node.apply_ac_mitigation(cone_dmg, hit_cn)
				cone_dmg = max(1, cone_dmg)
				hit_target.apply_damage(cone_dmg, "physical")

				# Same networking relay as the "enemy" branch above — each
				# cone target needs its own check/relay since they're
				# independent monsters.
				var hit_is_networked_monster: bool = hit_target is Monster and not hit_target.is_multiplayer_authority()
				if hit_is_networked_monster and cone_dmg > 0:
					hit_target.apply_networked_damage.rpc_id(1, cone_dmg, multiplayer.get_unique_id())

				GameLog.log_combat(CombatLogFormatter.spell_damage("You", spell_name, hit_desc, cone_dmg))
				_broadcast_combat(CombatLogFormatter.spell_damage(player_name, spell_name, hit_desc, cone_dmg))
				if hit_target.has_method("add_threat"):
					hit_target.add_threat(self, combat_node.generate_threat(cone_dmg))
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
			if player_class == "Troubadour":
				_cast_troubadour_group_song(spell_name, spell, effect_type, base_damage, display_name)
				return

			var ally_target: Node = self
			if target_node != null and is_instance_valid(target_node) and TargetFrame.faction_status(target_node) != "Enemy":
				ally_target = target_node
			var ally_cn = ally_target.get("combat_node")
			var ally_desc: String = "yourself" if ally_target == self else TargetFrame.display_name(ally_target)
			# Same "yourself" swap as _apply_generic_spell_effect's bcast_desc
			# — an ally-target broadcast naming this caster's real name when
			# the target is themself, otherwise the same name every observer
			# already sees.
			var ally_bcast_desc: String = player_name if ally_target == self else ally_desc

			match spell_name:
				"spirit_mend":
					if ally_cn is CombatNode:
						var healed: int = _heal_target(ally_target, ally_cn, base_damage)
						GameLog.log_combat("[color=#66ff99]You mend %s, restoring [b]%d[/b] health.[/color]" % [ally_desc, healed])
						_broadcast_combat(CombatLogFormatter.spell_heal(player_name, spell_name, ally_bcast_desc, healed))
				"ancestral_guidance":
					if ally_cn is CombatNode:
						_buff_target(ally_target, ally_cn, "ancestral_guidance", 8.0, {"damage_mult": 0.05})
						GameLog.log_general("[color=#88ffcc]Ancestral spirits quicken %s.[/color]" % ally_desc)
						_broadcast_combat("[color=#88ffcc]Ancestral spirits quicken %s.[/color]" % ally_bcast_desc)
				"earth_totem":
					# True small-radius group buff: caster + any non-Enemy within 8m.
					var protected: Array = [self]
					for node in get_tree().get_nodes_in_group("pets") + get_tree().get_nodes_in_group("npc_guard") + get_tree().get_nodes_in_group("npc_vendor"):
						if is_instance_valid(node) and node != self and global_position.distance_to(node.global_position) <= 8.0:
							protected.append(node)
					for node in protected:
						var cn = node.get("combat_node")
						if cn is CombatNode:
							cn.apply_effect("earth_totem", 15.0, {"damage_taken_mult": 0.05})
					GameLog.log_general("[color=#88cc66]You plant an Earth Totem, warding %d nearby allies.[/color]" % protected.size())
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
				if global_position.distance_to(monster.global_position) <= 8.0:
					pbaoe_targets.append(monster)
			if pbaoe_targets.is_empty():
				GameLog.log_general("Nothing is close enough to hit with [b]%s[/b]." % display_name)
				return
			for hit_target in pbaoe_targets:
				if not hit_target.has_method("apply_damage"):
					continue
				var hit_cn = hit_target.get("combat_node")
				var hit_desc: String = hit_target.get("monster_description") \
					if hit_target.get("monster_description") != "" else hit_target.get_monster_name()
				var pbaoe_dmg: int = _compute_spell_damage(base_damage, school, hit_cn)
				hit_target.apply_damage(pbaoe_dmg, "physical" if school == "physical" else "magic")
				var hit_is_networked_monster: bool = hit_target is Monster and not hit_target.is_multiplayer_authority()
				if hit_is_networked_monster and pbaoe_dmg > 0:
					hit_target.apply_networked_damage.rpc_id(1, pbaoe_dmg, multiplayer.get_unique_id())
				GameLog.log_combat(CombatLogFormatter.spell_damage("You", spell_name, hit_desc, pbaoe_dmg))
				_broadcast_combat(CombatLogFormatter.spell_damage(player_name, spell_name, hit_desc, pbaoe_dmg))
				if hit_target.has_method("add_threat"):
					hit_target.add_threat(self, combat_node.generate_threat(pbaoe_dmg))
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
				var hit_desc: String = hit_target.get("monster_description") \
					if hit_target.get("monster_description") != "" else hit_target.get_monster_name()
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

		# No real target at all — utility spells like a short teleport
		# (Blink, Swift Step). Distance comes from the spell's own "range"
		# field (e.g. "15m") so it stays data-driven per spell.
		"none":
			if spell.get("spell_type", "") == "teleport":
				var blink_distance: float = 10.0
				var range_str: String = str(spell.get("range", ""))
				if range_str.ends_with("m"):
					blink_distance = range_str.trim_suffix("m").to_float()
				var forward: Vector3 = -global_transform.basis.z
				global_position += forward * blink_distance
				GameLog.log_general("[color=#8888ff]You blink forward in a flash.[/color]")
			else:
				GameLog.log_combat("You use [b]%s[/b]." % display_name)


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
func _cast_troubadour_group_song(spell_name: String, spell: Dictionary, effect_type: String, base_damage: int, display_name: String) -> void:
	var radius: float = float(spell.get("aoe_radius", 8.0))
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
		if _apply_generic_spell_effect(effect_type, spell, combat_node, recipient_cn, recipient, recipient_desc):
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
		if target_cn is CombatNode:
			dmg = combat_node.apply_ac_mitigation(dmg, target_cn)
		return max(1, dmg)
	return combat_node.calculate_spell_damage(base_damage, school, target_cn)


# Generic, data-driven fallback for any spell whose effect_type isn't covered
# by one of the per-spell-name special cases in _resolve_spell_cast() above.
# This is what makes a newly-added class's spells (or any future one) do
# something sensible immediately, instead of being a silent damage-only/no-op
# until someone hand-writes bespoke code for it — named special cases above
# always take priority and are untouched by this. Returns true if it
# recognized and applied the effect_type, false if the caller should fall
# back to a generic flavor-text message.
func _apply_generic_spell_effect(effect_type: String, spell: Dictionary, caster_cn: CombatNode, target_cn, target_node: Node, target_desc: String) -> bool:
	if not (target_cn is CombatNode):
		return false

	var effect_name: String = spell.get("spell_name", "spell_effect")
	var duration_raw = spell.get("duration", 0)
	var duration: float = 0.0 if duration_raw is String else float(duration_raw)
	var magnitude: int = int(spell.get("damage", 0))

	# Racial resistance/immunity to harmful effects (Halfling's general
	# negative_effect_resist chance, Elf's root immunity, Dark Elf's blind
	# immunity) — checked against whichever entity is ON THE RECEIVING END
	# (target_cn), before any of it actually applies. "heal"/"hot"/"buff"/
	# "cure"/"absorb" are beneficial-or-neutral and never resistable this way.
	const NEGATIVE_EFFECT_TYPES := ["debuff", "dot", "snare", "stun", "fear",
		"charm", "mesmerize", "confuse", "root", "blind", "silence"]
	if effect_type in NEGATIVE_EFFECT_TYPES:
		if effect_type == "root" and target_cn.race_immune_to_root:
			GameLog.log_general("[color=#88ccff]%s is immune to being rooted.[/color]" % target_desc.capitalize())
			return false
		if effect_type == "blind" and target_cn.race_immune_to_blind:
			GameLog.log_general("[color=#88ccff]%s is immune to blindness.[/color]" % target_desc.capitalize())
			return false
		if target_cn.rolls_resist_negative_effect():
			GameLog.log_general("[color=#88ccff]%s resists the effect![/color]" % target_desc.capitalize())
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
	var self_cast_message: String = spell.get("cast_message", "") if target_desc == "yourself" else ""

	match effect_type:
		"heal":
			var healed: int = _heal_target(target_node, target_cn, magnitude)
			if healed <= 0:
				return false
			var heal_msg: String = self_cast_message if not self_cast_message.is_empty() \
				else "[color=#66ff99]%s healed for [b]%d[/b].[/color]" % [target_desc.capitalize(), healed]
			GameLog.log_combat(heal_msg)
			_broadcast_combat("[color=#66ff99]%s healed for [b]%d[/b].[/color]" % [bcast_desc.capitalize(), healed])
			return true
		"hot":
			if duration <= 0.0:
				return false
			var ticks := maxi(1, int(round(duration)))
			var per_tick := maxi(1, int(round(float(magnitude) / ticks)))
			_buff_target(target_node, target_cn, effect_name, duration, {}, 0, 1.0, per_tick)
			var hot_msg: String = self_cast_message if not self_cast_message.is_empty() \
				else "[color=#66ff99]%s begins regenerating health.[/color]" % target_desc.capitalize()
			GameLog.log_combat(hot_msg)
			_broadcast_combat("[color=#66ff99]%s begins regenerating health.[/color]" % bcast_desc.capitalize())
			return true
		"dot":
			if duration <= 0.0:
				return false
			var ticks := maxi(1, int(round(duration)))
			var per_tick := maxi(1, int(round(float(magnitude) / ticks)))
			_buff_target(target_node, target_cn, effect_name, duration, {}, per_tick, 1.0)
			GameLog.log_combat("[color=#77aa44]%s is afflicted with a lingering effect.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#77aa44]%s is afflicted with a lingering effect.[/color]" % bcast_desc.capitalize())
			return true
		"buff":
			if duration <= 0.0:
				return false
			_buff_target(target_node, target_cn, effect_name, duration, {"damage_mult": 0.05})
			var buff_msg: String = self_cast_message if not self_cast_message.is_empty() \
				else "[color=#88ffcc]%s is empowered.[/color]" % target_desc.capitalize()
			GameLog.log_general(buff_msg)
			_broadcast_combat("[color=#88ffcc]%s is empowered.[/color]" % bcast_desc.capitalize())
			return true
		"debuff":
			if duration <= 0.0:
				return false
			_buff_target(target_node, target_cn, effect_name, duration, {"damage_mult": -0.05})
			GameLog.log_general("[color=#8866ff]%s is weakened.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#8866ff]%s is weakened.[/color]" % bcast_desc.capitalize())
			return true
		"snare":
			if duration <= 0.0:
				return false
			_buff_target(target_node, target_cn, effect_name, duration, {"speed_slow": 0.15, "attack_speed_slow": 0.15})
			GameLog.log_general("[color=#8866ff]%s is slowed.[/color]" % target_desc.capitalize())
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
				GameLog.log_general("[color=#ffcc66]%s flees in terror![/color]" % target_desc.capitalize())
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
				GameLog.log_general("[color=#ffcc66]%s is charmed![/color]" % target_desc.capitalize())
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
			GameLog.log_general("[color=#8866ff]%s is rooted in place.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#8866ff]%s is rooted in place.[/color]" % bcast_desc.capitalize())
			return true
		"blind":
			if duration <= 0.0:
				return false
			_buff_target(target_node, target_cn, effect_name, duration, {"hit_chance": -25.0})
			GameLog.log_general("[color=#8866ff]%s is blinded.[/color]" % target_desc.capitalize())
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
			GameLog.log_general("[color=#8888ff]%s is silenced.[/color]" % target_desc.capitalize())
			_broadcast_combat("[color=#8888ff]%s is silenced.[/color]" % bcast_desc.capitalize())
			return true
		"cure":
			var to_remove: String = _find_debuff_to_cure(target_cn)
			if to_remove.is_empty():
				return false
			_remove_effect_from_target(target_node, target_cn, to_remove)
			GameLog.log_general("[color=#88ffaa]%s is cleansed of %s.[/color]" % [
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
			target_cn.apply_effect(effect_name, duration, {})
			target_cn.active_effects[effect_name]["absorb_remaining"] = magnitude
			GameLog.log_general("[color=#8866ff]%s is shielded, absorbing damage.[/color]" % target_desc.capitalize())
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
func _heal_target(target_node: Node, target_cn, amount: int) -> int:
	if not (target_cn is CombatNode):
		return 0
	if target_node == self or target_node.is_multiplayer_authority() \
			or not target_node.has_method("apply_networked_heal"):
		var healed: int = target_cn.heal(amount)
		if target_node.has_method("_check_bleedout_revival"):
			target_node._check_bleedout_revival()
		return healed
	target_node.apply_networked_heal.rpc_id(target_node.get_multiplayer_authority(), amount)
	return amount


func _buff_target(target_node: Node, target_cn, effect_name: String, duration: float,
		modifiers: Dictionary, tick_dmg: int = 0, tick_interval: float = 1.0, tick_heal: int = 0) -> void:
	if not (target_cn is CombatNode):
		return
	if target_node == self or target_node.is_multiplayer_authority():
		target_cn.apply_effect(effect_name, duration, modifiers, tick_dmg, tick_interval, tick_heal)
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


@rpc("any_peer", "call_remote", "reliable")
func apply_networked_heal(amount: int) -> void:
	if not is_multiplayer_authority():
		return
	var healed := combat_node.heal(amount)
	if healed > 0:
		GameLog.log_general("[color=#66ff99]You are healed for [b]%d[/b].[/color]" % healed)
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
	if animation_player and animation_player.has_animation("death") and animation_player.is_playing():
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
		if not spell.is_empty() and spell.get("target", "") == "enemy":
			return effect_name
	return ""


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
	if target_node.is_multiplayer_authority() or not target_node.has_method("apply_networked_disable"):
		target_node.can_attack = false
		target_node.attack_timer = duration
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
	if not is_instance_valid(_shadowlight_light):
		_shadowlight_light = OmniLight3D.new()
		# Bumped 2026-09-17 (was energy 0.6 / range 4.0 — barely noticeable,
		# especially now that night is darker overall) — noticeable violet
		# glow across ~5m without reading as a full light source.
		_shadowlight_light.light_color = Color(0.62, 0.35, 0.95)
		_shadowlight_light.light_energy = 1.4
		_shadowlight_light.omni_range = 5.0
		_shadowlight_light.omni_attenuation = 1.4  # falls off a bit faster than default so it stays a "glow," not a floodlight
		_shadowlight_light.position = Vector3(0, 1.3, 0)
		add_child(_shadowlight_light)
	_shadowlight_light.visible = true


# pet_type keys into PET_SCENES and is saved to Global.player_data so
# _restore_pet_if_saved() knows which scene to bring back on next login —
# before phantasmal_echo, only one pet type ever existed so this field didn't
# need to exist yet.
const PET_SCENES := {
	"spectral_minion": "res://Scenes/pet_minion.tscn",
	"raised_skeleton": "res://Scenes/pet_minion.tscn",
	"phantasmal_echo": "res://Scenes/phantasmal_echo_pet.tscn",
	"spirit_of_the_woods": "res://Scenes/wildspeaker_pet.tscn",
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
func _summon_pet(pet_type: String, preset_name: String = "") -> void:
	if is_instance_valid(active_pet):
		active_pet.queue_free()
	if is_instance_valid(active_pet_frame):
		active_pet_frame.queue_free()

	$PetSpawner.spawn({"pet_type": pet_type, "preset_name": preset_name})


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
	pet.setup(self, preset_name)
	active_pet = pet
	pet.dismissed.connect(_on_pet_gone)
	pet.died.connect(_on_pet_gone)
	pet.died.connect(_on_pet_died)

	if is_multiplayer_authority():
		_apply_pet_gear_bonus()

		Global.player_data["pet_active"] = true
		Global.player_data["pet_type"] = pet_type
		Global.player_data["pet_name"] = pet.pet_name
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
	match Global.player_data.get("pet_mode", 0):
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
		_summon_pet(Global.player_data.get("pet_type", "spectral_minion"), Global.player_data.get("pet_name", ""))


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
		"CONCENTRATION_FAILURE":
			GameLog.log_general("[color=#ff8866]%s[/color]" % result.get("message", ""))
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
					_buff_target(monster, mob_cn, "shadow_aura_debuff", 1.5, {"hit_chance": -5.0})


func _tick_skill(skill_name: String) -> void:
	if skill_name.is_empty() or skill_name == "none":
		return
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
	var cap: int = _skill_max
	if current >= cap:
		return
	var chance: float = 0.15 * (1.0 - float(current) / float(cap))
	if randf() < chance:
		skill_levels[skill_name] += 1
		GameLog.log_general("You've become better at [b]%s[/b]! (%d)" % [
			skill_name.replace("_", " ").capitalize(), skill_levels[skill_name]
		])
		_sync_weapon_skill()
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
func _tick_defense_skill(result: String) -> void:
	match result:
		"PARRY":
			_tick_skill("parry")
		"DODGE":
			_tick_skill("dodge")
		"BLOCK":
			_tick_skill("block")
		"RIPOSTE":
			_tick_skill("riposte")


func _sync_weapon_skill() -> void:
	var weapon := Inventory.get_equipped_weapon()
	if weapon.is_empty():
		return
	var skey: String = weapon.get("skill", "").to_lower().replace(" ", "_")
	if skey.is_empty() or skey == "none":
		return
	combat_node.weapon_skill = skill_levels.get(skey, 0)
	combat_node._stats_dirty = true


func on_level_up(new_level: int) -> void:
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
# player_class explicitly is before saving). Both this list and
# ULTRAVISION_RACES below were written with the CAPITALIZED DISPLAY names
# ("Elf", "Half-Elf") instead, so neither ever actually matched anything —
# race-based tracking has silently never worked for any race, and
# ultravision never worked for ANY race at all (not even the single-word
# ones, since "elf" != "Elf"). Class-based tracking (TRACKING_CLASSES) was
# unaffected since player_class genuinely is capitalized before saving.
const TRACKING_RACES := ["elf", "half_elf"]
const TRACKING_CLASSES := ["Woodstalker", "Wildspeaker", "Troubadour"]

func has_tracking_skill() -> bool:
	return player_race in TRACKING_RACES or player_class in TRACKING_CLASSES


# Ultravision — per user request (2026-09-17): "most elves, trolls, etc have
# it," mirroring character_options.json's per-race "ultravision" trait
# (everyone except Human). Kept as its own const/func here rather than
# reading character_options.json at call time, matching TRACKING_RACES'
# existing pattern — camera_controller.gd (the only caller) checks this every
# time the day/night phase flips, so it needs to be cheap. See TRACKING_RACES'
# comment above for why these are the lowercase-key form, not display names.
const ULTRAVISION_RACES := ["elf", "half_elf", "dwarf", "gnome", "halfling", "ogre", "troll", "dark_elf", "half_orc", "lizardkin"]

func has_ultravision() -> bool:
	return player_race in ULTRAVISION_RACES


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


func toggle_abilities_book() -> void:
	if abilities_book_instance:
		abilities_book_instance.queue_free()
		abilities_book_instance = null
	else:
		abilities_book_instance = load("res://Scenes/abilities_book.tscn").instantiate()
		get_tree().root.add_child(abilities_book_instance)
		if abilities_book_instance.has_method("set_player"):
			abilities_book_instance.set_player(self)


func toggle_backpack() -> void:
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
