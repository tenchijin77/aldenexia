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

const DEFAULT_PORT := 8910
const MAX_PLAYERS := 6

var is_multiplayer_game := false
var pending_zone_path := "res://Scenes/lumora_outskirts3d.tscn"


func _ready() -> void:
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


func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	is_multiplayer_game = false
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	is_multiplayer_game = false
	server_disconnected.emit()
