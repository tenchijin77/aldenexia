# trade_relay.gd — Player-to-player trading (items and coin). Right-click another player (or /trade with them targeted, or
# /trade <name>) to ask; they get an Accept/Decline popup; then both see the trade window (trade_window.gd): drag items
# from your bags into your side, set any coin, and press Accept. Changing either side clears both Accepts, so nobody is
# ever caught out by a last-second swap.
#
# The SERVER brokers every trade (a listen-server host is its own server). Characters keep their own inventories, so when
# both have accepted the server first asks each side to CHECK it still has everything it offered and has room for what it
# is getting (_rpc_verify). Only when both say yes does it tell both to make the swap (_rpc_commit); if either can't,
# nothing moves and the trade stays open with the reason shown. Walking more than MAX_DISTANCE apart, logging off or
# closing the window cancels it.
# A child of the zone's WorldItems node (created there on every peer), not part of Net: the Net autoload's RPC list must not change.
extends Node

const MAX_DISTANCE := 12.0
const INVITE_SECONDS := 30.0
const MAX_ITEMS := 8
const TRADE_WINDOW := preload("res://Scripts/trade_window.gd")

# SERVER state
var _invites := {}          # invited peer -> {"from": peer, "until_ms": int}
var _sessions := {}         # session id -> {"a": peer, "b": peer, "offers": {peer: {"items": [], "copper": 0}}, "accepted": {peer: bool}, "verifying": {peer: bool/null}}
var _peer_session := {}     # peer -> session id
var _next_session := 1

# CLIENT state (this player's machine)
var window: Node = null     # the open trade window, if any
var _pending_invite_from := 0


func _ready() -> void:
	add_to_group("trade_relay")
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(_delta: float) -> void:
	if not _is_server():
		return
	# Too far apart: the trade is off.
	for sid in _sessions.keys():
		var s: Dictionary = _sessions[sid]
		var a := _player(s["a"])
		var b := _player(s["b"])
		if a == null or b == null or a.global_position.distance_to(b.global_position) > MAX_DISTANCE:
			_end_session(sid, "You moved too far apart — the trade is cancelled.")


# ── Client API (called on the player's own machine) ─────────────────────────────────────────────────────────────────

# Ask `target` (another player's character node) to trade.
func request_trade(target: Node) -> void:
	var me := TargetFrame.local_player()
	if not is_instance_valid(target) or target == me or not target.is_in_group("player"):
		GameLog.log_general("You can only trade with another player.")
		return
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		GameLog.log_general("There is nobody else here to trade with.")
		return
	if (me as Node3D).global_position.distance_to((target as Node3D).global_position) > MAX_DISTANCE:
		GameLog.log_general("%s is too far away to trade." % str(target.get("player_name")))
		return
	_to_server("_srv_request", [target.get_multiplayer_authority()])
	GameLog.log_general("You ask %s to trade." % str(target.get("player_name")))


func set_offer(items: Array, copper: int) -> void:
	_to_server("_srv_set_offer", [JSON.stringify(items), copper])


func set_accepted(accepted: bool) -> void:
	_to_server("_srv_accept", [accepted])


func cancel() -> void:
	_to_server("_srv_cancel", [])


func answer_invite(accepted: bool) -> void:
	if _pending_invite_from == 0:
		return
	_to_server("_srv_answer", [_pending_invite_from, accepted])
	_pending_invite_from = 0


# ── Plumbing ────────────────────────────────────────────────────────────────────────────────────────────────────────

func _is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _my_id() -> int:
	return multiplayer.get_unique_id()


# Client -> server: an RPC, or a direct call when this machine IS the server (a listen-server host trading).
func _to_server(method: String, args: Array) -> void:
	if _is_server():
		callv(method, [_my_id()] + args)
	else:
		callv("rpc_id", [1, "_rpc" + method.trim_prefix("_srv")] + args)


# Server -> one client: an RPC, or a direct call when that client is this machine.
func _to_client(peer: int, method: String, args: Array) -> void:
	if peer == _my_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer, method] + args)


func _player(peer: int) -> Node3D:
	return TargetFrame.peer_id_to_player_node(peer) as Node3D


func _name(peer: int) -> String:
	var p := _player(peer)
	return str(p.get("player_name")) if p != null else "Someone"


# Client -> server RPCs: each just hands over to the matching _srv_ function with the sender's id.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(target_peer: int) -> void:
	if multiplayer.is_server():
		_srv_request(multiplayer.get_remote_sender_id(), target_peer)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_answer(from_peer: int, accepted: bool) -> void:
	if multiplayer.is_server():
		_srv_answer(multiplayer.get_remote_sender_id(), from_peer, accepted)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_offer(items_json: String, copper: int) -> void:
	if multiplayer.is_server():
		_srv_set_offer(multiplayer.get_remote_sender_id(), items_json, copper)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_accept(accepted: bool) -> void:
	if multiplayer.is_server():
		_srv_accept(multiplayer.get_remote_sender_id(), accepted)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_cancel() -> void:
	if multiplayer.is_server():
		_srv_cancel(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_verify_result(ok: bool, reason: String) -> void:
	if multiplayer.is_server():
		_srv_verify_result(multiplayer.get_remote_sender_id(), ok, reason)


# ── Server ──────────────────────────────────────────────────────────────────────────────────────────────────────────

func _srv_request(from: int, target: int) -> void:
	var a := _player(from)
	var b := _player(target)
	if a == null or b == null or from == target:
		return
	if _peer_session.has(from):
		_to_client(from, "_cl_notice", ["You are already trading."])
		return
	if _peer_session.has(target) or _invites.has(target):
		_to_client(from, "_cl_notice", ["%s is busy." % _name(target)])
		return
	if a.global_position.distance_to(b.global_position) > MAX_DISTANCE:
		_to_client(from, "_cl_notice", ["%s is too far away to trade." % _name(target)])
		return
	_invites[target] = {"from": from, "until_ms": Time.get_ticks_msec() + int(INVITE_SECONDS * 1000.0)}
	_to_client(target, "_cl_invite", [from, _name(from)])


func _srv_answer(answerer: int, from: int, accepted: bool) -> void:
	var invite: Dictionary = _invites.get(answerer, {})
	_invites.erase(answerer)
	if invite.is_empty() or int(invite["from"]) != from or Time.get_ticks_msec() > int(invite["until_ms"]):
		_to_client(answerer, "_cl_notice", ["That trade offer has expired."])
		return
	if not accepted:
		_to_client(from, "_cl_notice", ["%s declines to trade." % _name(answerer)])
		return
	if _peer_session.has(from) or _peer_session.has(answerer):
		_to_client(answerer, "_cl_notice", ["%s is busy." % _name(from)])
		return
	var sid := _next_session
	_next_session += 1
	_sessions[sid] = {"a": from, "b": answerer,
			"offers": {from: {"items": [], "copper": 0}, answerer: {"items": [], "copper": 0}},
			"accepted": {from: false, answerer: false}, "verifying": {}}
	_peer_session[from] = sid
	_peer_session[answerer] = sid
	_to_client(from, "_cl_open", [answerer, _name(answerer)])
	_to_client(answerer, "_cl_open", [from, _name(from)])


func _srv_set_offer(peer: int, items_json: String, copper: int) -> void:
	var sid: int = _peer_session.get(peer, 0)
	if sid == 0:
		return
	var items: Variant = JSON.parse_string(items_json)
	if typeof(items) != TYPE_ARRAY:
		return
	var clean: Array = []
	for entry in (items as Array).slice(0, MAX_ITEMS):
		if typeof(entry) == TYPE_DICTIONARY and not str(entry.get("item_id", "")).is_empty() and int(entry.get("quantity", 0)) > 0:
			clean.append({"item_id": str(entry["item_id"]), "quantity": int(entry["quantity"])})
	var s: Dictionary = _sessions[sid]
	s["offers"][peer] = {"items": clean, "copper": maxi(copper, 0)}
	s["accepted"] = {s["a"]: false, s["b"]: false}   # any change clears both Accepts
	s["verifying"] = {}
	_send_state(sid)


func _srv_accept(peer: int, accepted: bool) -> void:
	var sid: int = _peer_session.get(peer, 0)
	if sid == 0:
		return
	var s: Dictionary = _sessions[sid]
	s["accepted"][peer] = accepted
	_send_state(sid)
	if s["accepted"][s["a"]] and s["accepted"][s["b"]]:
		# Both accepted: each side checks it can really do its half before anything moves.
		s["verifying"] = {s["a"]: null, s["b"]: null}
		for p in [s["a"], s["b"]]:
			var other: int = s["b"] if p == s["a"] else s["a"]
			_to_client(p, "_cl_verify", [JSON.stringify(s["offers"][p]["items"]), int(s["offers"][p]["copper"]),
					JSON.stringify(s["offers"][other]["items"]), int(s["offers"][other]["copper"])])


func _srv_verify_result(peer: int, ok: bool, reason: String) -> void:
	var sid: int = _peer_session.get(peer, 0)
	if sid == 0:
		return
	var s: Dictionary = _sessions[sid]
	if not s["verifying"].has(peer):
		return  # the offer changed in the meantime: a stale answer
	if not ok:
		s["accepted"] = {s["a"]: false, s["b"]: false}
		s["verifying"] = {}
		for p in [s["a"], s["b"]]:
			_to_client(p, "_cl_notice", [reason if p == peer else "%s can't complete the trade: %s" % [_name(peer), reason]])
		_send_state(sid)
		return
	s["verifying"][peer] = true
	if s["verifying"][s["a"]] == true and s["verifying"][s["b"]] == true:
		var a: int = s["a"]
		var b: int = s["b"]
		if Net.is_dedicated_server:
			Net._slog("Trade: %s gave %s, %s gave %s" % [_name(a), JSON.stringify(s["offers"][a]), _name(b), JSON.stringify(s["offers"][b])])
		for p in [a, b]:
			var other: int = b if p == a else a
			_to_client(p, "_cl_commit", [JSON.stringify(s["offers"][p]["items"]), int(s["offers"][p]["copper"]),
					JSON.stringify(s["offers"][other]["items"]), int(s["offers"][other]["copper"]), _name(other)])
		_end_session(sid, "")


func _srv_cancel(peer: int) -> void:
	var sid: int = _peer_session.get(peer, 0)
	if sid != 0:
		_end_session(sid, "%s cancelled the trade." % _name(peer))


func _send_state(sid: int) -> void:
	var s: Dictionary = _sessions[sid]
	for p in [s["a"], s["b"]]:
		var other: int = s["b"] if p == s["a"] else s["a"]
		_to_client(p, "_cl_state", [JSON.stringify(s["offers"][p]["items"]), int(s["offers"][p]["copper"]),
				JSON.stringify(s["offers"][other]["items"]), int(s["offers"][other]["copper"]),
				bool(s["accepted"][p]), bool(s["accepted"][other])])


func _end_session(sid: int, reason: String) -> void:
	var s: Dictionary = _sessions.get(sid, {})
	_sessions.erase(sid)
	if s.is_empty():
		return
	for p in [s["a"], s["b"]]:
		_peer_session.erase(p)
		if _player(p) != null or p == _my_id():
			_to_client(p, "_cl_closed", [reason])


func _on_peer_disconnected(peer: int) -> void:
	if not _is_server():
		return
	_invites.erase(peer)
	var sid: int = _peer_session.get(peer, 0)
	if sid != 0:
		var s: Dictionary = _sessions[sid]
		_peer_session.erase(peer)
		s["a" if s["a"] == peer else "b"] = -1
		var other: int = s["b"] if s["a"] == -1 else s["a"]
		_sessions.erase(sid)
		_peer_session.erase(other)
		_to_client(other, "_cl_closed", ["The other player left — the trade is cancelled."])


# ── Client ──────────────────────────────────────────────────────────────────────────────────────────────────────────

@rpc("authority", "call_remote", "reliable")
func _cl_notice(text: String) -> void:
	GameLog.log_general("[color=#ffcc88]%s[/color]" % text)


@rpc("authority", "call_remote", "reliable")
func _cl_invite(from: int, from_name: String) -> void:
	_pending_invite_from = from
	_show_invite_popup(from_name)


@rpc("authority", "call_remote", "reliable")
func _cl_open(partner: int, partner_name: String) -> void:
	if is_instance_valid(window):
		window.queue_free()
	window = TRADE_WINDOW.new()
	get_tree().root.add_child(window)
	window.setup(self, partner_name)
	GameLog.log_general("[color=#ffcc88]You are trading with %s.[/color]" % partner_name)


@rpc("authority", "call_remote", "reliable")
func _cl_state(my_items: String, my_copper: int, their_items: String, their_copper: int, i_accepted: bool, they_accepted: bool) -> void:
	if is_instance_valid(window):
		window.show_state(_parse(my_items), my_copper, _parse(their_items), their_copper, i_accepted, they_accepted)


# Both accepted: can I really do my half? (still have what I offer, can afford my coin, have room for what I get)
@rpc("authority", "call_remote", "reliable")
func _cl_verify(give_json: String, give_copper: int, get_json: String, _get_copper: int) -> void:
	var give := _parse(give_json)
	var problem := ""
	var need := {}
	for entry in give:
		need[entry["item_id"]] = int(need.get(entry["item_id"], 0)) + int(entry["quantity"])
	for item_id in need:
		if ItemHelper.count(item_id) < int(need[item_id]):
			problem = "you no longer have everything you offered."
	if problem.is_empty() and not Global.can_afford(give_copper):
		problem = "you don't have that much coin."
	if problem.is_empty() and not Inventory.can_fit_all(_parse(get_json), give):
		problem = "there isn't room in your bags."
	_to_server("_srv_verify_result", [problem.is_empty(), "You can't complete the trade: " + problem if not problem.is_empty() else ""])


# The swap itself: take out what I gave, put in what I got.
@rpc("authority", "call_remote", "reliable")
func _cl_commit(give_json: String, give_copper: int, get_json: String, get_copper: int, partner_name: String) -> void:
	var gave: Array = []
	var got: Array = []
	for entry in _parse(give_json):
		ItemHelper.consume(entry["item_id"], int(entry["quantity"]))
		gave.append(_entry_text(entry))
	for entry in _parse(get_json):
		Inventory.add_item(entry["item_id"], int(entry["quantity"]))
		got.append(_entry_text(entry))
	if give_copper > 0:
		Global.spend_currency_copper(give_copper)
		gave.append(TRADE_WINDOW.coins_text(give_copper))
	if get_copper > 0:
		Global.add_currency_copper(get_copper)
		got.append(TRADE_WINDOW.coins_text(get_copper))
	Global.save_player_data_to_file()
	GameLog.log_general("[color=#88ffaa]Trade with %s complete.[/color]" % partner_name)
	if not gave.is_empty():
		GameLog.log_general("[color=#cccccc]  You gave: %s[/color]" % ", ".join(gave))
	if not got.is_empty():
		GameLog.log_general("[color=#cccccc]  You received: %s[/color]" % ", ".join(got))


@rpc("authority", "call_remote", "reliable")
func _cl_closed(reason: String) -> void:
	if not reason.is_empty():
		GameLog.log_general("[color=#ffcc88]%s[/color]" % reason)
	if is_instance_valid(window):
		window.queue_free()
	window = null


func _parse(json_text: String) -> Array:
	var parsed: Variant = JSON.parse_string(json_text)
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func _entry_text(entry: Dictionary) -> String:
	var item_name := str(Inventory.get_item_definition(str(entry["item_id"])).get("name", entry["item_id"]))
	return ("%d %s" % [int(entry["quantity"]), item_name]) if int(entry["quantity"]) > 1 else item_name


# "<Name> would like to trade with you." — Trade / Decline, in the same popup as a group invite (group_invite_popup.gd,
# centred and draggable); it declines itself after INVITE_SECONDS.
func _show_invite_popup(from_name: String) -> void:
	var popup: Node = load("res://Scenes/group_invite_popup.tscn").instantiate()
	get_tree().root.add_child(popup)
	popup.ask("%s would like to trade with you." % from_name, "Trade", "Decline", answer_invite)
	get_tree().create_timer(INVITE_SECONDS).timeout.connect(func():
		if is_instance_valid(popup):
			popup.expire())
