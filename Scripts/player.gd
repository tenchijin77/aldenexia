# player.gd
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
	update_player_label()

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
	if Input.is_action_pressed("ui_right"): input_direction.x += 1
	if Input.is_action_pressed("ui_left"): input_direction.x -= 1
	if Input.is_action_pressed("ui_down"): input_direction.y += 1
	if Input.is_action_pressed("ui_up"): input_direction.y -= 1

	if input_direction.length() > 0:
		velocity = input_direction.normalized() * speed
		last_direction = input_direction.normalized()
	else:
		velocity = Vector2.ZERO

	move_and_slide()

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
