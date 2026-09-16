# splash_screen.gd — Studio logo splash shown once at boot, before the main
# menu loads. Fades the Kuro Neko Sama Games logo in, holds, fades it out,
# then hands off to main_menu.tscn. Any key/click skips straight there.
extends Control

const HOLD_TIME := 1.6
const FADE_TIME := 0.6

@onready var logo: TextureRect = $Logo

var _leaving := false


func _ready() -> void:
	logo.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(logo, "modulate:a", 1.0, FADE_TIME)
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(logo, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(_go_to_main_menu)


func _go_to_main_menu() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	var skip: bool = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if skip:
		_go_to_main_menu()
