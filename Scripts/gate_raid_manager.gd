# gate_raid_manager.gd — Gate raids: every so often, while a player is near the town gate, a small band of bandits or goblins
# spawns out on the road and MARCHES on the gate (Monster.march_target). The guards banter (a warning, a rally, a taunt as the
# raiders arrive, a cheer when it is over), go out to meet the raiders (GuardNPC.raid_alert_range) and wear them down, but leave
# the killing to the players while any are near (GuardNPC.raid_soften), so the XP and loot are the players'. With nobody near, or
# after soften_seconds, the guards finish the job. Everything tunable and all the lines are in Data/gate_raids.json.
#
# Server-side (the scene node exists on every peer; only the authority decides). The raiders are ordinary replicated monsters from
# the zone's mob spawner; the only thing sent by RPC is the text (announcement, shouts). The guards' own lines go out through
# GuardNPC.shout_to_all(). /raid [bandits|goblins] (host/single-player) starts one now.
extends Node

const CONFIG_PATH := "res://Data/gate_raids.json"
const BANTER_GAP := 3.0
const TICK := 0.5
const RAID_ID_BASE := 500000   # monster node ids from this raider spawner, kept clear of the zone spawner's own counter

var _cfg: Dictionary = {}
var _countdown := 0.0             # seconds until the next raid; only counts while a player is near the gate
var _raid_active := false
var _raiders: Array = []
var _kind := ""
var _started_msec := 0
var _killed_any := false
var _arrived := false
var _shout_in := 0.0
var _tick := 0.0
var _next_id := RAID_ID_BASE


func _ready() -> void:
	add_to_group("gate_raid_manager")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
	_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_countdown = _minutes("first_raid_minutes", [8, 15])


func _minutes(key: String, fallback: Array) -> float:
	var range_arr: Array = _cfg.get(key, fallback)
	return randf_range(float(range_arr[0]), float(range_arr[1])) * 60.0


func _gate() -> Node3D:
	return get_parent().get_node_or_null(str(_cfg.get("gate_marker", "Markers/Town Gate"))) as Node3D


func _players_near(pos: Vector3, radius: float) -> int:
	var count := 0
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and player is Node3D and Vector2(player.global_position.x - pos.x, player.global_position.z - pos.z).length() <= radius:
			count += 1
	return count


func is_raid_active() -> bool:
	return _raid_active


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_tick += delta
	if _tick < TICK:
		return
	var dt := _tick
	_tick = 0.0
	if _raid_active:
		_update_raid(dt)
		return
	var gate := _gate()
	if gate != null and _players_near(gate.global_position, float(_cfg.get("activation_range", 300))) > 0:
		_countdown -= dt
		if _countdown <= 0.0:
			start_raid()


# ── Starting a raid ──
# kind: "bandits" / "goblins", or "" to pick by the weights in the config. Returns whether one started.
func start_raid(kind: String = "") -> bool:
	if _raid_active or not is_multiplayer_authority():
		return false
	var gate := _gate()
	var spawner_node := get_parent().get_node_or_null(str(_cfg.get("spawner", "monster_spawner")))
	var factions: Dictionary = _cfg.get("factions", {})
	if gate == null or spawner_node == null or factions.is_empty():
		push_warning("Gate raid: missing gate marker, mob spawner or config; no raid.")
		return false
	if not kind.is_empty() and not factions.has(kind):
		return false   # not a raid type
	if kind.is_empty():
		kind = _pick_faction(factions)
	var faction: Dictionary = factions[kind]

	var count_range: Array = faction.get("count", [3, 4])
	var count := randi_range(int(count_range[0]), int(count_range[1]))
	var near := _players_near(gate.global_position, float(_cfg.get("presence_range", 90)))
	count = mini(count + maxi(near - 1, 0) / maxi(int(_cfg.get("extra_per_players", 2)), 1), int(_cfg.get("max_raiders", 6)))

	var spawn_arr: Array = faction.get("spawn", [-65, 0, 92])
	var spawn_at := Vector3(float(spawn_arr[0]), float(spawn_arr[1]), float(spawn_arr[2]))
	var toward_spawn := Vector3(spawn_at.x - gate.global_position.x, 0.0, spawn_at.z - gate.global_position.z).normalized()
	var approach := gate.global_position + toward_spawn * float(_cfg.get("approach_distance", 12))
	var map_rid: RID = (get_parent() as Node3D).get_world_3d().navigation_map
	var roster: Array = faction.get("roster", ["bandit"])

	_raiders.clear()
	for i in count:
		var jitter := Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
		var at := NavigationServer3D.map_get_closest_point(map_rid, spawn_at + jitter)
		_next_id += 1
		var mob: Node = spawner_node.spawner.spawn({"id": _next_id, "mob_type": str(roster[randi() % roster.size()]), "position": [at.x, at.y, at.z]})
		if mob == null:
			continue
		mob.add_to_group("raiders")
		mob.march_target = approach + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		mob.change_state(mob.State.PATROL)   # start walking now, not after the usual idle pause
		_raiders.append(mob)
	if _raiders.is_empty():
		return false

	_raid_active = true
	_kind = kind
	_started_msec = Time.get_ticks_msec()
	_killed_any = false
	_arrived = false
	_shout_in = randf_range(4.0, 8.0)
	_broadcast_text("[color=#ff8866][b]%s[/b][/color]" % str(faction.get("announce", "The gate is under attack!")))
	print("⚔ Gate raid (%s): %d raiders marching on the gate." % [kind, _raiders.size()])
	_banter(_cfg.get("banter", {}).get("start", {}).get(kind, []))
	return true


func _pick_faction(factions: Dictionary) -> String:
	var total := 0.0
	for k in factions:
		total += float(factions[k].get("weight", 1))
	var roll := randf() * total
	for k in factions:
		roll -= float(factions[k].get("weight", 1))
		if roll <= 0.0:
			return str(k)
	return str(factions.keys()[0])


# ── While it lasts ──
func _update_raid(dt: float) -> void:
	var gate := _gate()
	var alive: Array = []
	for r in _raiders:
		if is_instance_valid(r) and r.current_state != r.State.DEAD:
			alive.append(r)
		elif is_instance_valid(r):
			r.remove_from_group("raiders")   # a corpse is not a raider any more
	var lost := _raiders.size() - alive.size()
	_raiders = alive
	if lost > 0 and not _killed_any and not alive.is_empty():
		_killed_any = true
		_banter(_cfg.get("banter", {}).get("first_kill", []))

	var age := (Time.get_ticks_msec() - _started_msec) / 1000.0
	if not _arrived and gate != null:
		for r in alive:
			if Vector2(r.global_position.x - gate.global_position.x, r.global_position.z - gate.global_position.z).length() <= float(_cfg.get("guard_alert_range", 32)):
				_arrived = true
				_banter(_cfg.get("banter", {}).get("arrive", []))
				break

	var players := _players_near(gate.global_position, float(_cfg.get("presence_range", 90))) if gate != null else 0
	for guard in _raid_guards():
		guard.raid_alert_range = float(_cfg.get("guard_alert_range", 32))
		guard.raid_soften = players > 0 and age < float(_cfg.get("soften_seconds", 120))

	_shout_in -= dt
	if _shout_in <= 0.0 and not alive.is_empty():
		_shout_in = randf_range(12.0, 20.0)
		_raider_shout(alive[randi() % alive.size()])

	if alive.is_empty():
		_end_raid("cleared")
	elif age > float(_cfg.get("raid_timeout_seconds", 480)):
		for r in alive:
			r.queue_free()
		_raiders.clear()
		_end_raid("fizzled")


func _end_raid(result: String) -> void:
	_raid_active = false
	for guard in _raid_guards():
		guard.raid_alert_range = 0.0
		guard.raid_soften = false
	_banter(_cfg.get("banter", {}).get(result, []))
	_countdown = _minutes("gap_minutes", [25, 45])
	print("⚔ Gate raid over (%s). Next in about %d min." % [result, int(_countdown / 60.0)])


# The guards that talk (Oni, the cat, is a GuardNPC too but sits this out).
func _raid_guards() -> Array:
	var out: Array = []
	for guard in get_tree().get_nodes_in_group("npc_guard"):
		if is_instance_valid(guard) and "raid_alert_range" in guard and guard.has_method("_can_talk") and guard._can_talk():
			out.append(guard)
	return out


# ── Words ──
func _banter(lines: Array) -> void:
	for i in lines.size():
		if i > 0:
			await get_tree().create_timer(BANTER_GAP).timeout
		if not is_inside_tree():
			return
		var entry: Dictionary = lines[i]
		var guard := _guard_named(str(entry.get("guard", "")))
		if guard != null:
			guard.shout_to_all(str(entry.get("line", "")))


func _guard_named(guard_name: String) -> Node:
	var fallback: Node = null
	for guard in _raid_guards():
		if str(guard.get("npc_name")) == guard_name:
			return guard
		if fallback == null:
			fallback = guard
	return fallback


func _raider_shout(raider: Node3D) -> void:
	var shouts: Array = _cfg.get("factions", {}).get(_kind, {}).get("shouts", [])
	if shouts.is_empty():
		return
	var desc: String = str(raider.get("monster_description")).capitalize()
	# The line travels in the raider's language (Languages.embed); each player's own machine scrambles what they don't know.
	var lang := Languages.of_monster(str(raider.get("monster_name")), str(raider.get("category")))
	_broadcast_text("[color=#e0a070]%s shouts%s, \"%s\"[/color]" % [desc, Languages.TAG_SLOT, Languages.embed(lang, str(shouts[randi() % shouts.size()]))], raider.global_position)


# Text for every player who is near enough to care (each peer checks its own player's distance).
func _broadcast_text(text: String, at: Vector3 = Vector3.INF) -> void:
	_show_text(text, at)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer():
		_rpc_text.rpc(text, at)


@rpc("authority", "call_remote", "reliable")
func _rpc_text(text: String, at: Vector3) -> void:
	_show_text(text, at)


func _show_text(text: String, at: Vector3) -> void:
	var player: Node3D = TargetFrame.local_player()
	var gate := _gate()
	if not is_instance_valid(player) or gate == null:
		return
	var centre := gate.global_position if at == Vector3.INF else at
	var range_m := 400.0 if at == Vector3.INF else 150.0
	if player.global_position.distance_to(centre) <= range_m:
		GameLog.log_general(Languages.localize(text))
