# spectral_bolt.gd — Traveling visual for Phantasmal Echo's ranged attack
# (phantasmal_echo_pet.gd's _perform_attack()). Damage is computed and AC-
# mitigated at launch, then re-validated and applied on impact via
# source_pet._resolve_bolt_impact() — a few tenths of a second of flight is
# enough for the target to die to something else first, so impact can't just
# trust the numbers it launched with.
#
# Placeholder visual (glowing sphere + light) — no dedicated spell-effect
# asset exists yet; swap _ready()'s visual for a real one once it does.
extends Node3D
class_name SpectralBolt

const SPEED := 18.0
const HIT_RADIUS := 0.6
const MAX_LIFETIME := 3.0

var target: Node = null
var damage: int = 0
var source_pet: Node = null

var _life: float = 0.0


func _ready() -> void:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	mesh_instance.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.6, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.45, 1.0)
	mat.emission_energy_multiplier = 2.5
	mesh_instance.material_override = mat
	add_child(mesh_instance)

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.279, 0.613, 0.941, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 3.0
	add_child(glow)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > MAX_LIFETIME or not is_instance_valid(target):
		queue_free()
		return

	var target_pos: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var to_target: Vector3 = target_pos - global_position
	if to_target.length() <= HIT_RADIUS:
		_impact()
		return

	var dir := to_target.normalized()
	look_at(global_position + dir, Vector3.UP)
	global_position += dir * SPEED * delta


func _impact() -> void:
	if is_instance_valid(source_pet) and source_pet.has_method("_resolve_bolt_impact"):
		source_pet._resolve_bolt_impact(target, damage)
	queue_free()
