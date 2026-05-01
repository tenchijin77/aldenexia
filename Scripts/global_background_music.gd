#global_background_music.gd
extends AudioStreamPlayer

var allowed_scenes = [
	"res://Scenes/main_menu.tscn",
	"res://Scenes/character_creation.tscn",
]

func _ready():
	finished.connect(_on_music_finished)
	get_tree().root.child_entered_tree.connect(_on_root_child_entered)
	_check_and_play_music()

func _on_root_child_entered(node: Node):
	await get_tree().process_frame
	_check_and_play_music()

func _on_music_finished():
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.scene_file_path in allowed_scenes:
		play()

func _check_and_play_music():
	var current_scene = get_tree().current_scene
	if current_scene:
		var scene_path = current_scene.scene_file_path
		if scene_path in allowed_scenes:
			if stream and not playing:
				play()
				print("✅ Music playing:", scene_path)
		else:
			if playing:
				stop()
				print("🚫 Music stopped for:", scene_path)
