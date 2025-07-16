#global_background_music.gd
extends AudioStreamPlayer

var allowed_scenes = [
	"res://Scenes/main_menu.tscn",
	"res://Scenes/character_creation.tscn",
]

func _ready():
	_check_and_play_music()
	get_tree().connect("scene_changed", _on_scene_changed)

func _check_and_play_music():
	var current_scene = get_tree().current_scene
	if current_scene:
		var scene_path = current_scene.scene_file_path
		print("📍 Scene:", scene_path)
		if scene_path in allowed_scenes:
			if stream and not playing:
				play()
				print("✅ Music started for allowed scene")
		else:
			stop()
			print("🚫 Scene not allowed — music stopped")


func _on_scene_changed(new_scene):
	if new_scene:
		var scene_path = new_scene.scene_file_path
		print("🔄 Scene changed to:", scene_path)

		if scene_path in allowed_scenes:
			print("✅ Allowed scene — should play global music")
			if stream and not playing:
				play()
				print("▶️ Global music playing")
			else:
				print("⚠️ Stream missing or already playing")
		else:
			print("🚫 Scene not allowed — stopping global music")
			stop()
