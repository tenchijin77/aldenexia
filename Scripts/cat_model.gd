# cat_model.gd — Builds the static (unrigged) Meshy cat models used by Kenji
# and Oni. Same shape as monster3d.gd's critter setup: the FBX is a bare mesh,
# so the real PBR maps are applied as a runtime material, the 180°-Y facing fix
# every Meshy model here needs is baked into the "Character" node's transform,
# and the model is scaled and then dropped so its lowest point sits exactly on
# its parent's origin (these meshes' pivots float at different heights).
class_name CatModel


# base_path is the FBX path minus ".fbx" — the maps sit next to it as
# <base>.png / _normal.png / _roughness.png / _metallic.png.
static func build(host: Node3D, base_path: String, model_scale: float) -> Node3D:
	var scene := load(base_path + ".fbx") as PackedScene
	if scene == null:
		push_error("❌ Cat model not found: %s.fbx" % base_path)
		return null
	var character: Node3D = scene.instantiate()
	character.name = "Character"
	character.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * model_scale), Vector3.ZERO)
	host.add_child(character)
	_apply_material(character, base_path)
	return character


# The animated version (tools/blender/animate_cat.py: idle, walk, run): the rigged .glb, with the same Meshy maps from
# texture_base (<base>.png ...), facing and scale as build(). Its AnimationPlayer's clips are set to loop.
static func build_animated(host: Node3D, glb_path: String, texture_base: String, model_scale: float) -> Node3D:
	var scene := load(glb_path) as PackedScene
	if scene == null:
		return build(host, texture_base, model_scale)
	var character: Node3D = scene.instantiate()
	character.name = "Character"
	character.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * model_scale), Vector3.ZERO)
	host.add_child(character)
	_apply_material(character, texture_base)
	for ap in character.find_children("*", "AnimationPlayer", true, false):
		for n in (ap as AnimationPlayer).get_animation_list():
			(ap as AnimationPlayer).get_animation(n).loop_mode = Animation.LOOP_LINEAR
	return character


static func animation_player(model: Node) -> AnimationPlayer:
	if model == null:
		return null
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		return ap
	return null


# Idle, walk or run by how fast the cat is really moving (worked out from its position, so it works on every screen,
# not only where its AI runs); the clip plays faster or slower to match the ground it covers.
const WALK_SPEED := 3.5    # m/s the walk clip plays at its own pace: Oni's patrol (cat_speed 35)
const RUN_SPEED := 7.0     # ... and the run: her chase (twice that)
const RUN_FROM := 5.0

static func animate_by_speed(ap: AnimationPlayer, speed: float) -> void:
	if ap == null:
		return
	var want := "idle"
	var rate := 1.0
	if speed > RUN_FROM:
		want = "run"
		rate = clampf(speed / RUN_SPEED, 0.7, 1.6)
	elif speed > 0.25:
		want = "walk"
		rate = clampf(speed / WALK_SPEED, 0.6, 1.8)
	if ap.has_animation(want) and ap.current_animation != want:
		ap.play(want, 0.2)
	ap.speed_scale = rate


static func _apply_material(node: Node, base_path: String) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(base_path + ".png") as Texture2D
	var normal := load(base_path + "_normal.png") as Texture2D
	if normal:
		mat.normal_enabled = true
		mat.normal_texture = normal
	mat.roughness_texture = load(base_path + "_roughness.png") as Texture2D
	var metallic := load(base_path + "_metallic.png") as Texture2D
	if metallic:
		mat.metallic_texture = metallic
		mat.metallic = 1.0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat


# Shifts `character` so its lowest vertex sits on host's origin, and returns the
# model's top height (host-relative) so callers can float a nameplate above it.
# Needs the host to be inside the tree — call after _ready() (deferred is fine).
static func ground_and_measure(host: Node3D, character: Node3D) -> float:
	var lowest := INF
	var highest := -INF
	var to_host := host.global_transform.affine_inverse()
	for mi in character.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var bb: AABB = (to_host * m.global_transform) * m.get_aabb()
		lowest = minf(lowest, bb.position.y)
		highest = maxf(highest, bb.position.y + bb.size.y)
	if lowest == INF:
		return 1.0
	character.position.y -= lowest
	return highest - lowest
