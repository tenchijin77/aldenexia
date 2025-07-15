extends CharacterBody2D
class_name BaseMonster

@export var speed: float = 50.0
@export var health: int = 100
@export var damage: int = 10
@export var zone_loot_file: String = "res://Data/lumora_loot.json"

var move_direction: Vector2 = Vector2.ZERO
var animation_map: Dictionary = {}
var monster_type: String = ""
var monster_name: String = ""

@onready var anim_player: AnimationPlayer = $AnimationPlayer

func _ready():
	randomize()
	monster_name = get_monster_name()
	if monster_name != "":
		load_stats_from_json(monster_name)

func _physics_process(delta: float) -> void:
	handle_movement()
	update_animation()

func handle_movement():
	move_direction = Vector2.ZERO
	velocity = move_direction * speed
	move_and_slide()

func update_animation():
	if animation_map.has("idle"):
		anim_player.play(animation_map["idle"])

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		drop_loot()
		die()

func die():
	queue_free()

func get_monster_name() -> String:
	return ""

func load_stats_from_json(monster_name: String) -> void:
	var file = FileAccess.open("res://Data/monsters.json", FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var data = JSON.parse_string(content)
		if data and monster_name in data:
			var stats = data[monster_name]
			speed = stats.get("speed", speed)
			health = stats.get("health", health)
			damage = stats.get("damage", damage)
			animation_map = stats.get("animations", {})
			monster_type = stats.get("type", "")
		else:
			push_warning("Monster stats not found for: " + monster_name)
	else:
		push_error("Failed to open monsters.json")

func drop_loot():
	var drops: Array = []

	# Load zone loot
	var zone_file = FileAccess.open(zone_loot_file, FileAccess.READ)
	if zone_file:
		var zone_data = JSON.parse_string(zone_file.get_as_text())
		if zone_data.has(monster_type):
			for entry in zone_data[monster_type]:
				if randf() <= entry["chance"]:
					drops.append(entry["item"])
				
				if entry.has("currency"):
					for coin_type in entry["currency"]:
						var range = entry["currency"][coin_type]
						var amount = randi_range(range["min"], range["max"])
						if amount > 0:
							print("Dropped %d %s coins" % [amount, coin_type])
							# Add to inventory or spawn coin pickup here

	# Load monster-specific loot
	var loot_file_path = "res://Data/" + monster_name + "_loot.json"
	var monster_file = FileAccess.open(loot_file_path, FileAccess.READ)
	if monster_file:
		var monster_data = JSON.parse_string(monster_file.get_as_text())
		if monster_data.has("loot"):
			for entry in monster_data["loot"]:
				if randf() <= entry["chance"]:
					drops.append(entry["item"])

	# Print or spawn the loot
	for item in drops:
		print("Dropped: ", item)
		# You could instance a loot scene here

	return drops
