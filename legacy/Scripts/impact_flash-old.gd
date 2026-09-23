#impact_flash.gd
extends Node2D

func _ready():
	$Timer.timeout.connect(func(): queue_free())
