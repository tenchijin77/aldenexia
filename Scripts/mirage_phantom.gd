# mirage_phantom.gd
# Mirage Phantom - Desert illusion given form by heat and magic
# Teleports short distances when hit (annoying mechanic)
# Casts "Blur" making it harder to hit
# Rare spawn, midday only (heat creates mirages)
extends Mob

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D

var teleport_cooldown: float = 0.0
const TELEPORT_DISTANCE: float = 100.0  # pixels
const TELEPORT_COOLDOWN_TIME: float = 3.0

func get_monster_name() -> String:
	return "mirage_phantom"

func _ready():
	super._ready()
	behavior_type = "ambush"
	
	# Set shimmer effect
	if sprite:
		sprite.modulate.a = 0.8  # Slightly transparent

func _physics_process(delta: float):
	super._physics_process(delta)
	
	# Update teleport cooldown
	if teleport_cooldown > 0.0:
		teleport_cooldown -= delta

func apply_damage(amount: int):
	super.apply_damage(amount)
	
	# Teleport when hit (if cooldown ready)
	if teleport_cooldown <= 0.0:
		teleport_random()
		teleport_cooldown = TELEPORT_COOLDOWN_TIME

func teleport_random():
	# Teleport 5m away in random direction
	var random_angle = randf() * TAU  # Random angle in radians
	var offset = Vector2(cos(random_angle), sin(random_angle)) * TELEPORT_DISTANCE
	global_position += offset
	
	# Visual effect (TODO: Add particle effect)
	print("[Mirage Phantom] Teleported!")
