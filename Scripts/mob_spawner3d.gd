# mob_spawner3d.gd
# Reads lumora_outskirts_spawns.json and dynamically spawns 3D monsters.
# Place as a Node3D in lumora_outskirts3d.tscn, with a "MobSpawner"
# (MultiplayerSpawner) + "SpawnedMobs" (Node3D) pair as its own children —
# same MultiplayerSpawner pattern multiplayer_player_spawner.gd already uses
# for players, so every connected client gets an identical, replicated copy
# of each monster instead of independently simulating its own (see
# project_multiplayer_netcode memory — this was the single biggest remaining
# netcode gap). Spawn DECISIONS (_process()/_try_spawn() below) only run on
# the server; the actual node-building (_build_mob(), the spawner's
# spawn_function) runs on every peer identically, same split
# multiplayer_player_spawner.gd's _spawn_player() uses. No-op change in
# single-player: Net.is_multiplayer_game stays false, so the server-only gate
# never triggers and every spawn happens exactly as before.
extends Node3D

@export var spawn_data_path: String = "res://Data/lumora_outskirts_spawns.json"
@export var tick_interval: float = 1.0

# All mobs use the shared 3D template. monster_name is set before _ready() fires
# so Monster._ready() loads the correct JSON stats automatically.
const MONSTER_TEMPLATE := "res://Scenes/monster_template.tscn"

# Valid mob_type keys (must match monsters.json keys)
const VALID_MOB_TYPES: Array = [
	"rat", "snake", "slime", "spider", "bat", "dune_scarab",
	"skeleton", "bandit", "goblin", "ghost", "mummy", "mirage_phantom",
]

@onready var spawner: MultiplayerSpawner = $MobSpawner
@onready var spawned_mobs: Node3D = $SpawnedMobs

var _entries: Array = []
var _cooldowns: Dictionary = {}
var _active: Dictionary = {}
var _tick: float = 0.0
var _next_mob_id: int = 0

func _ready() -> void:
	spawner.spawn_function = _build_mob
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
	# Spawn decisions are server-only — in single-player Net.is_multiplayer_game
	# is always false, so this never blocks solo play; see the file header.
	if Net.is_multiplayer_game and not multiplayer.is_server():
		return
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
		if mob_type.is_empty() or mob_type not in VALID_MOB_TYPES:
			continue
		if _active.get(mob_type, 0) >= entry.get("max_active", 3):
			continue
		if randf() > entry.get("spawn_chance", 0.5):
			continue
		_spawn(i, entry, mob_type)

func _spawn(idx: int, entry: Dictionary, mob_type: String) -> void:
	var pos_arr: Array = entry.get("position", [0.0, 2.0, 0.0])
	var base := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var radius: float = entry.get("spawn_radius", 5.0)
	var angle: float = randf() * TAU
	var offset := Vector3(cos(angle) * randf() * radius, 0.0, sin(angle) * randf() * radius)
	var target_pos := base + offset

	# Snap onto the navmesh surface. lumora_outskirts_spawns.json hardcodes a
	# flat Y per entry that rarely matches the real terrain height at the
	# randomized X/Z offset, leaving mobs floating above/below the ground —
	# NavigationAgent3D's first path waypoint then becomes a pure vertical
	# correction with zero horizontal component, which handle_movement()'s
	# "basically no movement needed" check (monster3d.gd) treats as "arrived,"
	# permanently blocking any real chase/patrol movement.
	var map_rid: RID = get_world_3d().navigation_map
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, target_pos)
	var spawn_pos: Vector3 = snapped if snapped != Vector3.ZERO else target_pos

	_next_mob_id += 1
	var spawn_data := {
		"id": _next_mob_id,
		"mob_type": mob_type,
		"position": [spawn_pos.x, spawn_pos.y, spawn_pos.z],
	}
	var mob: Node = spawner.spawn(spawn_data)

	_active[mob_type] = _active.get(mob_type, 0) + 1
	_cooldowns[idx] = float(entry.get("respawn_time", 15))

	mob.tree_exited.connect(func():
		_active[mob_type] = maxi(_active.get(mob_type, 1) - 1, 0)
	)

	print("🐾 Spawned %s at %.0f, %.0f, %.0f" % [mob_type, spawn_pos.x, spawn_pos.y, spawn_pos.z])


# Runs on every peer (server included) as part of MultiplayerSpawner's
# replication, building an identical local node from the same spawn_data —
# mirrors multiplayer_player_spawner.gd's _spawn_player(). Authority is
# always the server (peer id 1): unlike a player's own character, a monster
# has no per-connection owner, so every client is equally a "puppet" for it.
func _build_mob(data: Dictionary) -> Node:
	var packed: PackedScene = load(MONSTER_TEMPLATE)
	var mob := packed.instantiate()
	mob.name = "mob_%d" % int(data.get("id", 0))
	# Set monster_name BEFORE add_child so Monster._ready() loads the correct JSON stats
	mob.monster_name = str(data.get("mob_type", ""))
	var pos: Array = data.get("position", [0.0, 0.0, 0.0])
	mob.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	mob.set_multiplayer_authority(1)
	return mob
