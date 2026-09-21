# patch_loader.gd — the FIRST autoload (project.godot lists it before everything else). Applies a downloaded game update
# before any other game script is loaded, so the update can replace those scripts, scenes and data files.
#
# How updates work (see game_updater.gd and tools/update.sh): a "patch" is a small .pck holding only the files that changed
# since the full build (the "base") a player installed. game_updater.gd downloads it to user://patches/pending.pck (+ .json);
# it can't replace the pack that is currently in use (Windows locks it), so THIS script swaps it in at the next start and
# mounts it. Godot runs each autoload's _init() before it loads the next autoload's script, which is what makes this work.
#
# Keep this file tiny and dependency-free: it lives in the base build, so it can never itself be updated by a patch
# (neither can project.godot, the executable or the native libraries — those need a new full build).
#
# Skipped in the editor. `--no-patch` on the command line starts the plain base build (an escape hatch if a patch ever
# misbehaves); deleting the "patches" folder in the game's user data folder does the same permanently.
extends Node

const DIR := "user://patches"
const CURRENT := DIR + "/current.pck"
const CURRENT_INFO := DIR + "/current.json"
const PENDING := DIR + "/pending.pck"
const PENDING_INFO := DIR + "/pending.json"

## The stamp of the FULL build this install came from (read before any patch is mounted). "" for an unstamped build.
var base_stamp := ""
## The stamp of the patch that is mounted right now ("" = running the plain base build).
var patch_stamp := ""


func _init() -> void:
	base_stamp = _stamp_from("res://Data/build_info.json")
	if OS.has_feature("editor") or "--no-patch" in OS.get_cmdline_args() or "--no-patch" in OS.get_cmdline_user_args():
		return
	_swap_in_pending()
	_mount_current()


func _mount_current() -> void:
	if not FileAccess.file_exists(CURRENT) or not FileAccess.file_exists(CURRENT_INFO):
		return
	var info = JSON.parse_string(FileAccess.get_file_as_string(CURRENT_INFO))
	# A patch only fits the base it was made against; a newer full build makes an old patch obsolete.
	if typeof(info) != TYPE_DICTIONARY or str(info.get("base", "")) != base_stamp or FileAccess.get_sha256(CURRENT) != str(info.get("sha256", "")):
		push_warning("Discarding the downloaded update: it does not match this build (or the file is damaged).")
		_discard(CURRENT, CURRENT_INFO)
		return
	if ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(CURRENT), true):
		patch_stamp = str(info.get("stamp", ""))
		print("Update applied: build %s (patch on top of %s)" % [patch_stamp, base_stamp])
	else:
		push_warning("The downloaded update could not be loaded.")


# A finished download waits as pending.* until the next start; this puts it in place of the previous patch.
func _swap_in_pending() -> void:
	if not FileAccess.file_exists(PENDING) or not FileAccess.file_exists(PENDING_INFO):
		return
	_discard(CURRENT, CURRENT_INFO)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(PENDING), ProjectSettings.globalize_path(CURRENT))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(PENDING_INFO), ProjectSettings.globalize_path(CURRENT_INFO))


func _discard(pack: String, info: String) -> void:
	for path in [pack, info]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _stamp_from(path: String) -> String:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return str(data.get("build", "")) if typeof(data) == TYPE_DICTIONARY else ""
