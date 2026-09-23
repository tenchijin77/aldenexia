# crafting_station.gd — a town crafting station (Forge, Oven, Tannery, ...). Right-click in range (player3d.gd's
# _try_open_crafting_station()) opens the shared crafting window for its station_id; Data/tradeskill_recipes.json lists
# which recipes each station accepts (a town station takes everything its skill's kit can make, plus the town-only
# recipes). Placed by crafting_world_spawner.gd from Data/crafting_placements.json. Placeholder look (a labelled block)
# until the Meshy models exist.
extends Node3D
class_name CraftingStation

var station_id: String = ""
var display_name: String = "Crafting Station"
var use_range: float = 5.0


var model_config: Dictionary = {}  # Data/crafting_models.json entry for this station ({} = placeholder block)


func setup(id: String, title: String, model_cfg: Dictionary = {}) -> void:
	station_id = id
	display_name = title
	model_config = model_cfg
	name = "Station_%s" % id


func _ready() -> void:
	add_to_group("crafting_station")
	var height := CraftingStation.add_model(self, model_config)
	if height > 0.0:
		_add_label(height + 0.5)
		return
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 1.0, 1.0)
	block.mesh = box
	block.position = Vector3(0, 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.3, 0.2) if station_id != "forge" else Color(0.3, 0.28, 0.27)
	block.material_override = mat
	add_child(block)
	_add_label(1.6)


func _add_label(height: float) -> void:
	var label := Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	label.position = Vector3(0, height, 0)
	label.visibility_range_end = 30.0
	label.modulate = Color(1.0, 0.9, 0.7)
	add_child(label)


# Adds a Data/crafting_models.json model under `parent` (rotated and scaled as configured, then lifted so its lowest point
# sits on the parent's origin — the ground) and returns its height, or 0.0 if there is no model to add. Shared with
# gathering_node.gd.
static func add_model(parent: Node3D, cfg: Dictionary) -> float:
	var path := str(cfg.get("model", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return 0.0
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var rot: Array = cfg.get("rotation", [0, 0, 0])
	model.rotation_degrees = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
	model.scale = Vector3.ONE * float(cfg.get("scale", 1.0))
	parent.add_child(model)
	var bounds := AABB()
	var first := true
	var to_parent := parent.global_transform.affine_inverse()
	for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (to_parent * mesh_node.global_transform) * (mesh_node as MeshInstance3D).get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		return 0.0
	model.position.y -= bounds.position.y
	return bounds.size.y
