# spell_projectile.gd — the bolt a ranged spell (or an archery skill's arrow) flies from the caster to the target.
# player3d.gd launches one when a spell that "flies" (flies()) is cast at an enemy, and the spell's damage and effects
# land when it arrives (the `on_arrive` callback), with the spell's sound at the target. It homes on the target, so it
# always arrives; if the target is gone by then, it just fizzles out. Built entirely in code: a glowing orb in the colour
# of the spell's school with a short trail and a light (an arrow is a thin shaft instead), and a flash where it lands.
extends Node3D

const SPEED := 28.0            # metres per second
const MAX_FLIGHT := 3.0        # seconds: arrives by then whatever happens
const MIN_RANGE := 6.0         # spells with a shorter range than this (touch / melee skills) don't fly
const CHEST_HEIGHT := 1.1      # aims at the target's middle, not its feet
# Spells the data lists as aimed at an enemy that are really self-effects, placed things or melee blows: no bolt.
const NOT_A_BOLT := ["armor", "shield", "form", "ward", "vow", "veil", "aegis", "trap", "presence", "fist", "flurry",
		"strike", "nova", "aura", "finale", "totem", "wolf", "barrier", "illusory", "focus", "ki_flow", "mirror", "leader",
		"ascendancy", "oath", "summon", "coating", "stance", "apotheosis", "precision", "kick", "blade", "slash"]
const SCHOOL_COLOURS := {
	"fire": Color(1.0, 0.45, 0.1), "cold": Color(0.55, 0.85, 1.0), "lightning": Color(0.85, 0.9, 1.0),
	"poison": Color(0.4, 0.95, 0.3), "disease": Color(0.6, 0.65, 0.25), "magic": Color(0.6, 0.45, 1.0),
	"psychic": Color(1.0, 0.45, 0.85), "spirit": Color(0.3, 0.95, 0.85), "divine": Color(1.0, 0.85, 0.35),
}

var _target: Node3D = null
var _on_arrive: Callable
var _time := 0.0
var _arrow := false
var _colour := Color.WHITE


# Whether a spell aimed at an enemy flies to it as a projectile: harmful ranged spells and archery skills. Melee weapon
# skills, touch spells and taunts don't.
static func flies(spell: Dictionary) -> bool:
	var category := str(spell.get("skill_category", ""))
	var effect := str(spell.get("effect_type", "")) if spell.get("effect_type") is String else ""
	var kind := str(spell.get("spell_type", ""))
	var reach := float(str(spell.get("range", "15m")).to_lower().trim_suffix("m")) if str(spell.get("range", "15m")).to_lower().trim_suffix("m").is_valid_float() else 15.0
	if reach < MIN_RANGE or effect in ["taunt", "buff", "absorb", "heal", "hot"]:
		return false
	var spell_name := str(spell.get("spell_name", ""))
	for word in NOT_A_BOLT:
		if spell_name.contains(word):
			return false
	if category == "archery":
		return true
	if str(spell.get("spell_school", "")) == "physical":
		return false
	return kind in ["detrimental", "targeted_directional", "chain", "channel", "charm"]


# Fires one from `caster` at `target`; `on_arrive` is called when it gets there (not if the target has gone).
static func launch(caster: Node3D, target: Node3D, spell: Dictionary, on_arrive: Callable) -> void:
	var scene := caster.get_tree().current_scene
	if scene == null:
		on_arrive.call()
		return
	var bolt: Node3D = (load("res://Scripts/spell_projectile.gd") as GDScript).new()
	bolt.set("_target", target)
	bolt.set("_on_arrive", on_arrive)
	bolt.set("_arrow", str(spell.get("skill_category", "")) == "archery")
	bolt.set("_colour", SCHOOL_COLOURS.get(str(spell.get("spell_school", "magic")), SCHOOL_COLOURS["magic"]))
	scene.add_child(bolt)
	var forward := -caster.global_transform.basis.z
	bolt.global_position = caster.global_position + Vector3(0, 1.4, 0) + forward * 0.6  # from the caster's hands
	if not bolt.get("_arrow"):
		Sfx.play("spell_launch", caster)  # the whoosh of it leaving; the impact sound plays when it lands


func _ready() -> void:
	if _arrow:
		_build_arrow()
	else:
		_build_orb()


func _process(delta: float) -> void:
	_time += delta
	if not is_instance_valid(_target):
		_fizzle()
		return
	var aim := _target.global_position + Vector3(0, CHEST_HEIGHT, 0)
	var to_target := aim - global_position
	var step := SPEED * delta
	if to_target.length() <= step or _time >= MAX_FLIGHT:
		global_position = aim
		_arrive()
		return
	global_position += to_target.normalized() * step
	if to_target.length() > 0.01:
		look_at(aim, Vector3.UP)


func _arrive() -> void:
	set_process(false)
	if _on_arrive.is_valid():
		_on_arrive.call()
	if not _arrow:
		_flash()
	queue_free()


func _fizzle() -> void:
	set_process(false)
	queue_free()


# A glowing orb in the school's colour, a soft light and a short fading trail.
func _build_orb() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _colour.lightened(0.35)
	mat.emission_enabled = true
	mat.emission = _colour
	mat.emission_energy_multiplier = 3.0
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	orb.mesh = sphere
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = _colour
	light.light_energy = 1.6
	light.omni_range = 4.0
	add_child(light)
	var trail := CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.08
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.3
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 1.0
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(1, 0))
	trail.scale_amount_curve = fade
	var dot := SphereMesh.new()
	dot.radius = 0.07
	dot.height = 0.14
	dot.material = mat
	trail.mesh = dot
	add_child(trail)


# An arrow: a thin wooden shaft with a dark head, pointing where it flies.
func _build_arrow() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.4, 0.25)
	var shaft := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.015
	rod.bottom_radius = 0.015
	rod.height = 0.7
	shaft.mesh = rod
	shaft.material_override = wood
	shaft.rotation_degrees.x = 90.0  # lie along the flight direction (-Z)
	add_child(shaft)
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.035
	cone.height = 0.1
	tip.mesh = cone
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.25, 0.25, 0.27)
	tip.material_override = iron
	tip.rotation_degrees.x = -90.0
	tip.position = Vector3(0, 0, -0.38)
	add_child(tip)


# A quick burst of light where the bolt lands (left in the scene; it frees itself).
func _flash() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var light := OmniLight3D.new()
	light.light_color = _colour
	light.light_energy = 4.0
	light.omni_range = 5.0
	scene.add_child(light)
	light.global_position = global_position
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.3)
	tween.tween_callback(light.queue_free)
