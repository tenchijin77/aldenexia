# travel_portal.gd — what a travel spell looks like while it is being cast (player_travel.gd). Stand-in visuals, built in code:
#   bridge    a translucent glowing walkway from 3 m behind the Arcanist, 12 m long, with a ring of runes at their feet and an
#             arch at the far end. A group member who reaches the arch crosses to the destination.
#   rift      a jagged, flickering violet tear 3 m behind the Chaosborn. A group member who steps into it goes through.
#   tunnel    green spirit-vines rising in a ring around the Wildspeaker (the pull happens when the cast ends).
#   redoubt   a slowly folding blue sphere around the Arcanist.   wormhole   a churning earthy ring on the ground.
# One of these exists on every machine; only the local player is ever sent through (their own machine moves them).
extends Node3D
class_name TravelPortal

const BRIDGE_LENGTH := 12.0
const ENTER_RANGE := 1.8

var kind := ""
var dest := Vector2.ZERO
var dest_name := ""
var caster: Node = null
var _life := 0.0
var _time := 0.0
var _entry := Vector3.ZERO
var _parts: Array = []
var _sent := false
var _closing := false


func setup(p_kind: String, origin: Vector3, back: Vector3, p_dest: Vector2, p_dest_name: String, seconds: float, p_caster: Node) -> void:
	kind = p_kind
	dest = p_dest
	dest_name = p_dest_name
	caster = p_caster
	_life = seconds
	position = origin
	match kind:
		"bridge":
			_entry = origin + back * (3.0 + BRIDGE_LENGTH)
			var deck := _mesh(_box(Vector3(2.2, 0.08, BRIDGE_LENGTH)), Color(0.5, 0.8, 1.0, 0.45), 1.6)
			deck.position = back * (3.0 + BRIDGE_LENGTH / 2.0) + Vector3(0, 0.1, 0)
			deck.look_at_from_position(deck.position, deck.position + back, Vector3.UP)
			var runes := _mesh(_torus(0.9, 1.15), Color(0.6, 0.85, 1.0, 0.8), 2.5)
			runes.position.y = 0.05
			var arch := _mesh(_torus(1.2, 1.4), Color(0.6, 0.9, 1.0, 0.7), 2.5)
			arch.position = back * (3.0 + BRIDGE_LENGTH) + Vector3(0, 1.4, 0)
			arch.look_at_from_position(arch.position, arch.position + Vector3.UP, back)
		"rift":
			_entry = origin + back * 3.0
			var tear := _mesh(_box(Vector3(1.4, 2.6, 0.05)), Color(0.55, 0.2, 0.85, 0.75), 3.0)
			tear.position = back * 3.0 + Vector3(0, 1.4, 0)
			tear.look_at_from_position(tear.position, tear.position + back, Vector3.UP)
		"tunnel":
			for i in 8:
				var vine := _mesh(_cylinder(0.12, 0.2, 3.0), Color(0.25, 0.6, 0.2, 1.0), 0.6)
				vine.position = Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0) * 3.0
				vine.scale = Vector3(1, 0.01, 1)
		"redoubt":
			var sphere := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 4.0
			s.height = 8.0
			sphere.mesh = s
			sphere.material_override = _material(Color(0.5, 0.7, 1.0, 0.18), 1.0)
			add_child(sphere)
			_parts.append(sphere)
		"wormhole":
			var ring := _mesh(_torus(1.5, 3.2), Color(0.45, 0.35, 0.15, 0.85), 0.5)
			ring.position.y = 0.05


func _process(delta: float) -> void:
	_time += delta
	_life -= delta
	if _life <= 0.0 and not _closing:
		close()
		return
	match kind:
		"bridge":
			if _parts.size() > 1:
				_parts[1].rotate_y(delta * 1.5)
		"rift":
			if not _parts.is_empty():  # the "glitch": jittery size and brightness
				_parts[0].scale = Vector3(randf_range(0.85, 1.15), randf_range(0.9, 1.1), 1.0)
				_parts[0].material_override.emission_energy_multiplier = randf_range(1.5, 4.0)
		"tunnel":
			for p in _parts:
				p.scale.y = minf(1.0, _time / 1.5)
				p.position.y = 1.5 * p.scale.y
		"redoubt":
			_parts[0].scale = Vector3.ONE * (1.0 + 0.08 * sin(_time * 2.0))
		"wormhole":
			_parts[0].rotate_y(delta * 3.0)
	if kind in ["bridge", "rift"] and not _sent:
		_check_enter()


# A group member (not the caster, who is pulled through at the end) walking into the arch / the tear goes through.
func _check_enter() -> void:
	var me := TargetFrame.local_player()
	if me == null or me == caster or not is_instance_valid(caster):
		return
	if not (caster.get_multiplayer_authority() in me.group_members):
		return
	var flat := Vector2(me.global_position.x - _entry.x, me.global_position.z - _entry.z)
	if flat.length() <= ENTER_RANGE:
		_sent = true
		me.get_node("Travel").arrive(kind, dest, {"name": dest_name}, str(caster.get("player_name")))


func close() -> void:
	_closing = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.35)
	tween.tween_callback(queue_free)


func _mesh(mesh: Mesh, colour: Color, glow: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(colour, glow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_parts.append(mi)
	return mi


func _material(colour: Color, glow: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if colour.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(colour.r, colour.g, colour.b)
	mat.emission_energy_multiplier = glow
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t


func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	return c
