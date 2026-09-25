# structure_collision.gd — gives a zone's building models solid collision when the zone loads, so a model dragged in
# from Blender (the gates, the graveyard, the docks, ...) needs no hand-made collision. Every imported model sitting
# directly under the zone's root (.glb / .gltf / .blend / .fbx), or inside a plain Node3D used to group them (e.g.
# "Vendor Stalls", "Enemy Camps"), gets a StaticBody3D with an exact-shape (trimesh)
# collider for each of its meshes (solid from both sides; floors lying on the ground left out — the terrain is the floor),
# on collision layer 65 — layer 1 for players and monsters plus layer 7, which pets
# only collide with (pet_minion.gd WORLD_ONLY_MASK). A model that already has collision of its own is left alone, and any
# model whose name contains one of skip_names (water by default) stays walk-through.
# Place one of these as a direct child of the zone root. tools/bake_lumora_navmesh.gd bakes the navmesh after it has run.
extends Node

const WORLD_LAYER := 65
const MODEL_EXTENSIONS := [".glb", ".gltf", ".blend", ".fbx"]

@export var skip_names: PackedStringArray = PackedStringArray(["water"])


func _ready() -> void:
	_build.call_deferred()  # after the zone's other children have finished loading


func _build() -> void:
	var zone := get_parent()
	var terrain := zone.get_node_or_null("Terrain3D")
	var built := 0
	var candidates: Array = []
	for child in zone.get_children():
		if _is_model(child):
			candidates.append(child)
		elif _is_group(child):  # a plain Node3D used to group models ("Vendor Stalls", "Enemy Camps", ...)
			candidates.append_array(child.get_children().filter(_is_model))
	for model in candidates:
		if not _is_model(model) or _skipped(model) or not model.find_children("*", "CollisionObject3D", true, false).is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "StructureCollision"
		body.collision_layer = WORLD_LAYER
		model.add_child(body)
		for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh_node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			var faces := _solid_faces(mesh_instance, terrain)
			if faces.is_empty():
				continue
			var concave := ConcavePolygonShape3D.new()
			concave.set_faces(faces)
			concave.backface_collision = true   # solid from both sides: a wall facing "inward" can't be walked through
			var shape := CollisionShape3D.new()
			shape.shape = concave
			body.add_child(shape)
			shape.global_transform = mesh_instance.global_transform
		built += 1
	print("✅ Structure collision: %d model%s made solid" % [built, "" if built == 1 else "s"])


# The mesh's triangles for collision, minus any floor lying ON the ground (facing up, within FLOOR_ON_GROUND of the
# terrain there): the terrain already holds you up, and a second surface at the same height snags a walking character on
# its triangle edges — the mausoleum's floor trapped players (test 33 / 35).
const FLOOR_ON_GROUND := 0.25

func _solid_faces(mesh_instance: MeshInstance3D, terrain: Node) -> PackedVector3Array:
	var faces := mesh_instance.mesh.get_faces()
	var data = terrain.get("data") if terrain != null else null
	if data == null:
		return faces
	var xf := mesh_instance.global_transform
	var kept := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var a := xf * faces[i]
		var b := xf * faces[i + 1]
		var c := xf * faces[i + 2]
		var normal := (b - a).cross(c - a).normalized()
		if normal.y > 0.9:
			var centre := (a + b + c) / 3.0
			var ground: float = data.get_height(centre)
			if not is_nan(ground) and absf(centre.y - ground) <= FLOOR_ON_GROUND and absf(a.y - ground) <= FLOOR_ON_GROUND:
				continue
		kept.append(faces[i])
		kept.append(faces[i + 1])
		kept.append(faces[i + 2])
	return kept


func _is_model(node: Node) -> bool:
	if not (node is Node3D) or node.scene_file_path.is_empty():
		return false
	for ext in MODEL_EXTENSIONS:
		if node.scene_file_path.to_lower().ends_with(ext):
			return true
	return false


# A plain grouping node: a Node3D with no script and no scene of its own (not an NPC, spawner or manager).
func _is_group(node: Node) -> bool:
	return node.get_class() == "Node3D" and node.get_script() == null and node.scene_file_path.is_empty()


func _skipped(node: Node) -> bool:
	var lowered := str(node.name).to_lower()
	for word in skip_names:
		if word.to_lower() in lowered:
			return true
	return false
