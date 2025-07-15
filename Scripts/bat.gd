#bat.gd 
extends Mob

@export var bat_health: int = 15
@export var bat_speed: float = 80


func get_monster_name() -> String:
	return "bat"
	
func _ready():
	super._ready()
	behavior_type = "flutter" # <- bats
	
func die():
	$AnimationPlayer.play("death") #play rat specific death animation
	await $AnimationPlayer.animation_finished
	queue_free()
	
