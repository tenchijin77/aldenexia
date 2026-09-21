# gm_relay.gd — Carries game-master commands from a client to the server and the answer back (gm_commands.gd decides what a
# command does). It is a node in the zone scene, NOT part of Net, on purpose: the RPC set of the Net autoload has to stay exactly what
# already-distributed builds have. Godot compares each node's RPC list between peers, and Net carries the version handshake, so a
# changed Net makes an older client's server probe fail as "offline" and it can never see "Update needed" (it cannot even update).
# RPCs on other nodes cannot do that: a client that is behind is turned away by the handshake first, and updates.
extends Node

const GM := preload("res://Scripts/gm_commands.gd")
const MAX_WRONG_PASSWORDS := 5

var _authorized := {}   # SERVER: peer id -> true for everyone who logged in as a game master with the password
var _wrong := {}        # SERVER: peer id -> wrong passwords typed on this connection


func _ready() -> void:
	add_to_group("gm_relay")
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		_authorized.erase(id)
		_wrong.erase(id))


# Client side: ask the server to run it.
func send(command: String, arg: String) -> void:
	_rpc_gm_command.rpc_id(1, command, arg)


# Client side: ask the server to make me a game master / stop being one.
func login(password: String) -> void:
	_rpc_gm_login.rpc_id(1, password)


func logout() -> void:
	_rpc_gm_logout.rpc_id(1)


func _who(sender: int) -> String:
	var player := TargetFrame.peer_id_to_player_node(sender)
	return str(player.get("player_name")) if is_instance_valid(player) else "?"


@rpc("any_peer", "call_remote", "reliable")
func _rpc_gm_login(password: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not Net.is_dedicated_server:
		_rpc_gm_login_result.rpc_id(sender, false, "Game master access is only available on a dedicated server.")
		return
	if int(_wrong.get(sender, 0)) >= MAX_WRONG_PASSWORDS:
		_rpc_gm_login_result.rpc_id(sender, false, "[color=red]Too many wrong passwords. Reconnect to try again.[/color]")
		return
	var problem: String = GM.check_password(password)
	if problem.is_empty():
		_authorized[sender] = true
		_wrong.erase(sender)
		Net._slog("GM login: %s (peer %d)" % [_who(sender), sender])
		_rpc_gm_login_result.rpc_id(sender, true, "")
	else:
		if problem.contains("Wrong"):
			_wrong[sender] = int(_wrong.get(sender, 0)) + 1
			Net._slog("GM login FAILED: %s (peer %d), wrong password %d of %d" % [_who(sender), sender, _wrong[sender], MAX_WRONG_PASSWORDS])
		_rpc_gm_login_result.rpc_id(sender, false, problem)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_gm_logout() -> void:
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		if _authorized.erase(sender) and Net.is_dedicated_server:
			Net._slog("GM logout: %s (peer %d)" % [_who(sender), sender])


@rpc("authority", "call_remote", "reliable")
func _rpc_gm_login_result(ok: bool, message: String) -> void:
	GM.apply_login_result(TargetFrame.local_player(), ok, message)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_gm_command(command: String, arg: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := TargetFrame.peer_id_to_player_node(sender)
	var reply: String = GM.run(player, command, arg, get_tree(), _authorized.has(sender))
	if Net.is_dedicated_server:
		Net._slog("GM command /%s %s from %s (peer %d): %s" % [command, arg, _who(sender), sender, "denied" if reply.contains("Only game masters") else "ok"])
	if not reply.is_empty():
		_rpc_gm_reply.rpc_id(sender, reply)


@rpc("authority", "call_remote", "reliable")
func _rpc_gm_reply(text: String) -> void:
	GameLog.log_general(text)
