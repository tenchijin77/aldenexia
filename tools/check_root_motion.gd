# check_root_motion.gd — Finds character animations that are NOT "in place": clips where the hips travel across the ground
# over the clip, so the character walks/lunges forward and then snaps back when the clip restarts (that is what a walk downloaded
# from Mixamo without the "In Place" box ticked does). Run it after adding or re-downloading animations:
#
#   godot --headless --path . --script tools/check_root_motion.gd
#
# It scans every *animations.res library under res://models/ and lists each clip whose hips end more than 0.5 m from where they
# started. death / sit / jump are reported separately as INFO (those legitimately end in a different place). A clip that is in
# place shows 0.00. To fix one: re-download it from Mixamo with "In Place" ticked, drop it in the character's folder and
# rebuild that character's animation library (see the model pipeline notes).
extends SceneTree

const THRESHOLD := 0.5
const EXPECTED_TO_MOVE := ["death", "sit", "jump"]


func _init() -> void:
	var libs: Array = []
	_collect("res://models", libs)
	libs.sort()
	var problems := 0
	for path in libs:
		var lib := load(path) as AnimationLibrary
		if lib == null:
			continue
		var bad: Array = []
		var info: Array = []
		for clip in lib.get_animation_list():
			var travel := _travel(lib.get_animation(clip))
			if travel <= THRESHOLD:
				continue
			(info if String(clip) in EXPECTED_TO_MOVE else bad).append("%s %.2f m" % [clip, travel])
		if not bad.is_empty():
			problems += 1
			print("NOT IN PLACE  %s: %s" % [path.trim_prefix("res://models/"), ", ".join(bad)])
		elif not info.is_empty():
			print("ok (info)     %s: %s move by design" % [path.trim_prefix("res://models/"), ", ".join(info)])
	print("\n%d of %d libraries have clips that are not in place." % [problems, libs.size()])
	quit()


func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with("animations.res"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect(dir.path_join(sub), out)


# How far the hips end from where they start, over the clip (largest of x/y/z, in metres).
func _travel(anim: Animation) -> float:
	var worst := 0.0
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D or not String(anim.track_get_path(i)).to_lower().ends_with("hips"):
			continue
		var keys := anim.track_get_key_count(i)
		if keys < 2:
			continue
		var first: Vector3 = anim.track_get_key_value(i, 0)
		var last: Vector3 = anim.track_get_key_value(i, keys - 1)
		worst = maxf(worst, maxf(absf(last.x - first.x), maxf(absf(last.y - first.y), absf(last.z - first.z))))
	return worst
