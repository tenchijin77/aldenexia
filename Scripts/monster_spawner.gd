extends Node2D

@export var monster_scene:PackedScene
@export var spawn_count: int = 5
@export var spawn_radius: float = 200.0

var spawn_locations: Array[Vector2] = []

func _ready():
	spawn_monsters()
	
func spawn_monsters()
	for i in spawn_count:
		var monster = monster.scene.instantiate()
		var offset = Vector2(randf_range(-spawn_radius, spawn_radius), randf_range(-spawn_radius, spawn_radius))
		monster.position = global_position + offset
		monster.connect("died", Callable(self, "_on_monster_died"))
		
func _on_monster_died(death_position: Vector2):
	spawn_locations.append(death_position)
		
