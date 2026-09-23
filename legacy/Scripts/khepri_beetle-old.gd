# khepri_beetle.gd
# Khepri Beetle - Ancient scarab variant, tougher and aggressive
# Named after Egyptian scarab god, found near ruins
# Drops pristine carapace (rare crafting material)
extends Mob

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func get_monster_name() -> String:
	return "khepri_beetle"

func _ready():
	super._ready()
	behavior_type = "skitter"
	# Khepri beetles are aggressive unlike regular scarabs

func apply_damage(amount: int):
	super.apply_damage(amount)
