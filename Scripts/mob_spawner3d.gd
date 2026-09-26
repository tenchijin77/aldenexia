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

@export var spawn_data_path: String = ""   # "" = Data/<zone>_spawns.json (ZoneInfo.spawns_path())
@export var tick_interval: float = 1.0

# All mobs use the shared 3D template. monster_name is set before _ready() fires
# so Monster._ready() loads the correct JSON stats automatically.
const MONSTER_TEMPLATE := "res://Scenes/monster_template.tscn"

# A spawn entry's mob_type is valid when Data/monsters.json defines it (so a new monster needs no second list to keep in sync).
const MONSTERS_PATH := "res://Data/monsters.json"
var _valid_mob_types: Dictionary = {}

@onready var spawner: MultiplayerSpawner = $MobSpawner
@onready var spawned_mobs: Node3D = $SpawnedMobs

var _entries: Array = []
var _cooldowns: Dictionary = {}
## Live mobs per SPAWN ENTRY (index into _entries) — each entry's max_active caps its own spawn point. It used to be
## counted per mob TYPE across the whole zone, so every extra rat/skeleton entry just shared one pool: clusters filled to the
## type's total and adding more spawn points added nothing.
var _active: Dictionary = {}
## Data/lumora_outskirts_spawns.json "density": multiplies every entry's max_active (1.0 = as written; 0.5 = half the mobs,
## but never below 1 for an entry that has any). One knob for "too crowded / too empty" without editing every line.
var _density: float = 1.0
## Data/lumora_outskirts_spawns.json "activation_range" (metres): a spawn point only makes mobs while some player is this close.
## Every mob costs the (single-threaded) server animation + physics time each frame, and most of a big zone is far from every
## player most of the time. Mobs already spawned stay; 0 = no limit (everything spawns from the start, the old behaviour).
var _activation_range: float = 0.0
var _tick: float = 0.0
var _next_mob_id: int = 0
## Respawn timers start when a monster DIES, one per dead monster, EverQuest-style (test 42: "i can't kill enemies without them
## spawning on top of me. there is no way to setup a camp"). They used to start when one spawned, so by the time you'd killed
## it the timer had long run out and its replacement popped at once. idx -> [seconds left, ...]; a slot waiting here counts
## toward the entry's max_active.
var _respawns: Dictionary = {}
## A monster never appears within this of a player: the spot is picked again, or the spawn waits a moment.
const SPAWN_CLEAR_DISTANCE := 12.0
## Between two spawns of the same entry while it first fills up (so a cluster doesn't appear all in one second).
const FILL_STAGGER := 5.0

func _ready() -> void:
	spawner.spawn_function = _build_mob
	_load_valid_mob_types()
	_load_data()
	print("✅ MobSpawner3D: %d spawn entries loaded." % _entries.size())

func _load_valid_mob_types() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		for key in parsed:
			if not str(key).begins_with("_"):
				_valid_mob_types[str(key)] = true
	else:
		push_error("❌ MobSpawner3D: cannot read %s" % MONSTERS_PATH)


func _load_data() -> void:
	if spawn_data_path.is_empty():
		spawn_data_path = ZoneInfo.spawns_path(ZoneInfo.id_for(self))
		if not FileAccess.file_exists(spawn_data_path):
			print("MobSpawner3D: %s has no spawn file yet (%s) — no monsters." % [ZoneInfo.id_for(self), spawn_data_path])
			return
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
	_density = maxf(float(data.get("density", 1.0)), 0.0)
	_activation_range = maxf(float(data.get("activation_range", 0.0)), 0.0)
	for i in range(_entries.size()):
		_cooldowns[i] = 0.0
		_active[i] = 0
		_respawns[i] = []

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
	for i in _respawns:
		var waiting: Array = _respawns[i]
		for k in range(waiting.size() - 1, -1, -1):
			waiting[k] = float(waiting[k]) - tick_interval
			if waiting[k] <= 0.0:
				waiting.remove_at(k)
	_try_spawn()

func _try_spawn() -> void:
	var player_spots: Array = []
	# where the players are: for the activation range, and to keep spawns off them (SPAWN_CLEAR_DISTANCE)
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and player is Node3D:
			player_spots.append(Vector2(player.global_position.x, player.global_position.z))
	for i in range(_entries.size()):
		if _cooldowns[i] > 0.0:
			continue
		var entry: Dictionary = _entries[i]
		if _activation_range > 0.0 and not _player_within_range(entry, player_spots):
			continue
		var mob_type: String = entry.get("mob_type", "")
		if mob_type.is_empty() or not _valid_mob_types.has(mob_type):
			continue
		if _active.get(i, 0) + (_respawns.get(i, []) as Array).size() >= _entry_cap(entry):
			continue
		if randf() > entry.get("spawn_chance", 0.5):
			continue
		_spawn(i, entry, mob_type, player_spots)

func _player_within_range(entry: Dictionary, player_spots: Array) -> bool:
	var pos: Array = entry.get("position", [0.0, 0.0, 0.0])
	var spot := Vector2(float(pos[0]), float(pos[2]))
	for p in player_spots:
		if spot.distance_to(p) <= _activation_range + float(entry.get("spawn_radius", 0.0)):
			return true
	return false


# This entry's max_active after the file's density multiplier (an entry that has any mobs keeps at least 1 unless density is 0).
func _entry_cap(entry: Dictionary) -> int:
	var cap := int(entry.get("max_active", 3))
	if cap <= 0 or _density <= 0.0:
		return 0
	return maxi(1, roundi(cap * _density))


static func _near_a_player(pos: Vector3, player_spots: Array) -> bool:
	for p in player_spots:
		if Vector2(pos.x, pos.z).distance_to(p) < SPAWN_CLEAR_DISTANCE:
			return true
	return false


func _spawn(idx: int, entry: Dictionary, mob_type: String, player_spots: Array = []) -> void:
	var pos_arr: Array = entry.get("position", [0.0, 2.0, 0.0])
	var base := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var radius: float = entry.get("spawn_radius", 5.0)
	var target_pos := base
	var ok := false
	for attempt in 10:  # a spot outside the no-monster zones (the town; a circle may reach over the wall) and away from players
		var angle: float = randf() * TAU
		target_pos = base + Vector3(cos(angle) * randf() * radius, 0.0, sin(angle) * randf() * radius)
		if not Monster.in_no_monster_zone(target_pos) and not _near_a_player(target_pos, player_spots):
			ok = true
			break
	if not ok:
		# the whole circle is in town, or someone is standing on it: try again in a little while
		_cooldowns[idx] = minf(float(entry.get("respawn_time", 15)), FILL_STAGGER * 2.0)
		return

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

	_active[idx] = _active.get(idx, 0) + 1
	_cooldowns[idx] = minf(float(entry.get("respawn_time", 15)), FILL_STAGGER)

	# its replacement comes respawn_time after it dies (not when the corpse goes: an unlooted body lies there 5 minutes)
	var respawn_after := float(entry.get("respawn_time", 15))
	var counted := [true]   # still counted in _active
	var gone := func() -> void:
		if counted[0]:
			counted[0] = false
			_active[idx] = maxi(_active.get(idx, 1) - 1, 0)
			(_respawns[idx] as Array).append(respawn_after)
	if mob.has_signal("died"):
		mob.died.connect(gone)
	mob.tree_exited.connect(gone)   # removed some other way (a GM, the zone shutting down)

	print("🐾 Spawned %s at %.0f, %.0f, %.0f" % [mob_type, spawn_pos.x, spawn_pos.y, spawn_pos.z])


# A monster another one called in (monster3d.gd abilities, "summon"): spawned like any other so every player sees it,
# but outside this spawner's counts and respawn timers.
func spawn_extra(mob_type: String, at: Vector3) -> Node:
	var map_rid: RID = get_world_3d().navigation_map
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, at)
	_next_mob_id += 1
	return spawner.spawn({"id": _next_mob_id, "mob_type": mob_type, "position": [snapped.x if snapped != Vector3.ZERO else at.x,
			snapped.y if snapped != Vector3.ZERO else at.y, snapped.z if snapped != Vector3.ZERO else at.z]})


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
