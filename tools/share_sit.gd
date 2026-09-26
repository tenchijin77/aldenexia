# share_sit.gd — three ways to sit, for every character (2026-09-26; the user: "i'd like all three of those sitting models
# in game, and randomly pick one when you sit"). The models came with three kinds of sit between them:
#   sit    cross-legged (the human male's 10.9 s idle; the human, elf and dark elf females' own one-frame poses)
#   sit_2  legs out in front, leaning back on the hands (a one-frame pose most models had)
#   sit_3  reclining (the lizardkin female's)
# Each model keeps its own original where it has that kind; the others are retargeted onto it from the source below
# (make_animation_pack.gd's retarget(): each bone's turn from its T-pose, the hips' height scaled). Player3D picks one of
# sit / sit_2 / sit_3 at random each time you sit (pick_variant). Each clip is marked "sit_kind" (and "sit_from" when
# retargeted), in the model's own library and its _pack.res, so running it again changes nothing. Afterwards run
# tools/straighten_sit.gd, which sits the cross-legged one upright (it leaned back in game); the other two stay as made.
#   godot --headless --path . --script res://tools/share_sit.gd
extends SceneTree

const PACK := preload("res://tools/make_animation_pack.gd")
const KINDS := ["cross", "legs_out", "recline"]
const SLOT := {"cross": "sit", "legs_out": "sit_2", "recline": "sit_3"}
# where each kind comes from: [model key, its scene, its own library]
const SOURCES := {
	"cross": ["human_male", "res://models/Human Male/Human Male Breathing Idle.fbx", "res://models/Human Male/human_male_animations.res"],
	"legs_out": ["half_orc_female", "res://models/Half-Orc Female/Half-Orc Female Breathing Idle.fbx", "res://models/Half-Orc Female/half_orc_female_animations.res"],
	"recline": ["lizardkin_female", "res://models/Lizardkin Female/Lizardkin Female Breathing Idle.fbx", "res://models/Lizardkin Female/lizardkin_female_animations.res"],
}
# what each model's ORIGINAL "sit" is (anything not listed: a one-frame clip is legs out, a long one cross-legged)
const OWN_KIND := {"human_female": "cross", "elf_female": "cross", "dark_elf_female": "cross", "lizardkin_female": "recline",
		"half_elf_female": ""}   # "" = its own came out wrong (legs to the side): replaced


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://Scripts/player3d.gd")
	var re := RegEx.new()
	re.compile('"([a-z_]+)": \\{[^}]*?"scene":\\s*"(res://models/[^"]+)",\\s*"library":\\s*"([^"]+)"')   # comments may come first
	var models := re.search_all(src)
	# 1. every model's own library: label its original sit with its kind (and move it to that kind's slot)
	for m in models:
		var key := m.get_string(1)
		for lib_path in _libs(m.get_string(3)):
			var lib := load(lib_path) as AnimationLibrary
			if lib == null or not lib.has_animation("sit") or lib.get_animation("sit").has_meta("sit_kind"):
				continue
			var own := lib.get_animation("sit")
			var kind: String = OWN_KIND.get(key, "legs_out" if own.length < 1.0 else "cross")
			if kind == "":
				lib.remove_animation("sit")
			else:
				own.set_meta("sit_kind", kind)
				if SLOT[kind] != "sit":
					lib.remove_animation("sit")
					lib.add_animation(SLOT[kind], own)
			ResourceSaver.save(lib, lib_path, ResourceSaver.FLAG_COMPRESS)
	# 2. the source clips (the originals, now labelled)
	var sources := {}
	for kind in KINDS:
		var s: Array = SOURCES[kind]
		var scene: Node3D = load(s[1]).instantiate()
		root.add_child(scene)
		await process_frame   # nodes read their world orientation only inside a running tree
		var lib := load(s[2]) as AnimationLibrary
		sources[kind] = {"anim": lib.get_animation(SLOT[kind]), "skeleton": scene.find_children("*", "Skeleton3D", true, false)[0],
				"from": s[0]}
	# 3. fill every model's missing slots by retargeting
	for m in models:
		var target: Node3D = null
		for lib_path in _libs(m.get_string(3)):
			var lib := load(lib_path) as AnimationLibrary
			if lib == null:
				continue
			var added := []
			for kind in KINDS:
				if lib.has_animation(SLOT[kind]):
					continue
				if target == null:
					target = load(m.get_string(2)).instantiate()
					root.add_child(target)
					await process_frame
				var tsk := target.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
				var from: Dictionary = sources[kind]
				var anim: Animation = PACK.retarget(from["anim"], from["skeleton"], tsk)
				anim.loop_mode = (from["anim"] as Animation).loop_mode
				anim.set_meta("sit_kind", kind)
				anim.set_meta("sit_from", from["from"])
				lib.add_animation(SLOT[kind], anim)
				added.append("%s<-%s" % [SLOT[kind], from["from"]])
			if not added.is_empty():
				ResourceSaver.save(lib, lib_path, ResourceSaver.FLAG_COMPRESS)
			print("%-38s %s" % [lib_path.get_file(), ", ".join(added) if not added.is_empty() else "all three already"])
		if target:
			target.free()
	quit()


func _libs(pack_path: String) -> Array:
	var libs := [pack_path]
	var own := pack_path.replace("_pack.res", ".res")
	if own != pack_path and ResourceLoader.exists(own):
		libs.append(own)
	return libs
