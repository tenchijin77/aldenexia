# gm_relay.gd — Carries game-master commands from a client to the server and the answer back (gm_commands.gd decides what a
# command does). It is a node in the zone scene, NOT part of Net, on purpose: the RPC set of the Net autoload has to stay exactly what
# already-distributed builds have. Godot compares each node's RPC list between peers, and Net carries the version handshake, so a
# changed Net makes an older client's server probe fail as "offline" and it can never see "Update needed" (it cannot even update).
# RPCs on other nodes cannot do that: a client that is behind is turned away by the handshake first, and updates.
extends Node

const GM := preload("res://Scripts/gm_commands.gd")


func _ready() -> void:
	add_to_group("gm_relay")


# Client side: ask the server to run it.
func send(command: String, arg: String) -> void:
	_rpc_gm_command.rpc_id(1, command, arg)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_gm_command(command: String, arg: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := TargetFrame.peer_id_to_player_node(sender)
	var reply: String = GM.run(player, command, arg, get_tree())
	if Net.is_dedicated_server:
		Net._slog("GM command /%s %s from %s (peer %d): %s" % [command, arg, str(player.get("player_name")) if is_instance_valid(player) else "?", sender, "denied" if reply.contains("Only game masters") else "ok"])
	if not reply.is_empty():
		_rpc_gm_reply.rpc_id(sender, reply)


@rpc("authority", "call_remote", "reliable")
func _rpc_gm_reply(text: String) -> void:
	GameLog.log_general(text)
