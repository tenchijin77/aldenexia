#magic_missile.gd
extends Area2D

@export var speed := 300.0
var direction := Vector2.RIGHT

func _ready():
	if $cast_sound.stream:
		$cast_sound.play()

	var monsters := get_tree().get_nodes_in_group("monsters")
	var closest: CharacterBody2D = null
	var closest_dist := INF

	for monster in monsters:
		if monster is CharacterBody2D:
			var dist: float = monster.global_position.distance_to(global_position)
			if dist < closest_dist:
				closest = monster
				closest_dist = dist

	if closest:
		direction = (closest.global_position - global_position).normalized()
	else:
		direction = Vector2.RIGHT

func _process(delta):
	if direction != null:
		position += direction * speed * delta
		rotation = direction.angle()
	else:
		print("⚠️ Spell direction is null — check instantiation!")


func _on_body_entered(body):
	if body.is_in_group("monsters"):
		body.apply_damage(15)

		var flash := preload("res://Scenes/impact_flash.tscn").instantiate()
		flash.position = position
		get_parent().add_child(flash)

		queue_free()
	

		
		
