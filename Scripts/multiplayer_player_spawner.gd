# multiplayer_player_spawner.gd — Attached to each zone's root. In a multiplayer
# game EVERY player — the host's own character included — is spawned here through
# the MultiplayerSpawner, so every peer builds identical nodes and a dedicated
# server (no character of its own) needs nothing special. The zone's pre-placed
# player3d is only used in single-player; see Net.omit_preplaced_player.
# Server-only: clients receive these spawns automatically via MultiplayerSpawner
# replication, no RPCs of our own needed. A joiner runs _start_joining() instead.
# No-op entirely in single-player (Net.is_multiplayer_game stays false).
extends Node

@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var remote_players: Node3D = $RemotePlayers

const PLAYER_SCENE := preload("res://Scenes/player3d.tscn")

## Where a brand-new character appears — the transform the zone's pre-placed player
## used to carry. Saved characters override it with their last position; it also
## becomes a new character's bind point (player3d.gd's _ensure_bind_point()).
@export var spawn_position := Vector3(-32.28161, 1.5000012, 12.601559)


func _ready() -> void:
	spawner.spawn_function = _spawn_player

	# A joiner connects only now, with every spawner/synchronizer node already in
	# place to receive what the host sends — see Net.begin_join() for why.
	if Net.has_pending_join():
		_start_joining()
		return

	if not Net.is_multiplayer_game or not multiplayer.is_server():
		return

	Net.player_connected.connect(_on_player_connected)
	Net.player_disconnected.connect(_on_player_disconnected)

	# The host plays too, unless this is a dedicated server.
	if not Net.is_dedicated_server:
		spawner.spawn(1)

	# Catch peers that connected before this zone finished loading.
	for peer_id in multiplayer.get_peers():
		_on_player_connected(peer_id)


var _connecting_layer: CanvasLayer = null


func _start_joining() -> void:
	_connecting_layer = CanvasLayer.new()
	_connecting_layer.layer = 50
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.03, 0.04, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_connecting_layer.add_child(backdrop)
	var label := Label.new()
	label.text = "Connecting to %s..." % Net.pending_join_label()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	_connecting_layer.add_child(label)
	add_child(_connecting_layer)

	Net.connection_failed.connect(_on_join_failed, CONNECT_ONE_SHOT)
	Net.server_disconnected.connect(_on_server_lost, CONNECT_ONE_SHOT)
	if Net.complete_pending_join() != OK:
		if Net.last_failure_reason.is_empty():
			Net.last_failure_reason = "Failed to start the connection."
		_on_join_failed()


# Covers the whole zone until the joiner's own character has been spawned and
# replicated back, so they never see a half-built world or a phantom character.
func _process(_delta: float) -> void:
	if is_instance_valid(_connecting_layer) and is_instance_valid(TargetFrame.local_player()):
		_connecting_layer.queue_free()
		_connecting_layer = null


# The host/server went away mid-game. Without this the joiner would be left in a zone
# with no server — and, with no peer, its spawner would start acting like a solo game.
func _on_server_lost() -> void:
	if not Net.last_join_was_server:  # a server's character is saved server-side; there's nothing local to write
		Global.save_player_data_to_file()
	Net.last_failure_reason = Net.server_shutdown_notice if not Net.server_shutdown_notice.is_empty() else "Lost connection to the server."
	_on_join_failed()


func _on_join_failed() -> void:
	Net.disconnect_game()
	if Net.last_join_was_server:
		Global.return_to_join_server_menu = true
	else:
		Global.return_to_multiplayer_menu = true
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")


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
	instance.position = spawn_position
	instance.set_multiplayer_authority(peer_id)
	return instance
