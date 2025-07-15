#rat.gd 
extends Mob

@export var rat_health: int = 15
@export var rat_speed: float = 80

func get_monster_name() -> String:
	return "rat"
	
func _ready():
	super._ready()
	behavior_type = "flutter" #<- rats


func die():
	$AnimationPlayer.play("death") #play rat specific death animation
	await $AnimationPlayer.animation_finished
	queue_free()
	
