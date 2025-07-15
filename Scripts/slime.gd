extends Mob

@onready var sprite: Sprite2D = $Sprite2D


func _ready():
	behavior_type = "ambush" #<- rats

func get_monster_name() -> String:
	return "slime"
	
	
func handle_movement():
	move_direction.x = sin(Time.get_ticks_msec() / 500.0)
	velocity = move_direction * speed
	move_and_slide()

func update_animation():
	sprite.flip_h = velocity.x < 0
	
