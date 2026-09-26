# fire_fx.gd — a living fire for campfires and torches (test 40: "more realistic and random"). Put it where the flames
# are; `size` scales everything (1 = a campfire, ~0.35 = a torch). It builds, in code, with no textures to load:
#   flames — many small soft tongues, additive, each a different size, speed and life, pushed about by turbulence so no
#            two moments look the same: white-yellow at the core, orange, then deep red as they die;
#   embers — a few sparks that wander up and wink out;
#   smoke  — soft grey puffs that grow, thin out and drift a little downwind.
# The fire's OmniLight3D (the nearest one in its scene) flickers with noise instead of burning steady, and casts no
# shadows: shadowed omni lights were the most expensive part (a shadow cube map for every torch). Nothing is drawn beyond
# VISIBLE_RANGE. The scene's old "flames" / "smoke" particles, if any, are switched off. Runs in the editor too, so you
# see it where you place it.
@tool
class_name FireFX
extends Node3D

@export_range(0.1, 3.0) var size: float = 1.0:
	set(v):
		size = v
		if is_inside_tree():
			_build()
@export var smoke: bool = true
@export var embers: bool = true
@export var light_flicker: float = 0.3   # how much the light's energy wanders (0 = steady)

const VISIBLE_RANGE := 70.0

static var _soft_dot: Texture2D = null

var _flames: GPUParticles3D
var _embers: GPUParticles3D
var _smoke: GPUParticles3D
var _light: OmniLight3D
var _base_energy := 0.0
var _noise := FastNoiseLite.new()
var _time := 0.0
var _light_home := Vector3.ZERO


func _ready() -> void:
	_noise.frequency = 0.9
	_noise.seed = randi()
	_time = randf() * 100.0   # every fire flickers out of step with the others
	_build()


func _build() -> void:
	for child in get_children():
		if child.has_meta("fire_fx"):
			remove_child(child)
			child.queue_free()
	# the scene's old single-sprite particles
	var scene_root := owner if owner != null else get_parent()
	if scene_root != null:
		for old in scene_root.find_children("*", "GPUParticles3D", true, false):
			if old.name in ["flames", "smoke"] and not old.has_meta("fire_fx"):
				old.emitting = false
				old.visible = false
	_flames = _particles("Flames", _flame_material(), _flame_draw(), int(40 * clampf(size, 0.5, 1.5)), 0.9, 0.45, false)
	if embers:
		_embers = _particles("Embers", _ember_material(), _ember_draw(), int(8 * clampf(size, 0.5, 1.5)), 2.2, 0.6, false)
	if smoke:
		_smoke = _particles("Smoke", _smoke_material(), _smoke_draw(), int(14 * clampf(size, 0.5, 1.5)), 4.0, 0.5, true)
		_smoke.position = Vector3(0, 0.55 * size, 0)
	_light = _find_light(scene_root)
	if _light != null:
		_light.shadow_enabled = false
		if _base_energy <= 0.0:
			_base_energy = _light.light_energy
			_light_home = _light.position
		_light.distance_fade_enabled = true
		_light.distance_fade_begin = VISIBLE_RANGE * 0.6
		_light.distance_fade_length = VISIBLE_RANGE * 0.3


func _process(delta: float) -> void:
	if _light == null or not is_instance_valid(_light) or light_flicker <= 0.0:
		return
	_time += delta
	var n := _noise.get_noise_1d(_time * 6.0)          # -1..1, smooth
	var fast := _noise.get_noise_1d(_time * 23.0 + 50.0)
	_light.light_energy = _base_energy * (1.0 + light_flicker * (0.7 * n + 0.3 * fast))
	# the light sways a hand's width with the flames, so shadows of things near it breathe
	_light.position = _light_home + Vector3(n, fast * 0.5, -n) * 0.04 * size


func _find_light(scene_root: Node) -> OmniLight3D:
	if scene_root == null:
		return null
	var best: OmniLight3D = null
	for l in scene_root.find_children("*", "OmniLight3D", true, false):
		if best == null or (l as Node3D).global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
			best = l
	return best


func _particles(label: String, mat: ParticleProcessMaterial, mesh: Mesh, amount: int, lifetime: float, randomness: float, local: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = label
	p.set_meta("fire_fx", true)
	p.amount = maxi(amount, 3)
	p.lifetime = lifetime
	p.randomness = randomness
	p.preprocess = lifetime   # already burning when you arrive
	p.local_coords = local
	p.process_material = mat
	p.draw_pass_1 = mesh
	p.visibility_range_end = VISIBLE_RANGE
	p.visibility_range_end_margin = 8.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -0.5, -2) * size, Vector3(4, 6, 4) * size)
	add_child(p)
	return p


static func soft_dot() -> Texture2D:
	if _soft_dot == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_dot = t
	return _soft_dot


func _quad(side: float, additive: bool, shaded := false) -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if not shaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.no_depth_test = false
	var q := QuadMesh.new()
	q.size = Vector2(side, side)
	q.material = m
	return q


func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _flame_draw() -> Mesh:
	var q := _quad(0.5 * size, true)
	q.size = Vector2(0.42, 0.78) * size   # tongues, taller than wide
	return q


func _flame_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.22 * size
	m.direction = Vector3(0, 1, 0)
	m.spread = 14.0
	m.gravity = Vector3(0, 0.6 * size, 0)                # hot air rises
	m.initial_velocity_min = 0.6 * size
	m.initial_velocity_max = 1.5 * size
	m.damping_min = 0.4
	m.damping_max = 1.0
	m.scale_min = 0.55
	m.scale_max = 1.25
	m.scale_curve = _curve([Vector2(0.0, 0.55), Vector2(0.18, 1.0), Vector2(0.65, 0.6), Vector2(1.0, 0.0)])
	m.angle_min = -12.0   # tongues stay mostly upright, leaning a little
	m.angle_max = 12.0
	m.angular_velocity_min = -20.0
	m.angular_velocity_max = 20.0
	m.color_ramp = _ramp([0.0, 0.2, 0.5, 0.8, 1.0],
			[Color(1.0, 0.85, 0.55, 0.55), Color(1.0, 0.6, 0.18, 0.6), Color(0.95, 0.32, 0.06, 0.45), Color(0.55, 0.12, 0.03, 0.2), Color(0.2, 0.05, 0.02, 0.0)])
	m.hue_variation_min = -0.02
	m.hue_variation_max = 0.03
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.6
	m.turbulence_noise_scale = 2.2
	m.turbulence_noise_speed_random = 0.8
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.22
	return m


func _ember_draw() -> Mesh:
	return _quad(0.05 * size, true)


func _ember_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.15 * size
	m.direction = Vector3(0, 1, 0)
	m.spread = 25.0
	m.gravity = Vector3(0, 0.25, 0)
	m.initial_velocity_min = 0.8 * size
	m.initial_velocity_max = 2.2 * size
	m.damping_min = 0.3
	m.damping_max = 0.9
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.color_ramp = _ramp([0.0, 0.6, 1.0], [Color(1.0, 0.8, 0.4, 1.0), Color(1.0, 0.45, 0.1, 0.8), Color(0.6, 0.15, 0.05, 0.0)])
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 2.5
	m.turbulence_noise_scale = 1.5
	m.turbulence_influence_min = 0.2
	m.turbulence_influence_max = 0.5
	return m


func _smoke_draw() -> Mesh:
	return _quad(0.9 * size, false)


func _smoke_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.2 * size
	m.direction = Vector3(0, 1, 0)
	m.spread = 12.0
	m.gravity = Vector3(0.12, 0.25, 0.05)                 # rises, and drifts a little downwind
	m.initial_velocity_min = 0.35 * size
	m.initial_velocity_max = 0.8 * size
	m.damping_min = 0.1
	m.damping_max = 0.3
	m.scale_min = 0.6
	m.scale_max = 1.3
	m.scale_curve = _curve([Vector2(0.0, 0.35), Vector2(1.0, 2.6)])
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.angular_velocity_min = -25.0
	m.angular_velocity_max = 25.0
	m.color_ramp = _ramp([0.0, 0.15, 0.6, 1.0],
			[Color(0.25, 0.23, 0.22, 0.0), Color(0.3, 0.29, 0.28, 0.32), Color(0.42, 0.42, 0.42, 0.14), Color(0.5, 0.5, 0.5, 0.0)])
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.0
	m.turbulence_noise_scale = 3.0
	m.turbulence_influence_min = 0.03
	m.turbulence_influence_max = 0.1
	return m
