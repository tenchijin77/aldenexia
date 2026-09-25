# make_animation_pack.gd — one pool of animations for every race model (2026-09-25). Each race came with its own
# handful of clips; between them there are many more casting, buff and death animations. This retargets every one onto
# every race's skeleton and writes each model's pack: its own library, untouched, plus the others as VARIANTS
# ("cast_beneficial_2", "cast_detrimental_5", "death_3"...), which the game picks between at random.
#
# Retargeting: all the Meshy skeletons share bone names but not proportions or rest poses, so a clip can't simply be
# copied. For each bone, the source's turn away from ITS T-pose (in world space) is applied to the target's T-pose, then
# made local to the target's parent bone; the hips' movement is scaled by the two hips' heights. Bones the source lacks
# stay at rest. Clips are sampled at 30 frames a second.
# The ARMS are aimed instead: the models' "T-poses" differ (an ogre's and a dwarf's arms rest 30-37 degrees lower than an
# elf's), and copying the turn kept that offset (hands raised in a cast came out low). So each arm bone is turned so it
# points where the source's does, keeping the source's twist. Spine, legs and head differ by a few degrees: turned as is.
#
#   godot --headless --path . --script res://tools/make_animation_pack.gd
# Writes <library>_pack.res next to each model's library (the game's CHARACTER_MODELS "library" points at the pack).
# Re-run after adding animation files to a model folder (or the shared folder, Assets/animations/, when it exists).
extends SceneTree

const FPS := 30.0
const SKEL_PATH := "Armature/Skeleton3D"
# bone -> the child it points at: these are aimed at the source's direction
const AIMED := {"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
		"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand"}
# which kind of clip a file is, by its name (the first match wins); anything else is skipped
const KINDS := [["-buff", "cast_beneficial"], ["magic attack", "cast_detrimental"], ["spell casting", "cast_detrimental"],
		["cast spell", "cast_detrimental"], ["spell cast", "cast_detrimental"], ["death", "death"]]


func _init() -> void:
	await process_frame   # nodes read their world orientation only inside a running tree
	var models := _models()
	var sources := _sources(models)
	await process_frame
	sources = _unique(sources)
	print("sources: %d clips (%s)" % [sources.size(), ", ".join(sources.map(func(s): return "%s<-%s" % [s["kind"], s["label"]]))])
	for m in models:
		var target: Node = load(m["scene"]).instantiate()
		var tsk := target.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		root.add_child(target)
		await process_frame
		var lib := (load(m["library"]) as AnimationLibrary).duplicate(true) as AnimationLibrary
		var counts := {}
		var have := []   # fingerprints of what this model already has (its own clips, then each variant added)
		for kind in ["cast_beneficial", "cast_detrimental", "death"]:
			counts[kind] = 1 if lib.has_animation(kind) else 0
			if lib.has_animation(kind):
				have.append(signature(lib.get_animation(kind), tsk))
		for other in lib.get_animation_list():
			if not str(other) in ["cast_beneficial", "cast_detrimental", "death"]:
				have.append(signature(lib.get_animation(other), tsk))   # its attacks too: a cast that is really an attack
		var skipped := 0
		for s in sources:
			var anim := retarget(s["anim"], s["skeleton"], tsk)
			var sig := signature(anim, tsk)
			if have.any(func(h): return same_motion(sig, h)):
				skipped += 1
				continue   # the same motion as one it has (its own clip, or an earlier variant)
			have.append(sig)
			var kind: String = s["kind"]
			counts[kind] += 1
			var name: String = kind if counts[kind] == 1 else "%s_%d" % [kind, counts[kind]]
			anim.set_meta("source", s["label"])
			lib.add_animation(name, anim)
		var out: String = pack_path(m["library"])
		var err := ResourceSaver.save(lib, out, ResourceSaver.FLAG_COMPRESS)
		print("%s: %s (%d clips: %s; %d repeats left out)%s" % [m["folder"], out, lib.get_animation_list().size(), str(counts), skipped, "" if err == OK else " SAVE FAILED"])
		target.free()
	quit()


static func pack_path(library: String) -> String:
	return library.get_basename() + "_pack.res"


# The race models: CHARACTER_MODELS' scene / library pairs, read from player3d.gd (--script mode has no autoloads).
func _models() -> Array:
	var text := FileAccess.get_file_as_string("res://Scripts/player3d.gd")
	var re := RegEx.new()
	re.compile('"scene":\\s*"(res://models/([^/"]+)/[^"]+Breathing Idle\\.fbx)",\\s*\\n\\s*"library":\\s*"(res://[^"]+?)(?:_pack)?\\.res"')
	var out := []
	for r in re.search_all(text):
		out.append({"scene": r.get_string(1), "folder": r.get_string(2), "library": r.get_string(3) + ".res"})
	return out


# Every animation file in the race models' folders that is a kind we pool, loaded once; the same clip in several
# folders (one Mixamo animation given to five races) is taken once.
func _sources(models: Array) -> Array:
	var out := []
	var seen := {}
	for m in models:
		var dir: String = m["scene"].get_base_dir()
		for f in DirAccess.get_files_at(dir):
			if not f.to_lower().ends_with(".fbx") or f.contains("Breathing Idle") or f.begins_with("Meshy_AI"):
				continue
			var label: String = f.get_basename().trim_prefix(m["folder"] + " ")
			var kind := ""
			for k in KINDS:
				if label.to_lower().contains(k[0]):
					kind = k[1]
					break
			if kind.is_empty() or seen.has(label):
				continue
			var scene: Node = load(dir.path_join(f)).instantiate()
			var ap := scene.find_children("*", "AnimationPlayer", true, false)
			var sk := scene.find_children("*", "Skeleton3D", true, false)
			if ap.is_empty() or sk.is_empty():
				scene.free()
				continue
			var anim_name := ""
			for a in (ap[0] as AnimationPlayer).get_animation_list():
				if not str(a).contains("baselayer"):
					anim_name = a
			if anim_name.is_empty():
				scene.free()
				continue
			root.add_child(scene)
			seen[label] = true
			out.append({"label": label, "kind": kind, "folder": m["folder"], "anim": (ap[0] as AnimationPlayer).get_animation(anim_name),
					"skeleton": sk[0], "scene": scene})
	return out


# Drops sources that repeat an earlier one's motion (fingerprints; needs the scenes in the tree).
func _unique(sources: Array) -> Array:
	var kept := []
	for s in sources:
		s["sig"] = signature(s["anim"], s["skeleton"])
		var dup: Variant = null
		for k in kept:
			if same_motion(s["sig"], k["sig"]):
				dup = k
				break
		if dup != null:
			print("  repeat: %s (%s) = %s (%s)" % [s["label"], s["folder"], dup["label"], dup["folder"]])
			continue
		kept.append(s)
	return kept


# ── Repeats: a motion fingerprint ──
# Which way the arms point (world space) at nine moments. The same motion reached under two names (a "-buff" copy of
# an attack, one Mixamo clip given to five races) or a race's own clip coming back as a "variant" is found by comparing
# fingerprints, not file names.
const SIG_BONES := [["LeftArm", "LeftForeArm"], ["LeftForeArm", "LeftHand"], ["RightArm", "RightForeArm"], ["RightForeArm", "RightHand"]]


static func signature(anim: Animation, sk: Skeleton3D) -> Dictionary:
	var track := {}
	for i in anim.get_track_count():
		var path := str(anim.track_get_path(i))
		if path.contains(":") and anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			track[path.get_slice(":", 1)] = i
	var world := sk.global_transform.basis
	var dirs := []
	for k in 9:
		var t := anim.length * (k + 0.5) / 9.0
		var g := {}
		for i in sk.get_bone_count():
			var bone := sk.get_bone_name(i)
			var local: Quaternion = anim.rotation_track_interpolate(track[bone], t) if track.has(bone) else sk.get_bone_rest(i).basis.get_rotation_quaternion()
			var p := sk.get_bone_parent(i)
			g[bone] = (g[sk.get_bone_name(p)] if p >= 0 else Transform3D.IDENTITY) * Transform3D(Basis(local), sk.get_bone_rest(i).origin)
		for pr in SIG_BONES:
			if g.has(pr[0]) and g.has(pr[1]):
				dirs.append((world * ((g[pr[1]] as Transform3D).origin - (g[pr[0]] as Transform3D).origin)).normalized())
	return {"length": anim.length, "dirs": dirs}


# The same motion: lengths within 8% and the arms within 12 degrees on average.
static func same_motion(a: Dictionary, b: Dictionary) -> bool:
	if absf(float(a["length"]) - float(b["length"])) > 0.08 * maxf(float(a["length"]), float(b["length"])):
		return false
	var da: Array = a["dirs"]
	var db: Array = b["dirs"]
	if da.size() != db.size() or da.is_empty():
		return false
	var total := 0.0
	for i in da.size():
		total += rad_to_deg((da[i] as Vector3).angle_to(db[i]))
	return total / da.size() < 12.0


# The retarget itself (see the header). Returns a new Animation for `tsk`.
static func retarget(src: Animation, ssk: Skeleton3D, tsk: Skeleton3D) -> Animation:
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode
	var s_world := ssk.global_transform.basis.get_rotation_quaternion()
	var t_world := tsk.global_transform.basis.get_rotation_quaternion()
	var s_track := {}   # bone name -> rotation track in the source
	var s_pos := -1
	for i in src.get_track_count():
		var path := str(src.track_get_path(i))
		if not path.contains(":"):
			continue
		var bone := path.get_slice(":", 1)
		if src.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			s_track[bone] = i
		elif src.track_get_type(i) == Animation.TYPE_POSITION_3D and bone == ssk.get_bone_name(0):
			s_pos = i
	var s_rest_g := []
	for i in ssk.get_bone_count():
		s_rest_g.append(ssk.get_bone_global_rest(i).basis.get_rotation_quaternion())
	var t_rest_g := []
	for j in tsk.get_bone_count():
		t_rest_g.append(tsk.get_bone_global_rest(j).basis.get_rotation_quaternion())
	# the hips' movement, scaled by height (skeleton "up" = the world's up seen from inside the skeleton)
	var s_up := (ssk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var t_up := (tsk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var s_hips_rest := ssk.get_bone_rest(0).origin
	var t_hips_rest := tsk.get_bone_rest(0).origin
	var ratio := maxf(0.1, t_hips_rest.dot(t_up)) / maxf(0.1, s_hips_rest.dot(s_up))
	var tracks := {}
	for j in tsk.get_bone_count():
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath("%s:%s" % [SKEL_PATH, tsk.get_bone_name(j)]))
		tracks[j] = tr
	var pos_track := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pos_track, NodePath("%s:%s" % [SKEL_PATH, tsk.get_bone_name(0)]))
	var frames := maxi(1, int(ceil(src.length * FPS)))
	for f in frames + 1:
		var t := minf(f / FPS, src.length)
		# the source's pose: local rotations (rest where a bone has no track), then global
		var s_g := {}
		var s_gt := {}   # full global transforms (for bone directions)
		for i in ssk.get_bone_count():
			var bone := ssk.get_bone_name(i)
			var local: Quaternion = src.rotation_track_interpolate(s_track[bone], t) if s_track.has(bone) else ssk.get_bone_rest(i).basis.get_rotation_quaternion()
			var p := ssk.get_bone_parent(i)
			s_g[bone] = (s_g[ssk.get_bone_name(p)] if p >= 0 else Quaternion.IDENTITY) * local
			var lt := Transform3D(Basis(local), ssk.get_bone_rest(i).origin)
			s_gt[bone] = (s_gt[ssk.get_bone_name(p)] if p >= 0 else Transform3D.IDENTITY) * lt
		# the target's: each bone turned from its rest by the source bone's turn from ITS rest (in world space)
		var t_g := {}
		for j in tsk.get_bone_count():
			var bone := tsk.get_bone_name(j)
			var p := tsk.get_bone_parent(j)
			var parent_g: Quaternion = t_g[p] if p >= 0 else Quaternion.IDENTITY
			var g: Quaternion
			var si := ssk.find_bone(bone)
			if si >= 0:
				var delta_world: Quaternion = s_world * (s_g[bone] * (s_rest_g[si] as Quaternion).inverse()) * s_world.inverse()
				g = t_world.inverse() * delta_world * t_world * (t_rest_g[j] as Quaternion)
				if AIMED.has(bone) and ssk.find_bone(AIMED[bone]) >= 0 and tsk.find_bone(AIMED[bone]) >= 0:
					# where the source bone points, in world space, and where ours points after the turn: swing ours onto it
					var child: String = AIMED[bone]
					var want := s_world * ((s_gt[child] as Transform3D).origin - (s_gt[bone] as Transform3D).origin).normalized()
					var child_local := tsk.get_bone_rest(tsk.find_bone(child)).origin
					var have := t_world * (g * child_local).normalized()
					if want.length() > 0.5 and have.length() > 0.5:
						var swing := Quaternion(have.normalized(), want.normalized())
						g = t_world.inverse() * swing * t_world * g
			else:
				g = parent_g * tsk.get_bone_rest(j).basis.get_rotation_quaternion()
			t_g[j] = g
			out.rotation_track_insert_key(tracks[j], t, (parent_g.inverse() * g).normalized())
		var s_hips: Vector3 = src.position_track_interpolate(s_pos, t) if s_pos >= 0 else s_hips_rest
		var move_world := ssk.global_transform.basis * (s_hips - s_hips_rest)
		out.position_track_insert_key(pos_track, t, t_hips_rest + tsk.global_transform.basis.inverse() * move_world * ratio)
	return out
