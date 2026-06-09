# player.gd — 2D player controller
extends CharacterBody2D

@export var speed = 200.0

var combat_node: CombatNode
var player_name := "Default Hero"
var player_class := ""
var player_race := ""
var known_spells: Array = []
var _spell_cache: Dictionary = {}

var last_direction: Vector2 = Vector2.RIGHT
var faction_standing: Dictionary = {"Villagers of Lumora": 50}

var caster_classes := [
	"voidknight", "gravecaller", "runecaster", "arcanist", "chaosborn",
	"lightsworn", "lightmender", "spiritcaller", "wildspeaker", "woodstalker",
	"troubadour", "spiritweaver"
]

var magic_missile_scene: PackedScene = preload("res://Scenes/magic_missile.tscn")
var ranged_attack_scene: PackedScene = preload("res://Scenes/ranged_attack.tscn")
var magic_missile_cooldown := 0.0
var ranged_attack_cooldown := 0.0
var ranged_attack_cooldown_duration := 2.0
var dying: bool = false
var attacking_melee: bool = false

var regen_timer := 0.0
const REGEN_INTERVAL := 6.0

@onready var player_warrior := $player_warrior
@onready var player_caster := $player_caster
@onready var health_bar := $health_bar
@onready var mana_bar := $mana_bar
@onready var name_label := $name_label
@onready var weapon_marker = get_node("weapon_marker")


func _ready():
	combat_node = CombatNode.new()
	add_child(combat_node)

	health_bar.max_value = combat_node.max_hp
	health_bar.value = combat_node.current_hp
	name_label.text = player_name
	mana_bar.visible = false
	player_warrior.visible = true
	player_caster.visible = false

	load_faction_standing()
	_load_spell_cache()


func _load_spell_cache():
	var file = FileAccess.open("res://Data/player_spells.json", FileAccess.READ)
	if not file:
		push_error("❌ Failed to open player_spells.json")
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_ARRAY:
		return
	for spell in data:
		_spell_cache[spell.get("spell_id", -1)] = spell
	print("✅ Loaded %d spell definitions" % _spell_cache.size())


func load_character_data(data: Dictionary):
	player_name  = data.get("player_name",  "Unnamed Player")
	player_class = data.get("player_class", "Blademaster")
	player_race  = data.get("player_race",  "Human")

	var s = data.get("stats", {})
	combat_node.character_name = player_name
	combat_node.set_base_stat("level",        data.get("player_level", 1))
	combat_node.set_class(player_class)
	combat_node.set_base_stat("strength",     int(s.get("strength",     10)))
	combat_node.set_base_stat("constitution", int(s.get("constitution", 10)))
	combat_node.set_base_stat("dexterity",    int(s.get("dexterity",    10)))
	combat_node.set_base_stat("intelligence", int(s.get("intelligence", 10)))
	combat_node.set_base_stat("wisdom",       int(s.get("wisdom",       10)))
	combat_node.set_base_stat("charisma",     int(s.get("charisma",     10)))
	combat_node.set_base_stat("luck",         int(s.get("luck",         10)))
	combat_node.recalculate_derived_stats()

	var saved_hp = data.get("current_hp", -1)
	combat_node.current_hp = saved_hp if saved_hp >= 0 else combat_node.max_hp
	var saved_mana = data.get("current_mana", -1)
	combat_node.current_mana = saved_mana if saved_mana >= 0 else combat_node.max_mana

	apply_racial_modifiers(player_race)

	var is_caster = caster_classes.has(player_class.to_lower())
	player_warrior.visible = not is_caster
	player_caster.visible  = is_caster
	mana_bar.visible       = is_caster

	health_bar.max_value = combat_node.max_hp
	health_bar.value     = combat_node.current_hp
	if is_caster:
		mana_bar.max_value = combat_node.max_mana
		mana_bar.value     = combat_node.current_mana

	known_spells = data.get("known_spells", [])
	update_player_label()
	print("✅ Loaded stats for %s" % player_name)


func apply_racial_modifiers(race_name: String):
	match race_name.to_lower():
		"lizardkin":
			combat_node.gear_ac += 2
			combat_node._stats_dirty = true


func update_player_label():
	if is_instance_valid(name_label):
		name_label.text = player_name


func _physics_process(delta: float):
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right"): dir.x += 1
	if Input.is_action_pressed("ui_left"):  dir.x -= 1
	if Input.is_action_pressed("ui_down"):  dir.y += 1
	if Input.is_action_pressed("ui_up"):    dir.y -= 1

	velocity = dir.normalized() * speed if dir.length() > 0 else Vector2.ZERO
	if dir.length() > 0:
		last_direction = dir.normalized()

	if not dying:
		weapon_marker.look_at(get_global_mouse_position())
		move_and_slide()

	if magic_missile_cooldown > 0: magic_missile_cooldown = max(magic_missile_cooldown - delta, 0)
	if ranged_attack_cooldown > 0: ranged_attack_cooldown = max(ranged_attack_cooldown - delta, 0)


func _input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.is_action_pressed("melee_attack"):
			melee_attack(get_global_mouse_position())
		elif event.is_action_pressed("ranged_attack"):
			if player_warrior.visible:
				ranged_attack(get_global_mouse_position())
			elif player_caster.visible:
				cast_magic_missile()

	if Input.is_action_just_pressed("toggle_character_sheet"):
		toggle_character_sheet()


func melee_attack(target_position: Vector2):
	if attacking_melee:
		return
	attacking_melee = true

	var melee_range := 50.0
	var initial_offset := weapon_marker.position
	var attack_direction := (target_position - global_position).normalized()

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(weapon_marker, "position", initial_offset + attack_direction * 30.0, 0.1)
	tween.tween_callback(func():
		var attack_center = global_position + attack_direction * (melee_range / 2.0)
		for monster in get_tree().get_nodes_in_group("monsters"):
			if not (monster is CharacterBody2D) or not is_instance_valid(monster):
				continue
			if monster.global_position.distance_to(attack_center) >= melee_range:
				continue
			if "combat_node" in monster and monster.combat_node is CombatNode:
				var result = combat_node.resolve_attack(monster.combat_node)
				health_bar.value = combat_node.current_hp
				monster.sync_health_bar()
				if not monster.combat_node.is_alive():
					monster.die()
				if result["result"] != "MISS":
					GameLog.log_combat(result.get("message", ""))
			elif monster.has_method("apply_damage"):
				var is_crit = combat_node.roll_crit()
				var damage = combat_node.calculate_melee_damage(null, is_crit)
				monster.apply_damage(damage)
	)
	tween.tween_property(weapon_marker, "position", initial_offset, 0.2).set_delay(0.1)
	tween.tween_callback(func(): attacking_melee = false)


func return_default():
	var tween = create_tween()
	tween.tween_property(weapon_marker, "position", Vector2.ZERO, 0.2)
	await tween.finished
	attacking_melee = false


func _on_melee_body_entered(_body: Node2D) -> void:
	pass


func ranged_attack(mouse_pos: Vector2):
	if ranged_attack_cooldown > 0:
		return
	ranged_attack_cooldown = ranged_attack_cooldown_duration
	var projectile: Area2D = ranged_attack_scene.instantiate()
	if projectile:
		projectile.global_position = global_position
		projectile.direction = (mouse_pos - global_position).normalized()
		get_tree().current_scene.add_child(projectile)


func cast_magic_missile():
	if magic_missile_cooldown > 0:
		return

	var spell_id = 477
	if not _spell_cache.has(spell_id):
		return

	var spell: Dictionary = _spell_cache[spell_id]
	var mana_cost: int = spell.get("mana_cost", 0)
	if not combat_node.spend_mana(mana_cost):
		GameLog.log_combat("⚡ Not enough mana.")
		return

	mana_bar.value = combat_node.current_mana
	magic_missile_cooldown = spell.get("recast_time", 10.0)

	var base_dir := last_direction
	var closest: CharacterBody2D = null
	var monsters = get_tree().get_nodes_in_group("monsters")
	if not monsters.is_empty():
		closest = monsters.reduce(func(c, m):
			if not is_instance_valid(m) or not (m is CharacterBody2D): return c
			return m if c == null or m.global_position.distance_to(global_position) < c.global_position.distance_to(global_position) else c
		, null)

	base_dir = (closest.global_position - global_position).normalized() if closest \
		else (get_global_mouse_position() - global_position).normalized()

	for angle in [-15.0, 0.0, 15.0]:
		var missile: Area2D = magic_missile_scene.instantiate()
		if missile:
			missile.global_position = global_position
			missile.target    = closest
			missile.direction = base_dir.rotated(deg_to_rad(angle))
			get_tree().current_scene.add_child(missile)

	GameLog.log_combat("🪄 Magic Missile — %d mana" % mana_cost)


func toggle_character_sheet():
	if not ResourceLoader.exists("res://Scenes/character_sheet.tscn"):
		return
	var existing = get_tree().current_scene.find_child("character_sheet")
	if not is_instance_valid(existing):
		var sheet = (preload("res://Scenes/character_sheet.tscn") as PackedScene).instantiate()
		sheet.name = "character_sheet"
		sheet.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().current_scene.add_child(sheet)
		if Global.current_character_data and is_instance_valid(sheet):
			var is_caster = caster_classes.has(player_class.to_lower())
			var d = Global.current_character_data.duplicate()
			d["current_hp"]      = combat_node.current_hp
			d["max_hp"]          = combat_node.max_hp
			d["current_mana"]    = combat_node.current_mana
			d["max_mana"]        = combat_node.max_mana
			d["current_stamina"] = combat_node.current_stamina
			d["max_stamina"]     = combat_node.max_stamina
			d["armor_class"]     = combat_node.get_ac()
			d["crit_chance"]     = combat_node.get_crit_chance()
			d["attack"]          = combat_node.get_atk()
			d["max_weight"]      = combat_node.get_derived_stat("carry_weight")
			d["spell_power"]     = combat_node.get_arcane_power() if is_caster else 0
			d["resistances"]     = {
				"acid": combat_node.get_resistance("poison"), "cold": combat_node.get_resistance("cold"),
				"fire": combat_node.get_resistance("fire"),   "magic": combat_node.get_resistance("arcane"),
				"psychic": combat_node.get_resistance("psychic")
			}
			sheet.set_character_data(d)
	else:
		if is_instance_valid(existing):
			existing.queue_free()


func _process(delta: float):
	regen_timer += delta
	if regen_timer >= REGEN_INTERVAL:
		regen_timer = 0.0
		if combat_node.current_hp < combat_node.max_hp:
			combat_node.current_hp = mini(combat_node.current_hp + combat_node.get_derived_stat("hp_regen"), combat_node.max_hp)
			health_bar.value = combat_node.current_hp
		if mana_bar.visible and combat_node.current_mana < combat_node.max_mana:
			combat_node.current_mana = mini(combat_node.current_mana + combat_node.get_derived_stat("mana_regen"), combat_node.max_mana)
			mana_bar.value = combat_node.current_mana
	if combat_node.current_stamina < combat_node.max_stamina:
		combat_node.current_stamina = minf(
			combat_node.current_stamina + combat_node.get_derived_stat("stamina_regen") * delta,
			float(combat_node.max_stamina)
		)


func apply_damage(amount: int):
	combat_node.take_damage(amount)
	health_bar.value = combat_node.current_hp
	if not combat_node.is_alive():
		print("Player defeated!")


func get_last_direction() -> Vector2: return last_direction
func get_faction_standing(faction_name: String) -> int: return faction_standing.get(faction_name, 0)


func load_faction_standing():
	var file = FileAccess.open("res://Data/player_faction.json", FileAccess.READ)
	if file:
		var json_data = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(json_data) == TYPE_DICTIONARY and json_data.has("factions"):
			for faction in json_data["factions"]:
				if faction.has("name") and faction.has("standing"):
					faction_standing[faction["name"]] = faction["standing"]


func save_faction_standing():
	var file = FileAccess.open("user://saves/player_faction.json", FileAccess.WRITE)
	if file:
		var arr = []
		for n in faction_standing.keys():
			arr.append({"name": n, "standing": faction_standing[n]})
		file.store_string(JSON.stringify({"factions": arr}, "\t"))
		file.close()
