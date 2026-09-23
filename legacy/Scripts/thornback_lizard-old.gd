# thornback_lizard.gd
# Thornback Lizard - Large desert lizard with thorny back
# Non-aggressive, basks in sun (defensive)
# Counter-attack: Melee attackers take 2 damage from thorns
# Good for leather crafting materials
extends Mob

@onready var animation_player: AnimationPlayer = $AnimationPlayer

var is_sunbathing := true

func get_monster_name() -> String:
	return "thornback_lizard"

func _ready():
	super._ready()
	behavior_type = "skitter"
	# Set aggro_range to 0 in monsters.json for passive behavior

func apply_damage(amount: int):
	super.apply_damage(amount)
	
	# When hit, stop sunbathing and become aggressive
	if is_sunbathing:
		is_sunbathing = false
		print("[Thornback Lizard] Disturbed from sunbathing!")

# Future: Implement thorn damage
# When player hits lizard in melee range, player takes 2 damage
# func on_melee_hit_by_player(player):
#     player.apply_damage(2)
#     print("The thornback's spines prick you!")
