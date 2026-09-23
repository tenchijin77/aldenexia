# rat.gd
extends Mob

func _ready():
	add_to_group("monsters")
	super._ready()

func get_monster_name() -> String:
	return "rat"

func apply_damage(amount: int):
	super.apply_damage(amount)
