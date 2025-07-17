# player.gd working
extends CharacterBody2D

@export var speed = 200.0
@export var max_health := 100
@export var current_health := 100
@export var max_mana := 100
@export var current_mana := 100
@export var player_name := "Ross of Lumora"

@export var health_regen_rate := 1.0
@export var mana_regen_rate := 2.0
@export var regen_interval := 2.0
var regen_timer := 0.0

var armor_class := 0
var stats: Dictionary = {}
var last_direction: Vector2 = Vector2.RIGHT
var faction_standing: Dictionary = {"Villagers of Lumora": 50}

var caster_classes := [
	"voidknight", "gravecaller", "runecaster", "arcanist", "wildmage",
	"lightsworn", "lightmender", "spiritcaller", "wildspeaker", "woodstalker"
]

# Attack-related variables
var magic_missile_scene := preload("res://Scenes/magic_missile.tscn")
var ranged_attack_scene := preload("res://Scenes/ranged_attack.tscn")
var magic_missile_cooldown := 0.0
var magic_missile_cooldown_duration := 10.0
var ranged_attack_cooldown := 0.0
var ranged_attack_cooldown_duration := 2.0
var spells: Array = []

@onready var player_warrior := $player_warrior
@onready var player_caster := $player_caster
@onready var health_bar := $health_bar
@onready var mana_bar := $mana_bar
@onready var name_label := $name_label


func _ready():
	health_bar.max_value = max_health
	health_bar.value = current_health
	name_label.text = player_name
	mana_bar.visible = false
	player_warrior.visible = true
	player_caster.visible = false
	load_faction_standing()
	load_character_data()
	load_spells()
	update_player_label()
	# Debug: Verify class visibility and scene paths
	print("DEBUG: Initial visibility - Warrior: ", player_warrior.visible, ", Caster: ", player_caster.visible)
	if not ResourceLoader.exists("res://Scenes/ranged_attack.tscn"):
		print("ERROR: ranged_attack.tscn not found!")
	if not ResourceLoader.exists("res://Scenes/magic_missile.tscn"):
		print("ERROR: magic_missile.tscn not found!")


func load_character_data():
	print("DEBUG: Attempting to load character_stats.json")
	var file = FileAccess.open("res://Data/character_stats.json", FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var data = JSON.parse_string(content)
		file.close()

		if typeof(data) == TYPE_DICTIONARY:
			player_name = data.get("player_name", player_name)
			stats = data.get("stats", {})
			var derived = data.get("derived", {})

			if derived.has("health"):
				max_health = derived["health"]
				current_health = max_health
				health_bar.max_value = max_health
				health_bar.value = current_health

			if derived.has("mana"):
				max_mana = derived["mana"]
				current_mana = max_mana

			apply_racial_modifiers(data.get("player_race", ""))
			apply_mana_regen_bonus()

			var selected_class = data.get("player_class", "").to_lower()
			# Corrected to check against lowercase list
			var is_caster := caster_classes.has(selected_class)

			mana_bar.visible = is_caster
			if is_caster:
				mana_bar.max_value = max_mana
				mana_bar.value = current_mana
				player_caster.visible = true
				player_warrior.visible = false
				print("🧙 Caster sprite enabled for class:", selected_class)
			else:
				player_caster.visible = false
				player_warrior.visible = true
				print("⚔️ Warrior sprite enabled for class:", selected_class)

			print("✅ Loaded stats for", player_name)
		else:
			print("DEBUG: JSON parsing failed or returned non-dictionary")
	else:
		print("DEBUG: Failed to open character_stats.json")


func load_spells():
	print("DEBUG: Attempting to load player_spells.json")
	var file = FileAccess.open("res://Data/player_spells.json", FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var data = JSON.parse_string(content)
		file.close()
		if typeof(data) == TYPE_ARRAY:
			spells = data
			print("✅ Loaded spells from player_spells.json")
		else:
			print("DEBUG: Failed to parse player_spells.json")
	else:
		print("DEBUG: Failed to open player_spells.json")


func apply_racial_modifiers(race_name: String):
	var race = race_name.to_lower()
	if race == "troll" or race == "lizardkin":
		health_regen_rate *= 1.15
		if race == "lizardkin":
			armor_class += 2


func apply_mana_regen_bonus():
	var meditation_skill := 5
	mana_regen_rate = 1 + meditation_skill / 2


func update_player_label():
	if is_instance_valid(name_label):
		name_label.text = player_name
	else:
		print("Label is playing hide and seek! Check the path!")


func _physics_process(delta):
	var input_direction = Vector2.ZERO
	if Input.is_action_pressed("ui_right"):
		input_direction.x += 1
	if Input.is_action_pressed("ui_left"):
		input_direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		input_direction.y += 1
	if Input.is_action_pressed("ui_up"):
		input_direction.y -= 1

	if input_direction.length() > 0:
		velocity = input_direction.normalized() * speed
		last_direction = input_direction.normalized()
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	# Update cooldowns
	if magic_missile_cooldown > 0:
		magic_missile_cooldown = max(magic_missile_cooldown - delta, 0)
	if ranged_attack_cooldown > 0:
		ranged_attack_cooldown = max(ranged_attack_cooldown - delta, 0)


func _input(event):
	if event is InputEventMouseButton and event.pressed:
		# Melee attack on left click
		if event.is_action_pressed("ui_accept"):
			print("DEBUG: Left click detected - triggering melee attack")
			melee_attack()
		# Right click: ranged attack for warrior, spell attack for caster
		if event.is_action_pressed("ranged_attack"):
			print("DEBUG: Right click detected - Action: ranged_attack, Warrior visible: ", player_warrior.visible, ", Caster visible: ", player_caster.visible)
			if player_warrior.visible:
				var mouse_pos = get_global_mouse_position()
				ranged_attack(mouse_pos)
			elif player_caster.visible:
				cast_magic_missile()
			else:
				print("ERROR: Neither warrior nor caster sprite is visible!")
	# Character sheet on C key
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		print("DEBUG: C key pressed - toggling character sheet")
		toggle_character_sheet()


func melee_attack():
	var melee_range := 50.0
	var melee_damage := 20
	var attack_position = global_position + last_direction * melee_range
	var monsters = get_tree().get_nodes_in_group("monsters")
	for monster in monsters:
		if monster is CharacterBody2D and monster.global_position.distance_to(attack_position) < melee_range:
			monster.apply_damage(melee_damage)
			print("⚔️ Melee hit on", monster.name, "for", melee_damage, "damage")


func ranged_attack(mouse_pos: Vector2):
	if ranged_attack_cooldown > 0:
		print("🕒 Ranged attack on cooldown:", ranged_attack_cooldown, "seconds remaining")
		return

	ranged_attack_cooldown = ranged_attack_cooldown_duration
	var projectile = ranged_attack_scene.instantiate()
	if projectile:
		projectile.global_position = global_position
		var direction = (mouse_pos - global_position).normalized()
		projectile.direction = direction
		get_tree().current_scene.add_child(projectile)
		print("🏹 Fired ranged attack toward mouse position: ", mouse_pos)
	else:
		print("ERROR: Failed to instantiate ranged_attack.tscn")


func cast_magic_missile():
	if magic_missile_cooldown > 0:
		print("🕒 Magic Missile on cooldown:", magic_missile_cooldown, "seconds remaining")
		return

	var spell_results = spells.filter(func(s): return s["spell_id"] == 477)
	if spell_results.is_empty():
		print("⚠️ Magic Missile spell not found in player_spells.json")
		return
	var spell = spell_results[0]
	
	var mana_cost = spell["mana_cost"]
	if current_mana < mana_cost:
		print("⚡ Insufficient mana:", current_mana, "/", mana_cost)
		return

	current_mana = max(current_mana - mana_cost, 0)
	mana_bar.value = current_mana
	magic_missile_cooldown = spell["recast_time"]

	# Fire 3 projectiles with slight spread
	var angles = [-10, 0, 10]
	for angle in angles:
		var missile = magic_missile_scene.instantiate()
		if missile:
			missile.global_position = global_position
			var target_direction = last_direction
			var monsters = get_tree().get_nodes_in_group("monsters")
			var find_closest = func(closest, m):
				var dist = m.global_position.distance_to(global_position)
				return m if closest == null or dist < closest.global_position.distance_to(global_position) else closest
			var closest = monsters.reduce(find_closest, null)
			if closest:
				target_direction = (closest.global_position - global_position).normalized()
				missile.target = closest  # Assign target for homing
			var rad = deg_to_rad(angle)
			missile.direction = target_direction.rotated(rad)
			get_tree().current_scene.add_child(missile)
		else:
			print("ERROR: Failed to instantiate magic_missile.tscn")
	print("🪄 Cast Magic Missile: 3 bolts, 25 mana consumed")
func toggle_character_sheet():
	var character_sheet_scene = preload("res://Scenes/character_sheet.tscn")
	var character_sheet = get_tree().get_nodes_in_group("character_sheet")
	if character_sheet.is_empty():
		var instance = character_sheet_scene.instantiate()
		instance.add_to_group("character_sheet")
		get_tree().current_scene.add_child(instance)
		print("📋 Character sheet opened")
	else:
		for sheet in character_sheet:
			sheet.queue_free()
		print("📋 Character sheet closed")


func _process(delta):
	regen_timer += delta
	if regen_timer >= regen_interval:
		regen_timer = 0.0

		if current_health < max_health:
			current_health = min(current_health + health_regen_rate, max_health)
			health_bar.value = current_health

		if mana_bar.visible and current_mana < max_mana:
			current_mana = min(current_mana + mana_regen_rate, max_mana)
			mana_bar.value = current_mana


func apply_damage(amount: int):
	current_health = max(current_health - amount, 0)
	health_bar.value = current_health


func get_last_direction() -> Vector2:
	return last_direction


func get_faction_standing(faction_name: String) -> int:
	if faction_standing.has(faction_name):
		return faction_standing[faction_name]
	return 0


func load_faction_standing():
	var file = FileAccess.open("res://Data/player_faction.json", FileAccess.READ)
	if file:
		var json_data = JSON.parse_string(file.get_as_text())
		if json_data and json_data.has("factions"):
			for faction in json_data["factions"]:
				faction_standing[faction["name"]] = faction["standing"]
		file.close()


func save_faction_standing():
	var file = FileAccess.open("res://Data/player_faction.json", FileAccess.WRITE)
	if file:
		var factions_array = []
		for faction_name in faction_standing.keys():
			factions_array.append({
				"name": faction_name,
				"standing": faction_standing[faction_name]
			})
		var json_output = {"factions": factions_array}
		file.store_string(JSON.stringify(json_output, "\t"))
		file.close()
