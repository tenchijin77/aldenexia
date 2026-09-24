# net.gd — Thin wrapper around Godot's high-level multiplayer API (ENet).
# One machine hosts (a listen-server whose own character is spawned like everyone
# else's, or a headless dedicated server with no character — Net.is_dedicated_server);
# everyone else connects to that address by manual entry — no relay/NAT punchthrough.
# Joining loads the zone first and connects from inside it (see begin_join()).
extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed
signal connection_succeeded
signal server_disconnected
## A menu errand (request_server_delete / probe_server) finished: ok, a kind ("online", "deleted", "offline",
## "version", "bad_password"...), a message, and `info` (a probe's name/players/max_players/version).
signal server_request_done(ok: bool, kind: String, reason: String, info: Dictionary)

# Group invite/roster events — player3d.gd's authoritative side listens to
# these (see invite_to_group()/_on_group_invite_response() etc.); the invite
# itself pops a real accept/decline UI (see group_invite_popup.gd) rather
# than joining instantly.
signal group_invite_response_received(responder_peer_id: int, accepted: bool)
signal group_roster_received(peer_ids: Array)
signal group_removed_received(reason: String)

const DEFAULT_PORT := 8910
const MAX_PLAYERS := 6
const VERSION_CHECK_TIMEOUT := 5.0  # seconds a joiner has to send its version before the host drops it
const SERVER_MAX_FPS := 60  # a headless server has no vsync, so uncapped it would spin a core at 100%
const LOGIN_TIMEOUT := 20.0  # seconds a verified joiner has to log a character in before the server drops them
const REMOTE_SAVE_DELAY := 1.0  # a burst of Global.save_player_data_to_file() calls becomes one upload
const MAX_CHARACTER_BYTES := 1_000_000  # refuse absurd uploads; a real save is a few tens of KB
const CHARACTER_DIR := "user://server_characters"  # kept apart from user://saves so the host's own single-player list stays clean
const DELETED_DIR := "user://server_characters/deleted"  # deleted characters are moved here, never erased, so the server owner can undo a mistake
const MIN_PASSWORD_LENGTH := 4
const MAX_LOGIN_FAILURES := 5  # wrong passwords in a row before a character locks
const LOCKOUT_SECONDS := 60
const PASSWORD_HASH_ROUNDS := 5000  # stretches the hash a little; this is a friends' server, not a bank
const MENU_SLOTS := 8  # spare connection slots on a dedicated server for probes/delete errands, so a FULL server still answers "full" rather than looking offline
const MENU_REQUEST_TIMEOUT := 5.0  # seconds a probe/errand waits for the server before calling it offline
const TLS_CN := "aldenexia"  # the name the server certificate is issued for; clients pin the certificate itself
const TRUSTED_CERT_PATHS := ["res://Data/server_cert.crt", "user://server_tls/server.crt"]  # certificates a client will trust (see _client_tls_options)
const SHUTDOWN_GRACE := 8.0  # seconds a shutting-down server waits for players' final saves
const WORLD_SAVE_INTERVAL := 300.0  # seconds between world-state saves while running
const HITCH_LOG_SECONDS := 0.5  # a server frame longer than this is logged ("Long frame") — stalls make clients time out
# ENet gives up on a silent connection after ~5-6 s by default. Measured: a server (or network) stall of 6+ s dropped a client,
# which is easily reached by WiFi power-save/roaming or a starved VM. Both ends now wait longer before declaring the other dead.
# Cost: a really dead peer is noticed after PEER_TIMEOUT_MIN_MS instead of ~5 s (a crashed player's character stays "in the world" that long).
const PEER_TIMEOUT_LIMIT := 32
const PEER_TIMEOUT_MIN_MS := 20000
const PEER_TIMEOUT_MAX_MS := 60000
const CLIENT_HITCH_SECONDS := 1.0  # a frame this long on the PLAYER's machine is logged too (a frozen client also makes the server drop it)
const LINK_LOG_INTERVAL := 30.0  # seconds between the client's "link to server" log lines

var is_multiplayer_game := false
## Why the last join attempt failed, when the host said so (e.g. a version mismatch).
var last_failure_reason := ""
var _unverified_peers: Dictionary = {}  # host only: peer_id -> true until they pass the version check
var pending_zone_path := Global.START_ZONE_PATH

## True while the zone must NOT keep its pre-placed solo/host character: a joiner's own
## character comes from the host's PlayerSpawner instead, and a dedicated server has
## no character at all. player3d.gd checks this in _enter_tree() and frees itself.
var omit_preplaced_player := false
## True on a headless server: it hosts the world but has no character of its own.
var is_dedicated_server := false
## Players allowed in the world at once. A listen-server host takes one of these slots
## for their own character; a dedicated server has no character, so all of them are free.
var max_players := MAX_PLAYERS
## The server's short name; characters on it are stored as "<server_name>_<player>" (e.g. test_zozuur).
var server_name := "server"
# Dedicated server only: peers that passed the version check but haven't logged a character in yet,
# and the character key each logged-in peer owns (peer_id -> "test_zozuur").
var _awaiting_login: Dictionary = {}
var _peer_character: Dictionary = {}
var _last_ip: Dictionary = {}   # peer_id -> address, kept so the disconnect line can still say where they were
## Client side: True while this machine is playing a character that lives on a dedicated server.
## Global.save_player_data_to_file() then uploads to the server instead of writing user://saves.
var remote_character_mode := false
## True from begin_join_server() until the next begin_join()/host: where a failed or dropped join returns to
## (the Join a Server screen instead of the LAN one) and whether the character was a server's, not a local save.
var last_join_was_server := false
## Why the last failed join failed: "" (generic/network), "no_character", "name_taken", "already_online"...
## The Join a Server menu uses it to offer character creation.
var last_failure_kind := ""
## What the last successful login did: "created", "password_set" (an old character got its first password) or "".
var last_login_status := ""
var _login_name := ""
var _login_password := ""
var _login_creation_json := ""
## Server side: character key -> {"count": wrong passwords in a row, "until_ms": locked until this tick}.
var _login_failures: Dictionary = {}
## Server: where the TLS key/certificate live, and the file whose appearance means "shut down gracefully"
## (Godot's headless server can't catch SIGTERM — tools/run_server.sh touches this file when it is signalled).
var tls_dir := "user://server_tls"
var stop_file := "user://server_stop"
var maintenance_file := "user://server_maintenance"   # the update script writes the minutes to wait here (see server_notice.gd)
var banned_ips_file := "user://banned_ips"             # one IP per line (# comments allowed): refused on connect; GMs manage it with /ban, /unban, /bans (gm_commands.gd)
var gm_password_file := "user://gm_password"           # the game-master password (dedicated server): the first non-empty line; read at every attempt, so changing it needs no restart (see gm_commands.gd)
var maintenance_pending := false                        # an update countdown is running: new logins are refused
var _shutting_down := false
var _shutdown_done := false
var _shutdown_waiting: Array = []
var _stop_poll := 0.0
var _world_save_timer := 0.0
## Client: set when the server announced its shutdown, so the "connection lost" screen can say why.
var server_shutdown_notice := ""
var _shutdown_reply_pending := false
var _request_serial := 0
var _last_frame_ms := 0
var _link_log_timer := 0.0
var _last_link_stats := "no reading yet"
## Client side: a one-off errand to a server from a menu (delete a character...) — connect, do it, disconnect,
## no zone. Empty when idle. See request_server_delete().
var _menu_request: Dictionary = {}
var _remote_save_pending := false
var _saves_in_flight := 0  # uploads the server hasn't acknowledged yet
var _pending_join_address := ""
var _pending_join_port := DEFAULT_PORT


func _ready() -> void:
	print("Aldenexia %s" % GameVersion.display())
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Account messages live on this child (created on every peer) so Net's own RPC list never changes — see account_relay.gd.
	var account_relay := AccountRelay.new()
	account_relay.name = "Accounts"
	add_child(account_relay)
	if _wants_dedicated_server():
		_start_dedicated_server.call_deferred()


func accounts() -> AccountRelay:
	return get_node("Accounts") as AccountRelay


# Makes the connection to `peer_id` (1 = the server, from a client) more patient — see PEER_TIMEOUT_MIN_MS.
func _relax_timeouts(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null:
		return
	var link := peer.get_peer(peer_id)
	if link != null:
		link.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)


# Server log lines carry a wall-clock time so a disconnect can be matched to what happened at that moment.
func _slog(msg: String) -> void:
	print("%s [server] %s" % [Time.get_time_string_from_system(), msg])


func _slog_err(msg: String) -> void:
	printerr("%s [server] %s" % [Time.get_time_string_from_system(), msg])


# Client side (playing on a dedicated server): logs this machine's own stalls and the link quality, so a random
# disconnect can be told apart — did the PLAYER's game freeze (this prints a long frame right after), or did the link
# degrade (RTT/loss climbing), or neither (then look at the server's "Long frame" lines).
# Real seconds since the previous frame. NOT the `delta` _process receives: Godot clamps that, so a long stall (a
# frozen VM, a debugger pause) would look like a normal frame and the stall loggers would never fire.
func _real_frame_seconds() -> float:
	var now_ms := Time.get_ticks_msec()
	var seconds := 0.0 if _last_frame_ms == 0 else (now_ms - _last_frame_ms) / 1000.0
	_last_frame_ms = now_ms
	return seconds


func _monitor_client_link(delta: float, frame_seconds: float) -> void:
	if not remote_character_mode:
		return
	var now := Time.get_time_string_from_system()
	if frame_seconds > CLIENT_HITCH_SECONDS:
		print("%s [client] This game stalled for %.1f s (the server drops a client that stops answering for ~30 s)." % [now, frame_seconds])
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_link_log_timer += delta
	if _link_log_timer < LINK_LOG_INTERVAL:
		return
	_link_log_timer = 0.0
	var server_peer := peer.get_peer(1)
	if server_peer == null:
		return
	_last_link_stats = "RTT %d ms (variance %d), packet loss %.2f%%" % [
		int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)),
		int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)),
		float(server_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)) / 65536.0 * 100.0]
	print("%s [client] link to server: %s" % [now, _last_link_stats])


# ── Dedicated server ──────────────────────────────────────────────────────
# `godot --headless --path . -- --server [--name=test] [--port=8910] [--max-players=6]` (or an
# exported binary run the same way, or one built from a dedicated_server export
# preset, which is always a server). Skips the splash and every menu: hosts, then
# loads the zone with no character of its own.
func _wants_dedicated_server() -> bool:
	return OS.has_feature("dedicated_server") or _cmdline_flag("server")


func _cmdline_args() -> PackedStringArray:
	return OS.get_cmdline_args() + OS.get_cmdline_user_args()


func _cmdline_flag(name: String) -> bool:
	return _cmdline_args().has("--" + name)


# Reads `--name=value` or `--name value`; `fallback` if absent.
func _cmdline_value(name: String, fallback: String) -> String:
	var args := _cmdline_args()
	for i in args.size():
		if args[i].begins_with("--%s=" % name):
			return args[i].substr(name.length() + 3)
		if args[i] == "--" + name and i + 1 < args.size():
			return args[i + 1]
	return fallback


func _start_dedicated_server() -> void:
	is_dedicated_server = true
	Engine.max_fps = SERVER_MAX_FPS
	var port := int(_cmdline_value("port", str(DEFAULT_PORT)))
	max_players = clampi(int(_cmdline_value("max-players", str(MAX_PLAYERS))), 1, 64)
	tls_dir = _cmdline_value("tls-dir", tls_dir)
	stop_file = _cmdline_value("stop-file", stop_file)
	maintenance_file = _cmdline_value("maintenance-file", maintenance_file)
	gm_password_file = _cmdline_value("gm-password-file", gm_password_file)
	banned_ips_file = _cmdline_value("banned-ips-file", banned_ips_file)
	get_tree().auto_accept_quit = false  # a close request starts a graceful shutdown instead of dropping everyone
	var wanted_name := _cmdline_value("name", server_name)
	server_name = sanitize_name(wanted_name)
	if server_name.is_empty():
		_slog_err("--name must be letters/numbers only (got '%s')." % wanted_name)
		get_tree().quit(1)
		return
	Global.load_world_state(server_name)
	accounts().server_start()
	if host_game(port) != OK:
		_slog_err("Could not start (UDP port %d in use, or no usable TLS key/certificate — see errors above)." % port)
		get_tree().quit(1)
		return
	_slog("'%s' — Aldenexia %s listening on UDP %d (encrypted), up to %d players." % [server_name, GameVersion.display(), port, max_players])
	_slog("Stop it gracefully by creating the file %s (tools/run_server.sh does this on Ctrl-C / SIGTERM)." % ProjectSettings.globalize_path(stop_file))
	_slog("Update countdown: write the minutes to wait into %s (tools/server_maintenance.sh does this), or a GM types /maintenance." % ProjectSettings.globalize_path(maintenance_file))
	var gm_path := ProjectSettings.globalize_path(gm_password_file)
	if FileAccess.file_exists(gm_password_file):
		_slog("Game master password: read from %s (edit that file to change it; no restart needed)." % gm_path)
	else:
		_slog("Game master password: NOT SET. Nobody can become a game master until you create %s (tools/set_gm_password.sh does it)." % gm_path)
	get_tree().change_scene_to_file(pending_zone_path)
	_run_world_check()


# A few seconds after the zone loads, the server checks that the world it is actually running has ground
# collision, a usable navmesh and its monsters — and says so in the log. This matters most for a stripped
# dedicated-server export: if collision or navigation were lost in the strip, monsters would fall through
# the map or stand still, and this line is where that would show up.
func _run_world_check() -> void:
	await get_tree().create_timer(4.0).timeout
	var zone := get_tree().current_scene
	if zone == null:
		_slog_err("WORLD CHECK FAILED: no zone is loaded.")
		return
	var spawn: Vector3 = zone.get("spawn_position") if zone.get("spawn_position") != null else Vector3.ZERO
	var world: World3D = get_tree().root.world_3d
	var query := PhysicsRayQueryParameters3D.create(spawn + Vector3(0, 60, 0), spawn - Vector3(0, 80, 0))
	var hit: Dictionary = Global.ground_ray(world.direct_space_state, query)
	var nav_map: RID = world.navigation_map
	var here: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, spawn)
	var there: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, spawn + Vector3(25, 0, 25))
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, here, there, true)
	var mobs := zone.get_node_or_null("monster_spawner/SpawnedMobs")
	var mob_count: int = mobs.get_child_count() if mobs else -1
	var ground_ok: bool = not hit.is_empty()
	var nav_ok: bool = NavigationServer3D.map_get_regions(nav_map).size() > 0 and path.size() >= 2
	_slog("World check: ground under spawn %s, navmesh %s (%d region(s), %d-point test path), %d monsters." % [
		("OK (y=%.1f)" % hit["position"].y) if ground_ok else "MISSING",
		"OK" if nav_ok else "BROKEN", NavigationServer3D.map_get_regions(nav_map).size(), path.size(), mob_count])
	if not ground_ok:
		_slog_err("WARNING: no ground collision under the spawn point — monsters and players would fall through the world.")
	if not nav_ok:
		_slog_err("WARNING: the navigation mesh is missing or unusable — monsters won't be able to path.")


func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	# A dedicated server has every seat free plus spare slots for probes/errands (player limit is enforced at login);
	# a listen-server host fills one seat itself.
	var slots := (max_players + MENU_SLOTS) if is_dedicated_server else max_players - 1
	var err := peer.create_server(port, slots)
	if err != OK:
		push_error("Failed to host game: %s" % err)
		return err
	if is_dedicated_server:  # dedicated servers are always encrypted; LAN games stay plain
		var tls := _server_tls_options()
		if tls == null:
			peer.close()
			return ERR_FILE_CANT_READ
		err = peer.host.dtls_server_setup(tls)
		if err != OK:
			push_error("Could not enable DTLS encryption: %s" % err)
			peer.close()
			return err
	multiplayer.multiplayer_peer = peer
	is_multiplayer_game = true
	omit_preplaced_player = true  # the host's character is spawned like everyone else's
	return OK


func join_game(address: String, port: int = DEFAULT_PORT, encrypted: bool = false) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := _connect_client(peer, address, port, encrypted)
	if err != OK:
		push_error("Failed to join game: %s" % err)
		return err
	multiplayer.multiplayer_peer = peer
	is_multiplayer_game = true
	return OK


# Joining loads the zone FIRST and only then connects (the zone's spawner script
# calls complete_pending_join() from its _ready). The host starts replicating the
# moment a peer connects — spawns for every monster and player already in the
# world — and Godot silently drops a spawn whose spawner node doesn't exist yet on
# the receiving side ("Parameter 'spawner' is null"), never resending it. Connecting
# from the menu and loading the zone afterwards therefore left a joiner without their
# own character, any monsters, or the host's real name/model ("Default Hero").
func begin_join(address: String, port: int = DEFAULT_PORT) -> void:
	last_join_was_server = remote_character_mode
	_pending_join_address = address
	_pending_join_port = port
	last_failure_reason = ""
	omit_preplaced_player = true
	is_multiplayer_game = true
	get_tree().change_scene_to_file(pending_zone_path)


# Join a dedicated server: the character isn't loaded from this machine's saves — it is
# fetched from the server once connected (or created there, when creation_data is given).
# Same zone-first flow as begin_join(); see the server-side characters section below.
func begin_join_server(address: String, port: int, character_name: String, password: String, creation_data: Dictionary = {}) -> void:
	Global.clear_current_character_data()
	remote_character_mode = true
	last_join_was_server = true
	server_shutdown_notice = ""
	_login_name = character_name
	_login_password = password
	_login_creation_json = JSON.stringify(creation_data) if not creation_data.is_empty() else ""
	last_failure_kind = ""
	begin_join(address, port)


func has_pending_join() -> bool:
	return not _pending_join_address.is_empty()


func pending_join_label() -> String:
	return "%s:%d" % [_pending_join_address, _pending_join_port]


func complete_pending_join() -> Error:
	var address := _pending_join_address
	_pending_join_address = ""
	return join_game(address, _pending_join_port, last_join_was_server)


func disconnect_game() -> void:
	_menu_request = {}
	flush_remote_save()
	_await_save_acks()
	_forget_remote_character()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_multiplayer_game = false
	omit_preplaced_player = false
	_pending_join_address = ""


# Starts connecting `peer` to a server, wrapping it in DTLS when `encrypted` (every dedicated server).
# The handshake only succeeds if the server presents exactly the certificate this build trusts.
func _connect_client(peer: ENetMultiplayerPeer, address: String, port: int, encrypted: bool) -> Error:
	var err := peer.create_client(address, port)
	if err != OK or not encrypted:
		return err
	var tls := _client_tls_options()
	if tls == null:
		last_failure_reason = "This build has no server certificate, so it can't make an encrypted connection. Copy the server's server.crt to Data/server_cert.crt."
		peer.close()
		return ERR_FILE_NOT_FOUND
	err = peer.host.dtls_client_setup(TLS_CN, tls)
	if err != OK:
		peer.close()
	return err


# Best-guess LAN IP to show the host so they can read it off to whoever's
# joining — first non-loopback IPv4 address the OS reports.
func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127."):
			return ip
	return "127.0.0.1"


# /tell and /party route through here rather than a per-character RPC —
# autoloads have the same NodePath on every peer, so there's no need to
# resolve "the same node" across the network the way a per-player RPC would.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_tell(sender_name: String, message: String) -> void:
	GameLog.log_general(ChatChannels.tell_other(sender_name, message))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_party_message(sender_name: String, message: String) -> void:
	GameLog.log_general(ChatChannels.party_other(sender_name, message))


# /say and /zone. Like the rest of these, sender_name is whatever the sender claims — fine for
# a private/trusted game, to be checked against the peer id if this ever needs to be hardened.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_say(sender_name: String, message: String) -> void:
	GameLog.log_general(ChatChannels.say_other(sender_name, message))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_zone_message(sender_name: String, message: String) -> void:
	GameLog.log_general(ChatChannels.zone_other(sender_name, message))


func send_say(target_peer_id: int, sender_name: String, message: String) -> void:
	_rpc_receive_say.rpc_id(target_peer_id, sender_name, message)


# Everyone connected (there is one zone today; once there are several, the server filters this
# by the sender's zone).
func broadcast_zone_message(sender_name: String, message: String) -> void:
	for pid in multiplayer.get_peers():
		_rpc_receive_zone_message.rpc_id(pid, sender_name, message)


func send_tell(target_peer_id: int, sender_name: String, message: String) -> void:
	_rpc_receive_tell.rpc_id(target_peer_id, sender_name, message)


func send_party_message(peer_ids: Array, sender_name: String, message: String) -> void:
	for pid in peer_ids:
		_rpc_receive_party_message.rpc_id(pid, sender_name, message)


# Combat log relay — GameLog is purely local (see game_log.gd), so without
# this a second player never sees the first player's attacks/spells/buffs at
# all. Broadcast (not targeted) since there's no real party requirement to
# see combat, unlike /tell or /party; the source position rides along so each
# receiver's own game_log_window.gd applies the exact same 10m
# COMBAT_VISIBILITY_RANGE filter it already uses to hide distant NPC combat
# noise — no separate proximity system needed here.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_combat_message(text: String, position: Vector3) -> void:
	GameLog.log_combat(text, position)


func broadcast_combat_message(text: String, source_position: Vector3) -> void:
	for pid in multiplayer.get_peers():
		_rpc_receive_combat_message.rpc_id(pid, text, source_position)


# ── World announcements (join / leave) ───────────────────────────────────
# "X, the 10th season voidknight, enters the world!" — see world_announcer.gd
# and Data/world_announcements.json. The sender picks the line variant so every
# viewer sees the same wording. A joining client announces itself (it's the only
# one that knows its own loaded character, see player3d.gd's
# _announce_world_entry()); a departure is announced by the HOST, which still
# holds the leaver's replicated puppet at the moment of peer_disconnected.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_world_announce(kind: String, pname: String, level: int, cls: String, variant: int) -> void:
	if is_dedicated_server:
		_slog("%s: %s (level %d %s)" % [kind, pname, level, cls])
	WorldAnnouncer.announce(kind, pname, level, cls, variant)


func broadcast_world_announce(kind: String, pname: String, level: int, cls: String, except_peer: int = -1) -> void:
	if not is_multiplayer_game or not multiplayer.has_multiplayer_peer():
		return
	var variant := randi()
	for pid in multiplayer.get_peers():
		if pid != except_peer:
			_rpc_receive_world_announce.rpc_id(pid, kind, pname, level, cls, variant)


func _announce_departure(id: int) -> void:
	# Host only, and only while the session is really up — tearing our own
	# connection down also fires peer_disconnected for everyone else, which
	# must not read as a wave of "leaves the world" messages.
	if not is_multiplayer_game or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var puppet := TargetFrame.peer_id_to_player_node(id)
	if not is_instance_valid(puppet):
		return
	var info := WorldAnnouncer.player_info(puppet)
	var variant := randi()
	WorldAnnouncer.announce("leave", info["name"], info["level"], info["class"], variant)
	for pid in multiplayer.get_peers():
		if pid != id:
			_rpc_receive_world_announce.rpc_id(pid, "leave", info["name"], info["level"], info["class"], variant)


# ── Group invite / roster ────────────────────────────────────────────────
# An invite pops a real accept/decline popup on the target's screen (see
# group_invite_popup.gd) rather than joining them instantly. Once they
# respond, the inviter's player3d.gd updates its own group_members and
# broadcasts the full roster to everyone now in it, so every member's local
# copy stays in sync — simplest approach that works for a group this small
# (max 6) without a fancier distributed-membership protocol.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_group_invite(inviter_name: String) -> void:
	var inviter_id := multiplayer.get_remote_sender_id()
	var popup: Node = load("res://Scenes/group_invite_popup.tscn").instantiate()
	get_tree().root.add_child(popup)
	popup.setup(inviter_id, inviter_name)


func send_group_invite(target_peer_id: int, inviter_name: String) -> void:
	_rpc_receive_group_invite.rpc_id(target_peer_id, inviter_name)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_group_invite_response(accepted: bool) -> void:
	var responder_id := multiplayer.get_remote_sender_id()
	group_invite_response_received.emit(responder_id, accepted)


func send_group_invite_response(inviter_peer_id: int, accepted: bool) -> void:
	_rpc_receive_group_invite_response.rpc_id(inviter_peer_id, accepted)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_group_roster(peer_ids: Array) -> void:
	group_roster_received.emit(peer_ids)


# Sent to every member of a roster except the local caller (who already has
# the authoritative copy) — used both for "someone new joined" and "someone
# was kicked", since both are just "here's the current full roster."
func broadcast_group_roster(peer_ids: Array) -> void:
	for pid in peer_ids:
		if pid != multiplayer.get_unique_id():
			_rpc_receive_group_roster.rpc_id(pid, peer_ids)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_group_removed(reason: String) -> void:
	group_removed_received.emit(reason)


func send_group_removed(target_peer_id: int, reason: String) -> void:
	_rpc_receive_group_removed.rpc_id(target_peer_id, reason)


func _on_peer_connected(id: int) -> void:
	if is_multiplayer_game or is_dedicated_server:
		_relax_timeouts(id)
	if multiplayer.is_server() and is_ip_banned(peer_ip(id)):
		_last_ip[id] = peer_ip(id)
		_slog("Refused %s — the IP address is banned (peer %d)." % [peer_ip(id), id])
		_audit("REFUSED", peer_ip(id), "", "banned address")
		_kick.call_deferred(id)
		return
	if multiplayer.is_server():
		# The host holds player_connected (which spawns the newcomer's puppet)
		# until they've proven they run a compatible build — see below.
		_unverified_peers[id] = true
		get_tree().create_timer(VERSION_CHECK_TIMEOUT).timeout.connect(_on_version_check_timeout.bind(id))
	else:
		player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if is_dedicated_server:
		# Name the character (the key is "<server>_<name>"); a peer that never logged one in says so.
		_slog("%s disconnected — peer %d, %s (%d/%d)." % [_character_label(id), id, _last_ip.get(id, "?"), multiplayer.get_peers().size(), max_players])
		_audit("DISCONNECT", str(_last_ip.get(id, "?")), _character_label(id) if _peer_character.has(id) else "")
	_last_ip.erase(id)
	_unverified_peers.erase(id)
	_awaiting_login.erase(id)
	_peer_character.erase(id)
	_shutdown_waiting.erase(id)
	_check_shutdown_complete()
	_announce_departure(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	_relax_timeouts(1)
	# We only count as connected once the host has approved our build.
	_rpc_submit_version.rpc_id(1, GameVersion.version(), GameVersion.build_id())


# ── Version check ─────────────────────────────────────────────────────────
# Client -> host on connect. Same version number (and, when both builds are
# stamped, same build id) or the host refuses with a message; an older build
# that never sends a version is dropped after VERSION_CHECK_TIMEOUT. Nothing is
# spawned for the newcomer until they pass.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_version(client_version: String, client_build: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _unverified_peers.has(id):
		return
	if GameVersion.is_compatible(client_version, client_build):
		_unverified_peers.erase(id)
		_rpc_version_accepted.rpc_id(id, is_dedicated_server, server_name, _peer_character.size(), max_players, GameVersion.display())
		Global.send_time_to(id)
		if is_dedicated_server:
			# A dedicated server has no character of its own to lean on: the joiner must now log one
			# in (see _rpc_login) before their puppet is spawned.
			_last_ip[id] = peer_ip(id)
			_slog("Peer %d connected from %s (%d/%d), waiting for a character." % [id, _last_ip[id], multiplayer.get_peers().size(), max_players])
			_audit("CONNECT", str(_last_ip[id]), "", GameVersion.display())
			_awaiting_login[id] = true
			get_tree().create_timer(LOGIN_TIMEOUT).timeout.connect(_on_login_timeout.bind(id))
		else:
			player_connected.emit(id)
	else:
		print("Rejected peer %d: they run v%s (%s), host runs %s" % [id, client_version, client_build if client_build != "" else "no build id", GameVersion.display()])
		if is_dedicated_server:
			_audit("OLD VERSION", peer_ip(id), "", "v%s (%s)" % [client_version, client_build])
		_rpc_version_rejected.rpc_id(id, GameVersion.display())
		get_tree().create_timer(0.6).timeout.connect(_kick.bind(id))  # let the message land first


@rpc("authority", "call_remote", "reliable")
func _rpc_version_accepted(host_is_dedicated: bool, host_server_name: String, players: int, host_max_players: int, host_version: String) -> void:
	if not _menu_request.is_empty():
		if not host_is_dedicated:
			_fail_join("That address is a LAN game, not a dedicated server.", "wrong_mode")
		elif _menu_request["type"] == "delete":
			_rpc_delete_character.rpc_id(1, _menu_request["name"], _menu_request["password"])
		elif _menu_request["type"] == "account":
			accounts().send_errand(_menu_request)
		elif _menu_request["type"] == "probe":
			_finish_menu_request(true, "online", "", {"name": host_server_name, "players": players, "max_players": host_max_players, "version": host_version})
		return
	if remote_character_mode and not host_is_dedicated:
		_fail_join("That address is a LAN game, not a dedicated server. Use Multiplayer (LAN) to join it.", "wrong_mode")
	elif host_is_dedicated and not remote_character_mode:
		_fail_join("That address is a dedicated server. Use Join a Server to connect to it.", "wrong_mode")
	elif host_is_dedicated:
		server_name = host_server_name
		_rpc_login.rpc_id(1, _login_name, _login_password, _login_creation_json)
	else:
		connection_succeeded.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_version_rejected(host_display: String) -> void:
	if not _menu_request.is_empty():  # a probe learns the server is up but runs a different version
		_finish_menu_request(false, "version", "Update needed: the server runs %s, you have %s." % [host_display, GameVersion.display()], {"version": host_display})
		return
	_fail_join("Version mismatch: the host is running %s and you are running %s. Update your game to match the host." % [host_display, GameVersion.display()], "version")


# Client side: give up on this join, tear the connection down and report why.
func _fail_join(reason: String, kind: String = "") -> void:
	if not _menu_request.is_empty():
		_finish_menu_request(false, kind, reason)
		return
	last_failure_reason = reason
	last_failure_kind = kind
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_multiplayer_game = false
	omit_preplaced_player = false
	_forget_remote_character()
	connection_failed.emit()


func _on_version_check_timeout(id: int) -> void:
	if _unverified_peers.has(id):
		print("Peer %d never sent a version (an older build?) — dropped." % id)
		_kick(id)


# ── IP addresses and bans (server) ──
# The address a connected peer is talking to us from ("" if unknown, e.g. offline).
func peer_ip(id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return ""
	var packet_peer := enet.get_peer(id)
	return packet_peer.get_remote_address() if packet_peer != null else ""


# The banned addresses, read fresh from banned_ips_file every time (edit the file by hand too; no restart needed).
func banned_ips() -> Array:
	var out: Array = []
	for line in FileAccess.get_file_as_string(banned_ips_file).split("\n"):
		var ip := line.get_slice("#", 0).strip_edges()
		if not ip.is_empty():
			out.append(ip)
	return out


func is_ip_banned(ip: String) -> bool:
	return not ip.is_empty() and ip in banned_ips()


# Adds a ban (with a note: who banned it, when, whom) and disconnects everyone on that address. Returns how many were kicked.
func ban_ip(ip: String, note: String) -> int:
	if not is_ip_banned(ip):
		var text := FileAccess.get_file_as_string(banned_ips_file)
		var f := FileAccess.open(banned_ips_file, FileAccess.WRITE)
		f.store_string(text + ("" if text.is_empty() or text.ends_with("\n") else "\n") + "%s  # %s\n" % [ip, note])
		f.close()
	var kicked := 0
	for id in multiplayer.get_peers():
		if peer_ip(id) == ip:
			_slog("Kicked %s (peer %d, %s): banned." % [_character_label(id), id, ip])
			_audit("KICKED", ip, _character_label(id), "banned")
			_kick(id)
			kicked += 1
	return kicked


func unban_ip(ip: String) -> bool:
	var lines: PackedStringArray = FileAccess.get_file_as_string(banned_ips_file).split("\n")
	var kept: Array = []
	var found := false
	for line in lines:
		if line.get_slice("#", 0).strip_edges() == ip:
			found = true
		elif not line.is_empty():
			kept.append(line)
	if found:
		var f := FileAccess.open(banned_ips_file, FileAccess.WRITE)
		f.store_string("\n".join(kept) + ("\n" if not kept.is_empty() else ""))
		f.close()
	return found


# The peer playing a character called `player_name` (case-insensitive), or 0.
func peer_for_character(player_name: String) -> int:
	var wanted := "%s_%s" % [server_name, sanitize_name(player_name)]
	for id in _peer_character:
		if str(_peer_character[id]) == wanted:
			return id
	return 0


func _character_label(id: int) -> String:
	var key := str(_peer_character.get(id, ""))
	return _display_name(key.trim_prefix(server_name + "_")) if not key.is_empty() else "(not logged in)"


# "zozuur" -> "Zozuur" (capitalize() would also split letters from digits: "zzbot79053" -> "Zzbot 79053").
static func _display_name(character: String) -> String:
	return character.substr(0, 1).to_upper() + character.substr(1)


# The connections audit log (dedicated server): user://logs/connections.log — one line per connect, login (and failed
# login), disconnect, refusal, kick and ban, never rotated or trimmed (unlike godot.log, of which Godot keeps only the
# last five, one per server start). Tab-separated: date time, event, IP, character, details.
const AUDIT_LOG := "user://logs/connections.log"

func _audit(event: String, ip: String, character: String = "", details: String = "") -> void:
	if not is_dedicated_server:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUDIT_LOG.get_base_dir()))
	var f := FileAccess.open(AUDIT_LOG, FileAccess.READ_WRITE) if FileAccess.file_exists(AUDIT_LOG) else FileAccess.open(AUDIT_LOG, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s\t%-12s\t%-15s\t%-16s\t%s" % [Time.get_datetime_string_from_system(false, true), event, ip, character, details])
	f.close()


func _kick(id: int) -> void:
	_unverified_peers.erase(id)
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_connection_failed() -> void:
	if not _menu_request.is_empty():
		_finish_menu_request(false, "offline", "Could not connect. Check the address and make sure the server is running.")
		return
	multiplayer.multiplayer_peer = null
	is_multiplayer_game = false
	omit_preplaced_player = false
	_forget_remote_character()
	if last_failure_reason.is_empty():
		last_failure_reason = "Could not connect. Check the address and make sure the server is running."
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if remote_character_mode:
		print("%s [client] Lost the connection to the server. Last link reading: %s" % [Time.get_time_string_from_system(), _last_link_stats])
	if not _menu_request.is_empty():
		_finish_menu_request(false, "", "The server closed the connection.")
		return
	multiplayer.multiplayer_peer = null
	is_multiplayer_game = false
	omit_preplaced_player = false
	_remote_save_pending = false
	_saves_in_flight = 0
	_forget_remote_character()
	server_disconnected.emit()


# Ends "playing a server's character": drops the working copy so a later Global.save_player_data_to_file()
# (a scene teardown, a "server lost" handler) can't write it into the player's local saves.
func _forget_remote_character() -> void:
	if remote_character_mode:
		Global.clear_current_character_data()
	remote_character_mode = false


# ── Encryption (dedicated servers) ────────────────────────────────────────
# Dedicated servers speak DTLS over ENet, so passwords and characters aren't readable on the wire. The
# server owns a key + self-signed certificate (created on first start in tls_dir, printed for you to copy);
# a client build carries the matching PUBLIC certificate (Data/server_cert.crt) and trusts only that exact
# certificate — an impostor on the network can't present it, so a man-in-the-middle can't read or alter
# the traffic. LAN games are unencrypted, as before.
func _server_tls_options() -> TLSOptions:
	var key_path := tls_dir.path_join("server.key")
	var cert_path := tls_dir.path_join("server.crt")
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	if not (FileAccess.file_exists(key_path) and FileAccess.file_exists(cert_path)) or key.load(key_path) != OK or cert.load(cert_path) != OK:
		var crypto := Crypto.new()
		key = crypto.generate_rsa(2048)
		cert = crypto.generate_self_signed_certificate(key, "CN=%s,O=Aldenexia" % TLS_CN, "20260101000000", "20460101000000")
		DirAccess.make_dir_recursive_absolute(tls_dir)
		if key.save(key_path) != OK or cert.save(cert_path) != OK:
			_slog_err("Could not write the TLS key/certificate to %s" % tls_dir)
			return null
		_slog("Created a new TLS key and certificate in %s" % ProjectSettings.globalize_path(tls_dir))
		_slog(">>> Copy server.crt (the PUBLIC certificate) to Data/server_cert.crt in the game project and rebuild the client,")
		_slog(">>> or players can't connect. Keep server.key private — never put it in the project or share it.")
	return TLSOptions.server(key, cert)


# Null when this build has no certificate to trust (so it cannot verify a server at all).
func _client_tls_options() -> TLSOptions:
	for path in TRUSTED_CERT_PATHS:
		var cert := X509Certificate.new()
		if cert.load(path) == OK:
			return TLSOptions.client(cert, TLS_CN)
	return null


# ── Server-side characters (dedicated server) ─────────────────────────────
# On a dedicated server the character lives on the SERVER, stored as
# user://server_characters/<server>_<player>_character_stats.json (e.g. test_zozuur).
# The client keeps its working copy in Global.player_data exactly as in single player, so
# every existing Global.save_player_data_to_file() call site keeps working — that function
# just uploads the JSON here (request_remote_save) instead of writing user://saves.
#   1. joiner passes the version check, server marks them "awaiting login"
#   2. client -> _rpc_login(name, creation_json): loads the character, or creates it when
#      creation_json is set (name must be free; only level-1 characters are accepted)
#   3. server -> _rpc_login_ok(json): client fills Global.player_data, answers _rpc_login_ready
#   4. server emits player_connected, which finally spawns the joiner's character
# Like the rest of the netcode this trusts the client's numbers; it only guarantees that a
# peer can write nothing but the character it logged in as, one peer per character at a time.

# Lowercase letters/digits, 2-16 long — the only names a server accepts (they become file names).
static func sanitize_name(raw: String) -> String:
	var name := raw.strip_edges().to_lower()
	var valid := name.length() >= 2 and name.length() <= 16
	for i in name.length():
		var c := name.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57)):
			valid = false
	return name if valid else ""


func _character_path(key: String) -> String:
	return "%s/%s_character_stats.json" % [CHARACTER_DIR, key]


func _login_fail(id: int, kind: String, reason: String) -> void:
	if is_dedicated_server:
		_audit("LOGIN FAILED", peer_ip(id), "", kind)
	_slog("Login refused for peer %d: %s" % [id, reason])
	_rpc_login_failed.rpc_id(id, kind, reason)
	get_tree().create_timer(0.6).timeout.connect(_kick.bind(id))  # let the message land first


func _on_login_timeout(id: int) -> void:
	if _awaiting_login.has(id):
		_slog("Peer %d never logged a character in — dropped." % id)
		_awaiting_login.erase(id)
		_kick(id)


# The peer id currently logged in as `key`, or 0.
func _peer_holding(key: String) -> int:
	for peer_id in _peer_character:
		if _peer_character[peer_id] == key:
			return peer_id
	return 0


# Parses an uploaded/stored character; {} unless it is a real dictionary for `player` (a sanitized name).
func _parse_character(json_text: String, player: String) -> Dictionary:
	if json_text.length() > MAX_CHARACTER_BYTES:
		return {}
	# Permanent buffs are saved with an "infinite" duration, which Godot writes as 1e99999 and then WARNS about every time
	# it parses it ("Exponent too high") — once per buff per save upload, which flooded the server log. This copy is only
	# checked, never stored (the original text is what gets written), so a huge finite number is a safe stand-in.
	var data = JSON.parse_string(json_text.replace("1e99999", "1e308"))
	if typeof(data) != TYPE_DICTIONARY or sanitize_name(str(data.get("player_name", ""))) != player:
		return {}
	return data


# Write to a temp file and rename over the real one, so a crash mid-write can't leave half a file.
func _write_file_atomic(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if not file:
		push_error("[server] Could not write %s" % tmp)
		return false
	file.store_string(text)
	file.close()
	return DirAccess.rename_absolute(tmp, path) == OK


func _write_character(key: String, json_text: String) -> bool:
	return _write_file_atomic(_character_path(key), json_text)


# ── Passwords ──
# Each server character has a password, stored as a salted, stretched hash in a sidecar file next to the
# save — never inside the save itself, which the client uploads and could otherwise read or replace.
# A character with NO sidecar (created before passwords, or the owner deleted it to reset a forgotten
# password) simply takes whatever password its next login supplies.
func _auth_path(key: String) -> String:
	return "%s/%s_auth.json" % [CHARACTER_DIR, key]


func _hash_password(password: String, salt: String) -> String:
	var h := salt + password
	for i in PASSWORD_HASH_ROUNDS:
		h = (h + salt).sha256_text()
	return h


func _write_password(key: String, password: String) -> bool:
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	return _write_file_atomic(_auth_path(key), JSON.stringify({"salt": salt, "hash": _hash_password(password, salt)}))


func _password_matches(key: String, password: String) -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(_auth_path(key)))
	return typeof(data) == TYPE_DICTIONARY and _hash_password(password, str(data.get("salt", ""))) == str(data.get("hash", ""))


func _lockout_seconds_left(key: String) -> int:
	var until := int(_login_failures.get(key, {}).get("until_ms", 0))
	return maxi(ceili((until - Time.get_ticks_msec()) / 1000.0), 0)


# One wrong password. Returns the message for the player; the 5th in a row locks the character for a minute.
func _register_wrong_password(key: String) -> String:
	var entry: Dictionary = _login_failures.get(key, {"count": 0, "until_ms": 0})
	entry["count"] = int(entry["count"]) + 1
	if entry["count"] >= MAX_LOGIN_FAILURES:
		entry["count"] = 0
		entry["until_ms"] = Time.get_ticks_msec() + LOCKOUT_SECONDS * 1000
		_login_failures[key] = entry
		return "Wrong password. Too many tries — this character is locked for %d seconds." % LOCKOUT_SECONDS
	_login_failures[key] = entry
	var tries_left := MAX_LOGIN_FAILURES - int(entry["count"])
	return "Wrong password (%d %s left)." % [tries_left, "try" if tries_left == 1 else "tries"]


# Shared by login and delete: true if `password` opens the character. Otherwise the peer has already been
# told why (locked / wrong password) and this returns false.
func _check_access(id: int, key: String, password: String) -> bool:
	var left := _lockout_seconds_left(key)
	if left > 0:
		_login_fail(id, "locked", "Too many wrong passwords. Try again in %d seconds." % left)
		return false
	if not _password_matches(key, password):
		_login_fail(id, "bad_password", _register_wrong_password(key))
		return false
	_login_failures.erase(key)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_login(character_name: String, password: String, creation_json: String) -> void:
	if not is_dedicated_server or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _awaiting_login.has(id):
		return
	var player := sanitize_name(character_name)
	if player.is_empty():
		_login_fail(id, "invalid_name", "Character names use letters and numbers only, 2 to 16 characters.")
		return
	var key := "%s_%s" % [server_name, player]
	if _shutting_down:
		_login_fail(id, "shutting_down", "The server is shutting down. Try again in a few minutes.")
		return
	if maintenance_pending:
		_login_fail(id, "shutting_down", "The server is about to go down for an update. Try again in a few minutes.")
		return
	# Is this character still held by ANOTHER connection? After a dropped/crashed client the server keeps the old
	# connection open for ~30 s (see PEER_TIMEOUT_MIN_MS), and the player usually reconnects at once.
	var holder := _peer_holding(key)
	if holder == 0 and _peer_character.size() >= max_players:
		_login_fail(id, "server_full", "The server is full (%d/%d players). Try again later." % [_peer_character.size(), max_players])
		return
	var path := _character_path(key)
	var exists := FileAccess.file_exists(path)
	var json_text := ""
	var status := ""  # "created" / "password_set" / "" — told to the client
	# "" = an old-style character password; else the account that logged in (it may use this character).
	var account := accounts().check_login(id, player, password, not creation_json.is_empty())
	if account == "!":
		return
	if not creation_json.is_empty():
		if exists or holder != 0:
			_login_fail(id, "name_taken", "A character named %s already exists on this server." % player.capitalize())
			return
		if account.is_empty() and password.length() < MIN_PASSWORD_LENGTH:
			_login_fail(id, "weak_password", "Passwords need at least %d characters." % MIN_PASSWORD_LENGTH)
			return
		var data := _parse_character(creation_json, player)
		if data.is_empty() or int(data.get("player_level", 1)) > 1:
			_login_fail(id, "invalid_character", "That character can't be created here (new characters must start at level 1).")
			return
		# An account's character needs no password of its own: the account guards it.
		if not _write_character(key, creation_json) or (account.is_empty() and not _write_password(key, password)):
			DirAccess.remove_absolute(path)  # never leave a character that has no password behind
			_login_fail(id, "server_error", "The server could not save your new character.")
			return
		if not account.is_empty():
			accounts().add_character(account, player)
		json_text = creation_json
		status = "created"
	else:
		if not exists:
			_login_fail(id, "no_character", "There is no character named %s on this server." % player.capitalize())
			return
		var has_password := FileAccess.file_exists(_auth_path(key))
		if account.is_empty() and holder != 0 and not has_password:
			# Nothing proves this is the same player, so don't let anyone take the character over.
			_login_fail(id, "already_online", "%s is already in the world." % player.capitalize())
			return
		if not account.is_empty() or has_password:
			if account.is_empty() and not _check_access(id, key, password):
				return
			if holder != 0:
				# Correct password while the old connection is still open (the player's link dropped and they came
				# straight back): the new login replaces the old one instead of being turned away.
				_slog("Peer %d takes over %s from peer %d (the old connection was still open)." % [id, key, holder])
				_peer_character.erase(holder)
				# Graceful, not forced: a forced disconnect leaves the peer listed in multiplayer.get_peers() (no
				# disconnect event ever fires), and later broadcasts then fail with "Invalid target peer".
				var link := multiplayer.multiplayer_peer as ENetMultiplayerPeer
				if link != null:
					link.disconnect_peer(holder, false)
				player_disconnected.emit(holder)  # take the old player's body out of the world right now; the real disconnect event follows later (harmless repeat)
		elif password.length() < MIN_PASSWORD_LENGTH:
			_login_fail(id, "weak_password", "%s has no password yet. Enter one (at least %d characters) to set it." % [player.capitalize(), MIN_PASSWORD_LENGTH])
			return
		elif _write_password(key, password):
			status = "password_set"
		json_text = FileAccess.get_file_as_string(path)
		if _parse_character(json_text, player).is_empty():
			_login_fail(id, "server_error", "%s's save on the server is unreadable." % player.capitalize())
			return
		DirAccess.copy_absolute(path, path.get_basename() + ".bak")  # last known-good copy, refreshed every login
	_awaiting_login.erase(id)
	_peer_character[id] = key
	var notes := PackedStringArray()
	if not account.is_empty():
		notes.append("account " + account)
	if status == "created":
		notes.append("new character")
	_audit("LOGIN", peer_ip(id), _display_name(key.trim_prefix(server_name + "_")), ", ".join(notes))
	_slog("%s logged in — peer %d, %s%s%s." % [_display_name(key.trim_prefix(server_name + "_")), id, peer_ip(id), "" if account.is_empty() else ", account " + account, " (new character)" if status == "created" else (" (password set)" if status == "password_set" else "")])
	_rpc_login_ok.rpc_id(id, json_text, status)


# Menu errand: delete a character from the Load/Join screens without loading the zone. Needs the
# character's password; refuses while it is in the world. The files are MOVED to deleted/, not erased.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_delete_character(character_name: String, password: String) -> void:
	if not is_dedicated_server or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _awaiting_login.has(id):
		return
	var player := sanitize_name(character_name)
	var key := "%s_%s" % [server_name, player]
	if player.is_empty() or not FileAccess.file_exists(_character_path(key)):
		_login_fail(id, "no_character", "There is no character named %s on this server." % player.capitalize())
		return
	if _peer_character.values().has(key):
		_login_fail(id, "already_online", "%s is in the world right now and can't be deleted." % player.capitalize())
		return
	if not accounts().owner_of(player).is_empty():
		_login_fail(id, "account_character", "%s belongs to an account. Log in with the account to delete it." % player.capitalize())
		return
	if not FileAccess.file_exists(_auth_path(key)):
		_login_fail(id, "no_password", "%s has no password yet, so it can't be deleted from here. Log in with it once to set one." % player.capitalize())
		return
	if not _check_access(id, key, password):
		return
	var stamp := int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(DELETED_DIR)
	var moved := DirAccess.rename_absolute(_character_path(key), "%s/%s_%d_character_stats.json" % [DELETED_DIR, key, stamp]) == OK
	DirAccess.rename_absolute(_auth_path(key), "%s/%s_%d_auth.json" % [DELETED_DIR, key, stamp])
	if not moved:
		_login_fail(id, "server_error", "The server could not delete %s." % player.capitalize())
		return
	_slog("Peer %d deleted character %s (kept in deleted/)." % [id, key])
	_awaiting_login.erase(id)
	_rpc_delete_done.rpc_id(id, "%s was deleted." % player.capitalize())
	get_tree().create_timer(0.6).timeout.connect(_kick.bind(id))


@rpc("authority", "call_remote", "reliable")
func _rpc_delete_done(message: String) -> void:
	_finish_menu_request(true, "deleted", message)


# Client side. The Load/Join screens call these and wait for server_request_done. One errand at a time
# (they share the single multiplayer connection); each ends by itself, or after MENU_REQUEST_TIMEOUT.
func request_server_delete(address: String, port: int, character_name: String, password: String) -> void:
	_start_menu_request({"type": "delete", "name": character_name, "password": password}, address, port)


# Asks a server "are you up, what version, how many players?" without logging in — the Join a Server list
# uses it. Result: server_request_done(true, "online", "", {name, players, max_players, version}), or
# (false, "offline" / "version" / "wrong_mode" / ...). Cheap and fast when the server is up.
func probe_server(address: String, port: int) -> void:
	_start_menu_request({"type": "probe"}, address, port)


func _start_menu_request(request: Dictionary, address: String, port: int) -> void:
	if not _menu_request.is_empty() or _has_live_peer():
		server_request_done.emit(false, "busy", "Already connected or working on another request.", {})
		return
	var peer := ENetMultiplayerPeer.new()
	last_failure_reason = ""
	var err := _connect_client(peer, address, port, true)  # errands only ever go to dedicated servers: encrypted
	if err != OK:
		var reason := last_failure_reason if not last_failure_reason.is_empty() else "Could not start the connection."
		last_failure_reason = ""
		server_request_done.emit(false, "no_certificate" if err == ERR_FILE_NOT_FOUND else "", reason, {})
		return
	_request_serial += 1
	request["serial"] = _request_serial
	_menu_request = request
	multiplayer.multiplayer_peer = peer  # is_multiplayer_game stays false: this is an errand, not a game
	get_tree().create_timer(MENU_REQUEST_TIMEOUT).timeout.connect(_on_menu_request_timeout.bind(_request_serial))


func _on_menu_request_timeout(serial: int) -> void:
	if not _menu_request.is_empty() and _menu_request.get("serial") == serial:
		_finish_menu_request(false, "offline", "No answer from the server. It may be offline, or this build's certificate doesn't match it.")


# Abandons a running errand silently (the player did something else first).
func cancel_menu_request() -> void:
	if _menu_request.is_empty():
		return
	_menu_request = {}
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


# True while a real connection exists. Godot's idle state is an OfflineMultiplayerPeer at startup but null
# after we assign null ourselves, so both count as "not connected".
func _has_live_peer() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer


func _finish_menu_request(ok: bool, kind: String, reason: String, info: Dictionary = {}) -> void:
	_menu_request = {}
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	server_request_done.emit(ok, kind, reason, info)


@rpc("authority", "call_remote", "reliable")
func _rpc_login_failed(kind: String, reason: String) -> void:
	_fail_join(reason, kind)


@rpc("authority", "call_remote", "reliable")
func _rpc_login_ok(json_text: String, status: String) -> void:
	var data = JSON.parse_string(json_text)
	if typeof(data) != TYPE_DICTIONARY:
		_fail_join("The server sent a character this build can't read.", "server_error")
		return
	last_login_status = status
	Global.set_player_data(data)
	# The character must be in place BEFORE the server spawns our puppet, whose _ready reads it.
	_rpc_login_ready.rpc_id(1)
	connection_succeeded.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_login_ready() -> void:
	if not is_dedicated_server or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if _peer_character.has(id):
		player_connected.emit(id)


# Client -> server: the current character. Ignored unless it is the one this peer logged in as.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_save_character(json_text: String) -> void:
	if not is_dedicated_server or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var key: String = _peer_character.get(id, "")
	if key.is_empty():
		return
	var player := key.trim_prefix(server_name + "_")
	if _parse_character(json_text, player).is_empty():
		push_warning("[server] Refused a save from peer %d for %s (unreadable, oversized or wrong character)." % [id, key])
		return
	if _write_character(key, json_text):
		_rpc_save_acknowledged.rpc_id(id)


# Client side. Global.save_player_data_to_file() lands here in remote_character_mode; several
# calls in quick succession collapse into one upload REMOTE_SAVE_DELAY later.
func request_remote_save() -> void:
	if _remote_save_pending:
		return
	_remote_save_pending = true
	get_tree().create_timer(REMOTE_SAVE_DELAY).timeout.connect(flush_remote_save)


# Uploads right now (also called before quitting or leaving, which can't wait for the delay).
func flush_remote_save() -> void:
	if not _remote_save_pending:
		return
	_remote_save_pending = false
	var peer := multiplayer.multiplayer_peer
	if not remote_character_mode or peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var json_text := Global.serialize_player_data()
	if json_text.is_empty():
		return
	_saves_in_flight += 1
	_rpc_save_character.rpc_id(1, json_text)


@rpc("authority", "call_remote", "reliable")
func _rpc_save_acknowledged() -> void:
	_saves_in_flight = maxi(_saves_in_flight - 1, 0)
	if _shutdown_reply_pending and _saves_in_flight == 0:
		_shutdown_reply_pending = false
		_rpc_shutdown_ready.rpc_id(1)


# Leaving right after an upload (camp out, quit) must not cut it off: close() drops what ENet
# hasn't sent yet, and the server discards packets that arrive alongside a disconnect. So wait,
# briefly, for the server to confirm every upload before the connection goes away.
func _await_save_acks() -> void:
	var deadline := Time.get_ticks_msec() + 2000
	while _saves_in_flight > 0 and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			break
		multiplayer.poll()
		OS.delay_msec(5)
	_saves_in_flight = 0


# ── Graceful shutdown (dedicated server) ─────────────────────────────────
# Godot's headless server can't catch SIGTERM, so a shutdown is requested by creating stop_file (tools/run_server.sh
# does that when signalled) or by a window close request. The server then asks every logged-in player's game to
# upload its character right now, waits for each to confirm (up to SHUTDOWN_GRACE), saves the world clock and exits.
# Players see "The server shut down. Your character was saved." on the Join a Server screen.
func _process(delta: float) -> void:
	var frame_seconds := _real_frame_seconds()
	if not is_dedicated_server:
		_monitor_client_link(delta, frame_seconds)
		return
	if _shutting_down:
		return
	if frame_seconds > HITCH_LOG_SECONDS:
		_slog("Long frame: %.1f s (%d player(s) online) — this machine/VM stalled" % [frame_seconds, _peer_character.size()])
	_stop_poll += delta
	if _stop_poll >= 1.0:
		_stop_poll = 0.0
		if FileAccess.file_exists(stop_file):
			DirAccess.remove_absolute(stop_file)
			_slog("Stop requested.")
			begin_shutdown()
	_world_save_timer += delta
	if _world_save_timer >= WORLD_SAVE_INTERVAL:
		_world_save_timer = 0.0
		Global.save_world_state(server_name)


# How many players are logged in with a character right now (the dedicated server's view).
func logged_in_count() -> int:
	return _peer_character.size()


func begin_shutdown() -> void:
	if not is_dedicated_server or _shutting_down:
		return
	_shutting_down = true
	_shutdown_waiting = _peer_character.keys()
	_slog("Shutting down — waiting for %d player(s) to save." % _shutdown_waiting.size())
	for id in multiplayer.get_peers():
		_rpc_server_shutting_down.rpc_id(id)
	get_tree().create_timer(SHUTDOWN_GRACE).timeout.connect(_finish_shutdown)
	_check_shutdown_complete()


func _check_shutdown_complete() -> void:
	if _shutting_down and _shutdown_waiting.is_empty():
		_finish_shutdown()


func _finish_shutdown() -> void:
	if _shutdown_done:
		return
	_shutdown_done = true
	if not _shutdown_waiting.is_empty():
		_slog("%d player(s) did not confirm their save in time." % _shutdown_waiting.size())
	Global.save_world_state(server_name)
	_slog("World state saved. Goodbye.")
	# Tell everyone goodbye but leave the peer itself open until we quit: closing it made other nodes' _process
	# (weather, mob spawner) log errors reading multiplayer state during the last frame.
	if multiplayer.multiplayer_peer != null:
		for id in multiplayer.get_peers():
			multiplayer.multiplayer_peer.disconnect_peer(id)
		await get_tree().create_timer(0.3).timeout  # let the disconnects go out
	get_tree().quit()


# Server -> every peer. A player's game uploads its character immediately and confirms with _rpc_shutdown_ready.
@rpc("authority", "call_remote", "reliable")
func _rpc_server_shutting_down() -> void:
	server_shutdown_notice = "The server shut down. Your character was saved."
	if not _menu_request.is_empty():
		return  # a probe or delete errand; the server isn't waiting for it
	if remote_character_mode:
		GameLog.log_general("[color=#ffaa66]The server is shutting down — saving your character...[/color]")
		_remote_save_pending = true  # upload even if nothing changed since the last save
		flush_remote_save()
	if _saves_in_flight == 0:
		_rpc_shutdown_ready.rpc_id(1)
	else:
		_shutdown_reply_pending = true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_shutdown_ready() -> void:
	if not is_dedicated_server or not multiplayer.is_server():
		return
	_shutdown_waiting.erase(multiplayer.get_remote_sender_id())
	_check_shutdown_complete()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_dedicated_server:
			begin_shutdown()
		elif remote_character_mode:
			disconnect_game()
