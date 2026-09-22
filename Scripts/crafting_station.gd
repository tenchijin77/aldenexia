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


func setup(id: String, title: String) -> void:
	station_id = id
	display_name = title
	name = "Station_%s" % id


func _ready() -> void:
	add_to_group("crafting_station")
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 1.0, 1.0)
	block.mesh = box
	block.position = Vector3(0, 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.3, 0.2) if station_id != "forge" else Color(0.3, 0.28, 0.27)
	block.material_override = mat
	add_child(block)
	var label := Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	label.position = Vector3(0, 1.6, 0)
	label.visibility_range_end = 30.0
	label.modulate = Color(1.0, 0.9, 0.7)
	add_child(label)
