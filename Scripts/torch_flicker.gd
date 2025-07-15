# torch_flicker.gd
extends Node2D

@export var flicker_speed_min: float = 0.05
@export var flicker_speed_max: float = 0.15
@export var energy_min: float = 0.8
@export var energy_max: float = 1.2

var flicker_timer := 0.0
var flicker_speed := 0.1

@onready var light := $PointLight2D

func _ready():
	flicker_speed = randf_range(flicker_speed_min, flicker_speed_max)

func _process(delta: float) -> void:
	flicker_timer += delta
	if flicker_timer >= flicker_speed:
		light.energy = randf_range(energy_min, energy_max)
		flicker_timer = 0.0
		flicker_speed = randf_range(flicker_speed_min, flicker_speed_max)
