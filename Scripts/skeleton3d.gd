## skeleton3d.gd - 3D version
## Extends Monster base class (same pattern as 2D Skeleton extends Mob)
extends Monster

# ===== REFERENCES =====
@onready var mesh: MeshInstance3D = $MeshInstance3D  # 3D equivalent of sprite

# ===== OVERRIDE MONSTER NAME FOR JSON LOADING =====
func get_monster_name() -> String:
	return "skeleton"

# ===== READY =====
func _ready() -> void:
	super._ready()  # Call parent (loads JSON stats, etc.)

# ===== DAMAGE OVERRIDE (like 2D version) =====
func apply_damage(amount: int, damage_type: String = "physical") -> void:
	super.apply_damage(amount, damage_type)
	# Add skeleton-specific hit effects here

# ===== DAMAGE MODIFICATION (resistances/weaknesses) =====
func modify_damage(amount: int, damage_type: String) -> int:
	# Skeleton damage modifiers
	match damage_type:
		"piercing":
			return int(amount * 0.7)  # 30% resistance to arrows
		"blunt":
			return int(amount * 1.3)  # 30% weak to maces/hammers
		"fire":
			return int(amount * 1.1)  # 10% weak to fire
		_:
			return amount

# ===== CUSTOM MOVEMENT (if needed - like 2D handle_movement) =====
# Uncomment to override movement behavior
# func handle_movement(delta: float) -> void:
#	# Custom skeleton movement pattern
#	move_direction = Vector3(sin(Time.get_ticks_msec() / 400.0), 0, 0)
#	velocity = move_direction * speed
#	move_and_slide()

# ===== ANIMATION UPDATE (if using animations) =====
# func update_animation() -> void:
#	if mesh:
#		# Flip mesh based on direction
#		if velocity.x < 0:
#			mesh.scale.x = -1
#		elif velocity.x > 0:
#			mesh.scale.x = 1
