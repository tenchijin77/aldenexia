# appearance.gd — a character's look (2026-09-25): body sliders, height, and skin / hair / eye colour, chosen at
# character creation (or once at Lumora's mirror by a character made before sliders existed) and then LOCKED: after
# that only the hair colour, hair style, beard style and accessories can change (user's rule). Saved in the character's
# data as "appearance"; the server enforces the lock (ServerTrust.check -> Appearance.merge).
#
# How it shows: the body sliders are blend shapes in the rebuilt mesh (tools/blender/shape_body.py: bust, waist, hips,
# weight, muscle), height scales the model, and the colours go through Shaders/appearance.gdshader with the model's mask
# (tools/blender/make_masks.py: <scene>_mask.png + .json). Hair and beard STYLES and accessories need their own meshes,
# which don't exist yet: the keys are here so they save and lock correctly when they do.
# Pure functions + apply(): no autoloads, so the server's trust check and the tests can use it.
class_name Appearance
extends RefCounted

const VERSION := 1
# slider -> [min, max]; 0 is the model as it is. Weight's thin end is shallower: its shape thins along the surface,
# and thin limbs can't lose much.
const SLIDERS := {"height": [-1.0, 1.0], "weight": [-0.5, 1.0], "muscle": [-0.3, 1.0], "bust": [-1.0, 1.0], "waist": [-1.0, 1.0], "hips": [-1.0, 1.0]}
const FEMALE_ONLY := ["bust", "waist", "hips"]
const COLOURS := ["skin_color", "hair_color", "eye_color"]
# Eye colour is off until the eye masks are right: found automatically they cover the iris on only a few models (the
# rest have shadowed eye-whites to find it by, and the lids got the colour like eyeshadow). The key stays in the save.
const EYE_COLOUR_ENABLED := false
# what may still change once the look is locked
const CHANGEABLE_AFTER_LOCK := ["hair_color", "hair_style", "beard_style", "accessories"]
# how much the height slider stretches each race at its ends (a share of the model's height)
const HEIGHT_RANGE := {"dwarf": 0.05, "gnome": 0.05, "halfling": 0.05, "ogre": 0.07, "troll": 0.07}
const DEFAULT_HEIGHT_RANGE := 0.06

# Colour choices ("" = as the model was painted). Skin by race; hair and eyes for everyone.
const SKIN_PALETTES := {
	"human": ["#f3d6c3", "#e8bfa1", "#d9a37f", "#c68a63", "#a86b45", "#8a5232", "#6b3d24", "#4a2a18"],
	"elf": ["#f6e2d6", "#ecccb6", "#dcb394", "#c89b77", "#e9d7c9", "#d7c2ae"],
	"half_elf": ["#f3d6c3", "#e8bfa1", "#d9a37f", "#c68a63", "#a86b45", "#8a5232"],
	"dark_elf": ["#6e6a7a", "#5a5569", "#4b4a5e", "#3d3a4f", "#57506e", "#6c5f80", "#44415a", "#2f2d3d"],
	"dwarf": ["#f0cdb5", "#e2b192", "#cf9571", "#b57a55", "#94603f", "#734a30"],
	"gnome": ["#f3d6c3", "#e8bfa1", "#d9a37f", "#c68a63", "#a86b45", "#8a5232"],
	"halfling": ["#f3d6c3", "#e8bfa1", "#d9a37f", "#c68a63", "#a86b45", "#8a5232"],
	"half_orc": ["#8a9a6a", "#7a8a5c", "#6b7c52", "#8f9477", "#7d8570", "#a39a78", "#6e6a57", "#5c6647"],
	"troll": ["#6f8a5a", "#5f7a58", "#5a7a6e", "#4f6b62", "#6a7f75", "#7d8a66", "#4a5e4a", "#65705a"],
	"ogre": ["#b9a07e", "#a38b6c", "#8e7a61", "#9a9474", "#858a6c", "#a8927a", "#7a6e5a", "#96806a"],
	"lizardkin": ["#5f8a4f", "#4f7a5f", "#3f6a5a", "#7a8a4a", "#8a6a3f", "#6a4f3f", "#4f6a7a", "#8a4f3f"],
}
const HAIR_PALETTE := ["#141210", "#2b1d14", "#4a3020", "#6b4428", "#8a3b1f", "#b5552a", "#c98a4a", "#dcc080",
		"#e8ddc0", "#b8b4ac", "#f2f0ea", "#2a2d3a", "#8c8fa0", "#5a1f2a"]
const EYE_PALETTE := ["#4a2f1c", "#6b4a2a", "#7a6a3a", "#4f6b3a", "#3f6a8a", "#5a7a9a", "#7a7f86", "#c08a2a", "#7a4a9a", "#9a2a2a"]

static var _mask_cache: Dictionary = {}


static func defaults() -> Dictionary:
	var a := {"version": VERSION, "locked": false, "skin_color": "", "hair_color": "", "eye_color": "",
			"hair_style": "", "beard_style": "", "accessories": []}
	for s in SLIDERS:
		a[s] = 0.0
	return a


static func skin_palette(race: String) -> Array:
	return SKIN_PALETTES.get(race.to_lower().replace("-", "_").replace(" ", "_"), SKIN_PALETTES["human"])


static func height_range(race: String) -> float:
	return float(HEIGHT_RANGE.get(race.to_lower().replace("-", "_").replace(" ", "_"), DEFAULT_HEIGHT_RANGE))


# A clean appearance: every slider within its range (a woman's shapes only for women), colours from the palettes.
static func validate(a: Variant, sex: String, race: String) -> Dictionary:
	var out := defaults()
	if typeof(a) != TYPE_DICTIONARY:
		return out
	for s in SLIDERS:
		var r: Array = SLIDERS[s]
		out[s] = clampf(float(a.get(s, 0.0)), r[0], r[1]) if (sex.to_lower() == "female" or not FEMALE_ONLY.has(s)) else 0.0
	var palettes := {"skin_color": skin_palette(race), "hair_color": HAIR_PALETTE, "eye_color": EYE_PALETTE}
	for c in COLOURS:
		var v := str(a.get(c, ""))
		out[c] = v if palettes[c].has(v) and (c != "eye_color" or EYE_COLOUR_ENABLED) else ""
	for k in ["hair_style", "beard_style"]:
		out[k] = str(a.get(k, "")).substr(0, 32)
	out["accessories"] = (a.get("accessories", []) as Array).slice(0, 6).map(func(x): return str(x).substr(0, 32)) if a.get("accessories") is Array else []
	out["locked"] = bool(a.get("locked", false))
	return out


# The look to keep when a save arrives: once locked, only CHANGEABLE_AFTER_LOCK comes from the new one; before that
# (a new character, or an old one at the mirror) the new look is taken whole. Returns {"appearance", "changed": [keys refused]}.
static func merge(stored: Variant, incoming: Variant, sex: String, race: String) -> Dictionary:
	var inc := validate(incoming, sex, race)
	if typeof(stored) != TYPE_DICTIONARY or not bool(stored.get("locked", false)):
		return {"appearance": inc, "refused": []}
	var keep := validate(stored, sex, race)
	var refused: Array = []
	for k in inc:
		if CHANGEABLE_AFTER_LOCK.has(k):
			keep[k] = inc[k]
		elif JSON.stringify(inc[k]) != JSON.stringify(keep[k]) and k != "locked":
			refused.append(k)
	keep["locked"] = true
	return {"appearance": keep, "refused": refused}


# The mask next to a model's FBX, and each region's original colour: {"mask": Texture2D, "skin": Color, ...} or {}.
static func mask_for(scene_path: String) -> Dictionary:
	if _mask_cache.has(scene_path):
		return _mask_cache[scene_path]
	var base := scene_path.get_base_dir().path_join(scene_path.get_file().get_basename().to_lower().replace(" ", "_").replace("-", "_") + "_mask")
	var info := {}
	if ResourceLoader.exists(base + ".png") and FileAccess.file_exists(base + ".json"):
		var refs = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
		info["mask"] = load(base + ".png")
		for k in ["skin", "hair", "eyes"]:
			if typeof(refs) == TYPE_DICTIONARY and refs.get(k) is Array and (refs[k] as Array).size() == 3:
				info[k] = Color(float(refs[k][0]), float(refs[k][1]), float(refs[k][2]))
	_mask_cache[scene_path] = info
	return info


# Puts a look on a built character model (the "Character" node: the FBX scene instance). `base_scale` is its scale before
# height. Blend shapes only exist on the rebuilt meshes (not on a dedicated server, which draws nothing).
static func apply(character: Node3D, scene_path: String, texture_path: String, a: Dictionary, race: String, base_scale: Vector3) -> void:
	if character == null:
		return
	character.scale = base_scale * (1.0 + float(a.get("height", 0.0)) * height_range(race))
	for node in character.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.is_in_group(HeldGear.GROUP):
			continue   # a weapon or shield in hand keeps its own materials
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_blend_shape_count():
			var shape := str(mi.mesh.get_blend_shape_name(i))
			if SLIDERS.has(shape):
				mi.set_blend_shape_value(i, float(a.get(shape, 0.0)))
		var mat := material_for(scene_path, texture_path, a)
		if mat:
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, mat)


# The model's material: its texture, recoloured where the look asks (a plain material when nothing is recoloured or
# the model has no mask).
static func material_for(scene_path: String, texture_path: String, a: Dictionary) -> Material:
	var tex := load(texture_path) as Texture2D if not texture_path.is_empty() and ResourceLoader.exists(texture_path) else null
	if tex == null:
		return null
	var info := mask_for(scene_path)
	var wants := COLOURS.any(func(c): return not str(a.get(c, "")).is_empty())
	if info.is_empty() or not wants:
		var plain := StandardMaterial3D.new()
		plain.albedo_texture = tex
		return plain
	var m := ShaderMaterial.new()
	m.shader = load("res://Shaders/appearance.gdshader")
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("mask_tex", info["mask"])
	for pair in [["skin_color", "skin"], ["hair_color", "hair"], ["eye_color", "eyes"]]:
		var want := str(a.get(pair[0], ""))
		var p: String = "eye" if pair[1] == "eyes" else pair[1]
		var on := not want.is_empty() and info.has(pair[1])
		m.set_shader_parameter(p + "_on", 1.0 if on else 0.0)
		if on:
			m.set_shader_parameter(p + "_ref", info[pair[1]])
			m.set_shader_parameter(p + "_target", Color.html(want))
	return m
