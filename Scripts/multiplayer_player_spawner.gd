# multiplayer_player_spawner.gd — Attached to each zone's root. Spawns a
# player3d instance for every OTHER connected peer (the host's own character
# is the zone's pre-placed player3d node, authority 1 by default — no
# spawning needed for that one). Server-only: clients receive these spawns
# automatically via MultiplayerSpawner replication, no RPCs of our own needed.
# No-op entirely in single-player (Net.is_multiplayer_game stays false).
extends Node

@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var remote_players: Node3D = $RemotePlayers

const PLAYER_SCENE := preload("res://Scenes/player3d.tscn")


func _ready() -> void:
	spawner.spawn_function = _spawn_player

	if not Net.is_multiplayer_game or not multiplayer.is_server():
		return

	Net.player_connected.connect(_on_player_connected)
	Net.player_disconnected.connect(_on_player_disconnected)

	# Catch peers that connected before this zone finished loading.
	for peer_id in multiplayer.get_peers():
		_on_player_connected(peer_id)


func _on_player_connected(peer_id: int) -> void:
	spawner.spawn(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	var node := remote_players.get_node_or_null(str(peer_id))
	if is_instance_valid(node):
		node.queue_free()


# Runs on every peer (server included) as part of MultiplayerSpawner's
# replication — each machine builds its own local copy of the new player3d
# node, and setting multiplayer authority here (rather than after add_child
# server-side) is what makes it consistent across every peer.
func _spawn_player(peer_id: int) -> Node:
	var instance := PLAYER_SCENE.instantiate()
	instance.name = str(peer_id)
	instance.set_multiplayer_authority(peer_id)
	return instance
