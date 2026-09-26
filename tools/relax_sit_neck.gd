# relax_sit_neck.gd — the reclining sit (sit_3, the lizardkin female's, retargeted onto everyone by share_sit.gd) bent
# humans' necks back at a right angle (test 44: "female elf with the laying back sitting posture makes the neck look
# broken"): a lizard's neck and head sit differently on its spine. On every model that got it by retargeting, the neck and
# head keep the angle they have to the body when standing (their idle pose, averaged): lying back, they look straight up.
# The lizardkin female's own clip is left alone. Own library and _pack.res; marked "neck_neutral" (runs once).
#   godot --headless --path . --script res://tools/relax_sit_neck.gd
extends SceneTree

const BONES := ["neck", "Neck", "Head"]


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://Scripts/player3d.gd")
	var re := RegEx.new()
	re.compile('"scene":\\s*"(res://models/[^"]+)",\\s*"library":\\s*"(res://models/[^"]+_pack\\.res)"')
	for m in re.search_all(src):
		var pack := m.get_string(2)
		var scene: Node3D = load(m.get_string(1)).instantiate()
		var sk := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for lib_path in [pack, pack.replace("_pack.res", ".res")]:
			if not ResourceLoader.exists(lib_path):
				continue
			var lib := load(lib_path) as AnimationLibrary
			if not lib.has_animation("sit_3") or not lib.has_animation("idle"):
				continue
			var anim := lib.get_animation("sit_3")
			if not anim.has_meta("sit_from") or int(anim.get_meta("neck_neutral", 0)) >= 2:
				continue
			var idle := lib.get_animation("idle")
			var done := []
			for bone in BONES:
				var path := NodePath("Armature/Skeleton3D:" + bone)
				var bi := sk.find_bone(bone)
				if bi < 0:
					continue
				var it := idle.find_track(path, Animation.TYPE_ROTATION_3D)
				# the idle's own angle; a bone the idle never moves stands at its rest pose
				var ref := _average(idle, it) if it >= 0 else sk.get_bone_rest(bi).basis.get_rotation_quaternion()
				var t := anim.find_track(path, Animation.TYPE_ROTATION_3D)
				if t < 0:
					t = anim.add_track(Animation.TYPE_ROTATION_3D)
					anim.track_set_path(t, path)
					anim.rotation_track_insert_key(t, 0.0, ref)
				for k in anim.track_get_key_count(t):
					anim.track_set_key_value(t, k, ref)
				done.append(bone)
			anim.set_meta("neck_neutral", 2)   # 2: the neck too (v1 set only the head: the idle never keys the neck)
			ResourceSaver.save(lib, lib_path, ResourceSaver.FLAG_COMPRESS)
			print("%-38s sit_3 neck/head neutral (%s)" % [lib_path.get_file(), ", ".join(done)])
		scene.free()
	quit()


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
