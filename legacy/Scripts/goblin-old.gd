# goblin.gd
extends Mob

@onready var sprite: Sprite2D = $Sprite2D
@onready var detection_area: Area2D = $detection_area
@onready var player: CharacterBody2D = null

var is_chasing := false

func get_monster_name() -> String:
	return "goblin"

func _ready():
	super._ready()
	if detection_area:
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
	return super.get_move_direction()

func apply_damage(amount: int):
	super.apply_damage(amount)

func update_animation():
	sprite.flip_h = velocity.x < 0
