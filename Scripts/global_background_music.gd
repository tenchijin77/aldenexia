#global_background_music.gd
# Per-scene background music. The menu track (this player's own .tscn-assigned
# `stream`) plays for the menu/character-creation scenes; anything else listed
# in SCENE_MUSIC gets its own dedicated track instead (e.g. Lumora Outskirts'
# ambient loop). A scene not listed anywhere here plays no music at all.
#
# Combat music (added 2026-09-19): while the LOCAL player is fighting in a zone
# that has zone music, the zone track crossfades out (paused, so it resumes
# exactly where it left off) and COMBAT_TRACK crossfades in; COMBAT_LINGER
# seconds after the last blow dealt or taken, it crossfades back. "Fighting" is
# CombatNode.seconds_since_engaged() on the local player — see combatnode.gd.
extends AudioStreamPlayer

@export var menu_scenes: Array[String] = [
	"res://Scenes/main_menu.tscn",
	"res://Scenes/character_creation.tscn",
]

# Keyed by scene_file_path — add a new zone's ambient track here, no other
# code changes needed.
const SCENE_MUSIC := {
	"res://Scenes/lumora_outskirts3d.tscn": "res://Assets/music/sands_of_lumora.ogg",
	# Stand-ins until these zones have their own music (outstanding_items.txt, MISSING ASSETS).
	"res://Scenes/zones/dustwind_plateaus.tscn": "res://Assets/music/sands_of_lumora.ogg",
	"res://Scenes/zones/ashfall_dunes.tscn": "res://Assets/music/sands_of_lumora.ogg",
}

var _menu_stream: AudioStream
var _current_scene_path: String = ""

const COMBAT_TRACK := "res://Assets/music/tomb_of_the_lost.ogg"
const COMBAT_FADE := 1.5        # crossfade length, both directions (seconds)
const COMBAT_LINGER := 8.0      # quiet seconds before the zone music returns
const COMBAT_START_WINDOW := 1.0  # a blow this recent starts combat music
const SILENT_DB := -60.0
const POLL_INTERVAL := 0.25

var _combat_player: AudioStreamPlayer
var _combat_active := false
var _zone_base_db := 0.0
var _poll_accum := 0.0
var _fade_tween: Tween
var _music_gain := {}   # track path -> volume_db from Data/sounds.json "music" (tools/balance_sounds.py): every track equally loud


# The balanced volume of a track (0 dB when it isn't listed).
func _gain(track: AudioStream) -> float:
	if _music_gain.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://Data/sounds.json"))
		var music: Dictionary = parsed.get("music", {}) if typeof(parsed) == TYPE_DICTIONARY else {}
		for path in music:
			_music_gain[path] = float(music[path].get("volume_db", 0.0))
		_music_gain["_loaded"] = 0.0
	return float(_music_gain.get(track.resource_path, 0.0)) if track else 0.0


# The zone track's volume: the scene's own setting plus the current track's balance.
func _zone_db() -> float:
	return _zone_base_db + _gain(stream)


func _ready():
	_menu_stream = stream  # whatever the .tscn assigned — the existing menu loop
	finished.connect(_on_music_finished)
	_zone_base_db = volume_db
	_setup_combat_player()
	get_tree().root.child_entered_tree.connect(_on_root_child_entered)
	_check_and_play_music()

func _on_root_child_entered(node: Node):
	await get_tree().process_frame
	_check_and_play_music()

func _on_music_finished():
	_check_and_play_music()

func _check_and_play_music():
	var current_scene = get_tree().current_scene
	if not current_scene:
		return
	var scene_path: String = current_scene.scene_file_path

	var track: AudioStream = null
	if scene_path in menu_scenes:
		track = _menu_stream
	elif SCENE_MUSIC.has(scene_path):
		track = load(SCENE_MUSIC[scene_path])

	if track:
		if scene_path != _current_scene_path or not playing:
			_current_scene_path = scene_path
			stream = track
			stream_paused = false
			if not _combat_active:
				volume_db = _zone_db()
			play()
			print("✅ Music playing:", scene_path)
	else:
		if playing:
			stop()
			print("🚫 Music stopped for:", scene_path)
		_current_scene_path = ""


# ===== COMBAT MUSIC =====

func _setup_combat_player() -> void:
	_combat_player = AudioStreamPlayer.new()
	_combat_player.name = "CombatMusic"
	_combat_player.bus = bus
	_combat_player.volume_db = SILENT_DB
	var track := load(COMBAT_TRACK) as AudioStream
	if track is AudioStreamOggVorbis:
		(track as AudioStreamOggVorbis).loop = true  # import setting is loop=false
	_combat_player.stream = track
	add_child(_combat_player)


func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum < POLL_INTERVAL:
		return
	_poll_accum = 0.0
	_update_combat_music()


func _local_seconds_since_engaged() -> float:
	var p := TargetFrame.local_player()
	if not is_instance_valid(p) or not ("combat_node" in p) or not (p.combat_node is CombatNode):
		return INF
	return p.combat_node.seconds_since_engaged()


func _update_combat_music() -> void:
	var in_zone: bool = SCENE_MUSIC.has(_current_scene_path)
	var since := _local_seconds_since_engaged() if (in_zone or _combat_active) else INF
	if not _combat_active:
		if in_zone and since < COMBAT_START_WINDOW:
			_start_combat_music()
	elif not in_zone or since >= COMBAT_LINGER:
		_end_combat_music()


func _start_combat_music() -> void:
	if not is_instance_valid(_combat_player) or not _combat_player.stream:
		return
	_combat_active = true
	if not _combat_player.playing:
		_combat_player.play()
	_crossfade(SILENT_DB, _zone_base_db + _gain(_combat_player.stream), func(): if _combat_active: stream_paused = true)
	print("⚔️ Combat music on")


func _end_combat_music() -> void:
	_combat_active = false
	stream_paused = false  # zone track resumes from where it was paused
	_crossfade(_zone_db(), SILENT_DB, func(): if not _combat_active: _combat_player.stop())
	print("🕊️ Combat music off")


# Fades this (zone) player to `zone_db` and the combat player to `combat_db`
# together over COMBAT_FADE, then runs `done`. Kills any fade still in flight so
# a quick re-engage/disengage just reverses smoothly from the current volumes.
func _crossfade(zone_db: float, combat_db: float, done: Callable) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(self, "volume_db", zone_db, COMBAT_FADE)
	_fade_tween.tween_property(_combat_player, "volume_db", combat_db, COMBAT_FADE)
	_fade_tween.chain().tween_callback(done)
