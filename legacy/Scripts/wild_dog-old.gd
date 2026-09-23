# wild_dog.gd
# Wild Dog - Pack hunter, teaches players about social aggro mechanics
# Roams in packs of 2-3, links with nearby dogs when attacked
extends Mob

@onready var detection_area: Area2D = $detection_area
@onready var player: CharacterBody2D = null
@onready var sprite: Sprite2D = $Sprite2D

var is_chasing := false

func get_monster_name() -> String:
	return "wild_dog"

func _ready():
	super._ready()
	behavior_type = "ambush"
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	
func _on_body_entered(body: Node) -> void:
	if body.name == "player":
		player = body
		is_chasing = true
	
func _on_body_exited(body: Node) -> void:
	if body == player:
		is_chasing = false
		player = null
		
func get_move_direction() -> Vector2:
	if is_chasing and player:
		return (player.global_position - global_position).normalized()
	return Vector2.ZERO
	
func apply_damage(amount: int):
	super.apply_damage(amount)
	
func update_animation():
	sprite.flip_h = velocity.x < 0
