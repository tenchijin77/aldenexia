# campfire.gd — logs a flavor message when the player warms up near the fire
extends Node3D

@onready var warmth_area: Area3D = $WarmthArea

var _player_near: bool = false


func _ready() -> void:
	warmth_area.body_entered.connect(_on_body_entered)
	warmth_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if _player_near or not body.is_in_group("player"):
		return
	_player_near = true
	GameLog.log_general("The warmth of the fire renews your spirit as you take shelter nearby.")


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_near = false
