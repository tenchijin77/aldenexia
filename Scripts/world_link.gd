# world_link.gd — makes /tell, /who and the "enters / leaves the world" announcements work across zones (test 37).
# Every zone is its own server process on the same machine (tools/run_world.sh). The login server (the default zone)
# is the HUB: it listens on 127.0.0.1 only (base port + LINK_OFFSET, e.g. 8919: never reachable from outside, nothing
# to open on a firewall). Every other zone server connects to it. Over the link go:
#   roster    each zone's players (name, surname, level, class) whenever they change; the hub hands every zone the
#             whole world's list, so /who answers at once
#   announce  "X enters / leaves the world", passed to every other zone
#   tell      routed to the zone the player is in; the sender hears back whether it arrived
# Messages are one JSON object per line. If the link is down (a zone started alone), everything still works inside
# the zone, as before. /shout (/zone) stays zone-wide on purpose.
# A node in each zone scene (not Net: Net's RPC list must never change, see gm_relay.gd). Client side it carries the
# requests to the server and the answers back.
extends Node

const LINK_OFFSET := 9
const ROSTER_EVERY := 3.0     # seconds between roster checks
const RECONNECT_EVERY := 5.0

var _hub: TCPServer = null                 # the hub's listener
var _peers: Array = []                     # hub: [{tcp, buf, zone}]
var _up: StreamPeerTCP = null              # a zone's connection to the hub
var _up_buf := ""
var _up_hello := false
var _world: Dictionary = {}                # zone id -> [player rows] (the whole world, as the hub last said)
var _last_roster := ""
var _roster_timer := 0.0
var _reconnect_timer := 0.0
var _pending_tells := {}                   # client: lower-case name -> {message, lang} waiting for the server's answer
# Groups (test 38: zoning dropped your group). The hub keeps every group by character NAME — a zone's peer ids mean
# nothing in another zone — and hands the list to every zone: {leader lower-case: {"leader": Name, "members": [Names]}}.
# Each zone tells its players who is in their group and which of them are here (the local ones get group heals, the
# frame's health bars, XP sharing...). Invites still happen face to face (the popup); the leader's game reports the
# new list (request_group_set). /party goes through here to every member in any zone.
var groups: Dictionary = {}
var _pushed := {}                          # zone: peer id -> the group state last sent to them


func _ready() -> void:
	add_to_group("world_link")


func _server_active() -> bool:
	return Net.is_dedicated_server and multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func is_hub() -> bool:
	return ZoneInfo.current_id() == ZoneInfo.DEFAULT_ID


func link_port() -> int:
	return int(Net.base_port) + LINK_OFFSET


func _process(delta: float) -> void:
	if not _server_active():
		return
	if is_hub():
		_hub_process()
	else:
		_zone_process(delta)
	_roster_timer -= delta
	if _roster_timer <= 0.0:
		_roster_timer = ROSTER_EVERY
		_share_roster()
		_push_groups()   # only sends what changed for each player: catches anything a message missed


# ── The hub ──
func _hub_process() -> void:
	if _hub == null:
		_hub = TCPServer.new()
		if _hub.listen(link_port(), "127.0.0.1") != OK:
			Net._slog("World link: can't listen on 127.0.0.1:%d — zones won't share chat" % link_port())
			_hub = null
			set_process(false)
			return
		Net._slog("World link: hub listening on 127.0.0.1:%d" % link_port())
	while _hub.is_connection_available():
		var tcp := _hub.take_connection()
		tcp.set_no_delay(true)
		_peers.append({"tcp": tcp, "buf": "", "zone": ""})
	for p in _peers.duplicate():
		var tcp: StreamPeerTCP = p["tcp"]
		tcp.poll()
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.erase(p)
			if not str(p["zone"]).is_empty():
				_world.erase(p["zone"])
				Net._slog("World link: %s disconnected" % p["zone"])
				_hub_send_world()
			continue
		for msg in _read(tcp, p):
			_hub_handle(p, msg)


func _hub_handle(from: Dictionary, msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"hello":
			from["zone"] = str(msg.get("zone", ""))
			Net._slog("World link: %s connected" % from["zone"])
			_write(from["tcp"], {"t": "groups", "groups": groups})
		"roster":
			_world[str(msg.get("zone", ""))] = msg.get("players", [])
			_hub_send_world()
			_push_groups()   # a member arriving in the hub's zone
		"announce":
			_deliver_announce(msg)                       # the hub's own players
			for p in _peers:
				if p != from:
					_write(p["tcp"], msg)
		"tell":
			_route_tell(msg)
		"tell_result":
			_route_to_zone(str(msg.get("origin", "")), msg)
		"notice", "party":
			_handle_local(msg)                           # the hub's own players
			for p in _peers:
				if p != from:
					_write(p["tcp"], msg)
		"group_set", "group_leave", "group_join":
			_hub_group(msg)
		"to_player":
			_send_to_player(msg)


func _hub_send_world() -> void:
	var msg := {"t": "world", "world": _world}
	for p in _peers:
		_write(p["tcp"], msg)


# A tell arriving at the hub (from a zone, or from the hub's own player): deliver it where that player is.
func _route_tell(msg: Dictionary) -> void:
	var zone := zone_of(str(msg.get("to", "")))
	if zone.is_empty():
		_tell_result(msg, false, "")
		return
	if zone == ZoneInfo.current_id():
		_deliver_tell(msg)
	else:
		_route_to_zone(zone, msg)


func _route_to_zone(zone: String, msg: Dictionary) -> void:
	if zone == ZoneInfo.current_id():
		_handle_local(msg)
		return
	for p in _peers:
		if p["zone"] == zone:
			_write(p["tcp"], msg)
			return


# ── A zone ──
func _zone_process(delta: float) -> void:
	if _up == null or _up.get_status() == StreamPeerTCP.STATUS_NONE or _up.get_status() == StreamPeerTCP.STATUS_ERROR:
		_reconnect_timer -= delta
		if _reconnect_timer > 0.0:
			return
		_reconnect_timer = RECONNECT_EVERY
		_up = StreamPeerTCP.new()
		_up_hello = false
		_up_buf = ""
		_up.connect_to_host("127.0.0.1", link_port())
		return
	_up.poll()
	if _up.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	if not _up_hello:
		_up_hello = true
		_up.set_no_delay(true)
		_write(_up, {"t": "hello", "zone": ZoneInfo.current_id()})
		_last_roster = ""   # send it again
		Net._slog("World link: connected to the hub on 127.0.0.1:%d" % link_port())
	var holder := {"buf": _up_buf}
	for msg in _read(_up, holder):
		_handle_local(msg)
	_up_buf = holder["buf"]


# Messages that land on this zone (a zone from the hub, or the hub for its own players).
func _handle_local(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"world":
			_world = msg.get("world", {})
			_push_groups()
		"announce":
			_deliver_announce(msg)
		"notice":
			if str(msg.get("from", "")) != ZoneInfo.current_id():
				var board := get_tree().get_first_node_in_group("server_notice")
				if board != null:
					board.broadcast(str(msg.get("text", "")))
		"party":
			_deliver_party(msg)
		"groups":
			groups = msg.get("groups", {})
			_push_groups()
		"tell":
			_deliver_tell(msg)
		"to_player":
			_deliver_to_player(msg)
		"tell_result":
			var peer := int(msg.get("peer", 0))
			if peer > 0 and multiplayer.get_peers().has(peer):
				_rpc_tell_result.rpc_id(peer, str(msg.get("to", "")), bool(msg.get("ok", false)), str(msg.get("display", "")))


func _send_up(msg: Dictionary) -> bool:
	if is_hub():
		return false
	if _up == null or _up.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	_write(_up, msg)
	return true


# ── Roster ──
func local_players() -> Array:
	var rows := []
	for node in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(node):
			continue
		var info := WorldAnnouncer.player_info(node)
		if info["name"] == "Default Hero" or info["name"] == "Someone":
			continue
		rows.append({"name": info["name"], "surname": info["surname"], "level": info["level"], "class": info["class"],
				"peer": node.get_multiplayer_authority()})
	return rows


func _share_roster() -> void:
	var rows := local_players()
	var text := JSON.stringify(rows)
	if text == _last_roster:
		return
	if is_hub():
		_last_roster = text
		_world[ZoneInfo.current_id()] = rows
		_hub_send_world()
		_push_groups()   # someone arrived in (or left) the hub's own zone (test 42: back in the Outskirts, she'd lost her group)
	elif _send_up({"t": "roster", "zone": ZoneInfo.current_id(), "players": rows}):
		_last_roster = text


# The zone a player is in ("" = not online anywhere we know of). The world list covers every zone.
func zone_of(player_name: String) -> String:
	var want := player_name.to_lower()
	for row in local_players():
		if str(row["name"]).to_lower() == want:
			return ZoneInfo.current_id()
	for zone in _world:
		for row in _world[zone]:
			if str(row.get("name", "")).to_lower() == want:
				return zone
	return ""


# /who for the whole world: every zone's players, grouped by zone.
func who_text(asker: String) -> String:
	var world := _world.duplicate(true)
	world[ZoneInfo.current_id()] = local_players()
	var rows := []
	for zone in world:
		for r in world[zone]:
			var row: Dictionary = r.duplicate()
			row["zone"] = zone
			rows.append(row)
	rows.sort_custom(func(a, b): return String(a["name"]).to_lower() < String(b["name"]).to_lower())
	var out := ["[color=#88ccff]Players in Aldenexia (%d):[/color]" % rows.size()]
	for r in rows:
		var full := str(r["name"]) + (" " + str(r["surname"]) if not str(r.get("surname", "")).is_empty() else "")
		out.append("  [b]%s[/b] — Level %d %s — %s%s" % [full.replace("[", "[lb]"), int(r["level"]), str(r["class"]),
				ZoneInfo.name_for(str(r["zone"])), " (you)" if str(r["name"]) == asker else ""])
	return "\n".join(out)


# ── Announcements ──
# A world announcement made in this zone: pass it to every other zone.
func share_announce(kind: String, pname: String, level: int, cls: String, variant: int) -> void:
	if not _server_active():
		return
	var msg := {"t": "announce", "kind": kind, "name": pname, "level": level, "cls": cls, "variant": variant, "from": ZoneInfo.current_id()}
	if is_hub():
		for p in _peers:
			_write(p["tcp"], msg)
	else:
		_send_up(msg)


func _deliver_announce(msg: Dictionary) -> void:
	if str(msg.get("from", "")) == ZoneInfo.current_id():
		return
	for pid in multiplayer.get_peers():
		Net._rpc_receive_world_announce.rpc_id(pid, str(msg["kind"]), str(msg["name"]), int(msg["level"]), str(msg["cls"]), int(msg["variant"]))


# ── Tells ──
func _deliver_tell(msg: Dictionary) -> void:
	var want := str(msg.get("to", "")).to_lower()
	for node in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(node) and str(node.get("player_name")).to_lower() == want:
			Net._rpc_receive_tell.rpc_id(node.get_multiplayer_authority(), str(msg.get("from", "")), str(msg.get("message", "")))
			_tell_result(msg, true, TargetFrame.display_name(node))
			return
	_tell_result(msg, false, "")


func _tell_result(msg: Dictionary, ok: bool, display: String) -> void:
	var result := {"t": "tell_result", "origin": str(msg.get("origin", "")), "peer": int(msg.get("peer", 0)),
			"to": str(msg.get("to", "")), "ok": ok, "display": display}
	if str(msg.get("origin", "")) == ZoneInfo.current_id():
		_handle_local(result)
	elif is_hub():
		_route_to_zone(str(msg.get("origin", "")), result)
	else:
		_send_up(result)


# ── Client <-> server ──
# Client: ask the server to send a tell to someone who may be in another zone.
func request_tell(to: String, encoded: String, plain: String, lang: String) -> void:
	_pending_tells[to.to_lower()] = {"message": plain, "lang": lang}
	_rpc_tell.rpc_id(1, to, encoded)


func request_who() -> void:
	_rpc_who.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_tell(to: String, message: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var from_node := TargetFrame.peer_id_to_player_node(sender)
	if not is_instance_valid(from_node):
		return
	var msg := {"t": "tell", "from": str(from_node.get("player_name")), "to": to, "message": message.substr(0, 600),   # already cleaned by the sender; cleaning again would strip the language marks
			"origin": ZoneInfo.current_id(), "peer": sender}
	var zone := zone_of(to)
	if zone == ZoneInfo.current_id():
		_deliver_tell(msg)
	elif zone.is_empty():
		_tell_result(msg, false, "")
	elif is_hub():
		_route_to_zone(zone, msg)
	elif not _send_up(msg):
		_tell_result(msg, false, "")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_who() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var node := TargetFrame.peer_id_to_player_node(sender)
	_rpc_who_result.rpc_id(sender, who_text(str(node.get("player_name")) if is_instance_valid(node) else ""))


@rpc("authority", "call_remote", "reliable")
func _rpc_tell_result(to: String, ok: bool, display: String) -> void:
	var pending: Dictionary = _pending_tells.get(to.to_lower(), {})
	_pending_tells.erase(to.to_lower())
	if ok:
		GameLog.log_general(ChatChannels.tell_self(display if not display.is_empty() else to, str(pending.get("message", "")), str(pending.get("lang", "common"))))
	else:
		GameLog.log_general("[color=red]No player named '%s' is currently online.[/color]" % to)


@rpc("authority", "call_remote", "reliable")
func _rpc_who_result(text: String) -> void:
	for line in text.split("\n"):
		GameLog.log_general(line)


# ── Lines ──
func _write(tcp: StreamPeerTCP, msg: Dictionary) -> void:
	if tcp != null and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		tcp.put_data((JSON.stringify(msg) + "\n").to_utf8_buffer())


func _read(tcp: StreamPeerTCP, holder: Dictionary) -> Array:
	var out := []
	var n := tcp.get_available_bytes()
	if n > 0:
		var got: Array = tcp.get_partial_data(n)
		if got[0] == OK:
			holder["buf"] = str(holder["buf"]) + (got[1] as PackedByteArray).get_string_from_utf8()
	while str(holder["buf"]).contains("\n"):
		var line := str(holder["buf"]).get_slice("\n", 0)
		holder["buf"] = str(holder["buf"]).substr(line.length() + 1)
		var parsed = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			out.append(parsed)
	return out


# ── Groups ──
func _group_of(player_name: String) -> String:
	var want := player_name.to_lower()
	for leader in groups:
		for m in groups[leader]["members"]:
			if str(m).to_lower() == want:
				return leader
	return ""


# Hub: apply a change and tell every zone.
func _hub_group(msg: Dictionary) -> void:
	var by := str(msg.get("by", ""))
	if str(msg.get("t", "")) == "group_leave":
		_remove_member(by)
	elif str(msg.get("t", "")) == "group_join":   # an invite accepted across zones: the member joins the leader's group
		var leader := str(msg.get("leader", ""))
		var member := str(msg.get("member", ""))
		var g := _group_of(leader)
		var members: Array = groups[g]["members"].duplicate() if not g.is_empty() else [leader]
		if members.size() < MAX_GROUP and not members.any(func(m): return str(m).to_lower() == member.to_lower()):
			var old_g := _group_of(member)
			if not old_g.is_empty():
				_remove_member(member)
			g = _group_of(leader)
			members = groups[g]["members"].duplicate() if not g.is_empty() else [leader]
			members.append(member)
			var lead := str(groups[g]["leader"]) if not g.is_empty() else leader
			if not g.is_empty():
				groups.erase(g)
			groups[lead.to_lower()] = {"leader": lead, "members": members}
	else:
		var members: Array = (msg.get("members", []) as Array).map(func(m): return str(m))
		if members.size() <= 1:
			var g := _group_of(by)
			if not g.is_empty() and g == by.to_lower():
				groups.erase(g)          # the leader disbanded it
			else:
				_remove_member(by)       # a member left it
		else:
			for m in members:
				var g := _group_of(m)
				if not g.is_empty() and g != by.to_lower():
					_remove_member(m)    # in someone else's group before: not any more
			groups[by.to_lower()] = {"leader": by, "members": members}
	var out := {"t": "groups", "groups": groups}
	for p in _peers:
		_write(p["tcp"], out)
	_push_groups()


func _remove_member(player_name: String) -> void:
	var g := _group_of(player_name)
	if g.is_empty():
		return
	var members: Array = groups[g]["members"].filter(func(m): return str(m).to_lower() != player_name.to_lower())
	groups.erase(g)
	if members.size() > 1:
		var leader := str(members[0])   # the next member leads
		groups[leader.to_lower()] = {"leader": leader, "members": members}


func _group_change(msg: Dictionary) -> void:
	if is_hub():
		_hub_group(msg)
	else:
		_send_up(msg)


# Zone: tell each local player in a group who's in it and who of them is here (only when it changed).
func _push_groups() -> void:
	if not _server_active():
		return
	var here := {}
	for row in local_players():
		here[str(row["name"]).to_lower()] = int(row["peer"])
	var where := {}
	for zone in _world:
		for row in _world[zone]:
			where[str(row.get("name", "")).to_lower()] = zone
	for name_lower in here:
		var peer: int = here[name_lower]
		var g := _group_of(name_lower)
		var state := {"members": [], "local": [], "remote": []}
		if not g.is_empty():
			for m in groups[g]["members"]:
				var ml := str(m).to_lower()
				state["members"].append(str(m))
				if here.has(ml):
					state["local"].append(here[ml])
				else:
					state["remote"].append({"name": str(m), "zone": ZoneInfo.name_for(str(where.get(ml, ""))) if where.has(ml) else "offline"})
		var text := JSON.stringify(state)
		if _pushed.get(peer, "") == text:
			continue
		_pushed[peer] = text
		if multiplayer.get_peers().has(peer):
			_rpc_group_state.rpc_id(peer, state["members"], state["local"], JSON.stringify(state["remote"]))


# A real logout (not a zone change) leaves the group.
func player_left_world(player_name: String) -> void:
	if _server_active():
		_group_change({"t": "group_leave", "by": player_name})


# ── Messages to one player, by name, in whatever zone they're in (cross-zone group invites, test 39) ──
const MAX_GROUP := 6


# Sends `msg` ({"t": "to_player", "to": name, "kind": ...}) toward the zone its player is in. False if they're offline.
func _send_to_player(msg: Dictionary) -> bool:
	var zone := zone_of(str(msg.get("to", "")))
	if zone.is_empty():
		return false
	if zone == ZoneInfo.current_id():
		_deliver_to_player(msg)
	elif is_hub():
		_route_to_zone(zone, msg)
	else:
		return _send_up(msg)
	return true


func _deliver_to_player(msg: Dictionary) -> void:
	var want := str(msg.get("to", "")).to_lower()
	for node in get_tree().get_nodes_in_group("player"):
		if not (is_instance_valid(node) and str(node.get("player_name")).to_lower() == want):
			continue
		var peer: int = node.get_multiplayer_authority()
		if not multiplayer.get_peers().has(peer):
			return
		match str(msg.get("kind", "")):
			"invite":
				_rpc_invite_offer.rpc_id(peer, str(msg.get("from", "")))
			"note":
				_rpc_note.rpc_id(peer, str(msg.get("text", "")))
		return


func _note_to(player_name: String, text: String) -> void:
	_send_to_player({"t": "to_player", "to": player_name, "kind": "note", "text": text})


# Client: /invite someone who isn't in this zone.
func request_invite(target_name: String) -> void:
	_rpc_invite.rpc_id(1, target_name)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_invite(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var node := TargetFrame.peer_id_to_player_node(multiplayer.get_remote_sender_id())
	if not is_instance_valid(node):
		return
	var leader := str(node.get("player_name"))
	var target := target_name.strip_edges().substr(0, 32)
	var g := _group_of(leader)
	if not g.is_empty() and groups[g]["members"].size() >= MAX_GROUP:
		_note_to(leader, "[color=#ffaa66]Your group is full (%d/%d).[/color]" % [MAX_GROUP, MAX_GROUP])
	elif not _group_of(target).is_empty() and _group_of(target) == g:
		_note_to(leader, "%s is already in your group." % target)
	elif not _group_of(target).is_empty():
		_note_to(leader, "[color=#ffaa66]%s is already in a group.[/color]" % target)
	elif not _send_to_player({"t": "to_player", "to": target, "kind": "invite", "from": leader}):
		_note_to(leader, "[color=red]No player named '%s' is currently online.[/color]" % target)
	else:
		_note_to(leader, "[color=#88ccff]You invite %s to your group.[/color]" % target)


# Client: someone in another zone invites you; the answer goes back through the server.
@rpc("authority", "call_remote", "reliable")
func _rpc_invite_offer(leader: String) -> void:
	var popup: Node = load("res://Scenes/group_invite_popup.tscn").instantiate()
	get_tree().root.add_child(popup)
	popup.ask("%s invites you to their group." % leader, "Accept", "Decline",
			func(accepted: bool): _rpc_invite_answer.rpc_id(1, leader, accepted))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_invite_answer(leader: String, accepted: bool) -> void:
	if not multiplayer.is_server():
		return
	var node := TargetFrame.peer_id_to_player_node(multiplayer.get_remote_sender_id())
	if not is_instance_valid(node):
		return
	var member := str(node.get("player_name"))
	if not accepted:
		_note_to(leader, "[color=#ffaa66]%s declined your invite.[/color]" % member)
		return
	_group_change({"t": "group_join", "leader": leader.substr(0, 32), "member": member})
	_note_to(leader, "[color=#88ccff]%s has joined your group.[/color]" % member)
	_note_to(member, "[color=#88ccff]You join %s's group.[/color]" % leader)


@rpc("authority", "call_remote", "reliable")
func _rpc_note(text: String) -> void:
	GameLog.log_general(text)


func share_notice(text: String) -> void:
	if not _server_active():
		return
	var msg := {"t": "notice", "text": text, "from": ZoneInfo.current_id()}
	if is_hub():
		for p in _peers:
			_write(p["tcp"], msg)
	else:
		_send_up(msg)


func _deliver_party(msg: Dictionary) -> void:
	var members: Array = (msg.get("members", []) as Array).map(func(m): return str(m).to_lower())
	var from := str(msg.get("from", ""))
	for row in local_players():
		var n := str(row["name"])
		if members.has(n.to_lower()) and n != from and multiplayer.get_peers().has(int(row["peer"])):
			Net._rpc_receive_party_message.rpc_id(int(row["peer"]), from, str(msg.get("message", "")))


# Client: the group changed on this machine (someone joined, was removed, the group disbanded).
func request_group_set(member_names: Array) -> void:
	_rpc_group_set.rpc_id(1, member_names)


func request_party(encoded: String) -> void:
	_rpc_party.rpc_id(1, encoded)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_group_set(member_names: Array) -> void:
	if not multiplayer.is_server():
		return
	var node := TargetFrame.peer_id_to_player_node(multiplayer.get_remote_sender_id())
	if not is_instance_valid(node):
		return
	var names: Array = member_names.slice(0, 6).map(func(m): return str(m).substr(0, 32))
	_group_change({"t": "group_set", "by": str(node.get("player_name")), "members": names})


@rpc("any_peer", "call_remote", "reliable")
func _rpc_party(message: String) -> void:
	if not multiplayer.is_server():
		return
	var node := TargetFrame.peer_id_to_player_node(multiplayer.get_remote_sender_id())
	if not is_instance_valid(node):
		return
	var from := str(node.get("player_name"))
	var g := _group_of(from)
	if g.is_empty():
		return
	var msg := {"t": "party", "from": from, "message": message.substr(0, 600), "members": groups[g]["members"]}
	_deliver_party(msg)
	if is_hub():
		for p in _peers:
			_write(p["tcp"], msg)
	else:
		_send_up(msg)


@rpc("authority", "call_remote", "reliable")
func _rpc_group_state(members: Array, local_peers: Array, remote_json: String) -> void:
	var me := TargetFrame.local_player()
	if not is_instance_valid(me):
		return
	var parsed = JSON.parse_string(remote_json)
	me.apply_group_state(members, local_peers, parsed if parsed is Array else [])
