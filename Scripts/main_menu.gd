#main_menu.gd
extends Node

@onready var torch_left = $Panel/torch
@onready var torch_right = $Panel/TorchRightAnchor/torch2
@onready var light = $Panel/torch/PointLight2D
@onready var light_right = $Panel/TorchRightAnchor/torch2/PointLight2D2
@onready var torch_sound = $torch_sound


func _ready():
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


# Stub — the button is disabled until real netcode exists (listen-server
# co-op, per the roadmap in change_list.txt). Left wired up now so enabling
# it later is a one-line `disabled = false` in main_menu.tscn, not a rewire.
func _on_multiplayer_pressed() -> void:
	print("🌐 Multiplayer selected — not implemented yet.")


func _on_credits_pressed() -> void:
	pass # Replace with function body.
	

func _on_options_pressed() -> void:
	pass # Replace with function body.


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
