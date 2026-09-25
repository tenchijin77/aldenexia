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


# ── The world's zones (Data/zones.json) ──
const ZONES_PATH := "res://Data/zones.json"
static var _zones: Dictionary = {}


static func zones() -> Dictionary:
	if _zones.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ZONES_PATH)) if FileAccess.file_exists(ZONES_PATH) else null
		_zones = parsed.get("zones", {}) if typeof(parsed) == TYPE_DICTIONARY else {}
	return _zones


static func exists(id: String) -> bool:
	return zones().has(id)


static func scene_for(id: String) -> String:
	return str(zones().get(id, zones().get(DEFAULT_ID, {})).get("scene", "res://Scenes/lumora_outskirts3d.tscn"))


static func name_for(id: String) -> String:
	return str(zones().get(id, {}).get("name", id.replace("_", " ").capitalize()))


# The port a zone's server listens on: the login server's port plus the zone's offset.
static func port_for(id: String, base_port: int) -> int:
	return base_port + int(zones().get(id, {}).get("port_offset", 0))


# The zone a saved character is in ("zone"; characters from before zones are in the starting zone).
static func of_character(data: Dictionary) -> String:
	var id := str(data.get("zone", ""))
	return id if exists(id) else DEFAULT_ID


# The zone's monster spawn file (Data/<zone>_spawns.json). A zone without one simply has no monsters yet.
static func spawns_path(id: String = "") -> String:
	return "res://Data/%s_spawns.json" % (current_id() if id.is_empty() else id)
