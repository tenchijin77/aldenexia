# sandshifter.gd
# Sandshifter - Elemental creature made of living sand
# Semi-transparent, phases in/out of sand
# Takes reduced physical damage, increased magic damage
# Teaches players about elemental resistances
extends Mob

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D

func get_monster_name() -> String:
	return "sandshifter"

func _ready():
	super._ready()
	behavior_type = "flutter"  # Shifts through sand erratically
	
	# Set transparency for semi-transparent effect
	if sprite:
		sprite.modulate.a = 0.7  # 70% opacity
	
	# TODO: Implement damage resistance
	# Physical damage: 50% reduction
	# Magic damage: 50% increase

func apply_damage(amount: int):
	# Future: Check damage type and apply modifiers
	# if damage_type == "physical":
	#     amount = amount * 0.5
	# elif damage_type == "magic":
	#     amount = amount * 1.5
	
	super.apply_damage(amount)
	
func update_animation():
	# Sandshifters phase/shimmer rather than flip
	pass
