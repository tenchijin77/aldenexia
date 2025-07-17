# bat.gd
extends Mob

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func get_monster_name() -> String:
	return "bat"
	
func _ready():
	super._ready()
	behavior_type = "flutter"
	
func apply_damage(amount: int):
	super.apply_damage(amount)

func die():
	if animation_player:
		animation_player.play("death")
		await animation_player.animation_finished
	queue_free()
