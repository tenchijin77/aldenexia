# dune_scarab.gd
# Dune Scarab - Passive desert beetle, non-aggressive
# Drops valuable Scarab Carapace for crafting
# Only attacks if provoked
extends Mob

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func get_monster_name() -> String:
	return "dune_scarab"

func _ready():
	super._ready()
	behavior_type = "skitter"
	# Note: Scarabs are passive - set aggro_range to 0 in monsters.json
	# or implement passive AI behavior

func apply_damage(amount: int):
	super.apply_damage(amount)
