# game_updater.gd — downloads game updates from a server's update address and stages them for patch_loader.gd.
#
# The whole scheme (tools/update.sh does the publishing side):
#   * The developer publishes, next to the game server, a small signed "manifest.json" plus a patch .pck (only the
#     files that changed since the full build players installed — the "base").
#   * check() fetches manifest.json + manifest.sig over plain HTTP and verifies the signature against the public key
#     baked into the game (Data/update_public_key.json). An update is CODE that runs on the player's PC, so nothing
#     unsigned is ever accepted — HTTP is fine because the signature (and the patch's sha256 inside the manifest) prove
#     it is genuine and complete.
#   * download() saves the patch as user://patches/pending.pck (+ pending.json), checks its size and sha256, and
#     restart() relaunches the game; patch_loader.gd swaps the patch in and mounts it before any script loads.
# Anything a patch cannot carry (a new version number in project.godot, the executable, native libraries, patch_loader
# itself) makes check() answer "full_build_required": the player needs a fresh full download.
class_name GameUpdater
extends Node

signal progress(received: int, total: int)

const KEY_PATH := "res://Data/update_public_key.json"
const DEFAULT_PORT := 8911
const MANIFEST_FORMAT := 1
const REQUEST_TIMEOUT := 15.0
const STALL_SECONDS := 30.0
const PENDING := "user://patches/pending.pck"
const PENDING_PART := "user://patches/pending.pck.part"
const PENDING_INFO := "user://patches/pending.json"

var manifest: Dictionary = {}
var _base_url := ""


# "http://host:port" for a server address, unless a full update_url was configured (Data/servers.json).
static func url_for(address: String, update_port: int = DEFAULT_PORT, update_url: String = "") -> String:
	if not update_url.is_empty():
		return update_url.trim_suffix("/")
	return "http://%s:%d" % [address, update_port]


# Asks the update address what the newest published update is. Returns {status, message, manifest} where status is:
#   "available"           an update for this base exists (manifest holds it; call download())
#   "up_to_date"          this game is already at the published build
#   "full_build_required" the published update can't be applied to this install (different base or version)
#   "error"               unreachable / bad signature / malformed
func check(base_url: String) -> Dictionary:
	_base_url = base_url.trim_suffix("/")
	manifest = {}
	var m := await _fetch(_base_url + "/manifest.json")
	if not m.ok:
		return _result("error", "Could not reach the update server (%s)." % m.error)
	var s := await _fetch(_base_url + "/manifest.sig")
	if not s.ok:
		return _result("error", "The update server has no signature for its update (%s)." % s.error)
	if not _signature_valid(m.body, s.body):
		return _result("error", "The update's signature is not valid, so it will not be installed.")
	var parsed = JSON.parse_string(m.body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("format", 0)) != MANIFEST_FORMAT:
		return _result("error", "The update information is not in a format this game understands. A newer full build may be needed.")
	manifest = parsed
	var published_stamp := str(manifest.get("stamp", ""))
	if str(manifest.get("version", "")) != GameVersion.version():
		return _result("full_build_required", "The latest update is for game version %s and this is %s: it needs a new full download, not a patch." % [manifest.get("version", "?"), GameVersion.version()])
	if str(manifest.get("base", "")) != PatchLoader.base_stamp:
		return _result("full_build_required", "The latest update was made for a newer full build (%s) than the one you installed (%s). Download the new full build." % [manifest.get("base", "?"), PatchLoader.base_stamp])
	if published_stamp == GameVersion.build_id():
		return _result("up_to_date", "Your game is already at the latest build (%s)." % published_stamp)
	if int(manifest.get("commit_count", 0)) < _my_commit_count():
		return _result("error", "The published update (%s) is older than your build; not going backwards." % published_stamp)
	if str(manifest.get("patch_file", "")).is_empty():
		return _result("full_build_required", "The published build (%s) has no patch for your install." % published_stamp)
	return _result("available", "Update available: %s." % published_stamp)


# Downloads the manifest's patch to user://patches/pending.* — returns {ok, message}. Progress is emitted as it goes.
func download() -> Dictionary:
	if manifest.is_empty() or str(manifest.get("patch_file", "")).is_empty():
		return {"ok": false, "message": "There is no update to download; check first."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://patches"))
	for path in [PENDING, PENDING_PART, PENDING_INFO]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var expected_size := int(manifest.get("patch_size", 0))
	var req := HTTPRequest.new()
	req.download_file = PENDING_PART
	req.timeout = 0.0  # a big file may legitimately take long; the stall watchdog below catches a dead connection
	add_child(req)
	var err := req.request(_base_url + "/" + str(manifest["patch_file"]))
	if err != OK:
		req.queue_free()
		return {"ok": false, "message": "Could not start the download."}
	var last_bytes := -1
	var last_change := Time.get_ticks_msec()
	# A dictionary, not plain variables: a lambda captures locals by value, so it could never report back through them.
	var state := {"done": false, "result": -1, "code": 0}
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		state["result"] = result
		state["code"] = code
		state["done"] = true)
	while not state["done"]:
		await get_tree().create_timer(0.2).timeout
		var got := req.get_downloaded_bytes()
		if got != last_bytes:
			last_bytes = got
			last_change = Time.get_ticks_msec()
			progress.emit(got, expected_size)
		elif Time.get_ticks_msec() - last_change > STALL_SECONDS * 1000.0:
			req.cancel_request()
			req.queue_free()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_PART))
			return {"ok": false, "message": "The download stalled."}
	req.queue_free()
	if state["result"] != HTTPRequest.RESULT_SUCCESS or state["code"] != 200:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_PART))
		return {"ok": false, "message": "The download failed (%s)." % ("HTTP %d" % state["code"] if state["result"] == HTTPRequest.RESULT_SUCCESS else "connection error %d" % state["result"])}
	var part := ProjectSettings.globalize_path(PENDING_PART)
	if expected_size > 0 and FileAccess.get_file_as_bytes(PENDING_PART).size() != expected_size:
		DirAccess.remove_absolute(part)
		return {"ok": false, "message": "The download is incomplete. Try again."}
	var sha := FileAccess.get_sha256(PENDING_PART)
	if sha != str(manifest.get("patch_sha256", "")):
		DirAccess.remove_absolute(part)
		return {"ok": false, "message": "The downloaded update is damaged (checksum mismatch). Try again."}
	# pending.pck first, pending.json last: patch_loader.gd needs both, so a half-finished download is never applied.
	DirAccess.rename_absolute(part, ProjectSettings.globalize_path(PENDING))
	var info := FileAccess.open(PENDING_INFO, FileAccess.WRITE)
	info.store_string(JSON.stringify({"base": manifest.get("base", ""), "stamp": manifest.get("stamp", ""), "sha256": sha}))
	info.close()
	progress.emit(expected_size, expected_size)
	return {"ok": true, "message": "Update %s downloaded. The game restarts to apply it." % manifest.get("stamp", "")}


# Quits and starts the game again (the same command line); patch_loader.gd applies the pending patch on the way up.
static func restart(tree: SceneTree) -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	tree.quit()


# Command line: `game --headless -- --update-from=http://host:8911` checks, downloads and stages an update, prints what
# happened and exits. For testing and for anyone who can't reach the Join screen. Returns true when it took over.
static func run_cli_if_requested(host: Node) -> bool:
	var url := ""
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--update-from="):
			url = arg.substr("--update-from=".length())
	if url.is_empty():
		return false
	var updater := GameUpdater.new()
	host.add_child(updater)
	var checked := await updater.check(url)
	print("[update] check: %s — %s" % [checked.status, checked.message])
	var code := 0 if checked.status in ["up_to_date", "available"] else 1
	if checked.status == "available":
		var got := await updater.download()
		print("[update] download: %s — %s" % ["ok" if got.ok else "FAILED", got.message])
		code = 0 if got.ok else 1
	host.get_tree().quit(code)
	return true


func _result(status: String, message: String) -> Dictionary:
	return {"status": status, "message": message, "manifest": manifest}


func _my_commit_count() -> int:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://Data/build_info.json")) if FileAccess.file_exists("res://Data/build_info.json") else null
	return int(data.get("commit_count", 0)) if typeof(data) == TYPE_DICTIONARY else 0


func _signature_valid(manifest_bytes: PackedByteArray, signature: PackedByteArray) -> bool:
	var key_data = JSON.parse_string(FileAccess.get_file_as_string(KEY_PATH)) if FileAccess.file_exists(KEY_PATH) else null
	if typeof(key_data) != TYPE_DICTIONARY:
		return false
	var key := CryptoKey.new()
	if key.load_from_string(str(key_data.get("pem", "")), true) != OK:
		return false
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(manifest_bytes)
	return Crypto.new().verify(HashingContext.HASH_SHA256, hashing.finish(), signature, key)


# GET a small file. Returns {ok, body, error}.
func _fetch(url: String) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = REQUEST_TIMEOUT
	add_child(req)
	var err := req.request(url)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "could not start the request"}
	var r: Array = await req.request_completed
	req.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "no connection" if r[0] in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_TIMEOUT] else "request error %d" % r[0]}
	if r[1] != 200:
		return {"ok": false, "error": "HTTP %d" % r[1]}
	return {"ok": true, "body": r[3]}
