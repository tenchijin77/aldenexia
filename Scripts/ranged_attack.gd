# ranged_attack.gd
extends Area2D

@export var speed := 300.0
@export var damage := 15.0
var direction := Vector2.RIGHT

func _ready():
	$attack_sound	.play()

func _process(delta):
	if direction != null:
		position += direction * speed * delta
		rotation = direction.angle()
	else:
		print("⚠️ Ranged attack direction is null — check instantiation!")

func _on_body_entered(body):
	if body.is_in_group("monsters"):
		body.apply_damage(damage)

		var flash := preload("res://Scenes/impact_flash.tscn").instantiate()
		flash.position = position
		get_parent().add_child(flash)

		queue_free()
