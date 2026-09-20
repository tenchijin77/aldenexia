# net.gd — Thin wrapper around Godot's high-level multiplayer API (ENet) for
# LAN co-op. One player hosts a listen-server (their own player3d instance
# doubles as the server), everyone else connects to that host's LAN IP —
# manual IP entry, no relay/NAT punchthrough, matching the "6-player co-op
# over a listen-server" plan in change_list.txt. Good enough to test across
# two machines on the same network; revisit if we ever need internet play.
extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed
signal connection_succeeded
signal server_disconnected

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

var is_multiplayer_game := false
## Why the last join attempt failed, when the host said so (e.g. a version mismatch).
var last_failure_reason := ""
var _unverified_peers: Dictionary = {}  # host only: peer_id -> true until they pass the version check
var pending_zone_path := "res://Scenes/lumora_outskirts3d.tscn"


func _ready() -> void:
	print("Aldenexia %s" % GameVersion.display())
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		push_error("Failed to host game: %s" % err)
		return err
	multiplayer.multiplayer_peer = peer
	is_multiplayer_game = true
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("Failed to join game: %s" % err)
		return err
	multiplayer.multiplayer_peer = peer
	is_multiplayer_game = true
	return OK


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_multiplayer_game = false


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
	GameLog.log_general("[color=#cc88ff]%s tells you, '%s'[/color]" % [sender_name, message])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_party_message(sender_name: String, message: String) -> void:
	GameLog.log_general("[color=#88ccff][Party] %s: %s[/color]" % [sender_name, message])


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
	if multiplayer.is_server():
		# The host holds player_connected (which spawns the newcomer's puppet)
		# until they've proven they run a compatible build — see below.
		_unverified_peers[id] = true
		get_tree().create_timer(VERSION_CHECK_TIMEOUT).timeout.connect(_on_version_check_timeout.bind(id))
	else:
		player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	_unverified_peers.erase(id)
	_announce_departure(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
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
		_rpc_version_accepted.rpc_id(id)
		player_connected.emit(id)
	else:
		print("Rejected peer %d: they run v%s (%s), host runs %s" % [id, client_version, client_build if client_build != "" else "no build id", GameVersion.display()])
		_rpc_version_rejected.rpc_id(id, GameVersion.display())
		get_tree().create_timer(0.6).timeout.connect(_kick.bind(id))  # let the message land first


@rpc("authority", "call_remote", "reliable")
func _rpc_version_accepted() -> void:
	connection_succeeded.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_version_rejected(host_display: String) -> void:
	last_failure_reason = "Version mismatch: the host is running %s and you are running %s. Update your game to match the host." % [host_display, GameVersion.display()]
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_multiplayer_game = false
	connection_failed.emit()


func _on_version_check_timeout(id: int) -> void:
	if _unverified_peers.has(id):
		print("Peer %d never sent a version (an older build?) — dropped." % id)
		_kick(id)


func _kick(id: int) -> void:
	_unverified_peers.erase(id)
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	is_multiplayer_game = false
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	is_multiplayer_game = false
	server_disconnected.emit()
