# zone_info.gd — which zone is loaded, for the data files that are keyed by zone (spawns, crafting placements, ley-lines,
# perception spots, world objects). A zone scene's root (multiplayer_player_spawner.gd) carries "zone_id"; a scene without
# one falls back to its file name ("lumora_outskirts3d.tscn" -> "lumora_outskirts"). New zones start from
# Scenes/zones/zone_template.tscn (the notes are at the top of Scenes/zones/README.txt).
class_name ZoneInfo
extends RefCounted

const DEFAULT_ID := "lumora_outskirts"


static func current_id() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	return id_of_scene(tree.current_scene if tree != null else null)


# The zone a node belongs to (the scene root that owns it) — right even when the zone isn't the current scene (tools
# that load a zone as a child, like the navmesh baker).
static func id_for(node: Node) -> String:
	var root: Node = node.owner if node != null and node.owner != null else node
	while root != null and root.get("zone_id") == null and root.owner != null:
		root = root.owner
	return id_of_scene(root) if root != null and root.get("zone_id") != null else current_id()


static func id_of_scene(scene: Node) -> String:
	if scene == null:
		return DEFAULT_ID
	var id := str(scene.get("zone_id")) if scene.get("zone_id") != null else ""
	if not id.is_empty():
		return id
	var base := scene.scene_file_path.get_file().get_basename()
	if base.is_empty():
		return DEFAULT_ID
	return base.left(base.length() - 2) if base.ends_with("3d") else base


# The zone's monster spawn file (Data/<zone>_spawns.json). A zone without one simply has no monsters yet.
static func spawns_path(id: String = "") -> String:
	return "res://Data/%s_spawns.json" % (current_id() if id.is_empty() else id)
