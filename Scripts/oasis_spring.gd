# oasis_spring.gd — Lumora's central oasis (Data/lumora.json signature_features.central_oasis: "+3 CON for 15 minutes"):
# rest by the water for LINGER_SECONDS and you're Refreshed by the Oasis. Like the campfire's warmth (campfire.gd): each
# player's own game notices its own player arriving, so it works the same on every screen. A stand-in pool (a flat disc of
# water) is drawn until the real oasis model exists (outstanding_items.txt, MISSING ASSETS).
extends Node3D

@export var radius: float = 14.0
@export var draw_pool: bool = true
const LINGER_SECONDS := 10.0
const BUFF_SECONDS := 900.0   # 15 minutes: the non-combat buff rule
const BUFF := {"stat_constitution": 3}

var _area: Area3D
var _timer := Timer.new()
var _resting: Node3D = null


func _ready() -> void:
	add_to_group("oasis_spring")
	_area = Area3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 6.0
	shape.shape = cyl
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_enter)
	_area.body_exited.connect(_on_exit)
	_timer.one_shot = true
	_timer.wait_time = LINGER_SECONDS
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	if draw_pool and DisplayServer.get_name() != "headless":
		var pool := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = radius * 0.7
		disc.bottom_radius = radius * 0.7
		disc.height = 0.08
		pool.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.45, 0.55, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.metallic = 0.3
		mat.roughness = 0.08
		pool.material_override = mat
		pool.position.y = 0.05
		add_child(pool)
	var label := Label3D.new()
	label.text = "The Oasis"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 56
	label.outline_size = 10
	label.position.y = 3.0
	add_child(label)


func _on_enter(body: Node3D) -> void:
	if not body.is_in_group("player") or not body.is_multiplayer_authority() or _resting != null:
		return
	_resting = body
	GameLog.log_general("The cool air off the water eases the heat of the desert.")
	_timer.start()


func _on_exit(body: Node3D) -> void:
	if body == _resting:
		_resting = null
		_timer.stop()


func _refresh() -> void:
	if not is_instance_valid(_resting) or not (_resting.get("combat_node") is CombatNode):
		return
	_resting.combat_node.apply_effect("oasis_refreshed", BUFF_SECONDS, BUFF.duplicate())
	GameLog.log_general("[color=#88ddff]You feel refreshed by the oasis. (+3 Constitution for 15 minutes)[/color]")
