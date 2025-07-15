#skeleton.gd
extends Mob

@onready var sprite: Sprite2D = $Sprite2D

func get_monster_name() -> String:
	return "skeleton"

func handle_movement():
	move_direction.x = sin(Time.get_ticks_msec() / 400.0)
	velocity = move_direction * speed
	move_and_slide()

func update_animation():
	sprite.flip_h = velocity.x < 0
