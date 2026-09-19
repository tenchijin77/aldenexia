#global_background_music.gd
# Per-scene background music. The menu track (this player's own .tscn-assigned
# `stream`) plays for the menu/character-creation scenes; anything else listed
# in SCENE_MUSIC gets its own dedicated track instead (e.g. Lumora Outskirts'
# ambient loop). A scene not listed anywhere here plays no music at all.
extends AudioStreamPlayer

@export var menu_scenes: Array[String] = [
	"res://Scenes/main_menu.tscn",
	"res://Scenes/character_creation.tscn",
]

# Keyed by scene_file_path — add a new zone's ambient track here, no other
# code changes needed.
const SCENE_MUSIC := {
	"res://Scenes/lumora_outskirts3d.tscn": "res://Assets/Sands of Lumora.ogg",
}

var _menu_stream: AudioStream
var _current_scene_path: String = ""


func _ready():
	_menu_stream = stream  # whatever the .tscn assigned — the existing menu loop
	finished.connect(_on_music_finished)
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
			play()
			print("✅ Music playing:", scene_path)
	else:
		if playing:
			stop()
			print("🚫 Music stopped for:", scene_path)
		_current_scene_path = ""
