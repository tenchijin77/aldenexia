# spectral_bolt.gd — The traveling projectile for the ranged pets' attacks (Phantasmal Echo, Wildspeaker's spirit).
# A glowing green core with a soft particle trail and drifting sparkles, and a burst of particles plus a flash on impact.
# Damage is computed and AC-mitigated at launch by the pet, then re-validated and applied on impact via
# source_pet._resolve_bolt_impact() — a few tenths of a second of flight is enough for the target to die to something
# else first, so impact can't just trust the numbers it launched with.
#
# Only the pet owner's machine makes a bolt that deals damage. Every OTHER player gets a visual-only copy
# (visual_only = true, launched by PetMinion._rpc_show_bolt) so they see the shot too; it deals nothing.
extends Node3D
class_name SpectralBolt

const SPEED := 18.0
const HIT_RADIUS := 0.6
const MAX_LIFETIME := 3.0

var target: Node = null
var damage: int = 0
var source_pet: Node = null
## The bolt's colour — each pet picks its own shade of green (see PetMinion._launch_bolt()).
var bolt_color: Color = Color(0.35, 1.0, 0.45)
## A copy shown on other players' screens: flies and bursts, but applies no damage.
var visual_only: bool = false
## Where a visual-only bolt flies if it cannot find the target node on this machine.
var fixed_target: Vector3 = Vector3.ZERO

var _life: float = 0.0
var _spent: bool = false
var _orb: Node3D
var _light: OmniLight3D
var _trail: GPUParticles3D
var _sparkles: GPUParticles3D


# A soft round glow texture for the particle quads (white centre fading to transparent) so they read as light, not squares.
static func _glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex


static func _particle_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _glow_texture()
	mat.albedo_color = color
	return mat


# Fade-out colour ramp for a particle: `color` at birth, transparent at death.
static func _fade_ramp(color: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(color.r, color.g, color.b, 0.95), Color(color.r * 0.6, color.g * 0.9, color.b * 0.6, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


static func _make_particles(color: Color, amount: int, lifetime: float, quad_size: float, velocity_min: float, velocity_max: float, radius: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false          # particles stay where they were emitted, so a moving bolt leaves a trail
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3.ZERO
	pm.spread = 180.0
	pm.initial_velocity_min = velocity_min
	pm.initial_velocity_max = velocity_max
	pm.gravity = Vector3(0, 0.4, 0)   # motes drift gently upward, like embers
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _fade_ramp(color)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	quad.material = _particle_material(Color(1, 1, 1, 1))
	p.draw_pass_1 = quad
	return p


func _ready() -> void:
	# Bright core + a larger, faint halo.
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	core.mesh = sphere
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = bolt_color.lerp(Color.WHITE, 0.55)
	core_mat.emission_enabled = true
	core_mat.emission = bolt_color
	core_mat.emission_energy_multiplier = 3.0
	core.material_override = core_mat
	var halo := MeshInstance3D.new()
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 0.3
	halo_mesh.height = 0.6
	halo.mesh = halo_mesh
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.albedo_color = Color(bolt_color.r, bolt_color.g, bolt_color.b, 0.28)
	halo.material_override = halo_mat
	_orb = Node3D.new()
	_orb.add_child(core)
	_orb.add_child(halo)
	add_child(_orb)

	_light = OmniLight3D.new()
	_light.light_color = bolt_color
	_light.light_energy = 1.6
	_light.omni_range = 3.5
	add_child(_light)

	# Soft trail behind the bolt, plus a few faster, brighter sparkles drifting off it.
	_trail = _make_particles(bolt_color, 42, 0.5, 0.34, 0.1, 0.5, 0.07)
	add_child(_trail)
	_sparkles = _make_particles(bolt_color.lerp(Color.WHITE, 0.5), 18, 0.75, 0.13, 0.5, 1.4, 0.12)
	add_child(_sparkles)
	_trail.emitting = true
	_sparkles.emitting = true


func _aim_point() -> Vector3:
	if is_instance_valid(target):
		return target.global_position + Vector3(0, 1.0, 0)
	return fixed_target


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_life += delta
	var has_goal := is_instance_valid(target) or visual_only
	if _life > MAX_LIFETIME or not has_goal:
		_finish(false)
		return

	var to_target: Vector3 = _aim_point() - global_position
	if to_target.length() <= HIT_RADIUS:
		_impact()
		return

	var dir := to_target.normalized()
	look_at(global_position + dir, Vector3.UP)
	global_position += dir * SPEED * delta


func _impact() -> void:
	if not visual_only and is_instance_valid(source_pet) and source_pet.has_method("_resolve_bolt_impact"):
		source_pet._resolve_bolt_impact(target, damage)
	_burst()
	_finish(true)


# A burst of green motes flying outward from the point of impact, plus a brief flash of light. Lives on the scene root
# so it keeps playing after the bolt itself is gone.
func _burst() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var burst := _make_particles(bolt_color.lerp(Color.WHITE, 0.25), 34, 0.6, 0.22, 1.6, 3.6, 0.1)
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 34
	(burst.process_material as ParticleProcessMaterial).gravity = Vector3(0, -1.2, 0)
	scene.add_child(burst)
	burst.global_position = global_position
	burst.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = bolt_color
	flash.light_energy = 3.0
	flash.omni_range = 4.5
	scene.add_child(flash)
	flash.global_position = global_position
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)
	get_tree().create_timer(1.2).timeout.connect(burst.queue_free)


# Ends the bolt: hides the orb and stops emitting, but keeps the node a moment so the trail can fade out on its own.
func _finish(_hit: bool) -> void:
	if _spent:
		return
	_spent = true
	_orb.hide()
	_light.hide()
	_trail.emitting = false
	_sparkles.emitting = false
	get_tree().create_timer(0.9).timeout.connect(queue_free)
