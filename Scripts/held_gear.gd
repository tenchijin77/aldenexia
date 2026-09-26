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
const UPRIGHT := ["staff"]              # held pointing up, not forward
const SHIELDS := ["buckler", "round_shield", "tower_shield", "kite_shield"]

# skeleton-space directions in the bind pose
const FORWARD := Vector3(0, -1, 0)
const UP := Vector3(0, 0, 1)


# "primary_item|offhand_item" for the replicated Player3D.held_gear string.
static func encode(primary_id: String, offhand_id: String) -> String:
	return "%s|%s" % [primary_id, offhand_id]


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


static func _attach(skeleton: Skeleton3D, model: String, bone: String, other: String, shield: bool) -> void:
	var bi := skeleton.find_bone(bone)
	var oi := skeleton.find_bone(other)
	if bi < 0 or oi < 0:
		return
	var rest := skeleton.get_bone_global_rest(bi)
	var forearm := rest.origin.distance_to(skeleton.get_bone_global_rest(oi).origin)   # hand<->forearm joint distance
	var size := forearm / REFERENCE_FOREARM
	var holder := BoneAttachment3D.new()
	holder.name = "Held_" + model
	holder.bone_name = bone
	holder.add_to_group(GROUP)
	skeleton.add_child(holder)
	var gear: Node3D = (load(MODEL_DIR + model + ".glb") as PackedScene).instantiate()
	holder.add_child(gear)
	for mi in gear.find_children("*", "MeshInstance3D", true, false):
		mi.add_to_group(GROUP)
	gear.transform = grip_transform(rest, forearm, model, shield).scaled_local(Vector3.ONE * size)


# Where the model sits in the bone's own frame, from the bone's bind-pose (global rest) transform.
static func grip_transform(rest: Transform3D, forearm: float, model: String, shield: bool) -> Transform3D:
	var inv := rest.basis.orthonormalized().inverse()
	var along := (rest.basis.y).normalized()        # the bone points down the arm, toward the fingers
	var palm := (rest.basis.z).normalized()         # palms-down bind pose: the bone's z is the palm's normal
	var want: Basis
	var pos: Vector3
	if shield:
		# strapped to the forearm: face out of the back of the arm, top toward the hand, halfway down the forearm
		var face := -palm
		var top := along
		want = Basis(top.cross(face), top, face)
		pos = along * forearm * 0.5 + face * forearm * 0.2
	else:
		var tip := UP if UPRIGHT.has(model) else FORWARD
		var edge := UP if not UPRIGHT.has(model) else FORWARD
		var flat := edge.cross(tip)
		want = Basis(edge, tip, flat)
		pos = along * forearm * 0.45 + palm * forearm * 0.15   # in the fist: past the wrist, a little into the palm
	return Transform3D(inv * want.orthonormalized(), inv * pos)
