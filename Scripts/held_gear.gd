# held_gear.gd — shows a character's equipped weapon and shield in their hands (test 39: "holding their weapons all the
# time for now"). The models are models/Weapons/<name>.glb, laid out by tools/blender/fix_props.py: a weapon's grip at the
# origin pointing +Y, a shield's handle at the origin facing +Z with its top +Y. An item says which model it shows with
# "held_model" in items.json (no field, or hand-to-hand wraps: nothing shown).
#
# The fit is worked out from each model's own skeleton, so no race needs hand-tuning: in the bind pose (arms out, palms
# down) a weapon points FORWARD out of the right fist (a staff points UP), its edge up and down; a shield straps to the left
# forearm with its face out from the back of the arm and its top toward the hand. Sizes scale with the forearm (an ogre's
# sword is bigger than a gnome's). The Meshy skeletons are Z-up and face -Y (left is +X): see CHARACTER_MODELS.
class_name HeldGear
extends RefCounted

const MODEL_DIR := "res://models/Weapons/"
const GROUP := "held_gear"              # every held-gear mesh: the appearance recolour and texture override leave them alone
const REFERENCE_FOREARM := 0.195        # the human male's forearm (m): weapons are modelled for him
const UPRIGHT := ["staff", "quarterstaff", "hand_torch", "lantern", "bow"]   # held pointing up, not forward (a lantern
                                        # hangs from its handle, its origin: "up" hangs the body below the fist)
const SHIELDS := ["buckler", "round_shield", "tower_shield", "kite_shield"]

# skeleton-space directions in the bind pose
const FORWARD := Vector3(0, -1, 0)
const UP := Vector3(0, 0, 1)


# "primary_item|offhand_item" for the replicated Player3D.held_gear string.
# "primary|offhand" or "primary|offhand|left": the third is shown in the LEFT HAND when nothing is in the off hand
# (2026-09-26): a lit torch or lantern, else the ranged weapon (a bow, a crossbow).
# A fourth, "back", is worn on the back: a quiver in the ammo slot.
static func encode(primary_id: String, offhand_id: String, left_id: String = "", back_id: String = "") -> String:
	if not back_id.is_empty():
		return "%s|%s|%s|%s" % [primary_id, offhand_id, left_id, back_id]
	return "%s|%s" % [primary_id, offhand_id] if left_id.is_empty() else "%s|%s|%s" % [primary_id, offhand_id, left_id]


static func model_for(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	var def: Dictionary = Inventory.get_item_definition(item_id)
	var m := str(def.get("held_model", ""))
	if m.is_empty() or not ResourceLoader.exists(MODEL_DIR + m + ".glb"):
		return ""
	return m


# Removes whatever this character holds and attaches what `encoded` says. `character` is the model (Player3D's
# "Character" node).
static func apply(character: Node3D, encoded: String) -> void:
	if character == null:
		return
	var skeleton: Skeleton3D = null
	for s in character.find_children("*", "Skeleton3D", true, false):
		skeleton = s
		break
	if skeleton == null:
		return
	for old in skeleton.get_children():
		if old.is_in_group(GROUP):
			skeleton.remove_child(old)
			old.queue_free()
	var parts := encoded.split("|")
	var primary := model_for(parts[0] if parts.size() > 0 else "")
	var offhand := model_for(parts[1] if parts.size() > 1 else "")
	if not primary.is_empty() and not SHIELDS.has(primary):
		_attach(skeleton, primary, "RightHand", "RightForeArm", false)
	if not offhand.is_empty() and SHIELDS.has(offhand):
		_attach(skeleton, offhand, "LeftForeArm", "LeftHand", true)
	var left := model_for(parts[2] if parts.size() > 2 else "")
	if not left.is_empty() and (parts.size() < 2 or parts[1].is_empty()):
		_attach(skeleton, left, "LeftHand", "LeftForeArm", false)
	var back := model_for(parts[3] if parts.size() > 3 else "")
	if not back.is_empty():
		_attach_back(skeleton, back)


# Worn on the back (a quiver): on the upper spine bone, upright, a hand's width behind the shoulder blades, tilted a
# little so the fletchings sit over the right shoulder.
const BACK := Vector3(0, 1, 0)   # the Meshy skeletons face -Y: +Y is behind them

static func _attach_back(skeleton: Skeleton3D, model: String) -> void:
	var bi := skeleton.find_bone("Spine")
	if bi < 0:
		return
	var key := "%s|%s|back" % [str(skeleton.owner.scene_file_path) if skeleton.owner != null else str(skeleton.get_path()), model]
	if not _fit_cache.has(key):
		var poses := _idle_poses(skeleton, [bi])
		var pose: Transform3D = poses[bi]
		var inv := pose.basis.orthonormalized().inverse()
		var up := (UP + LEFT * -0.35).normalized()   # leaning toward the right shoulder
		var want := Basis(up.cross(BACK).normalized(), up, BACK)
		var hips := skeleton.get_bone_global_rest(skeleton.find_bone("Hips")).origin if skeleton.find_bone("Hips") >= 0 else Vector3.ZERO
		var size := maxf(pose.origin.distance_to(hips), 0.1) / 0.45   # the torso's length against a human male's
		_fit_cache[key] = Transform3D(inv * want.orthonormalized(), inv * (BACK * 0.16 * size)).scaled_local(Vector3.ONE * size)
	var holder := BoneAttachment3D.new()
	holder.name = "Held_" + model
	holder.bone_name = "Spine"
	holder.add_to_group(GROUP)
	skeleton.add_child(holder)
	var gear: Node3D = (load(MODEL_DIR + model + ".glb") as PackedScene).instantiate()
	holder.add_child(gear)
	for mi in gear.find_children("*", "MeshInstance3D", true, false):
		mi.add_to_group(GROUP)
	gear.transform = _fit_cache[key]


static var _fit_cache := {}   # "<skeleton's model>|<model>|<bone>" -> the fitted transform (worked out once per race model)


static func _attach(skeleton: Skeleton3D, model: String, bone: String, other: String, shield: bool) -> void:
	var bi := skeleton.find_bone(bone)
	var oi := skeleton.find_bone(other)
	if bi < 0 or oi < 0:
		return
	var key := "%s|%s|%s" % [str(skeleton.owner.scene_file_path) if skeleton.owner != null else str(skeleton.get_path()), model, bone]
	if not _fit_cache.has(key):
		var poses := _idle_poses(skeleton, [bi, oi])
		var forearm: float = (poses[bi] as Transform3D).origin.distance_to((poses[oi] as Transform3D).origin)
		_fit_cache[key] = grip_transform(poses[bi], forearm, model, shield).scaled_local(Vector3.ONE * (forearm / REFERENCE_FOREARM))
	var holder := BoneAttachment3D.new()
	holder.name = "Held_" + model
	holder.bone_name = bone
	holder.add_to_group(GROUP)
	skeleton.add_child(holder)
	var gear: Node3D = (load(MODEL_DIR + model + ".glb") as PackedScene).instantiate()
	holder.add_child(gear)
	for mi in gear.find_children("*", "MeshInstance3D", true, false):
		mi.add_to_group(GROUP)
	gear.transform = _fit_cache[key]
	if model == "hand_torch" and DisplayServer.get_name() != "headless":
		var fire := FireFX.new()   # a torch in hand is only ever shown lit: it burns (fire_fx.gd, as the wall torches)
		fire.size = 0.3
		fire.smoke = false
		fire.position = Vector3(0, 0.47, 0)   # the head of models/Weapons/hand_torch.glb (0.65 m, grip at the origin)
		gear.add_child(fire)


# The bones' skeleton-space transforms in the character's standing idle, the pose you see most (test 40: fitting to the
# arms-out bind pose left the sword across the body and the shield through the arm once the arms hung down). Plays the
# idle's first moment, reads the bones, and puts whatever was playing back.
static func _idle_poses(skeleton: Skeleton3D, bones: Array) -> Dictionary:
	var out := {}
	var ap: AnimationPlayer = null
	var root := skeleton.owner if skeleton.owner != null else skeleton.get_parent()
	for n in root.find_children("*", "AnimationPlayer", true, false):
		ap = n
		break
	var was := ""
	var at := 0.0
	var posed := false
	if ap != null and ap.has_animation("idle"):
		was = ap.current_animation
		at = ap.current_animation_position if not was.is_empty() else 0.0
		ap.play("idle")
		ap.seek(0.2, true)
		skeleton.force_update_all_bone_transforms()
		posed = true
	for b in bones:
		out[b] = skeleton.get_bone_global_pose(b) if posed else skeleton.get_bone_global_rest(b)
	if posed and not was.is_empty() and was != "idle":
		ap.play(was)
		ap.seek(at, true)
	return out


# Where the model sits in the bone's own frame, from the bone's skeleton-space transform in the idle pose.
#   weapon: tip forward and a little down from the fist (a staff stands upright), the edge up and down;
#   shield: hanging on the outside of the left forearm, face out to the left, top up.
const LEFT := Vector3(1, 0, 0)   # the Meshy skeletons' left

static func grip_transform(pose: Transform3D, forearm: float, model: String, shield: bool) -> Transform3D:
	var inv := pose.basis.orthonormalized().inverse()
	var along := pose.basis.y.normalized()        # the bone points down the arm, toward the fingers
	var want: Basis
	var pos: Vector3
	if shield:
		var face := LEFT
		var top := UP
		want = Basis(top.cross(face), top, face)
		pos = along * forearm * 0.5 + face * forearm * 0.45   # halfway down the forearm (the bone starts at the elbow), out from the arm
	else:
		var tip: Vector3 = UP if UPRIGHT.has(model) else (FORWARD * 0.9 + UP * -0.35).normalized()
		var edge: Vector3 = (UP - tip * UP.dot(tip)).normalized() if not UPRIGHT.has(model) else FORWARD
		var flat := edge.cross(tip)
		want = Basis(edge, tip, flat)
		pos = along * forearm * 0.45   # in the fist, past the wrist
	return Transform3D(inv * want.orthonormalized(), inv * pos)
