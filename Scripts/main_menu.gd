#main_menu.gd
extends Node

@onready var torch_left = $Panel/torch
@onready var torch_right = $Panel/torch2
@onready var light = $Panel/torch/PointLight2D
@onready var light_right = $Panel/torch2/PointLight2D2
@onready var music = $background_music
@onready var torch_sound = $torch_sound


func _ready():
	torch_left.play("torch_flicker")
	torch_right.play("torch_flicker")
	torch_sound.play()

	
	music.play()
	music.connect("finished", Callable(self, "_on_music_finished"))

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



func _on_new_game_pressed() -> void:
		get_tree().change_scene_to_file("res://Scenes/lumora_outskirts.tscn")



func _on_load_game_pressed() -> void:
	pass # Replace with function body.
	
	
func _on_credits_pressed() -> void:
	pass # Replace with function body.
	

func _on_options_pressed() -> void:
	pass # Replace with function body.


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


func _on_background_music_finished() -> void:
	music.play()
