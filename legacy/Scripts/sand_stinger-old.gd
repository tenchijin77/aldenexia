# sand_stinger.gd
# Sand Stinger - Venomous desert scorpion
# Ambush predator with poison DoT attack
# Hides in sand, strikes when player gets close
extends Mob

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func get_monster_name() -> String:
	return "sand_stinger"

func _ready():
	super._ready()
	behavior_type = "ambush"
	# TODO: Implement poison attack
	# On hit: Apply DoT (5 damage/sec for 10 seconds)

func apply_damage(amount: int):
	super.apply_damage(amount)
	
# Future: Add poison damage method
# func apply_poison_to_player(player):
#     player.apply_dot("poison", 5, 10)  # 5 dmg/sec for 10 sec
