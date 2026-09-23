# skeleton.gd
extends Mob

@onready var sprite: Sprite2D = $Sprite2D

func get_monster_name() -> String:
	return "skeleton"

func _ready():
	super._ready()

func apply_damage(amount: int):
	super.apply_damage(amount)

func handle_movement():
	move_direction = Vector2(sin(Time.get_ticks_msec() / 400.0), 0)
	velocity = move_direction * speed
	move_and_slide()

func update_animation():
	sprite.flip_h = velocity.x < 0
