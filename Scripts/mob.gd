#mob.gd
class_name Mob
extends CharacterBody2D

@export var behavior_type := "default" # Customize per mob: "skitter", "flutter", "ambush"
@export var speed: float = 100.0
@export var max_health: int = 10
@export var damage: int = 1
@onready var name_label: Label = $name_label
@onready var health_bar: ProgressBar = $health_bar
var current_health: int
var movement_offset := 0.0

func  _ready():
	movement_offset = randf_range(0.0, TAU)
	
	var monster_name = get_monster_name()
	var stats = load_monster_stats(monster_name)
	
	if typeof(stats) == TYPE_DICTIONARY:
		max_health - stats.get("health", 10 )
		speed = stats.get("speed", 100.0)
		damage = stats.get ("damage", 5)
		
	current_health = max_health
	
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
		
	if name_label:
		name_label.text = stats.get("description", monster_name)
	
	
func load_monster_stats(monster_name: String) -> Dictionary:
	var path = "res://Data/monsters.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var content := file.get_as_text()
		var result: Dictionary = JSON.parse_string(content) as Dictionary
		if result.has(monster_name):
			return result[monster_name]
	return {}
	
func get_monster_name() -> String:
	return "mob"
	
func load_monster_description(monster_name: String) -> String:
	var path = "res://Data/monsters.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var content := file.get_as_text()
		var result: Dictionary = JSON.parse_string(content)
		if typeof(result) == TYPE_DICTIONARY and result.has(monster_name):
			return result[monster_name].get("description", monster_name)
	return monster_name # fallback
	
	
	
func  _physics_process(delta):
	var direction = get_move_direction()
	velocity = direction * speed
	move_and_slide()
	
func get_move_direction() -> Vector2:
	match behavior_type:
		"skitter":
			return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		"flutter":
			var t = Time.get_ticks_msec() / 1000.0 + movement_offset
			return Vector2(cos(t), sin(t * 3.0)).normalized()
		"ambush":
			var t = Time.get_ticks_msec() / 1000.0 + movement_offset
			return Vector2.RIGHT.rotated(fmod(t, TAU)).normalized()
		_:
			var t = Time.get_ticks_msec() / 1000.0 + movement_offset
			return Vector2.RIGHT.rotated(fmod(t, TAU)).normalized()
	
func take_damage(amount: int):
	current_health -= amount
	if current_health <= 0:
		die()
		
func die():
	queue_free() #can trgger animations or effects here
