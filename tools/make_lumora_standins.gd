# make_lumora_standins.gd — stand-in buildings for Lumora's districts (2026-09-26; the user: "i'll make some models, but
# please put some stand-ins for now"). Each building is its own scene in Scenes/props/lumora/ (sandstone walls with a
# doorway, a flat roof, solid collision and its name on a sign over the door), so it can be moved in the editor or swapped
# for the real model later without touching the zone. It also works out where each goes: behind its district marker with
# the door facing the marker (so guard patrols, which walk to the markers, stay in the open), and where the NPCs stand, in
# front of the door, and writes that to Data/lumora_standins_placement.json for tools/place_lumora_standins.py.
#   godot --headless --path . --script res://tools/make_lumora_standins.gd            (new stand-ins only)
#   godot --headless --path . --script res://tools/make_lumora_standins.gd -- --force (rebuild every stand-in scene)
# An existing scene is never overwritten without --force: once you've put the real model in it, it stays. Afterwards re-bake the navmesh (tools/bake_lumora_navmesh.gd) so monsters and guards walk round the new walls.
extends SceneTree

const OUT_DIR := "res://Scenes/props/lumora"
const WALL := 0.6
const DOOR_W := 3.2
const DOOR_H := 3.6
const SANDSTONE := Color(0.84, 0.74, 0.56)
const ROOF := Color(0.62, 0.45, 0.32)
const DARK := Color(0.42, 0.38, 0.34)

# id, sign, size (width, height, depth), zone, [marker x, z], facing point [x, z] (where the door looks), wall colour
const BUILDINGS := [
	["sunlit_rest", "The Sunlit Rest", Vector3(16, 7, 12), "lumora", [120, 300], [0, 300], SANDSTONE],
	["oasisheart_citadel", "Oasisheart Citadel", Vector3(30, 12, 22), "lumora", [0, 170], [0, 290], SANDSTONE],
	["hall_of_arms", "Hall of Arms", Vector3(16, 8, 12), "lumora", [70, 165], [0, 165], SANDSTONE],
	["courthouse", "Courthouse", Vector3(14, 8, 12), "lumora", [60, 215], [0, 215], SANDSTONE],
	["lycaeum_annex", "Lycaeum Annex", Vector3(16, 9, 12), "lumora", [-110, 120], [0, 120], SANDSTONE],
	["temple_of_the_dawn", "Temple of the Dawn", Vector3(18, 10, 14), "lumora", [-230, 132], [-230, 100], SANDSTONE],
	["old_town_lodge", "The Lantern Lodge", Vector3(14, 7, 12), "lumora", [300, 110], [0, 110], DARK],
	["cisterns_entrance", "The Cisterns", Vector3(7, 4, 6), "lumora", [330, 80], [0, 80], DARK],
	["ralphs_last_round", "Ralph's Last Round", Vector3(12, 6, 10), "lumora_outskirts", [68, 40], [68, 14], SANDSTONE],
	["solaris_vault", "Solaris Vault", Vector3(14, 9, 12), "lumora", [0, 80], [0, 290], DARK],
	["caravanserai", "The Caravanserai", Vector3(26, 7, 20), "lumora", [610, 180], [785, 180], SANDSTONE],
	["wayfarers_lodge", "Wayfarers' Lodge", Vector3(14, 7, 10), "lumora", [560, 250], [560, 180], SANDSTONE],
	["paladins_vigil", "The Paladin's Vigil", Vector3(4, 7, 4), "lumora", [0, 260], [0, 290], SANDSTONE],
]
const STATUES := ["paladins_vigil"]   # a statue on a plinth, not a building: stands on its marker
const GAP := 1.5   # between the marker and the front wall


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var placement := {}
	for b in BUILDINGS:
		var id: String = b[0]
		var size: Vector3 = b[2]
		var path := "%s/%s.tscn" % [OUT_DIR, id]
		# never overwrite a scene that's already there (it may hold the real model by now) unless asked: -- --force
		if not ResourceLoader.exists(path) or OS.get_cmdline_user_args().has("--force"):
			var root := _build_statue(id, b[1], size, b[6]) if STATUES.has(id) else _build(id, b[1], size, b[6])
			var packed := PackedScene.new()
			packed.pack(root)
			ResourceSaver.save(packed, path)
			root.free()
		var marker := Vector3(float(b[4][0]), 0.0, float(b[4][1]))
		var face := Vector3(float(b[5][0]), 0.0, float(b[5][1])) - marker
		face = face.normalized() if face.length() > 0.01 else Vector3(0, 0, 1)
		var basis := Basis(Vector3.UP, atan2(face.x, face.z))      # the building's +Z (its door) turned to `face`
		var center := marker if STATUES.has(id) else marker - face * (size.z * 0.5 + GAP)
		var npc_basis := basis                                     # NPCs by the door look out the same way
		placement[id] = {
			"scene": path, "zone": b[3], "sign": b[1],
			"transform": var_to_str(Transform3D(basis, center)),
			# spots in front of the door, left to right along the front: for the NPCs who work there
			"spots": [
				var_to_str(Transform3D(npc_basis, marker + basis.x * -3.0)),
				var_to_str(Transform3D(npc_basis, marker + basis.x * 3.0)),
				var_to_str(Transform3D(npc_basis, marker + basis.x * -6.0)),
				var_to_str(Transform3D(npc_basis, marker + basis.x * 6.0)),
			],
		}
		print("BUILT %s at %s facing %s" % [path, center.round(), face.snapped(Vector3.ONE * 0.01)])
	var f := FileAccess.open("res://Data/lumora_standins_placement.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(placement, "\t"))
	f.close()
	quit()


func _build(id: String, sign_text: String, size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	var body := StaticBody3D.new()
	body.name = "Walls"
	root.add_child(body)
	body.owner = root
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = color
	wall_mat.roughness = 0.95
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = ROOF
	roof_mat.roughness = 0.9
	var w := size.x
	var h := size.y
	var d := size.z
	var door := minf(DOOR_W, w - 2.0 * WALL - 0.5)
	var door_h := minf(DOOR_H, h - 0.6)
	var side := (w - door) * 0.5
	var parts := [
		# [name, size, centre, material]
		["Back", Vector3(w, h, WALL), Vector3(0, h * 0.5, -d * 0.5 + WALL * 0.5), wall_mat],
		["Left", Vector3(WALL, h, d), Vector3(-w * 0.5 + WALL * 0.5, h * 0.5, 0), wall_mat],
		["Right", Vector3(WALL, h, d), Vector3(w * 0.5 - WALL * 0.5, h * 0.5, 0), wall_mat],
		["FrontLeft", Vector3(side, h, WALL), Vector3(-w * 0.5 + side * 0.5, h * 0.5, d * 0.5 - WALL * 0.5), wall_mat],
		["FrontRight", Vector3(side, h, WALL), Vector3(w * 0.5 - side * 0.5, h * 0.5, d * 0.5 - WALL * 0.5), wall_mat],
		["Lintel", Vector3(door, h - door_h, WALL), Vector3(0, door_h + (h - door_h) * 0.5, d * 0.5 - WALL * 0.5), wall_mat],
		["Roof", Vector3(w + 0.8, 0.5, d + 0.8), Vector3(0, h + 0.25, 0), roof_mat],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.name = p[0]
		var box := BoxMesh.new()
		box.size = p[1]
		mi.mesh = box
		mi.material_override = p[3]
		mi.position = p[2]
		root.add_child(mi)
		mi.owner = root
		var col := CollisionShape3D.new()
		col.name = "%sShape" % p[0]
		var shape := BoxShape3D.new()
		shape.size = p[1]
		col.shape = shape
		col.position = p[2]
		body.add_child(col)
		col.owner = root
	var label := Label3D.new()
	label.name = "Sign"
	label.text = sign_text
	label.font_size = 64
	label.outline_size = 12
	label.modulate = Color(1.0, 0.93, 0.75)
	label.position = Vector3(0, door_h + 0.9, d * 0.5 + 0.05)
	root.add_child(label)
	label.owner = root
	root.set_meta("stand_in", true)   # replace with the real model when it exists (outstanding_items.txt, MISSING ASSETS)
	return root


# A plinth and a standing figure-shaped column (the Paladin's Vigil): solid, with its name above.
func _build_statue(id: String, sign_text: String, size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	var body := StaticBody3D.new()
	body.name = "Stone"
	root.add_child(body)
	body.owner = root
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.lightened(0.15)
	mat.roughness = 0.8
	var parts := [
		["Plinth", Vector3(size.x, 1.2, size.z), Vector3(0, 0.6, 0)],
		["Figure", Vector3(size.x * 0.35, size.y - 2.2, size.x * 0.3), Vector3(0, 1.2 + (size.y - 2.2) * 0.5, 0)],
		["Head", Vector3(size.x * 0.22, 0.7, size.x * 0.22), Vector3(0, size.y - 0.65, 0)],
		["Blade", Vector3(0.2, size.y * 0.55, 0.1), Vector3(size.x * 0.28, 1.2 + size.y * 0.3, 0.2)],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.name = p[0]
		var box := BoxMesh.new()
		box.size = p[1]
		mi.mesh = box
		mi.material_override = mat
		mi.position = p[2]
		root.add_child(mi)
		mi.owner = root
		var col := CollisionShape3D.new()
		col.name = "%sShape" % p[0]
		var shape := BoxShape3D.new()
		shape.size = p[1]
		col.shape = shape
		col.position = p[2]
		body.add_child(col)
		col.owner = root
	var label := Label3D.new()
	label.name = "Sign"
	label.text = sign_text
	label.font_size = 56
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, size.y + 1.0, 0)
	root.add_child(label)
	label.owner = root
	root.set_meta("stand_in", true)
	return root
