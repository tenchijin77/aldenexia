# zone_boundary.gd — invisible walls around the edge of a zone's terrain, so nobody walks off the map into the void
# (test 34.5: walking past Dustwind's zone line fell forever). Built when the zone loads from the Terrain3D next to it:
# the rectangle around all of its regions, one wall per side, from well below the ground to well above the hills.
# A zone line should sit a few metres inside the edge, so you reach it before the wall. A gap INSIDE the rectangle
# (a missing region) isn't walled; Player3D's fall safety catches anyone who drops through one.
extends Node3D

const WALL_THICKNESS := 2.0
const WALL_BOTTOM := -60.0
const WALL_TOP := 260.0

var bounds := Rect2()   # x, z of the terrain's outer rectangle (set once built; for tests)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	await get_tree().process_frame   # the terrain's regions are loaded by then
	var terrain := get_parent().get_node_or_null("Terrain3D")
	if terrain == null or terrain.get("data") == null:
		return
	var locations: Array = terrain.data.get_region_locations()
	if locations.is_empty():
		return
	var size := float(terrain.region_size) * float(terrain.vertex_spacing)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for loc in locations:
		lo = Vector2(minf(lo.x, loc.x * size), minf(lo.y, loc.y * size))
		hi = Vector2(maxf(hi.x, (loc.x + 1) * size), maxf(hi.y, (loc.y + 1) * size))
	bounds = Rect2(lo, hi - lo)
	var height := WALL_TOP - WALL_BOTTOM
	var mid_y := (WALL_TOP + WALL_BOTTOM) / 2.0
	var t := WALL_THICKNESS
	# north / south walls run along X; west / east along Z (each just outside the edge)
	_wall(Vector3((lo.x + hi.x) / 2.0, mid_y, lo.y - t / 2.0), Vector3(hi.x - lo.x + 2.0 * t, height, t))
	_wall(Vector3((lo.x + hi.x) / 2.0, mid_y, hi.y + t / 2.0), Vector3(hi.x - lo.x + 2.0 * t, height, t))
	_wall(Vector3(lo.x - t / 2.0, mid_y, (lo.y + hi.y) / 2.0), Vector3(t, height, hi.y - lo.y + 2.0 * t))
	_wall(Vector3(hi.x + t / 2.0, mid_y, (lo.y + hi.y) / 2.0), Vector3(t, height, hi.y - lo.y + 2.0 * t))


func _wall(centre: Vector3, box_size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = centre
