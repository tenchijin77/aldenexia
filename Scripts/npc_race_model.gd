# npc_race_model.gd — Builds an NPC's body from one of the player race/sex models (Player3D.CHARACTER_MODELS, e.g.
# "halfling_male"), so an NPC can look like a person of the world without new art and gets the full animation set
# (idle, walk, run...). Same recipe player3d.gd uses for the player: instance the model, swap in its animation library,
# apply the known-good texture as a material override (the FBX's own texture link is unreliable).
class_name NPCRaceModel
extends RefCounted


# Adds a "Character" child to `npc` and returns its AnimationPlayer (null if the model has none). Starts the idle clip.
static func build(npc: Node3D, model_key: String) -> AnimationPlayer:
	var info: Dictionary = Player3D.CHARACTER_MODELS.get(model_key, Player3D.DEFAULT_CHARACTER_MODEL)
	var scene := load(info["scene"]) as PackedScene
	if scene == null:
		return null
	var character: Node3D = scene.instantiate()
	character.name = "Character"
	MeshSmoothing.smooth_model(character)   # smooth shading (mesh_smoothing.gd)
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)  # the facing correction every Mixamo export needs
	var model_scale: float = info.get("scale", 1.0)
	if model_scale != 1.0:
		character.transform = character.transform.scaled(Vector3.ONE * model_scale)
	npc.add_child(character)

	var player := character.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null:
		var lib := load(info["library"]) as AnimationLibrary
		if lib != null:
			if player.has_animation_library(""):
				player.remove_animation_library("")
			player.add_animation_library("", lib)
			if player.has_animation("idle"):
				player.play("idle")
	if info.has("texture_override"):
		var tex := load(info["texture_override"]) as Texture2D
		if tex != null:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = tex
			_override_materials(character, mat)
	return player


static func _override_materials(node: Node, mat: Material) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_override_materials(child, mat)
