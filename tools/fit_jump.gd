# fit_jump.gd — fits every character's jump clip to the jump the game actually makes (test 44: "when you jump, it seems
# to lose forward momentum, and makes the player almost stop in place and start moving upwards"). The Mixamo jumps run
# 1.0-3.2 s with a crouching wind-up first, and lift the hips 0.4-1 m themselves; the game's jump (Player3D.JUMP_VELOCITY,
# default gravity) is ~1.2 s in the air. So through most of a real jump the model was still crouching for take-off, and
# it landed before the clip ever left the ground. This keeps only the airborne part of each clip (from the hips rising
# through standing height to their coming back down), stretches or squeezes it to the real airtime, and takes out the
# clip's own rise (the physics carries the body). Legs still tuck and arms still swing. Own library and _pack.res; marked
# "jump_fitted" (runs once).
#   godot --headless --path . --script res://tools/fit_jump.gd
extends SceneTree

const FPS := 30.0


func _init() -> void:
	var airtime := 2.0 * 6.0 / float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))   # JUMP_VELOCITY 6
	var src := FileAccess.get_file_as_string("res://Scripts/player3d.gd")
	var re := RegEx.new()
	re.compile('"library":\\s*"(res://models/[^"]+_pack\\.res)"')
	for m in re.search_all(src):
		var pack := m.get_string(1)
		for lib_path in [pack, pack.replace("_pack.res", ".res")]:
			if not ResourceLoader.exists(lib_path):
				continue
			var lib := load(lib_path) as AnimationLibrary
			if not lib.has_animation("jump") or lib.get_animation("jump").has_meta("jump_fitted"):
				continue
			var fitted := fit(lib.get_animation("jump"), airtime)
			if fitted == null:
				print("%s: couldn't find the airborne part, left as it was" % lib_path.get_file())
				continue
			lib.remove_animation("jump")
			lib.add_animation("jump", fitted)
			ResourceSaver.save(lib, lib_path, ResourceSaver.FLAG_COMPRESS)
			print("%-38s jump %.2f s of air (from %.2f-%.2f s of a %.2f s clip)" % [lib_path.get_file(), fitted.length,
					fitted.get_meta("jump_fitted")[0], fitted.get_meta("jump_fitted")[1], fitted.get_meta("jump_fitted")[2]])
	quit()


static func fit(src: Animation, airtime: float) -> Animation:
	var hips := src.find_track(NodePath("Armature/Skeleton3D:Hips"), Animation.TYPE_POSITION_3D)
	if hips < 0:
		return null
	# the hips' height through the clip (skeleton space is Z-up)
	var n := int(src.length * FPS)
	var z0: float = (src.position_track_interpolate(hips, 0.0) as Vector3).z
	var peak_t := 0.0
	var peak := -INF
	for i in n + 1:
		var t := src.length * i / float(n)
		var z: float = (src.position_track_interpolate(hips, t) as Vector3).z
		if z > peak:
			peak = z
			peak_t = t
	if peak - z0 < 0.05:
		return null
	# take-off: the last moment before the peak the hips were at standing height; landing: the first after it
	var t0 := 0.0
	var t1 := src.length
	for i in n + 1:
		var t := src.length * i / float(n)
		var z: float = (src.position_track_interpolate(hips, t) as Vector3).z
		if t < peak_t and z <= z0:
			t0 = t
		if t > peak_t and z <= z0 and t1 == src.length:
			t1 = t
	if t1 - t0 < 0.1:
		return null
	var out := Animation.new()
	out.length = airtime
	out.loop_mode = Animation.LOOP_NONE
	var frames := int(ceil(airtime * FPS))
	for tr in src.get_track_count():
		var type := src.track_get_type(tr)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var d := out.add_track(type)
		out.track_set_path(d, src.track_get_path(tr))
		for f in frames + 1:
			var nt := minf(airtime * f / float(frames), airtime)
			var st := t0 + (t1 - t0) * nt / airtime
			match type:
				Animation.TYPE_POSITION_3D:
					var p: Vector3 = src.position_track_interpolate(tr, st)
					if tr == hips:
						p.z = z0   # the physics lifts the body; the clip only moves the limbs
					out.position_track_insert_key(d, nt, p)
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(d, nt, src.rotation_track_interpolate(tr, st))
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(d, nt, src.scale_track_interpolate(tr, st))
	out.set_meta("jump_fitted", [snappedf(t0, 0.01), snappedf(t1, 0.01), snappedf(src.length, 0.01)])
	return out
