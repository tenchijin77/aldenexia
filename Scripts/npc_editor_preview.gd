# npc_editor_preview.gd — shows an NPC's real model and name IN THE EDITOR, so NPCs can be placed by dragging them around
# the zone scene like crafting stations. It is a child ("EditorPreview") of each NPC scene that builds its body at runtime
# (talking vendors, the banker, Tobble, Kenji, Oni, the harbour master). In the game it deletes itself at once: the NPC's
# own script builds the real body, so nothing here runs in play.
# It reads the NPC's settings from its parent: "model_key" (a race model, e.g. "dwarf_male", as NPCRaceModel uses),
# "vendor_model_key" (VENDOR_MODELS), or a cat's MODEL_BASE + model_scale; and "npc_name" for the label. Change the
# NPC's Model Key in the Inspector and the preview follows (it refreshes about once a second).
# Height doesn't need to be exact: vendors stand on whatever ground is under them when the game starts (VendorNPC.snap_to_floor()).
@tool
extends Node3D

var _shown_key := ""
var _label: Label3D = null
var _timer := 0.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
	_rebuild()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_timer += delta
	if _timer < 1.0:
		return
	_timer = 0.0
	if _key() != _shown_key:
		_rebuild()
	elif _label != null:
		_label.text = _name()


func _key() -> String:
	var npc := get_parent()
	if npc == null:
		return ""
	var consts: Dictionary = npc.get_script().get_script_constant_map() if npc.get_script() != null else {}
	if consts.has("MODEL_BASE"):
		return "cat:%s:%s" % [consts["MODEL_BASE"], str(npc.get("model_scale"))]
	if consts.get("VENDOR_MODELS", {}).has(str(npc.get("vendor_model_key"))):
		return "vendor:" + str(npc.get("vendor_model_key"))   # a vendor's own model wins over its race
	if npc.get("model_key") != null:
		return "race:" + str(npc.get("model_key"))
	if npc.get("vendor_model_key") != null:
		return "vendor:" + str(npc.get("vendor_model_key"))
	return ""


func _name() -> String:
	var npc := get_parent()
	var n = npc.get("npc_name") if npc != null else null
	return str(n) if n != null and not str(n).is_empty() else str(npc.name if npc != null else "NPC")


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_shown_key = _key()
	var height := 2.0
	var parts := _shown_key.split(":")
	match parts[0] if parts.size() > 0 else "":
		"race":
			height = _add_race_model(parts[1])
		"vendor":
			var consts: Dictionary = get_parent().get_script().get_script_constant_map()
			var info: Dictionary = consts.get("VENDOR_MODELS", {}).get(parts[1], consts.get("DEFAULT_VENDOR_MODEL", {}))
			height = _add_model(str(info.get("scene", "")), str(info.get("texture_override", "")), 1.0)
		"cat":
			var base := _shown_key.trim_prefix("cat:").rsplit(":", true, 1)
			height = _add_model(base[0] + ".fbx", base[0] + ".png", float(base[1]) if base[1].is_valid_float() else 0.5)
	_label = Label3D.new()
	_label.text = _name()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.006
	_label.position = Vector3(0, height + 0.4, 0)
	_label.modulate = Color(0.8, 0.95, 1.0)
	add_child(_label)


func _add_race_model(key: String) -> float:
	var models: Dictionary = load("res://Scripts/player3d.gd").get_script_constant_map()
	var info: Dictionary = models.get("CHARACTER_MODELS", {}).get(key, models.get("DEFAULT_CHARACTER_MODEL", {}))
	return _add_model(str(info.get("scene", "")), str(info.get("texture_override", "")), float(info.get("scale", 1.0)))


# The model, turned to face the way the NPC faces in game, with its texture. Returns roughly how tall it is.
func _add_model(scene_path: String, texture_path: String, model_scale: float) -> float:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		var capsule := MeshInstance3D.new()
		capsule.mesh = CapsuleMesh.new()
		capsule.position.y = 1.0
		add_child(capsule)
		return 2.0
	var model: Node3D = (load(scene_path) as PackedScene).instantiate()
	MeshSmoothing.use_rebuilt_mesh(model)   # the smooth Blender-rebuilt mesh, as in game
	model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * model_scale), Vector3.ZERO)
	add_child(model)
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(texture_path) as Texture2D
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
	var top := 0.0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb() if (mi as MeshInstance3D).is_inside_tree() else AABB()
		top = maxf(top, box.end.y - global_position.y)
	return top if top > 0.2 else 1.8
