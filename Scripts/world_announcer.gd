# world_announcer.gd — "X enters/leaves the world" announcements and the /who
# listing. Pure static helpers (no node needed); the network side lives in
# net.gd (broadcast_world_announce() / the peer_disconnected handler) and the
# joining side in player3d.gd (_announce_world_entry()). Announcement text is
# data — Data/world_announcements.json — so it can be edited without code.
class_name WorldAnnouncer

const DATA_PATH := "res://Data/world_announcements.json"
const JOIN_COLOR := "#ffd27f"
const LEAVE_COLOR := "#b8ad94"
const FALLBACK := {
	"join": ["{name}, the {level} season {class}, enters the world!"],
	"leave": ["{name}, the {level} season {class}, leaves the world."],
}

static var _lines: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _lines.is_empty():
		return
	_lines = FALLBACK.duplicate(true)
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if not file:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for kind in ["join", "leave"]:
		var list = data.get(kind, [])
		if typeof(list) == TYPE_ARRAY and not list.is_empty():
			_lines[kind] = list


# 1 -> "1st", 2 -> "2nd", 11 -> "11th", 22 -> "22nd", 101 -> "101st"
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]


static func format_line(kind: String, pname: String, level: int, cls: String, variant: int) -> String:
	_ensure_loaded()
	var list: Array = _lines.get(kind, FALLBACK["join"])
	var template: String = list[absi(variant) % list.size()]
	return template.replace("{name}", _escape(pname)).replace("{level}", ordinal(level)).replace("{class}", cls.to_lower())


static func announce(kind: String, pname: String, level: int, cls: String, variant: int) -> void:
	var color := JOIN_COLOR if kind == "join" else LEAVE_COLOR
	GameLog.log_general("[color=%s]%s[/color]" % [color, format_line(kind, pname, level, cls, variant)])


# Name/level/class of a player3d node (the local player or a replicated
# puppet — name, level and class are all in player3d.tscn's replication list).
static func player_info(p: Node) -> Dictionary:
	var lvl := 1
	if "combat_node" in p and p.combat_node != null and "level" in p.combat_node:
		lvl = int(p.combat_node.level)
	return {
		"name": str(p.get("player_name")) if "player_name" in p else "Someone",
		"level": lvl,
		"class": str(p.get("player_class")) if "player_class" in p else "",
	}


# "lumora_outskirts3d" -> "Lumora Outskirts" (works for any future zone scene).
static func zone_display_name() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.current_scene:
		return "Unknown"
	var base := tree.current_scene.scene_file_path.get_file().get_basename()
	if base.ends_with("3d"):
		base = base.left(base.length() - 2)
	return base.replace("_", " ").capitalize()


# Lines for /who: every player currently in this world (you included).
static func who_lines(local_player: Node) -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var rows: Array = []
	for node in tree.get_nodes_in_group("player"):
		if not is_instance_valid(node):
			continue
		var info := player_info(node)
		# A puppet that hasn't received its first replicated values yet still
		# carries the scene default — skip that transient state.
		if node != local_player and info["name"] == "Default Hero":
			continue
		info["is_self"] = node == local_player
		rows.append(info)
	rows.sort_custom(func(a, b): return String(a["name"]).to_lower() < String(b["name"]).to_lower())
	var zone := zone_display_name()
	var out: Array[String] = ["[color=#88ccff]Players in Aldenexia (%d):[/color]" % rows.size()]
	for r in rows:
		out.append("  [b]%s[/b] — Level %d %s — %s%s" % [_escape(r["name"]), r["level"], r["class"], zone, " (you)" if r["is_self"] else ""])
	return out


static func print_who(local_player: Node) -> void:
	for line in who_lines(local_player):
		GameLog.log_general(line)


# Player names are free text — keep a stray "[" from being read as BBCode.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
