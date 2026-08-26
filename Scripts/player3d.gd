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
var known_spells: Array = []
var known_skills: Array = []
var skill_levels: Dictionary = {}
var regen_bonus: int = 0  # Racial bonus HP added to each regen tick (e.g. Troll regeneration)
var action_bar_slots: Array = []  # Array of {type, name} dicts, 12 elements
var _spell_cache: Dictionary = {}
var _spell_by_name: Dictionary = {}
var _skill_data: Dictionary = {}   # flat skill_name -> description
var _spell_cooldowns: Dictionary = {}
var _skill_cooldowns: Dictionary = {}
var _appraisal_cooldowns: Dictionary = {}  # target instance ID -> remaining seconds
var active_pet: Node = null
var active_pet_frame: Node = null
var current_stance: String = ""

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
	"lightsworn", "lightmender", "spiritcaller", "wildspeaker",
	"woodstalker", "aetherfist", "troubadour", "spiritweaver"
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
var dying: bool = false
var attacking: bool = false
var autoattack_enabled: bool = false
var attack_cooldown: float = 0.0
var attack_cooldown_duration: float = 1.0
var current_target: Node = null
var _target_idx: int = -1
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
#endregion

#region Node references
@onready var camera_rig: Node3D = $CameraRig
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
#endregion

#region Loot interaction
const LOOT_RANGE := 5.0

var _pause_menu_instance: Node = null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_try_loot_corpse()
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
					_try_click_target(event.position)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not event.ctrl_pressed:
			_toggle_pause_menu()
			return

		if event.is_action_pressed("hail") and not (get_viewport().gui_get_focus_owner() is LineEdit):
			try_hail_nearby_npc()
			return

		if event.is_action_pressed("appraise") and not (get_viewport().gui_get_focus_owner() is LineEdit):
			try_appraise_target()
			return

		const SLOT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]
		var idx := SLOT_KEYS.find(event.keycode)
		if idx >= 0 and idx < action_bar_slots.size():
			var slot: Dictionary = action_bar_slots[idx]
			match slot.get("type", ""):
				"spell": cast_spell(slot["name"])
				"skill": use_skill(slot["name"])


func _toggle_pause_menu() -> void:
	if is_instance_valid(_pause_menu_instance):
		_pause_menu_instance.queue_free()
		_pause_menu_instance = null
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	_pause_menu_instance = load("res://Scenes/pause_menu.tscn").instantiate()
	_pause_menu_instance.closed.connect(func():
		_pause_menu_instance = null
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	)
	get_tree().root.add_child(_pause_menu_instance)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

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

	if nearest.is_lootable:
		nearest.open_loot_window()
	else:
		GameLog.log_general("You search the corpse but find nothing upon it.")


const HAIL_RANGE := 5.0

func try_hail_nearby_npc() -> void:
	var nearest: Node = null
	var nearest_dist := HAIL_RANGE

	for node in get_tree().get_nodes_in_group("npc_guard"):
		if not is_instance_valid(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node

	if nearest == null:
		GameLog.log_general("There's no one nearby to hail.")
		return

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

	var target_level := int(current_target.get("level") if "level" in current_target else 1)
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

	combat_node = CombatNode.new()
	add_child(combat_node)

	Inventory.equipment_changed.connect(_on_equipment_changed)

	load_faction_standing()
	_load_spell_cache()
	load_player_data_from_global()
	_spawn_hud()

	print("[Player3D] ✅ %s initialized | HP: %d/%d | Mana: %d/%d" % [
		player_name, combat_node.current_hp, combat_node.max_hp,
		combat_node.current_mana, combat_node.max_mana
	])


func _spawn_hud() -> void:
	var root = get_tree().root
	for scene_path in [
		"res://Scenes/player_frame.tscn",
		"res://Scenes/target_frame.tscn",
		"res://Scenes/game_log_window.tscn",
		"res://Scenes/action_bar.tscn",
		"res://Scenes/stance_bar.tscn",
	]:
		var node: Node = load(scene_path).instantiate()
		node.add_to_group("game_hud")
		root.add_child(node)
	GameLog.log_general("Welcome, [b]%s[/b]." % player_name)
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

	# Load skill descriptions — flatten {category: {name: desc}} into {name: desc}
	var sf := FileAccess.open("res://Data/player_skills.json", FileAccess.READ)
	if sf:
		var sd = JSON.parse_string(sf.get_as_text())
		sf.close()
		if typeof(sd) == TYPE_DICTIONARY:
			for category in sd:
				var cat = sd[category]
				if typeof(cat) == TYPE_DICTIONARY:
					for skill_name in cat:
						_skill_data[skill_name] = cat[skill_name]
#endregion

#region Physics process (movement / stamina / combat)
func _physics_process(delta: float) -> void:
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

	move_and_slide()
#endregion

#region Process (regen / vitals / cooldowns)
func _process(delta: float) -> void:
	if dying:
		return

	regen_timer += delta
	if regen_timer >= REGEN_INTERVAL:
		regen_timer = 0.0

		if combat_node.current_hp < combat_node.max_hp:
			var regen_h: int = combat_node.get_derived_stat("hp_regen") + regen_bonus
			if is_sitting:
				regen_h = int(regen_h * 3.0)
			if satiety < 25:
				regen_h = int(regen_h * 0.8)
			combat_node.current_hp = mini(combat_node.current_hp + regen_h, combat_node.max_hp)

		if combat_node.current_mana < combat_node.max_mana:
			var regen_m: int = combat_node.get_derived_stat("mana_regen")
			if is_sitting:
				regen_m = int(regen_m * 3.0)
			if thirst < 25:
				regen_m = int(regen_m * 0.8)
			combat_node.current_mana = mini(combat_node.current_mana + regen_m, combat_node.max_mana)

	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	update_vitals_decay(delta)
#endregion

#region Vitals decay system
func update_vitals_decay(delta: float) -> void:
	satiety_timer += delta
	thirst_timer += delta

	if satiety_timer >= DECAY_INTERVAL:
		satiety_timer = 0.0
		satiety = max(satiety - int(SATIETY_DECAY_RATE), 0)
		if satiety <= 0:
			apply_starvation_damage()
		elif satiety < 25:
			print("🍖 Warning: Getting hungry! (%d/100)" % satiety)

	if thirst_timer >= DECAY_INTERVAL:
		thirst_timer = 0.0
		thirst = max(thirst - int(THIRST_DECAY_RATE), 0)
		if thirst <= 0:
			apply_dehydration_damage()
		elif thirst < 25:
			print("💧 Warning: Getting thirsty! (%d/100)" % thirst)


func apply_starvation_damage() -> void:
	var dmg: int = max(1, int(combat_node.max_hp * 0.01))
	combat_node.take_damage(dmg)
	combat_node.current_hp = max(combat_node.current_hp, 1)  # starvation can't kill
	print("💀 STARVING! Taking %d damage." % dmg)


func apply_dehydration_damage() -> void:
	var dmg: int = max(1, int(combat_node.max_hp * 0.02))
	combat_node.take_damage(dmg)
	combat_node.current_hp = max(combat_node.current_hp, 1)  # dehydration can't kill
	print("💀 DEHYDRATED! Taking %d damage." % dmg)


func get_stat_penalty() -> float:
	var penalty := 1.0
	if satiety < 25:
		penalty *= 0.95
	if thirst < 25:
		penalty *= 0.90
	return penalty
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

	var forward_dir: Vector3 = -transform.basis.z.normalized()
	var right_dir: Vector3 = transform.basis.x.normalized()
	var world_move: Vector3 = (right_dir * strafe + forward_dir * forward).normalized()

	velocity.x = world_move.x * target_speed
	velocity.z = world_move.z * target_speed
	current_speed = Vector2(velocity.x, velocity.z).length()


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
	elif is_on_floor():
		var regen_rate: float
		if is_sitting:
			regen_rate = STAMINA_REGEN_SIT
		elif is_moving:
			regen_rate = STAMINA_REGEN_WALK
		else:
			regen_rate = STAMINA_REGEN_STAND
		current_stamina += regen_rate * delta

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
	if autoattack_enabled and current_target and attack_cooldown <= 0.0:
		attack_current_target()
	if Input.is_action_just_pressed("melee_attack") and attack_cooldown <= 0.0:
		perform_melee_attack()
	if Input.is_action_just_pressed("toggle_character_sheet"):
		toggle_character_sheet()
	if Input.is_action_just_pressed("toggle_abilities_book"):
		toggle_abilities_book()



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


func tab_cycle_target() -> void:
	var candidates := get_tree().get_nodes_in_group("monsters") + get_tree().get_nodes_in_group("npc_guard")
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
	if hit and (hit.collider is Monster or hit.collider is GuardNPC):
		var m: Node = hit.collider
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
	attack_cooldown = attack_cooldown_duration

	if "combat_node" in current_target and current_target.combat_node is CombatNode:
		var result = combat_node.resolve_attack(current_target.combat_node)
		if not combat_node.is_alive():
			die()
			return
		if current_target.has_method("add_threat"):
			current_target.add_threat(self, combat_node.generate_threat(result.get("damage", 0)))
		var target_desc: String = current_target.get("monster_description") if current_target.get("monster_description") != "" else current_target.get_monster_name()
		var weapon := Inventory.get_equipped_weapon()
		var weapon_name: String = weapon.get("name", "")
		var dmg_type: String = CombatLogFormatter.damage_type_from_item(weapon)
		var msg: String = CombatLogFormatter.player_attack(result, target_desc, weapon_name, dmg_type)
		if not msg.is_empty():
			GameLog.log_combat(msg)
		if result["result"] == "HIT":
			var skey: String = weapon.get("skill", "").to_lower().replace(" ", "_")
			_tick_skill(skey)
		elif result["result"] == "PARRY":
			_tick_skill("parry")
		elif result["result"] == "DODGE":
			_tick_skill("dodge")
		elif result["result"] == "RIPOSTE":
			_tick_skill("riposte")
		if not current_target.combat_node.is_alive():
			var dead := current_target
			GameLog.log_combat(CombatLogFormatter.death("You", target_desc))
			_set_target_frame(null)
			current_target = null
			autoattack_enabled = false
			GameLog.set_autoattack(false)
			if dead.has_method("die"):
				dead.die()
	else:
		var penalty := get_stat_penalty()
		var total_damage := int(combat_node.calculate_melee_damage(null, combat_node.roll_crit()) * penalty)
		if current_target.has_method("apply_damage"):
			current_target.apply_damage(total_damage, "physical")
			var target_desc: String = current_target.get("monster_description") if current_target.get("monster_description") != "" else current_target.get_monster_name()
			GameLog.log_combat("You hit %s for [b]%d[/b] damage." % [target_desc, total_damage])
		if not is_instance_valid(current_target) or current_target.current_health <= 0:
			var target_desc: String = current_target.get("monster_description") if current_target.get("monster_description") != "" else current_target.get_monster_name()
			GameLog.log_combat("%s has been defeated!" % target_desc.capitalize())
			_set_target_frame(null)
			current_target = null
			autoattack_enabled = false
			GameLog.set_autoattack(false)

	await get_tree().create_timer(0.3).timeout
	attacking = false


func perform_melee_attack() -> void:
	if attacking or dying:
		return

	attacking = true
	attack_cooldown = attack_cooldown_duration

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
			var result = combat_node.resolve_attack(target.combat_node)
			if not combat_node.is_alive():
				die()
				return
			var target_desc: String = TargetFrame.display_name(target)
			var weapon := Inventory.get_equipped_weapon()
			var weapon_name: String = weapon.get("name", "")
			var dmg_type: String = CombatLogFormatter.damage_type_from_item(weapon)
			var msg: String = CombatLogFormatter.player_attack(result, target_desc, weapon_name, dmg_type)
			if not msg.is_empty():
				GameLog.log_combat(msg)
			if result["result"] == "HIT":
				var skey: String = weapon.get("skill", "").to_lower().replace(" ", "_")
				_tick_skill(skey)
			elif result["result"] == "PARRY":
				_tick_skill("parry")
			elif result["result"] == "DODGE":
				_tick_skill("dodge")
			elif result["result"] == "RIPOSTE":
				_tick_skill("riposte")
			if not target.combat_node.is_alive() and target.has_method("die"):
				GameLog.log_combat(CombatLogFormatter.death("You", target_desc))
				if target == current_target:
					_set_target_frame(null)
					current_target = null
				target.die()
		else:
			var penalty := get_stat_penalty()
			var total_damage := int(combat_node.calculate_melee_damage(null, combat_node.roll_crit()) * penalty)
			if target.has_method("apply_damage"):
				target.apply_damage(total_damage, "physical")
				var tname = target.get_monster_name() if target.has_method("get_monster_name") else "enemy"
				GameLog.log_combat("You hit %s for %d damage." % [tname, total_damage])
	else:
		GameLog.log_combat("No target in range.")

	await get_tree().create_timer(0.3).timeout
	attacking = false


func take_damage(amount: int) -> void:
	if dying:
		return
	combat_node.take_damage(amount)
	GameLog.log_combat("💔 You take %d damage. [HP: %d/%d]" % [amount, combat_node.current_hp, combat_node.max_hp])
	if not combat_node.is_alive():
		die()


func apply_damage(amount: int) -> void:
	take_damage(amount)


func die() -> void:
	dying = true
	GameLog.log_combat("[color=red]You have been defeated![/color]")
	print("💀 Player defeated!")


func _set_target_frame(target: Node) -> void:
	for tf in get_tree().get_nodes_in_group("target_frame"):
		tf.set_target(target)
#endregion

#region Character sheet management
func toggle_character_sheet() -> void:
	if character_sheet_instance:
		character_sheet_instance.queue_free()
		character_sheet_instance = null
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
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
					"acid":    combat_node.get_resistance("poison"),
					"cold":    combat_node.get_resistance("cold"),
					"fire":    combat_node.get_resistance("fire"),
					"magic":   combat_node.get_resistance("arcane"),
					"psychic": combat_node.get_resistance("psychic")
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
	stats        = data.get("stats",        {})

	data["resistances"] = data.get("resistances", {
		"acid": 0, "cold": 0, "fire": 0, "magic": 0, "psychic": 0
	})
	data["equipment"] = data.get("equipment", {})

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


func apply_racial_modifiers(race_name: String) -> void:
	match race_name.to_lower():
		"lizardkin":
			combat_node.gear_ac += 2
			combat_node._stats_dirty = true
		"troll":
			regen_bonus = 4  # Troll regeneration trait: +4 HP per regen tick (stacks with sitting bonus)
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
			weapon_dmg = item.get("damage", 0)
		else:
			bonus_ac += item.get("armor_class", 0)

	combat_node.weapon_damage = weapon_dmg
	combat_node.gear_ac       = bonus_ac
	combat_node._stats_dirty  = true
	combat_node.recalculate_derived_stats()


# ================================================================================
# ⭐ SPELL CASTING
# ================================================================================

# Spells whose in-fiction name isn't derivable from the internal snake_case
# spell_name via the usual replace("_"," ").capitalize() convention.
const SPELL_DISPLAY_NAMES := {
	"shadow_aura": "Aura of the Shadow",
	"spectral_minion": "Morthan's Call",
}

static func spell_display_name(spell_name: String) -> String:
	return SPELL_DISPLAY_NAMES.get(spell_name, spell_name.replace("_", " ").capitalize())


func cast_spell(spell_name: String) -> void:
	if spell_name == "improved_block":
		GameLog.log_general("[b]Improved Block[/b] is passive — no need to cast it.")
		return

	var spell: Dictionary = _spell_by_name.get(spell_name, {})
	if spell.is_empty():
		GameLog.log_general("Unknown spell or ability: [b]%s[/b]." % spell_display_name(spell_name))
		return

	var cd_remaining: float = _spell_cooldowns.get(spell_name, 0.0)
	if cd_remaining > 0.0:
		GameLog.log_general("[b]%s[/b] is not ready. (%.1fs remaining)" % [spell_display_name(spell_name), cd_remaining])
		return

	var cost: int = int(spell.get("mana_cost", 0.0))
	if combat_node.current_mana < cost:
		GameLog.log_general("Insufficient mana to use [b]%s[/b]!" % spell_display_name(spell_name))
		return

	var display_name    := spell_display_name(spell_name)
	var school: String   = spell.get("spell_school", "arcane")
	var spell_target    := spell.get("target", "enemy") as String
	var base_damage: int = spell.get("damage", 0)
	var target_node: Node = current_target if (current_target and is_instance_valid(current_target)) else null

	# Begin cast message
	GameLog.log_general(CombatLogFormatter.begin_cast("You"))

	# Commit mana and cooldown
	combat_node.current_mana -= cost
	_spell_cooldowns[spell_name] = float(spell.get("recast_time", 10.0))

	# Tick spell_casting skill
	_tick_skill("spell_casting")

	match spell_target:
		"enemy":
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

			var target_cn = target_node.get("combat_node")
			var target_desc: String = target_node.get("monster_description") \
				if target_node.get("monster_description") != "" else target_node.get_monster_name()

			var final_dmg: int
			if school == "physical":
				# Physical combat abilities scale with STR and are mitigated by AC
				final_dmg = base_damage + int(combat_node.strength / 2.0)
				if target_cn is CombatNode:
					final_dmg = combat_node.apply_ac_mitigation(final_dmg, target_cn)
				final_dmg = max(1, final_dmg)
				target_node.apply_damage(final_dmg, "physical")
			else:
				# Magical spells scale with arcane/divine power and are resisted
				var is_arcane := school in ["arcane", "fire", "cold", "poison", "shadow", "void"]
				final_dmg = combat_node.calculate_spell_damage(base_damage, is_arcane, target_cn)
				target_node.apply_damage(final_dmg, "magic")

			GameLog.log_combat(CombatLogFormatter.spell_damage("You", spell_name, target_desc, final_dmg))

			if target_node.has_method("add_threat"):
				target_node.add_threat(self, combat_node.generate_threat(final_dmg))

			match spell_name:
				"life_siphon":
					var heal_pct := randf_range(0.30, 0.70)
					var heal_amount := int(final_dmg * heal_pct * (1.0 + combat_node.get_modifier("life_drain_heal_mult")))
					var healed := combat_node.heal(heal_amount)
					if healed > 0:
						GameLog.log_general("[color=#66ff99]You siphon life, healing yourself for [b]%d[/b].[/color]" % healed)
						if target_node.has_method("add_threat"):
							target_node.add_threat(self, combat_node.generate_threat(0, healed))
				"necrotic_grasp":
					if target_cn is CombatNode:
						target_cn.apply_effect("necrotic_grasp", 6.0, {"speed_slow": 0.15, "attack_speed_slow": 0.15})
						GameLog.log_general("[color=#8866ff]%s is gripped by necrotic energy, slowing them.[/color]" % target_desc.capitalize())

			if not target_node.combat_node.is_alive():
				GameLog.log_combat(CombatLogFormatter.death("You", target_desc))
				_set_target_frame(null)
				current_target = null
				autoattack_enabled = false
				GameLog.set_autoattack(false)

		"self":
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
					GameLog.log_combat("[color=#8855cc]A dim violet light kindles across your weapon.[/color]")
				"spectral_minion":
					_summon_spectral_minion()
				_:
					GameLog.log_combat("You use [b]%s[/b] on yourself." % display_name)

		"group":
			GameLog.log_combat("[color=#ffdd88]You use [b]%s[/b]! Your battle cry fills the air.[/color]" % display_name)


func _summon_spectral_minion() -> void:
	if is_instance_valid(active_pet):
		active_pet.queue_free()
	if is_instance_valid(active_pet_frame):
		active_pet_frame.queue_free()

	var pet: Node = load("res://Scenes/pet_minion.tscn").instantiate()
	get_tree().current_scene.add_child(pet)
	pet.setup(self)
	active_pet = pet

	var frame: Node = load("res://Scenes/pet_frame.tscn").instantiate()
	get_tree().root.add_child(frame)
	frame.set_pet(pet)
	active_pet_frame = frame

	GameLog.log_general("[color=#aa88ff]You invoke Morthan's Call — a skeleton warrior rises to fight at your side.[/color]")


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


func _tick_cooldowns(delta: float) -> void:
	for spell_name in _spell_cooldowns.keys():
		_spell_cooldowns[spell_name] = maxf(_spell_cooldowns[spell_name] - delta, 0.0)
	for skill_name in _skill_cooldowns.keys():
		_skill_cooldowns[skill_name] = maxf(_skill_cooldowns[skill_name] - delta, 0.0)
	for target_id in _appraisal_cooldowns.keys():
		_appraisal_cooldowns[target_id] = maxf(_appraisal_cooldowns[target_id] - delta, 0.0)


func _tick_active_spell_effects(_delta: float) -> void:
	# shadow_aura: continuously debuff accuracy of nearby monsters while active
	if combat_node.has_effect("shadow_aura"):
		for monster in get_tree().get_nodes_in_group("monsters"):
			if monster.get("current_state") == monster.State.DEAD:
				continue
			if global_position.distance_to(monster.global_position) <= 10.0:
				var mob_cn = monster.get("combat_node")
				if mob_cn is CombatNode:
					mob_cn.apply_effect("shadow_aura_debuff", 1.5, {"hit_chance": -5.0})


func _tick_skill(skill_name: String) -> void:
	if skill_name.is_empty() or skill_name == "none":
		return
	if not skill_levels.has(skill_name):
		return
	var current: int = skill_levels[skill_name]
	var cap: int = 252
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
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		print("🎒 Backpack closed")
	else:
		backpack_instance = backpack_scene.instantiate()
		get_tree().root.add_child(backpack_instance)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		print("🎒 Backpack opened")
