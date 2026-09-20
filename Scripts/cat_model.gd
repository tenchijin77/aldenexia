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
