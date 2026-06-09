# mob_spawner3d.gd
# Reads lumora_outskirts_spawns.json and dynamically spawns 3D monsters.
# Place as a Node3D in lumora_outskirts3d.tscn.
extends Node3D

@export var spawn_data_path: String = "res://Data/lumora_outskirts_spawns.json"
@export var tick_interval: float = 1.0

const MOB_SCENES: Dictionary = {
	"rat":      "res://Scenes/rat.tscn",
	"snake":    "res://Scenes/snake.tscn",
	"slime":    "res://Scenes/slime.tscn",
	"spider":   "res://Scenes/spider.tscn",
	"bat":      "res://Scenes/bat.tscn",
	"skeleton": "res://Scenes/skeleton.tscn",
	"bandit":   "res://Scenes/bandit.tscn",
	"goblin":   "res://Scenes/goblin.tscn",
	"ghost":    "res://Scenes/ghost.tscn",
}

var _entries: Array = []
var _cooldowns: Dictionary = {}
var _active: Dictionary = {}
var _tick: float = 0.0

func _ready() -> void:
	_load_data()
	print("✅ MobSpawner3D: %d spawn entries loaded." % _entries.size())

func _load_data() -> void:
	var file := FileAccess.open(spawn_data_path, FileAccess.READ)
	if not file:
		push_error("❌ MobSpawner3D: cannot open %s" % spawn_data_path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("spawns"):
		push_error("❌ MobSpawner3D: invalid data in %s" % spawn_data_path)
		return
	_entries = data["spawns"]
	for i in range(_entries.size()):
		_cooldowns[i] = 0.0
	for entry in _entries:
		var mt: String = entry.get("mob_type", "")
		if mt and not _active.has(mt):
			_active[mt] = 0

func _process(delta: float) -> void:
	_tick += delta
	if _tick < tick_interval:
		return
	_tick = 0.0
	for i in _cooldowns:
		_cooldowns[i] = maxf(_cooldowns[i] - tick_interval, 0.0)
	_try_spawn()

func _try_spawn() -> void:
	for i in range(_entries.size()):
		if _cooldowns[i] > 0.0:
			continue
		var entry: Dictionary = _entries[i]
		var mob_type: String = entry.get("mob_type", "")
		if mob_type.is_empty() or not MOB_SCENES.has(mob_type):
			continue
		if _active.get(mob_type, 0) >= entry.get("max_active", 3):
			continue
		if randf() > entry.get("spawn_chance", 0.5):
			continue
		_spawn(i, entry, mob_type)

func _spawn(idx: int, entry: Dictionary, mob_type: String) -> void:
	var packed: PackedScene = load(MOB_SCENES[mob_type])
	if not packed:
		push_error("❌ MobSpawner3D: failed to load scene for %s" % mob_type)
		return

	var mob := packed.instantiate()

	var pos_arr: Array = entry.get("position", [0.0, 2.0, 0.0])
	var base := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var radius: float = entry.get("spawn_radius", 5.0)
	var angle: float = randf() * TAU
	var offset := Vector3(cos(angle) * randf() * radius, 0.0, sin(angle) * randf() * radius)
	mob.global_position = base + offset

	get_tree().current_scene.add_child(mob)
	_active[mob_type] = _active.get(mob_type, 0) + 1
	_cooldowns[idx] = float(entry.get("respawn_time", 15))

	mob.connect("tree_exited", func():
		_active[mob_type] = maxi(_active.get(mob_type, 1) - 1, 0)
	)

	print("🐾 Spawned %s at %.0f, %.0f, %.0f" % [mob_type, mob.global_position.x, mob.global_position.y, mob.global_position.z])
