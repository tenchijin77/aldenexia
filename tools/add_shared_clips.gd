# add_shared_clips.gd — the user's Mixamo animations (2026-09-26: exported on one of our own models, so the bones already
# have our names: Hips, Spine02, neck...) retargeted onto every race's skeleton and ADDED to each model's pack
# (<library>_pack.res), under the game's clip names below. Unlike make_animation_pack.gd this doesn't rebuild a pack from
# its base library, so the fixes made to packs afterwards (share_sit, straighten_sit, fit_jump, relax_shoulders...) stay.
# Run it again after adding a file: clips already there are replaced.
#   godot --headless --path . --script res://tools/add_shared_clips.gd
# Files: Assets/animations/mixamo/<name>.fbx. A clip that walks away from its spot (Mixamo without "In Place") has its
# drift taken out, so the character stays where the game puts it.
extends SceneTree

const DIR := "res://Assets/animations/mixamo/"
const PackTool := preload("res://tools/make_animation_pack.gd")
# file -> [clip name, loops]
const CLIPS := {
	"blow_a_kiss": ["emote_kiss", false], "quick_informal_bow": ["emote_bow", false], "cheering": ["emote_cheer", false],
	"clapping": ["emote_clap", false], "waving": ["emote_wave", false], "taunt_gesture": ["emote_taunt", false],
	"belly_dance": ["dance_1", true], "silly_dancing": ["dance_2", true], "snake_hip_hop_dance": ["dance_3", true],
	"breakdance_swipes": ["dance_4", true], "thriller_part_4": ["dance_5", true],
	"sneak_walk": ["sneak", true], "unarmed_walk_back": ["walk_back", true],
	"swimming": ["swim", true], "swimming_to_edge": ["swim_out", false],
	"climbing_ladder": ["climb", true], "climbing_to_top": ["climb_top", false],
	"fishing_cast": ["fish_cast", false], "fishing_idle": ["fish_idle", true], "taking_item": ["pick_up", false],
	"standing_react_small_from_front": ["hit_front", false], "standing_react_large_from_back": ["hit_back", false],
	"dodging": ["dodge", false], "dodging_complex": ["dodge_2", false],
	"punching": ["punch", false], "combo_punch": ["punch_combo", false], "standing_melee_attack_kick_ver_1": ["kick", false],
	"flying_kick": ["flying_kick", false], "sword_and_shield_kick": ["shield_kick", false],
	"dual_weapon_combo": ["dual_combo", false], "one_hand_club_combo": ["club_combo", false],
	"heavy_weapon_swing": ["heavy_swing", false],
}


func _init() -> void:
	await process_frame
	var sources := []
	for f in DirAccess.get_files_at(DIR):
		var key := f.get_basename()
		if not f.ends_with(".fbx") or not CLIPS.has(key):
			if f.ends_with(".fbx"):
				print("  (no clip name for %s: add it to CLIPS)" % f)
			continue
		var scene: Node = load(DIR + f).instantiate()
		root.add_child(scene)
		var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var anim: Animation = ap.get_animation(ap.get_animation_list()[ap.get_animation_list().size() - 1])
		sources.append({"key": key, "anim": anim, "skeleton": scene.find_children("*", "Skeleton3D", true, false)[0], "scene": scene})
	await process_frame
	for m in _models():
		var target: Node = load(m["scene"]).instantiate()
		root.add_child(target)
		await process_frame
		var tsk := target.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var pack_path: String = PackTool.pack_path(m["library"])
		var lib := load(pack_path) as AnimationLibrary
		for s in sources:
			var clip: Array = CLIPS[s["key"]]
			var anim := PackTool.retarget(s["anim"], s["skeleton"], tsk)
			_stay_in_place(anim, tsk)
			anim.loop_mode = Animation.LOOP_LINEAR if clip[1] else Animation.LOOP_NONE
			anim.set_meta("source", "mixamo/" + s["key"])
			if lib.has_animation(clip[0]):
				lib.remove_animation(clip[0])
			lib.add_animation(clip[0], anim)
		var err := ResourceSaver.save(lib, pack_path, ResourceSaver.FLAG_COMPRESS)
		print("%s: %d clips added%s" % [m["folder"], sources.size(), "" if err == OK else " SAVE FAILED"])
		target.free()
	quit()


# The race models (the same list make_animation_pack.gd reads from player3d.gd).
func _models() -> Array:
	var text := FileAccess.get_file_as_string("res://Scripts/player3d.gd")
	var re := RegEx.new()
	re.compile('"scene":\\s*"(res://models/([^/"]+)/[^"]+Breathing Idle\\.fbx)",\\s*\\n\\s*"library":\\s*"(res://[^"]+?)(?:_pack)?\\.res"')
	var out := []
	for r in re.search_all(text):
		out.append({"scene": r.get_string(1), "folder": r.get_string(2), "library": r.get_string(3) + ".res"})
	return out


# Takes the hips' sideways/forward drift out, evenly over the clip (a lunge still leans in, then eases back), keeping
# their height: the game moves the body, the clip only moves the limbs.
static func _stay_in_place(anim: Animation, sk: Skeleton3D) -> void:
	var up := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var n := anim.track_get_key_count(i)
		if n < 2:
			continue
		var first: Vector3 = anim.track_get_key_value(i, 0)
		var drift: Vector3 = anim.track_get_key_value(i, n - 1) - first
		drift -= up * drift.dot(up)
		if drift.length() < 0.05:
			continue
		for k in n:
			var t := anim.track_get_key_time(i, k) / maxf(anim.length, 0.001)
			anim.track_set_key_value(i, k, (anim.track_get_key_value(i, k) as Vector3) - drift * t)
