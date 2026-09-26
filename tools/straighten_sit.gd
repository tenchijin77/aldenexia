# straighten_sit.gd — sits every character up straight (2026-09-26, the user: "the sitting posture should be a person
# sitting indian style; for some reason they look like their upper body is angled backwards at about a 45 degree angle").
# Retargeted onto each body, the sit leaned the torso back 15-50 degrees (the lizardkin female almost lay down). This turns
# the lowest spine bone forward about the body's side axis (the legs stay crossed as they are) until the line from the hips to the
# neck leans no more than it does when that model stands idle. Works on each model's own library and its _pack.res
# (make_animation_pack.gd copies the own clips as they are, so the fix survives a pack rebuild). Marks the animation
# (metadata "sit_straightened") so running it twice changes nothing.
#   godot --headless --path . --script res://tools/straighten_sit.gd            every model in Player3D.CHARACTER_MODELS
#   godot --headless --path . --script res://tools/straighten_sit.gd -- "Ogre Female"   only folders containing that text
extends SceneTree

const SIDE := Vector3(1, 0, 0)   # skeleton space of these imports is Z-up, toes point -Y: X is the body's side axis


func _init() -> void:
	var only := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	var src := FileAccess.get_file_as_string("res://Scripts/player3d.gd")
	var re := RegEx.new()
	re.compile('"scene":\\s*"(res://models/[^"]+)",\\s*"library":\\s*"([^"]+)"')
	for m in re.search_all(src):
		var scene_path := m.get_string(1)
		if only != "" and not scene_path.contains(only):
			continue
		var pack_path := m.get_string(2)
		var libs := [pack_path]
		var own := pack_path.replace("_pack.res", ".res")
		if own != pack_path and ResourceLoader.exists(own):
			libs.append(own)
		for lib_path in libs:
			await _straighten(scene_path, lib_path)
	quit()


func _straighten(scene_path: String, lib_path: String) -> void:
	var lib := load(lib_path) as AnimationLibrary
	if lib == null or not lib.has_animation("sit"):
		return
	var sit := lib.get_animation("sit")
	if sit.has_meta("sit_upright"):
		print("%s: already upright" % lib_path.get_file())
		return
	var scene: Node3D = load(scene_path).instantiate()
	root.add_child(scene)
	await process_frame   # the AnimationPlayer only poses the skeleton inside a running tree
	var sk := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	if ap.has_animation_library(""):
		ap.remove_animation_library("")
	ap.add_animation_library("", lib)
	var hips := sk.find_bone("Hips")
	var neck := sk.find_bone("neck") if sk.find_bone("neck") >= 0 else sk.find_bone("Neck")
	# The back and head from the bottom up. These Meshy rigs number the spine top-down (Hips -> Spine02 -> Spine01 -> Spine
	# -> neck -> Head), so walk it from the bone on the hips. Each bone's segment (bone -> the next one up; the head: Head ->
	# head_end) is turned about the body's side axis until it leans as it does standing idle (test 42 follow-up, the user:
	# "please make sure their heads are upright, not hunched over"). Only the forward/back tilt changes: turns and sways stay.
	var chain: Array[int] = []
	var b := hips
	while true:
		var next := -1
		for c in sk.get_bone_count():
			if sk.get_bone_parent(c) == b and (sk.get_bone_name(c).begins_with("Spine") or c == neck or sk.get_bone_name(c) == "Head"):
				next = c
		if next < 0:
			break
		chain.append(next)
		b = next
	var head_end := sk.find_bone("head_end")
	if hips < 0 or neck < 0 or chain.size() < 3 or head_end < 0:
		print("%s: no hips / spine / neck / head, skipped" % lib_path.get_file())
		scene.queue_free()
		return
	var tips: Array[int] = []   # the far end of each bone's segment
	for n in chain.size():
		tips.append(chain[n + 1] if n + 1 < chain.size() else head_end)
	var before := _lean(ap, sk, "sit", hips, neck)
	var report := []
	for n in chain.size():
		var bone := chain[n]
		var target := _pitch(ap, sk, "idle", bone, tips[n])
		var was := _pitch(ap, sk, "sit", bone, tips[n])
		var path := NodePath("Armature/Skeleton3D:" + sk.get_bone_name(bone))
		var track := sit.find_track(path, Animation.TYPE_ROTATION_3D)
		if track < 0:   # the clip leaves it at rest: give it a key to turn
			track = sit.add_track(Animation.TYPE_ROTATION_3D)
			sit.track_set_path(track, path)
			sit.rotation_track_insert_key(track, 0.0, sk.get_bone_rest(bone).basis.get_rotation_quaternion())
			ap.clear_caches()
		for pass_i in 4:   # a turn about the bone's own head lands a little short of where it's aimed: repeat
			var fix := _pitch(ap, sk, "sit", bone, tips[n]) - target
			if absf(fix) < 0.5:
				break
			var parent := sk.get_bone_parent(bone)
			for k in sit.track_get_key_count(track):
				ap.play("sit")
				sk.reset_bone_poses()
				ap.seek(sit.track_get_key_time(track, k), true)
				var parent_q := sk.get_bone_global_pose(parent).basis.get_rotation_quaternion()
				var q: Quaternion = sit.track_get_key_value(track, k)
				# leaning back puts the segment's end toward +Y; a positive turn about +X brings it forward (measured)
				var turn := Quaternion(SIDE, deg_to_rad(fix))
				sit.track_set_key_value(track, k, (parent_q.inverse() * turn * parent_q * q).normalized())
			ap.clear_caches()
		report.append("%s %+.0f>%+.0f(t%+.0f)" % [sk.get_bone_name(bone), was, _pitch(ap, sk, "sit", bone, tips[n]), target])
	var after := _lean(ap, sk, "sit", hips, neck)
	sit.set_meta("sit_upright", true)
	ResourceSaver.save(lib, lib_path, ResourceSaver.FLAG_COMPRESS)
	print("%-36s lean %+.1f -> %+.1f | %s" % [lib_path.get_file(), before, after, ", ".join(report)])
	scene.queue_free()
	await process_frame


# How far a bone's segment (bone -> tip) leans back from upright (degrees, + = back), averaged over the clip.
func _pitch(ap: AnimationPlayer, sk: Skeleton3D, anim: String, bone: int, tip: int) -> float:
	ap.play(anim)
	var a := ap.get_animation(anim)
	var n := 8
	var sum := 0.0
	for i in n:
		sk.reset_bone_poses()   # else bones this clip doesn't key keep the last clip's pose (the sit's, when measuring idle)
		ap.seek(a.length * float(i) / float(n), true)
		var d := sk.get_bone_global_pose(tip).origin - sk.get_bone_global_pose(bone).origin
		sum += rad_to_deg(atan2(d.y, d.z))
	return sum / float(n)


# How far the hips-to-neck line leans back from upright (degrees, + = back), averaged over the clip.
func _lean(ap: AnimationPlayer, sk: Skeleton3D, anim: String, hips: int, neck: int) -> float:
	ap.play(anim)
	var a := ap.get_animation(anim)
	var n := 8
	var sum := 0.0
	for i in n:
		sk.reset_bone_poses()
		ap.seek(a.length * float(i) / float(n), true)
		var d := sk.get_bone_global_pose(neck).origin - sk.get_bone_global_pose(hips).origin
		sum += rad_to_deg(atan2(d.y, d.z))
	return sum / float(n)
