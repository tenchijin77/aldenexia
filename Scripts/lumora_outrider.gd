# lumora_outrider.gd
# Lumora Outrider - Friendly NPC guard on foot patrol
# Found at oasis and patrolling roads
# Quest giver, Soul Binder (at oasis captain)
# Does NOT attack unless player attacks them first
extends Mob

@onready var sprite: Sprite2D = $Sprite2D
@onready var detection_area: Area2D = $detection_area

var is_friendly := true
var player_is_hostile := false

func get_monster_name() -> String:
	return "lumora_outrider"

func _ready():
	super._ready()
	behavior_type = "skitter"  # Patrols slowly
	# Set faction to "Lumora" in monsters.json
	# Only aggros if player attacks first

func _on_player_attacked_guard():
	# If player attacks, turn hostile
	is_friendly = false
	player_is_hostile = true
	# TODO: Link nearby guards (social aggro)

func interact():
	# For future dialogue/quest system
	if is_friendly:
		print("Lumora Outrider: 'Safe travels, friend. The desert can be dangerous.'")
		# TODO: Open quest/dialogue window
	
func apply_damage(amount: int):
	super.apply_damage(amount)
	_on_player_attacked_guard()
