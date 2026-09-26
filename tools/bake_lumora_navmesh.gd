# bake_lumora_navmesh.gd
# Re-bakes a zone's navmesh from its collision (every static collider in the zone, including the building collision
# Scripts/structure_collision.gd adds at load) plus every visible
# Terrain3D in the zone, and saves it to the navmesh file the scene uses. Run it after changing the zone's geometry:
#   godot --headless --path . --script res://tools/bake_lumora_navmesh.gd                    Lumora Outskirts (Terrain3D)
#   godot --headless --path . --script res://tools/bake_lumora_navmesh.gd -- flat            the old flat zone (archived)
#   godot --headless --path . --script res://tools/bake_lumora_navmesh.gd -- res://Scenes/x.tscn   any zone
# The navmesh is saved to whatever file the scene's NavigationRegion3D already points at (Lumora Outskirts:
# Data/lumora_outskirts_terrain_navmesh.tres; the old flat zone: Data/lumora_outskirts_navmesh.tres), so baking one zone never
# overwrites another's. For the flat zone, run tools/regen_lumora_collision.gd first (stale collision = stale navmesh);
# tools/regen_lumora_collision.sh does both. The Terrain3D surface is added the same way Terrain3D's own editor baker
# does it (addons/terrain_3d/menu/baker.gd). Takes a few seconds; "Parameter material is null" errors are headless
# debug-draw noise. (Cell size, agent size and the STATIC_COLLIDERS source type are stored in the .tres itself.)
extends SceneTree

const DEFAULT_SCENE := "res://Scenes/lumora_outskirts3d.tscn"
const FLAT_SCENE := "res://Scenes/lumora_outskirts3d_flat.tscn"


func _initialize() -> void:
	await process_frame
	var scene_path := DEFAULT_SCENE
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		scene_path = FLAT_SCENE if args[0] == "flat" else args[0]
	Engine.set_meta("navmesh_baking", true)   # dungeon_builder.gd: furniture baked as solid to the ceiling (no walkable tops)
	var zone: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(zone)
	await create_timer(1.0).timeout
	var region := zone.get_node("NavigationRegion3D") as NavigationRegion3D
	var nav_mesh: NavigationMesh = region.navigation_mesh
	var save_path := nav_mesh.resource_path
	var old_uid := _file_uid(save_path)
	print("Baking %s -> %s (before: %d polygons)" % [scene_path, save_path, nav_mesh.get_polygon_count()])
	var started := Time.get_ticks_msec()

	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, zone)  # every static collider in the zone, incl. structure_collision.gd's
	var terrains := 0
	for terrain in zone.find_children("*", "Terrain3D", true, false):  # anywhere in the zone (usually the scene root)
		if not terrain.visible:
			continue
		var aabb: AABB = nav_mesh.filter_baking_aabb
		aabb.position += nav_mesh.filter_baking_aabb_offset
		aabb = region.global_transform * aabb
		# require_nav false = the whole terrain is walkable. Once navigation is painted with Terrain3D's Navigation tool, pass
		# true to bake only the painted areas.
		var faces: PackedVector3Array = terrain.generate_nav_mesh_source_geometry(aabb, false)
		if not faces.is_empty():
			source.add_faces(faces, Transform3D.IDENTITY)
			terrains += 1
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)

	if nav_mesh.get_polygon_count() == 0:
		printerr("Navmesh bake came out empty — nothing saved.")
		quit(1)
		return
	var err := ResourceSaver.save(nav_mesh, save_path)
	if err == OK and not old_uid.is_empty():
		_restore_uid(save_path, old_uid)
	print("Navmesh baked in %.1f s (%d Terrain3D surface%s included): %d vertices, %d polygons. Saved: %s" % [
		(Time.get_ticks_msec() - started) / 1000.0, terrains, "" if terrains == 1 else "s",
		nav_mesh.get_vertices().size(), nav_mesh.get_polygon_count(), str(err == OK)])
	quit(0 if err == OK else 1)


# A script run (--script) saves without the editor's UID cache, which drops the file's uid="..." — and the zone scene
# refers to the navmesh by that uid. Put the old one back into the saved file's header.
func _file_uid(path: String) -> String:
	var header := FileAccess.get_file_as_string(path).get_slice("\n", 0)
	var found := RegEx.create_from_string('uid="(uid://[a-z0-9]+)"').search(header)
	return found.get_string(1) if found else ""


func _restore_uid(path: String, uid: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var header := text.get_slice("\n", 0)
	if header.contains("uid="):
		return
	var fixed := header.trim_suffix("]") + ' uid="%s"]' % uid
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(fixed + text.substr(header.length()))
	f.close()
