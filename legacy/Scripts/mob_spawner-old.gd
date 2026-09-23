# mob_spawner.gd
extends Node2D

@export var spawn_data_path: String = "res://Data/lumora_outskirts_spawns.json"
@export var spawn_interval: float = 1.0  # Check frequency in seconds

var spawn_points: Array = []
var cooldowns: Dictionary = {}
var active_mobs: Array = []

var mob_scenes: Dictionary = {
	"bat": preload("res://legacy/Scenes/bat-old.tscn"),
	"rat": preload("res://legacy/Scenes/rat-old.tscn"),
	"slime": preload("res://legacy/Scenes/slime-old.tscn"),
	"spider": preload("res://legacy/Scenes/spider-old.tscn"),
	"snake": preload("res://legacy/Scenes/snake-old.tscn"),
	"skeleton": preload("res://legacy/Scenes/skeleton-old.tscn"),
	"bandit": preload("res://legacy/Scenes/bandit-old.tscn"),
	"ghost": preload("res://legacy/Scenes/ghost-old.tscn"),
	"goblin": preload("res://legacy/Scenes/goblin-old.tscn")
}

func _ready():
	load_spawn_data()
	print("Mob spawner initialized with", spawn_points.size(), "spawn points")

func _process(delta):
	for i in range(spawn_points.size()):
		cooldowns[i] = max(cooldowns[i] - delta, 0.0)
	spawn_mobs()

func load_spawn_data():
	var file = FileAccess.open(spawn_data_path, FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data and data.has("spawns"):
			spawn_points = data["spawns"]
			for i in range(spawn_points.size()):
				cooldowns[i] = 0.0
		else:
			push_error("Invalid spawn data in %s" % spawn_data_path)
	else:
		push_error("Failed to load %s" % spawn_data_path)

func get_active_count_by_type(mob_type: String) -> int:
	var count = 0
	for mob in active_mobs:
		if mob.has_meta("mob_type") and mob.get_meta("mob_type") == mob_type:
			count += 1
	return count

func spawn_mobs():
	for i in range(spawn_points.size()):
		var point = spawn_points[i]

		if cooldowns[i] > 0.0:
			continue

		var mob_type = point.get("mob_type", "bat")
		var max_active = point.get("max_active", 3)
		if get_active_count_by_type(mob_type) >= max_active:
			continue

		var spawn_chance = point.get("spawn_chance", 0.5)
		if randf() > spawn_chance:
			continue

		if not mob_scenes.has(mob_type):
			print("WARNING: mob_scenes missing key:", mob_type)
			continue

		var mob = mob_scenes[mob_type].instantiate()

		var base_pos = Vector2(point.get("x", 0), point.get("y", 0))
		var radius = point.get("spawn_radius", 0)
		if radius > 0:
			var angle = randf() * TAU
			var offset = Vector2(cos(angle), sin(angle)) * randf() * radius
			mob.global_position = base_pos + offset
		else:
			mob.global_position = base_pos

		mob.set_meta("mob_type", mob_type)

		var min_level = point.get("min_level", 1)
		var max_level = point.get("max_level", min_level)
		var level = randi_range(min_level, max_level)
		mob.set_meta("level", level)

		get_tree().current_scene.add_child(mob)
		active_mobs.append(mob)

		mob.connect("tree_exited", func(): active_mobs.erase(mob))

		print("Spawned %s at %s (level %d)" % [mob_type, mob.global_position, level])
		cooldowns[i] = point.get("respawn_time", 10.0)
