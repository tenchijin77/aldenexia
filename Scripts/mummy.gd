# mummy.gd
# Mummy - Ancient undead tomb guardian
# Spawns only at night near ruins in sandy areas
# Slow but tough, social aggro with other mummies
# Drops: Ancient bandages, dusty coin purse, rare relics
extends Mob

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func get_monster_name() -> String:
	return "mummy"

func _ready():
	super._ready()
	behavior_type = "skitter"
	# Mummies are slow but relentless
	# Set is_social: true in monsters.json (tomb guardians link)

func apply_damage(amount: int):
	super.apply_damage(amount)
