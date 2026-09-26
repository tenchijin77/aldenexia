# relax_shoulders.gd — calms the shoulder (clavicle) bones in a model's run and walk (test 42, the troll male: "when they
# run [the lats] seem to bunch up on their upper back and it doesn't look right"). Mixamo's run shrugs the clavicles
# 20-40 degrees off rest; on a slim body that's a shoulder roll, but a troll's back is so heavy that the skin weighted to
# them piles up into a hump between the shoulder blades. This keeps only `keep` of each shoulder's movement away from its
# average idle pose (the arms, children of the shoulders, still swing fully). Edits the library in place and marks each
# animation (metadata "shoulders_relaxed") so running it twice changes nothing. Run it on the model's own library AND its
# _pack.res (make_animation_pack.gd copies the own clips as they are, so the fix survives a pack rebuild).
#   godot --headless --path . --script res://tools/relax_shoulders.gd -- "<animations .res>" [keep=0.4] [run,walk]
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var lib_path := args[0]
	var keep := float(args[1]) if args.size() > 1 else 0.4
	var anims: Array = Array(args[2].split(",")) if args.size() > 2 else ["run", "walk"]
	var lib := load(lib_path) as AnimationLibrary
	var idle := lib.get_animation("idle")
	var changed := false
	for anim_name in anims:
		if not lib.has_animation(anim_name):
			continue
		var anim := lib.get_animation(anim_name)
		if anim.has_meta("shoulders_relaxed"):
			print("%s: already relaxed (%s)" % [anim_name, anim.get_meta("shoulders_relaxed")])
			continue
		for bone in ["LeftShoulder", "RightShoulder"]:
			var path := NodePath("Armature/Skeleton3D:" + bone)
			var t := anim.find_track(path, Animation.TYPE_ROTATION_3D)
			var it := idle.find_track(path, Animation.TYPE_ROTATION_3D)
			if t < 0 or it < 0:
				continue
			var ref := _average(idle, it)
			for k in anim.track_get_key_count(t):
				var q: Quaternion = anim.track_get_key_value(t, k)
				anim.track_set_key_value(t, k, ref.slerp(q, keep))
		anim.set_meta("shoulders_relaxed", keep)
		changed = true
		print("%s: shoulders keep %.0f%% of their movement" % [anim_name, keep * 100.0])
	if changed:
		ResourceSaver.save(lib, lib_path, ResourceSaver.FLAG_COMPRESS)
	quit()


# The idle's shoulder pose, averaged over the clip (the quaternions are close together, so a normalised sum will do).
func _average(anim: Animation, t: int) -> Quaternion:
	var first: Quaternion = anim.track_get_key_value(t, 0)
	var sum := Vector4()
	for k in anim.track_get_key_count(t):
		var q: Quaternion = anim.track_get_key_value(t, k)
		if q.dot(first) < 0.0:
			q = -q
		sum += Vector4(q.x, q.y, q.z, q.w)
	sum = sum.normalized()
	return Quaternion(sum.x, sum.y, sum.z, sum.w)
