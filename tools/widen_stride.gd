# widen_stride.gd — fixes a character whose feet cross the centre line when it walks or runs (the elf male, 2026-09-25:
# "pigeon toed ... when he runs it doesn't look right"). His Mixamo run and walk were made for wider hips: on his narrow
# hips each foot landed on or across the middle, knees knocking in. This swings both thighs outward (about the body's
# forward axis) in the chosen animations (default: the run), by the smallest angle that keeps the feet at least MIN_GAP apart in the run.
# Writes the model's animation library in place; marks each fixed animation (metadata "stride_widened") so a second run
# changes nothing. Back up the .res first (git has it).
#   godot --headless --path . --script res://tools/widen_stride.gd -- "<model .fbx>" "<animations .res>" [min_gap] [run,walk]
# (elf male: min_gap 0.06 = the human's run, scaled to his narrower hips; run only -> 3 degrees)
extends SceneTree

var ANIMS := ["run"]   # his walk was fine (feet 0.09 m apart); only the run crossed
const FORWARD := Vector3(0, -1, 0)   # skeleton space of these Mixamo FBX imports is Z-up (the Armature node turns it): toes point -Y


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var fbx := args[0]
	var lib_path := args[1]
	var min_gap := float(args[2]) if args.size() > 2 else 0.06
	if args.size() > 3:
		ANIMS = Array(args[3].split(","))
	var scene: Node3D = load(fbx).instantiate()
	root.add_child(scene)
	await process_frame   # the AnimationPlayer only poses the skeleton once it's in a running tree
	var sk := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var lib := load(lib_path) as AnimationLibrary
	if ap.has_animation_library(""):
		ap.remove_animation_library("")
	ap.add_animation_library("", lib)
	var original := {}
	for anim in ANIMS:
		original[anim] = lib.get_animation(anim).duplicate(true)
	if lib.get_animation("run").has_meta("stride_widened"):
		print("already widened: ", lib.get_animation("run").get_meta("stride_widened"), " degrees")
		quit()
		return
	print("before: run min gap %.3f, walk %.3f" % [_min_gap(ap, sk, "run"), _min_gap(ap, sk, "walk")])
	var angle := 0.0
	for deg in range(1, 16):
		for anim in ANIMS:
			_apply(lib.get_animation(anim), original[anim], ap, sk, deg)
		ap.clear_caches()   # the player keeps its own copy of the tracks
		if _min_gap(ap, sk, "run") >= min_gap:
			angle = deg
			break
	if angle == 0.0:
		angle = 15.0
	for anim in ANIMS:
		lib.get_animation(anim).set_meta("stride_widened", angle)
	print("widened %d degrees: run min gap %.3f, walk %.3f" % [angle, _min_gap(ap, sk, "run"), _min_gap(ap, sk, "walk")])
	ResourceSaver.save(lib, lib_path)
	quit()


# Rebuilds `anim`'s thigh rotation keys from `src`, each thigh turned `deg` outward about the forward axis (in the hips'
# own frame at that moment, so it follows the hips' sway).
func _apply(anim: Animation, src: Animation, ap: AnimationPlayer, sk: Skeleton3D, deg: float) -> void:
	for side in ["Left", "Right"]:
		var path := NodePath("Armature/Skeleton3D:%sUpLeg" % side)
		var t := src.find_track(path, Animation.TYPE_ROTATION_3D)
		var dst := anim.find_track(path, Animation.TYPE_ROTATION_3D)
		if t < 0 or dst < 0:
			continue
		var outward := 1.0 if sk.get_bone_global_rest(sk.find_bone(side + "UpLeg")).origin.x > 0.0 else -1.0
		for k in src.track_get_key_count(t):
			var time := src.track_get_key_time(t, k)
			var q: Quaternion = src.track_get_key_value(t, k)
			# the hips' orientation at this moment (from the unmodified source)
			var hips_q := _hips_rotation(src, time, sk)
			var axis := (hips_q.inverse() * FORWARD).normalized()   # forward, in the hips' frame
			# a positive turn about forward swings a +X thigh further out (measured: the other sign crossed his feet more)
			var turn := Quaternion(axis, deg_to_rad(deg) * outward)
			anim.track_set_key_value(dst, k, turn * q)


func _hips_rotation(src: Animation, time: float, sk: Skeleton3D) -> Quaternion:
	var t := src.find_track(NodePath("Armature/Skeleton3D:Hips"), Animation.TYPE_ROTATION_3D)
	var local: Quaternion = src.rotation_track_interpolate(t, time) if t >= 0 else sk.get_bone_rest(sk.find_bone("Hips")).basis.get_rotation_quaternion()
	var parent := sk.get_bone_parent(sk.find_bone("Hips"))
	var parent_q := sk.get_bone_global_rest(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	return parent_q * local


func _min_gap(ap: AnimationPlayer, sk: Skeleton3D, anim: String) -> float:
	ap.stop()
	ap.play(anim)
	var a := ap.get_animation(anim)
	var gap := INF
	for i in 60:
		ap.seek(a.length * i / 60.0, true)
		var l := sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin.x
		var r := sk.get_bone_global_pose(sk.find_bone("RightFoot")).origin.x
		gap = minf(gap, l - r)
	return gap
