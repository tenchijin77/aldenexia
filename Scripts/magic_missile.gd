# magic_missile.gd
extends Area2D

@export var speed: float = 200.0
@export var damage: int = 10
var direction: Vector2 = Vector2.ZERO
var target: Node2D = null # The enemy to track

func _ready():
	collision_layer = 1 << 2 # Projectile layer (layer 3)
	collision_mask = 1 << 3 # Enemy layer (layer 4)
	
	# Connect to body_entered signal for detecting CharacterBody2D
	body_entered.connect(_on_body_entered)
	print("DEBUG: Magic Missile initialized with target: ", target.name if target else "No target")

func _physics_process(delta):
	if target and is_instance_valid(target):
		direction = (target.global_position - global_position).normalized()
		rotation = direction.angle() # Rotate sprite to face direction
		print("DEBUG: Magic Missile at ", global_position, " tracking target at ", target.global_position)
	else:
		print("DEBUG: Magic Missile at ", global_position, " with no valid target")

	global_position += direction * speed * delta

func _on_body_entered(body: Node2D):
	if body.is_in_group("monsters"):
		if body.has_method("apply_damage"):
			body.apply_damage(damage)
			print("DEBUG: Magic Missile hit ", body.name, " for ", damage, " damage")
		else:
			print("DEBUG: Magic Missile hit monster without apply_damage method: ", body.name)
		queue_free()
	else:
		print("DEBUG: Magic Missile hit non-monster body: ", body.name if body else "null")
		# Optionally queue_free() here if you want it to destroy on any non-monster hit
