# tail_rig.gd — a tail that moves (2026-09-26, the user: "can you please animate the lizardkins' tails in their
# animations?"). A model with a <scene>_tail_mesh.res (made by tools/make_tail.gd) gets its tail bones added to the
# skeleton and that mesh and skin swapped in; then this node, a child of the model, swings the tail every frame on top of
# whatever animation is playing, so every animation (the packs have no tail tracks) gets a live tail:
#   still     a slow, lazy sway
#   walking   a steady swing from side to side, the tip following behind (a wave down the chain)
#   running   a quicker, wider swing
# and it keeps the tail off the floor: whenever the tip would sink into the ground (sitting, lying dead) the root lifts
# until it rests along it. Movement is measured from the model's own position, so it works on every screen.
class_name TailRig
extends Node

const FLOOR := 0.06            # the tip stays at least this high (skeleton space: 0 = the feet)
const LIFT_SPEED := 90.0       # degrees a second the root lifts / settles to keep the tip off the floor
const MAX_LIFT := 80.0

var _sk: Skeleton3D
var _bones: Array[int] = []
var _rests: Array[Quaternion] = []
var _model: Node3D
var _time := 0.0
var _speed := 0.0
var _last := Vector3.INF
var _lift := 0.0
var _up := Vector3(0, 0, 1)     # the body's up and side axes in the tail bones' frame (the hips' rest frame)
var _side := Vector3(1, 0, 0)


# Adds the tail to a freshly built character model if it has one. True if it did.
static func attach(model: Node3D) -> bool:
	if model == null or model.scene_file_path.is_empty() or DisplayServer.get_name() == "headless":
		return false   # nothing is drawn there
	var path := MeshSmoothing.rebuilt_mesh_path(model.scene_file_path).replace("_smooth_mesh.res", "_tail_mesh.res")
	if not ResourceLoader.exists(path):
		return false
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if meshes.size() != 1 or skels.is_empty():
		return false
	var mesh: ArrayMesh = load(path)
	var sk := skels[0] as Skeleton3D
	var rig := TailRig.new()
	rig.name = "TailRig"
	rig._sk = sk
	rig._model = model
	var hips_basis := sk.get_bone_global_rest(sk.find_bone("Hips")).basis.orthonormalized()
	rig._up = (hips_basis.inverse() * Vector3(0, 0, 1)).normalized()     # skeleton space is Z-up, the back is +Y
	rig._side = (hips_basis.inverse() * Vector3(1, 0, 0)).normalized()
	for row in mesh.get_meta("tail_bones", []):
		var idx := sk.find_bone(str(row[0]))
		if idx < 0:
			idx = sk.get_bone_count()
			sk.add_bone(str(row[0]))
			sk.set_bone_parent(idx, sk.find_bone(str(row[1])))
			sk.set_bone_rest(idx, row[2])
			sk.reset_bone_pose(idx)
		rig._bones.append(idx)
		rig._rests.append((row[2] as Transform3D).basis.get_rotation_quaternion())
	var mi := meshes[0] as MeshInstance3D
	mi.skin = mesh.get_meta("tail_skin")
	mi.mesh = mesh
	model.add_child(rig)
	return true


func _process(delta: float) -> void:
	if not is_instance_valid(_sk) or _bones.is_empty() or delta <= 0.0:
		return
	var p := _model.global_position
	var step := 0.0 if _last == Vector3.INF else Vector2(p.x - _last.x, p.z - _last.z).length() / delta
	_last = p
	_speed = lerpf(_speed, minf(step, 10.0), clampf(delta * 6.0, 0.0, 1.0))
	var run := clampf((_speed - 1.0) / 5.0, 0.0, 1.0)     # 0 still .. 1 at a run
	var amp := lerpf(7.0, 16.0, run)                        # degrees a bone
	var freq := lerpf(0.35, 1.6, run)                       # swings a second
	_time += delta * freq
	for k in _bones.size():
		var sway := deg_to_rad(amp * sin(TAU * _time - float(k) * 0.7))   # a wave travelling down to the tip
		var q := Quaternion(_up, sway)
		if k == 0 and _lift != 0.0:
			q = Quaternion(_side, deg_to_rad(_lift)) * q   # a turn about the side axis swings the back-pointing tail up
		_sk.set_bone_pose_rotation(_bones[k], _rests[k] * q)
	# keep the tip out of the floor
	var tip_z := _sk.get_bone_global_pose(_bones[_bones.size() - 1]).origin.z
	if tip_z < FLOOR:
		_lift = minf(_lift + LIFT_SPEED * delta, MAX_LIFT)
	elif tip_z > FLOOR + 0.15:
		_lift = maxf(_lift - LIFT_SPEED * 0.5 * delta, 0.0)
