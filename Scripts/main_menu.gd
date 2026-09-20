#main_menu.gd
extends Node

@onready var torch_left = $Panel/torch
@onready var torch_right = $Panel/TorchRightAnchor/torch2
@onready var light = $Panel/torch/PointLight2D
@onready var light_right = $Panel/TorchRightAnchor/torch2/PointLight2D2
@onready var torch_sound = $torch_sound


func _ready():
	_add_version_label()
	torch_left.play("torch_flicker")
	torch_right.play("torch_flicker")
	torch_sound.play()
	# GlobalBackgroundMusic already autoplays on boot and restarts itself via
	# its own _check_and_play_music() (child_entered_tree hook) the moment
	# main_menu becomes the current scene — this explicit stop()+play() was
	# fully redundant with that, and restarted the track from the beginning
	# every time you returned to the main menu. Removed 2026-09-14 while
	# investigating a reported music startup delay (see global.gd's
	# _warm_up_audio() — this wasn't the cause, just dead weight found along
	# the way).

	# Coming back from character_creation.tscn's "Create New Character"
	# shortcut off the multiplayer menu — reopen that overlay (its dropdown
	# repopulates from disk in _ready(), so the new character shows up) rather
	# than stranding the player on a bare main menu. See global.gd's
	# return_to_multiplayer_menu doc comment.
	if Global.return_to_multiplayer_menu:
		Global.return_to_multiplayer_menu = false
		_on_multiplayer_pressed()
	# Same for the Join a Server screen: a failed/dropped server join, or backing out of creating a
	# server character, lands here and reopens it.
	if Global.return_to_join_server_menu:
		Global.return_to_join_server_menu = false
		Global.server_creation = {}
		_on_join_server_pressed()


# Version (and build, if stamped) in the bottom-right corner — see game_version.gd.
func _add_version_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var label := Label.new()
	label.text = GameVersion.display()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.72, 0.65, 0.5, 0.85))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_right = -14
	label.offset_bottom = -10
	layer.add_child(label)


var flicker_timer_left := 0.0
var flicker_timer_right := 0.0
var flicker_speed_left := 0.05 + randf() * 0.1
var flicker_speed_right := 0.05 + randf() * 0.1

func _process(delta: float) -> void:
	flicker_timer_left += delta
	flicker_timer_right += delta

	if flicker_timer_left >= flicker_speed_left:
		light.energy = randf_range(0.8, 1.2)
		flicker_timer_left = 0.0
		flicker_speed_left = 0.05 + randf() * 0.1

	if flicker_timer_right >= flicker_speed_right:
		light_right.energy = randf_range(0.8, 1.2)
		flicker_timer_right = 0.0
		flicker_speed_right = 0.05 + randf() * 0.1



func _on_create_character_pressed() -> void:
	print("🧭 Create Character button pressed.")
	get_tree().change_scene_to_file("res://Scenes/character_creation.tscn")



func _on_load_game_pressed() -> void:
	var load_game_scene = preload("res://Scenes/load_game.tscn").instantiate()
	add_child(load_game_scene)
	print("DEBUG: Load game menu opened")
	#get_tree().change_scene_to_file("res://Scenes/lumora_outskirts.tscn")


func _on_multiplayer_pressed() -> void:
	var menu = preload("res://Scenes/multiplayer_menu.tscn").instantiate()
	add_child(menu)


func _on_join_server_pressed() -> void:
	var menu = preload("res://Scenes/join_server_menu.tscn").instantiate()
	add_child(menu)


func _on_credits_pressed() -> void:
	pass # Replace with function body.
	

func _on_options_pressed() -> void:
	pass # Replace with function body.


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
