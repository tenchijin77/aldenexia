# game_version.gd — The game's version, for the main menu label and the
# multiplayer join check (net.gd). Two parts:
#   * version(): the number you bump by hand — Project Settings -> Application ->
#     Config -> Version (project.godot "config/version"), e.g. "0.1.0".
#   * build_id(): the exact git commit an export was made from, stamped into
#     Data/build_info.json by tools/stamp_build.sh right before exporting.
#     Ignored when running from the editor (always "dev") and missing in an
#     unstamped build.
# Two builds can join each other only if the version numbers match, and — when
# BOTH were stamped — their build ids match too (catches "same number, stale
# export"). Editor/unstamped runs only need the numbers to match.
class_name GameVersion

const BUILD_INFO_PATH := "res://Data/build_info.json"

static var _build_id_cache: String = ""
static var _build_id_loaded: bool = false


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func build_id() -> String:
	if not _build_id_loaded:
		_build_id_loaded = true
		# Editor runs are always "dev": a stamp file left over from the last export
		# would otherwise make them look like that old commit and get refused by a
		# newer stamped build.
		var file := FileAccess.open(BUILD_INFO_PATH, FileAccess.READ) if not OS.has_feature("editor") else null
		if file:
			var data = JSON.parse_string(file.get_as_text())
			file.close()
			if typeof(data) == TYPE_DICTIONARY:
				_build_id_cache = str(data.get("build", ""))
	return _build_id_cache


# "v0.1.0 (1ce742b)", or "v0.1.0 (dev)" from the editor, or just "v0.1.0".
static func display() -> String:
	var text := "v" + version()
	var build := build_id()
	if not build.is_empty():
		text += " (%s)" % build
	elif OS.has_feature("editor"):
		text += " (dev)"
	return text


static func is_compatible(other_version: String, other_build: String) -> bool:
	if other_version != version():
		return false
	var mine := build_id()
	return mine.is_empty() or other_build.is_empty() or mine == other_build
