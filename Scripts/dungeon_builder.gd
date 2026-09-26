# dungeon_builder.gd — builds an indoor dungeon's stand-in rooms from an ASCII map (Data/<zone_id>_layout.txt), so a
# dungeon can be laid out (and re-laid out) in a text editor before any art exists. The Warden Crypts under the Outskirts
# mausoleum are the first (2026-09-26). Each character is one CELL x CELL square, rows run +Z (south), columns +X (east),
# cell (0, 0) has its corner at this node's origin:
#   #  solid rock (nothing is built there; the walls around it are)
#   .  floor
#   T  floor, with a wall torch on the nearest wall (a flickering light)
#   S  the stairs back up: steps rising toward the nearest wall (put the zone line and arrival marker there by hand)
#   C  floor with a sarcophagus / altar block on it
# Floors, walls and ceilings are merged meshes with one collision body on the world layer (65, like Terrain3D and the
# buildings), so the navmesh bakes from them (tools/bake_lumora_navmesh.gd) and the camera stops at walls. Everything is
# rebuilt at load and in the editor (@tool) and never saved into the scene: edit the text file, reopen the scene.
@tool
extends Node3D

const CELL := 3.0
const WALL_HEIGHT := 4.5
const STEP_COUNT := 5
const STEP_RISE := 0.35
const WORLD_LAYER := 65
const STONE_FLOOR := Color(0.30, 0.28, 0.26)
const STONE_WALL := Color(0.40, 0.37, 0.33)
const STONE_CEILING := Color(0.18, 0.17, 0.16)
const TORCH_COLOR := Color(1.0, 0.62, 0.30)

@export_file("*.txt") var layout_path := ""

var _rows: PackedStringArray = PackedStringArray()
var _torches: Array[OmniLight3D] = []


func _ready() -> void:
	build()


func build() -> void:
	for child in get_children():
		if child.has_meta("built"):
			child.free()
	_torches.clear()
	_rows = load_rows(layout_path)
	if _rows.is_empty():
		return
	var floor_st := _surface()
	var wall_st := _surface()
	var ceiling_st := _surface()
	var faces := PackedVector3Array()
	for r in _rows.size():
		for c in _rows[r].length():
			if not is_open(c, r):
				continue
			var x0 := c * CELL
			var z0 := r * CELL
			var a := Vector3(x0, 0, z0)
			var b := Vector3(x0 + CELL, 0, z0)
			var d := Vector3(x0 + CELL, 0, z0 + CELL)
			var e := Vector3(x0, 0, z0 + CELL)
			_quad(floor_st, faces, Vector3.UP, a, b, d, e)   # facing up
			var up := Vector3(0, WALL_HEIGHT, 0)
			_quad(ceiling_st, faces, Vector3.DOWN, e + up, d + up, b + up, a + up)   # facing down
			# a wall on each side that meets rock, facing into this cell
			if not is_open(c, r - 1):
				_quad(wall_st, faces, Vector3(0, 0, 1), a + up, b + up, b, a)
			if not is_open(c, r + 1):
				_quad(wall_st, faces, Vector3(0, 0, -1), d + up, e + up, e, d)
			if not is_open(c - 1, r):
				_quad(wall_st, faces, Vector3(1, 0, 0), e + up, a + up, a, e)
			if not is_open(c + 1, r):
				_quad(wall_st, faces, Vector3(-1, 0, 0), b + up, d + up, d, b)
			match cell(c, r):
				"S":
					_add_stairs(c, r, faces)
				"C":
					# (while the navmesh bakes, solid to the ceiling: monsters walk around a tomb, never onto it)
					var h := WALL_HEIGHT if Engine.has_meta("navmesh_baking") else 1.1
					_add_box(Vector3(x0 + CELL / 2.0, h / 2.0, z0 + CELL / 2.0), Vector3(1.2, h, 2.3), STONE_WALL.darkened(0.15), faces)
				"T":
					_add_torch(c, r)
	_add_mesh(floor_st, STONE_FLOOR, "Floor")
	_add_mesh(wall_st, STONE_WALL, "Walls")
	_add_mesh(ceiling_st, STONE_CEILING, "Ceiling")
	var body := StaticBody3D.new()
	body.name = "DungeonCollision"
	body.collision_layer = WORLD_LAYER
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	_keep(body)


static func load_rows(path: String) -> PackedStringArray:
	if path.is_empty() or not FileAccess.file_exists(path):
		return PackedStringArray()
	var rows := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if not line.strip_edges().is_empty():
			rows.append(line.strip_edges(false, true))
	return rows


func cell(c: int, r: int) -> String:
	if r < 0 or r >= _rows.size() or c < 0 or c >= _rows[r].length():
		return "#"
	return _rows[r][c]


func is_open(c: int, r: int) -> bool:
	return cell(c, r) != "#"


## The world position of the middle of a cell (on the floor).
func cell_centre(c: int, r: int) -> Vector3:
	return global_transform * Vector3((c + 0.5) * CELL, 0, (r + 0.5) * CELL)


func _surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


# One square face that faces `normal` (Godot draws clockwise faces: the corners are put in that order whatever order
# they come in).
func _quad(st: SurfaceTool, faces: PackedVector3Array, normal: Vector3, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var corners := [p0, p1, p2, p3]
	if (p1 - p0).cross(p2 - p0).dot(normal) > 0.0:
		corners.reverse()
	for i in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = corners[i]
		st.set_normal(normal)
		st.set_uv(Vector2(p.x + p.z, p.y) / CELL)
		st.add_vertex(p)
		faces.append(p)


func _add_mesh(st: SurfaceTool, color: Color, node_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = _stone(color)
	_keep(mi)


func _stone(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	if DisplayServer.get_name() != "headless":
		var noise := FastNoiseLite.new()
		noise.frequency = 0.08
		var tex := NoiseTexture2D.new()
		tex.noise = noise
		tex.seamless = true
		tex.color_ramp = Gradient.new()
		tex.color_ramp.set_color(0, Color(0.7, 0.7, 0.7))
		tex.color_ramp.set_color(1, Color(1.0, 1.0, 1.0))
		mat.albedo_texture = tex
	return mat


func _add_box(centre: Vector3, size: Vector3, color: Color, faces: PackedVector3Array) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = centre
	mi.material_override = _stone(color)
	_keep(mi)
	var tri := box.get_faces()
	for i in tri.size():
		faces.append(tri[i] + centre)


# The steps climb toward the rock side of the stairs cell (the wall the stairwell goes up through).
func _add_stairs(c: int, r: int, faces: PackedVector3Array) -> void:
	var dir := Vector3.ZERO
	if not is_open(c, r - 1):
		dir = Vector3(0, 0, -1)
	elif not is_open(c, r + 1):
		dir = Vector3(0, 0, 1)
	elif not is_open(c - 1, r):
		dir = Vector3(-1, 0, 0)
	else:
		dir = Vector3(1, 0, 0)
	var centre := Vector3((c + 0.5) * CELL, 0, (r + 0.5) * CELL)
	var depth := CELL / STEP_COUNT
	for i in STEP_COUNT:
		var h := STEP_RISE * (i + 1)
		var along := -CELL / 2.0 + depth * (i + 0.5)
		var size := Vector3(CELL if dir.x == 0.0 else depth, h, CELL if dir.z == 0.0 else depth)
		_add_box(centre + dir * along + Vector3(0, h / 2.0, 0), size, STONE_FLOOR.lightened(0.1), faces)


# A wall torch: the hand torch (models/Weapons/hand_torch.glb, grip at the origin, 0.65 m) in an iron bracket, leaning out
# from the wall, burning (fire_fx.gd, which also flickers its light).
const TORCH_MODEL := "res://models/Weapons/hand_torch.glb"
const TORCH_HEAD := 0.47   # the torch's head above its grip


func _add_torch(c: int, r: int) -> void:
	var toward := Vector3.ZERO
	for n in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
		if not is_open(c + n[0], r + n[1]):
			toward = Vector3(n[0], 0, n[1])
			break
	var torch := Node3D.new()
	torch.name = "WallTorch%d" % (_torches.size() + 1)
	torch.position = Vector3((c + 0.5) * CELL, 2.2, (r + 0.5) * CELL) + toward * (CELL / 2.0 - 0.18)
	_keep(torch)
	if toward != Vector3.ZERO:
		torch.look_at(torch.global_position - toward, Vector3.UP)   # -Z away from the wall
	var bracket := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, 0.3)
	bracket.mesh = box
	bracket.position = Vector3(0, -0.05, 0.1)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.11, 0.1)
	iron.metallic = 0.7
	iron.roughness = 0.6
	bracket.material_override = iron
	torch.add_child(bracket)
	var lean := Node3D.new()
	lean.rotation.x = deg_to_rad(-25.0)   # the head leans out from the wall
	torch.add_child(lean)
	if ResourceLoader.exists(TORCH_MODEL):
		lean.add_child((load(TORCH_MODEL) as PackedScene).instantiate())
	var light := OmniLight3D.new()
	light.position = Vector3(0, TORCH_HEAD + 0.15, 0)
	light.light_color = TORCH_COLOR
	light.light_energy = 2.0
	light.omni_range = 13.0
	light.omni_attenuation = 1.2
	lean.add_child(light)
	_torches.append(light)
	if DisplayServer.get_name() != "headless" and not Engine.is_editor_hint():
		var fire := FireFX.new()
		fire.size = 0.35
		fire.smoke = false
		fire.position = Vector3(0, TORCH_HEAD, 0)
		lean.add_child(fire)


func _keep(node: Node) -> void:
	node.set_meta("built", true)
	add_child(node)   # no owner: rebuilt every load, never saved into the scene
