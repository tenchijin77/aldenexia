# snake.gd
extends Mob

@onready var sprite: Sprite2D = $Sprite2D

func get_monster_name() -> String:
	return "snake"

func _ready():
	super._ready()

func apply_damage(amount: int):
	super.apply_damage(amount)

func update_animation():
	sprite.flip_h = velocity.x < 0
