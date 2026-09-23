# bonegnawer.gd
# Bonegnawer - Half-human, half-dog scavenger (gnoll-like creature)
# Attracted to corpses, eats them (loot disappears!)
# Pack hunters (2-4 together), lower health but coordinated
# Creates urgency on corpse runs
extends Mob

@onready var detection_area: Area2D = $detection_area
@onready var player: CharacterBody2D = null
@onready var sprite: Sprite2D = $Sprite2D

var is_chasing := false
var target_corpse: Node2D = null
var is_eating := false

func get_monster_name() -> String:
	return "bonegnawer"

func _ready():
	super._ready()
	behavior_type = "ambush"
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	
	# TODO: Also detect corpses in area
	# Prioritize corpses over players (scavenger behavior)

func _on_body_entered(body: Node) -> void:
	if body.name == "player":
		player = body
		is_chasing = true
	# TODO: Detect corpses
	# if body.is_in_group("corpses") and not is_eating:
	#     target_corpse = body
	#     is_eating = true
	
func _on_body_exited(body: Node) -> void:
	if body == player:
		is_chasing = false
		player = null
		
func get_move_direction() -> Vector2:
	# Prioritize corpses over player (scavenger first!)
	if target_corpse and is_instance_valid(target_corpse):
		return (target_corpse.global_position - global_position).normalized()
	elif is_chasing and player:
		return (player.global_position - global_position).normalized()
	return Vector2.ZERO
	
func apply_damage(amount: int):
	super.apply_damage(amount)
	# Stop eating if attacked
	if is_eating:
		is_eating = false
		target_corpse = null
	
func update_animation():
	sprite.flip_h = velocity.x < 0
