# server_notice.gd — Notices to every player, and the dedicated server's "an update is coming" countdown.
#
# NOTICE: a big red message in the middle of the screen (it fades after a few seconds) that is also written to the chat. The server sends it
# with broadcast(); every player's game shows it. GM command: /announce <text>.
#
# MAINTENANCE (dedicated server only): start_maintenance(minutes) announces the update, refuses new logins (Net.maintenance_pending), sends
# reminders (3 min, 1 min, 30 s, 10 s), and takes the server down through the ordinary graceful shutdown (every player's character is saved
# first): as soon as nobody is logged in, or when the time is up. It is started by the GM command /maintenance [minutes] or by a request
# file the update script writes (Net.maintenance_file; it contains the minutes, or "cancel"), so it works with no one logged in.
# The words are in Data/server_notices.json. The scene node lives in the zone next to GMRelay: its RPC is on a scene node, not on Net,
# because the RPC list of the Net autoload must not change between released builds.
extends Node

const NOTICES_PATH := "res://Data/server_notices.json"
const BANNER_LAYER := 90
const POLL_SECONDS := 1.0
const STALE_REQUEST_SECONDS := 900.0   # a request file older than this is ignored (the update script that wrote it is long gone)

var _cfg: Dictionary = {}
var _active := false
var _deadline_msec := 0
var _reminders: Array = []
var _poll := 0.0
var _finishing := false

var _banner: CanvasLayer = null
var _label: Label = null
var _strip: ColorRect = null
var _tween: Tween = null


func _ready() -> void:
	add_to_group("server_notice")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(NOTICES_PATH)) if FileAccess.file_exists(NOTICES_PATH) else null
	_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	if Net.is_dedicated_server and FileAccess.file_exists(Net.maintenance_file):
		DirAccess.remove_absolute(Net.maintenance_file)   # a request left over from before this server started must not take it down again
		Net._slog("Ignored a stale update request left in %s." % Net.maintenance_file)


func _pick(key: String, time_text: String = "") -> String:
	var lines: Array = _cfg.get(key, [])
	if lines.is_empty():
		return ""
	return str(lines[randi() % lines.size()]).replace("{time}", time_text)


static func time_text(seconds: float) -> String:
	if seconds >= 90.0:
		var minutes := int(round(seconds / 60.0))
		return "%d minute%s" % [minutes, "" if minutes == 1 else "s"]
	var whole := maxi(int(round(seconds)), 1)
	return "%d second%s" % [whole, "" if whole == 1 else "s"]


# ── Sending a notice (the server / host / single-player decides; everyone shows it) ──
func broadcast(text: String, seconds: float = -1.0) -> void:
	if text.is_empty():
		return
	var shown_for := seconds if seconds > 0.0 else float(_cfg.get("banner_seconds", 9))
	_show(text, shown_for)
	if Net.is_multiplayer_game and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_notice.rpc(text, shown_for)


@rpc("authority", "call_remote", "reliable")
func _rpc_notice(text: String, seconds: float) -> void:
	_show(text, seconds)


func _show(text: String, seconds: float) -> void:
	if Net.is_dedicated_server:
		Net._slog("Notice: %s" % text)
		return
	GameLog.log_general("[color=#ff4040][b]%s[/b][/color]" % text)
	_ensure_banner()
	_label.text = text
	_banner.visible = true
	if _tween != null:
		_tween.kill()
	_banner.get_child(0).modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_banner.get_child(0), "modulate:a", 1.0, 0.5)
	_tween.tween_interval(maxf(seconds - 2.0, 1.0))
	_tween.tween_property(_banner.get_child(0), "modulate:a", 0.0, 1.5)
	_tween.tween_callback(func() -> void: _banner.visible = false)


func _ensure_banner() -> void:
	if is_instance_valid(_banner):
		return
	_banner = CanvasLayer.new()
	_banner.layer = BANNER_LAYER
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(holder)
	# a dark red band behind the words so they read against any sky
	_strip = ColorRect.new()
	_strip.color = Color(0.12, 0.0, 0.0, 0.55)
	_strip.anchor_left = 0.0
	_strip.anchor_right = 1.0
	_strip.anchor_top = 0.16
	_strip.anchor_bottom = 0.16
	_strip.offset_top = -10.0
	_strip.offset_bottom = 110.0
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_strip)
	_label = Label.new()
	_label.anchor_left = 0.12
	_label.anchor_right = 0.88
	_label.anchor_top = 0.16
	_label.anchor_bottom = 0.16
	_label.offset_bottom = 100.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.16))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_label.add_theme_constant_override("outline_size", 8)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_label)
	get_tree().root.add_child(_banner)
	_banner.visible = false


# ── The update countdown (dedicated server) ──
func is_maintenance_active() -> bool:
	return _active


# Returns a line for whoever asked (a GM's chat, the server log).
func start_maintenance(minutes: float) -> String:
	if not Net.is_dedicated_server:
		return "Only a dedicated server can be taken down this way."
	if _active:
		return "An update countdown is already running (/maintenance cancel to stop it)."
	minutes = clampf(minutes, 0.0, 60.0)
	_active = true
	_finishing = false
	Net.maintenance_pending = true
	_deadline_msec = Time.get_ticks_msec() + int(minutes * 60000.0)
	_reminders = []
	for seconds in _cfg.get("reminder_seconds", [180, 60, 30, 10]):
		if float(seconds) < minutes * 60.0 - 1.0:
			_reminders.append(float(seconds))
	_reminders.sort()
	_reminders.reverse()
	var players := Net.logged_in_count()
	Net._slog("Maintenance: the server goes down in %s (%d player(s) online); new logins are refused." % [time_text(minutes * 60.0), players])
	if players > 0:
		broadcast(_pick("start", time_text(minutes * 60.0)))
	return "The server goes down for an update in %s, sooner if everyone logs out (%d online)." % [time_text(minutes * 60.0), players]


func cancel_maintenance() -> String:
	if not _active:
		return "No update countdown is running."
	_active = false
	Net.maintenance_pending = false
	Net._slog("Maintenance cancelled.")
	broadcast(_pick("cancelled"))
	return "The update countdown is cancelled."


func _process(delta: float) -> void:
	if not Net.is_dedicated_server or not is_multiplayer_authority():
		return
	_poll += delta
	if _poll >= POLL_SECONDS:
		_poll = 0.0
		_check_request_file()
	if not _active or _finishing:
		return
	var remaining := float(_deadline_msec - Time.get_ticks_msec()) / 1000.0
	if Net.logged_in_count() == 0:
		_finish(false)   # nobody to wait for
		return
	while not _reminders.is_empty() and remaining <= float(_reminders[0]):
		_reminders.pop_front()
		broadcast(_pick("reminder", time_text(maxf(remaining, 1.0))))
	if remaining <= 0.0:
		_finish(true)


# The update script (or you, by hand) creates this file; its content is the minutes to wait, or "cancel".
func _check_request_file() -> void:
	var path: String = Net.maintenance_file
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path).strip_edges().to_lower()
	var age := Time.get_unix_time_from_system() - float(FileAccess.get_modified_time(path))
	DirAccess.remove_absolute(path)
	if age > STALE_REQUEST_SECONDS:
		Net._slog("Ignored an update request that is %d minutes old." % int(age / 60.0))
		return
	if text == "cancel":
		cancel_maintenance()
		return
	var minutes := text.to_float() if text.is_valid_float() else float(_cfg.get("default_minutes", 5))
	Net._slog("Maintenance requested (%s)." % start_maintenance(minutes))


func _finish(had_players: bool) -> void:
	_finishing = true
	if had_players:
		broadcast(_pick("final"), 6.0)
		await get_tree().create_timer(2.5).timeout   # let the last notice reach everyone
	Net._slog("Maintenance: shutting down now.")
	Net.begin_shutdown()
