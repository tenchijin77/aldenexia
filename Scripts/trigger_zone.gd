extends Area2D

@onready var dialogue_manager: Node = %dialogue_manager

func _on_body_entered(body: Node2D) -> void:
	if body.name == "player":
		dialogue_manager.start_dialogue()extends Node
