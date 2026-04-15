# sunmaddened_wanderer.gd
# Sunmaddened Wanderer - Tragic desert madman, driven insane by heat
# Lost traveler who has gone mad from sun exposure
# Wanders randomly, attacks erratically (often misses)
# Sometimes begs for water before attacking (storytelling)
# Drops: Tattered robes, dried rations, broken compass
extends Mob

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var madness_timer: float = 0.0
var begged_for_water := false

func get_monster_name() -> String:
	return "sunmaddened_wanderer"

func _ready():
	super._ready()
	behavior_type = "skitter"  # Wanders erratically
	
	# Random chance to beg for water on spawn
	if randf() < 0.3:  # 30% chance
		call_deferred("beg_for_water")

func _physics_process(delta: float):
	super._physics_process(delta)
	
	# Erratic behavior - randomly change direction
	madness_timer += delta
	if madness_timer > 3.0:
		madness_timer = 0.0
		# TODO: Change wandering direction randomly

func beg_for_water():
	if not begged_for_water:
		begged_for_water = true
		print("[Sunmaddened Wanderer] 'Water... please... water...'")
		# Wait 2 seconds, then become hostile
		await get_tree().create_timer(2.0).timeout
		print("[Sunmaddened Wanderer] *attacks in confusion*")

func apply_damage(amount: int):
	super.apply_damage(amount)
	
	# Random chance to miss player (erratic attacks)
	# TODO: Implement in combat system
	# attack_accuracy = 0.6  # Only hits 60% of time

func update_animation():
	sprite.flip_h = velocity.x < 0
