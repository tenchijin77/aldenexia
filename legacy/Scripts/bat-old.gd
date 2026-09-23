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
