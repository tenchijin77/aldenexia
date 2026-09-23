# world_items.gd — Items lying on the ground in little pouches. Drag an item out of a bag window and let go over the world (no
# window, no NPC under the cursor — slot_button.gd) and it drops at your feet as a pouch; right-click a pouch within
# PICKUP_RANGE (player3d.gd _try_pickup_pouch()) to take it back. Anyone can pick up anyone's pouch; the first one to ask
# gets it. A pouch disappears after LIFETIME_SECONDS.
#
# The SERVER owns the list of pouches (single-player and a listen-server host are their own server): a drop is sent to it,
# it tells every peer to show the pouch, and a pickup is a request it grants to exactly one player, so an item can never
# be picked up twice. A player who joins later asks for the pouches already lying around.
# Like GMRelay, this is a node in the zone scene, not part of Net: the Net autoload's RPC list must stay what released builds have.
# It also creates the TradeRelay (trade_relay.gd) as its child.
extends Node

const PICKUP_RANGE := 3.0
const LIFETIME_SECONDS := 900.0      # 15 minutes on the ground
const LABEL_RANGE := 12.0
const EXPIRY_CHECK_SECONDS := 5.0

var _pouches := {}          # SERVER: id -> {"item": Dictionary, "pos": Vector3, "expires_ms": int, "dropped_by": String}
var _nodes := {}            # every peer: id -> the pouch Node3D shown in the world
var _next_id := 1
var _expiry_timer := 0.0
var _asked_for_snapshot := false
var _label_timer := 0.0


const TRADE_RELAY := preload("res://Scripts/trade_relay.gd")


func _ready() -> void:
	add_to_group("world_items")
	# Player-to-player trading rides along on this node: made here on every peer, so its path (and RPCs) match everywhere
	# without another node in the zone scene.
	var relay := TRADE_RELAY.new()
	relay.name = "TradeRelay"
	add_child(relay)
	multiplayer.server_disconnected.connect(func() -> void: _asked_for_snapshot = false)


func _process(delta: float) -> void:
	if _is_server():
		_expiry_timer -= delta
		if _expiry_timer <= 0.0:
			_expiry_timer = EXPIRY_CHECK_SECONDS
			_expire_old()
	elif not _asked_for_snapshot and is_instance_valid(TargetFrame.local_player()):
		# A client that just arrived: ask for what is already on the ground (once its own character is in the world).
		_asked_for_snapshot = true
		_rpc_request_snapshot.rpc_id(1)
	_label_timer -= delta
	if _label_timer <= 0.0:
		_label_timer = 0.25
		_update_labels()


# ── Called by the game (on the player's own machine) ─────────────────────────────────────────────────────────────────

# Puts an item (already taken out of the inventory by the caller) on the ground at `pos` as a pouch.
func drop(item: Dictionary, pos: Vector3, dropped_by: String) -> void:
	if _is_server():
		_server_drop(item, pos, dropped_by)
	else:
		_rpc_drop.rpc_id(1, JSON.stringify(item), pos, dropped_by)


# The pouch nearest `pos` within PICKUP_RANGE (-1 if none).
func nearest_pouch(pos: Vector3) -> int:
	var best := -1
	var best_dist := PICKUP_RANGE
	for id in _nodes:
		var node: Node3D = _nodes[id]
		if is_instance_valid(node):
			var dist := node.global_position.distance_to(pos)
			if dist <= best_dist:
				best_dist = dist
				best = id
	return best


# Asks for the pouch; the item arrives in _receive_item() if nobody else got there first.
func pick_up(id: int) -> void:
	if _is_server():
		_server_claim(id, multiplayer.get_unique_id())
	else:
		_rpc_claim.rpc_id(1, id)


# ── Server ──────────────────────────────────────────────────────────────────────────────────────────────────────────

func _is_server() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _has_remote_peers() -> bool:
	return multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
			and not multiplayer.get_peers().is_empty()


func _server_drop(item: Dictionary, pos: Vector3, dropped_by: String) -> void:
	if item.is_empty() or str(item.get("item_id", "")).is_empty():
		return
	var id := _next_id
	_next_id += 1
	_pouches[id] = {"item": item, "pos": pos, "dropped_by": dropped_by,
			"expires_ms": Time.get_ticks_msec() + int(LIFETIME_SECONDS * 1000.0)}
	var label := _label_for(item)
	if not Net.is_dedicated_server:
		_show_pouch(id, pos, label)
	if _has_remote_peers():
		_rpc_show.rpc(id, pos, label)


func _server_claim(id: int, peer: int) -> void:
	if not _pouches.has(id):
		return  # someone else was quicker (or it just expired)
	var item: Dictionary = _pouches[id]["item"]
	_remove_everywhere(id)
	if peer == multiplayer.get_unique_id():
		_receive_item(item)
	else:
		_rpc_give.rpc_id(peer, JSON.stringify(item))


func _remove_everywhere(id: int) -> void:
	_pouches.erase(id)
	_hide_pouch(id)
	if _has_remote_peers():
		_rpc_hide.rpc(id)


func _expire_old() -> void:
	var now := Time.get_ticks_msec()
	for id in _pouches.keys():
		if now >= int(_pouches[id]["expires_ms"]):
			_remove_everywhere(id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_drop(item_json: String, pos: Vector3, dropped_by: String) -> void:
	if not multiplayer.is_server():
		return
	var item: Variant = JSON.parse_string(item_json)
	if typeof(item) == TYPE_DICTIONARY:
		_server_drop(item, pos, dropped_by)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_claim(id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := TargetFrame.peer_id_to_player_node(sender) as Node3D
	# The claim must come from someone standing by it (a little slack for lag).
	if _pouches.has(id) and is_instance_valid(player) and player.global_position.distance_to(_pouches[id]["pos"]) > PICKUP_RANGE + 4.0:
		return
	_server_claim(id, sender)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_snapshot() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	for id in _pouches:
		_rpc_show.rpc_id(sender, id, _pouches[id]["pos"], _label_for(_pouches[id]["item"]))


# ── Every peer: what is shown ────────────────────────────────────────────────────────────────────────────────────────

@rpc("authority", "call_remote", "reliable")
func _rpc_show(id: int, pos: Vector3, label: String) -> void:
	_show_pouch(id, pos, label)


@rpc("authority", "call_remote", "reliable")
func _rpc_hide(id: int) -> void:
	_hide_pouch(id)


@rpc("authority", "call_remote", "reliable")
func _rpc_give(item_json: String) -> void:
	var item: Variant = JSON.parse_string(item_json)
	if typeof(item) == TYPE_DICTIONARY:
		_receive_item(item)


# The pouch's item goes into the bags; if they are full it goes straight back on the ground.
func _receive_item(item: Dictionary) -> void:
	var item_id := str(item.get("item_id", ""))
	var qty := int(item.get("quantity", 1)) if item.get("stackable", false) else 1
	var player := TargetFrame.local_player() as Node3D
	if Inventory.add_item(item_id, qty):
		GameLog.log_general("[color=#88ffaa]You pick up %s.[/color]" % _label_for(item))
	else:
		GameLog.log_general("[color=#ff8866]Your bags are full — the pouch stays on the ground.[/color]")
		if is_instance_valid(player):
			drop(item, player.global_position, str(player.get("player_name")))


func _label_for(item: Dictionary) -> String:
	var qty := int(item.get("quantity", 1)) if item.get("stackable", false) else 1
	return "%s%s" % [str(item.get("name", item.get("item_id", "something"))), (" x%d" % qty) if qty > 1 else ""]


func _show_pouch(id: int, pos: Vector3, label: String) -> void:
	_hide_pouch(id)
	var zone := get_tree().current_scene
	if zone == null:
		return
	var pouch := _build_pouch(label)
	pouch.name = "Pouch_%d" % id
	zone.add_child(pouch)
	pouch.global_position = pos
	_nodes[id] = pouch


func _hide_pouch(id: int) -> void:
	var node: Node = _nodes.get(id)
	_nodes.erase(id)
	if is_instance_valid(node):
		node.queue_free()


func _update_labels() -> void:
	var player := TargetFrame.local_player() as Node3D
	for id in _nodes:
		var node: Node3D = _nodes[id]
		if not is_instance_valid(node):
			continue
		var label := node.get_node_or_null("Label") as Label3D
		if label:
			label.visible = is_instance_valid(player) and player.global_position.distance_to(node.global_position) <= LABEL_RANGE


# A small leather drawstring pouch, built in code: a squat sack, a cinched neck, a tie, and the item's name above it.
func _build_pouch(label_text: String) -> Node3D:
	var root := Node3D.new()
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.45, 0.3, 0.17)
	leather.roughness = 0.85
	var sack := MeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = 0.2
	body.height = 0.3
	sack.mesh = body
	sack.material_override = leather
	sack.position = Vector3(0, 0.14, 0)
	root.add_child(sack)
	var neck := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.09
	cone.bottom_radius = 0.05
	cone.height = 0.12
	neck.mesh = cone
	neck.material_override = leather
	neck.position = Vector3(0, 0.33, 0)
	root.add_child(neck)
	var tie := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.045
	ring.outer_radius = 0.065
	tie.mesh = ring
	var cord := StandardMaterial3D.new()
	cord.albedo_color = Color(0.85, 0.7, 0.35)
	tie.material_override = cord
	tie.position = Vector3(0, 0.29, 0)
	root.add_child(tie)
	root.rotation_degrees.y = randf() * 360.0
	var label := Label3D.new()
	label.name = "Label"
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.pixel_size = 0.004
	label.outline_size = 8
	label.modulate = Color(1.0, 0.9, 0.6)
	label.position = Vector3(0, 0.65, 0)
	label.visible = false
	root.add_child(label)
	return root
