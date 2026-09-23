# sfx.gd — plays the game's sound effects by name: Sfx.play("weapon_hit"), Sfx.play("spell_heal", target), and for
# sounds that last while something is going on, handle = Sfx.start_loop("gather_mining", self) ... Sfx.stop(handle).
# Every sound, and how it plays, is in Data/sounds.json: its files (one picked at random), its volume (balanced by
# tools/balance_sounds.py so every sound sits at a consistent level), and optionally loop / max_seconds / start /
# pitch / positional. Everything plays on the "SFX" bus, so the Options menu's effects volume applies.
#
# Also clicks every Button the game makes (install(), from Global._ready()). A dedicated server plays nothing.
# Static (no autoload: a patch can't add one) — the players it makes are ordinary nodes that free themselves.
class_name Sfx
extends RefCounted

const DATA_PATH := "res://Data/sounds.json"
const FADE := 0.12            # seconds of fade when a sound is cut short (max_seconds, or a loop being stopped)
const REPEAT_GAP_MS := 35     # the same sound twice this close together plays once (a flurry of hits in one frame)
const MAX_DISTANCE := 40.0    # positional sounds fade out by this distance

static var _sounds: Dictionary = {}
static var _loaded := false
static var _streams: Dictionary = {}     # file path -> AudioStream (loaded once)
static var _last_played: Dictionary = {} # sound id -> Time.get_ticks_msec()
static var requested: Array = []         # the last few sound ids asked for (newest last) — for tests and debugging


# Plays a one-shot sound. `where` (a Node3D or a Vector3) makes a "positional" sound come from that spot in the world;
# without it (or for a non-positional sound) it plays straight in your ears. Returns the player node, or null.
static func play(id: String, where: Variant = null) -> Node:
	var cfg := _config(id)
	_note(id)
	if cfg.is_empty() or not _can_play():
		return null
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -100000)) < REPEAT_GAP_MS:
		return null
	_last_played[id] = now
	var player := _make_player(cfg, where)
	if player == null:
		return null
	player.finished.connect(player.queue_free)
	player.play(float(cfg.get("start", 0.0)))
	var limit := float(cfg.get("max_seconds", 0.0))
	if limit > 0.0:
		_fade_out_after(player, limit)
	return player


# Starts a looping sound as a child of `owner` (it stops by itself if the owner goes away). Keep the returned node
# and pass it to stop(). Returns null if nothing could play.
static func start_loop(id: String, owner: Node) -> Node:
	var cfg := _config(id)
	_note("loop:" + id)
	if cfg.is_empty() or not _can_play() or not is_instance_valid(owner):
		return null
	var player := AudioStreamPlayer.new()
	player.stream = _looping(_stream(cfg))
	player.bus = &"SFX"
	player.volume_db = float(cfg.get("volume_db", 0.0))
	owner.add_child(player)
	player.play(randf() * maxf(player.stream.get_length() - 1.0, 0.0) if player.stream else 0.0)  # start somewhere in the loop
	return player


# Stops a loop from start_loop() with a short fade. Safe to call with null or an already-stopped handle.
static func stop(handle: Variant) -> void:
	if not is_instance_valid(handle):
		return
	var player := handle as Node
	if player.is_queued_for_deletion():
		return
	var tween := player.create_tween()
	tween.tween_property(player, "volume_db", -60.0, FADE)
	tween.tween_callback(player.queue_free)


# Every Button the game creates clicks when pressed (item slots and spell buttons, which are TextureButtons, don't —
# they have their own sounds). Called once from Global._ready().
static func install(tree: SceneTree) -> void:
	if not _can_play():
		return
	tree.node_added.connect(func(node: Node) -> void:
		if node is Button and not node.pressed.is_connected(_click):
			node.pressed.connect(_click))


static func _click() -> void:
	play("click")


# ── Internals ──
static func _note(id: String) -> void:
	requested.append(id)
	if requested.size() > 100:
		requested.pop_front()


static func _can_play() -> bool:
	return not Net.is_dedicated_server and DisplayServer.get_name() != "headless"


static func _config(id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		_sounds = parsed.get("sounds", {}) if typeof(parsed) == TYPE_DICTIONARY else {}
	var cfg: Variant = _sounds.get(id)
	if typeof(cfg) != TYPE_DICTIONARY:
		push_warning("Sfx: no sound called '%s' in %s" % [id, DATA_PATH])
		return {}
	return cfg


static func _stream(cfg: Dictionary) -> AudioStream:
	var files: Array = cfg.get("files", [])
	if files.is_empty():
		return null
	var path := str(files[randi() % files.size()])
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


# A copy of the stream set to loop (the imported file itself is left alone, so its one-shot uses don't loop).
static func _looping(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var copy := stream.duplicate()
	if copy is AudioStreamMP3 or copy is AudioStreamOggVorbis:
		copy.loop = true
	elif copy is AudioStreamWAV:
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copy.loop_end = int(copy.get_length() * copy.mix_rate)
	return copy


static func _make_player(cfg: Dictionary, where: Variant) -> Node:
	var stream := _stream(cfg)
	var tree := Engine.get_main_loop() as SceneTree
	if stream == null or tree == null:
		return null
	var at: Variant = null
	if bool(cfg.get("positional", false)):
		if where is Node3D and is_instance_valid(where):
			at = (where as Node3D).global_position
		elif where is Vector3:
			at = where
	var pitch := 1.0 + randf_range(-1.0, 1.0) * float(cfg.get("pitch", 0.0))
	var volume := float(cfg.get("volume_db", 0.0))
	if at != null and tree.current_scene != null:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.bus = &"SFX"
		p3.volume_db = volume
		p3.pitch_scale = pitch
		p3.max_distance = MAX_DISTANCE
		p3.unit_size = 6.0
		tree.current_scene.add_child(p3)
		p3.global_position = at
		return p3
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = &"SFX"
	p.volume_db = volume
	p.pitch_scale = pitch
	tree.root.add_child(p)
	return p


static func _fade_out_after(player: Node, seconds: float) -> void:
	var tween := player.create_tween()
	tween.tween_interval(maxf(seconds - FADE, 0.0))
	tween.tween_property(player, "volume_db", -60.0, FADE)
	tween.tween_callback(player.queue_free)
