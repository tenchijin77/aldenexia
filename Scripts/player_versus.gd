# player_versus.gd — duels and PvP (user, 2026-09-25: "I'd like both a pvp and a duel system: /pvp and /duel, targeted
# or name of player"). A child ("Versus") of every Player3D; only the local player's copy decides anything.
#
#   /duel [name]  challenge your target (or the named player). They accept or decline; a 3-second count, then you fight.
#                 A duel ends when one of you would fall to 0 (left at 1 health: no death, no penalty), with /yield, when
#                 you move more than DUEL_LEASH apart, or after DUEL_SECONDS. /dual works too.
#   /pvp [name]   declare PvP on your target: no consent needed. They're warned and get PVP_GRACE seconds, then the two of
#                 you can fight to the death (normal death rules). It lasts until PVP_MINUTES pass with no blows traded.
#                 Only from level PVP_MIN_LEVEL, and only within PVP_LEVEL_RANGE levels of each other (no ganking new
#                 players). Striking another player in town is a crime if a guard sees it (crime.gd); a duel isn't.
# Only the two players are hostile to each other; to everyone else they're still allies. Player3D.hostile_to (replicated)
# holds the names you're hostile with right now; TargetFrame.faction_status() reads it both ways (mutual only).
# Hits go to the victim's own machine (_rpc_hit), which checks the attacker really is a foe, close by, before taking it.
class_name PlayerVersus
extends Node

const DUEL_COUNTDOWN := 3.0
const DUEL_SECONDS := 300.0
const DUEL_LEASH := 40.0
const DUEL_ASK_SECONDS := 30.0
const PVP_GRACE := 5.0
const PVP_MINUTES := 10.0
const PVP_MIN_LEVEL := 5
const PVP_LEVEL_RANGE := 5
const HIT_RANGE := 45.0        # a hit from farther than this (spells reach ~30 m) is refused

var player: Node = null
var duel_with := ""            # lower-case name of the duel opponent
var duel_state := ""           # "" | "asking" (we challenged) | "count" | "fighting"
var _duel_timer := 0.0
var _foes := {}                # PvP: lower-case name -> seconds left (a pending grace uses "grace:" + seconds)
var _grace := {}               # lower-case name -> seconds until we may be attacked by them


func _ready() -> void:
	player = get_parent()


func me() -> String:
	return str(player.get("player_name")).to_lower()


# ── Challenges ──
func challenge_duel(target: Node) -> void:
	var why := _cant_target(target)
	if not why.is_empty():
		GameLog.log_general("[color=#ff8866]%s[/color]" % why)
		return
	if not duel_with.is_empty():
		GameLog.log_general("[color=#ff8866]You're already in a duel.[/color]")
		return
	duel_with = _name(target)
	duel_state = "asking"
	_duel_timer = DUEL_ASK_SECONDS
	GameLog.log_general("[color=#ffcc66]You challenge %s to a duel.[/color]" % TargetFrame.display_name(target))
	_send(target, "_rpc_duel_request", [])


func declare_pvp(target: Node) -> void:
	var why := _cant_target(target)
	if why.is_empty():
		var mine := int(player.combat_node.level)
		var theirs := int(target.combat_node.level) if target.get("combat_node") != null else mine
		if mine < PVP_MIN_LEVEL or theirs < PVP_MIN_LEVEL:
			why = "PvP starts at level %d, for both of you." % PVP_MIN_LEVEL
		elif absi(mine - theirs) > PVP_LEVEL_RANGE:
			why = "%s is too far from your level for PvP (within %d levels)." % [TargetFrame.display_name(target), PVP_LEVEL_RANGE]
	if not why.is_empty():
		GameLog.log_general("[color=#ff8866]%s[/color]" % why)
		return
	var n := _name(target)
	_foes[n] = PVP_MINUTES * 60.0
	_refresh()
	GameLog.log_general("[color=#ff5544]You declare PvP on %s! In %d seconds you can fight to the death.[/color]" % [TargetFrame.display_name(target), int(PVP_GRACE)])
	_send(target, "_rpc_pvp_declared", [])


func yield_duel() -> void:
	if duel_with.is_empty():
		GameLog.log_general("You aren't in a duel.")
		return
	var opp := _node_named(duel_with)
	GameLog.log_general("[color=#ffcc66]You yield.[/color]")
	if opp != null:
		_send(opp, "_rpc_duel_over", [str(opp.get("player_name")), "yielded"])
	_duel_over(duel_with, "yielded")


func _cant_target(target: Node) -> String:
	if target == null or not is_instance_valid(target) or not target.is_in_group("player"):
		return "Target another player (or give their name)."
	if target == player:
		return "You can't fight yourself."
	if (target as Node3D).global_position.distance_to((player as Node3D).global_position) > DUEL_LEASH:
		return "%s is too far away." % TargetFrame.display_name(target)
	if player.get("dying"):
		return "Not while you're down."
	return ""


# ── Is this player a foe right now (from our side)? ──
func is_foe(name_lower: String) -> bool:
	if duel_state == "fighting" and duel_with == name_lower:
		return true
	return _foes.has(name_lower) and not _grace.has(name_lower)


func _refresh() -> void:
	var names := PackedStringArray()
	if duel_state == "fighting" and not duel_with.is_empty():
		names.append(duel_with)
	for n in _foes:
		if not _grace.has(n) and not names.has(n):
			names.append(n)
	if player.get("hostile_to") != names:
		player.set("hostile_to", names)


func _process(delta: float) -> void:
	if not (is_instance_valid(player) and player.is_multiplayer_authority()):
		return
	var changed := false
	# the PvP grace a declaration gives, then the foes that time out
	for n in _grace.keys():
		_grace[n] -= delta
		if _grace[n] <= 0.0:
			_grace.erase(n)
			changed = true
			GameLog.log_general("[color=#ff5544]%s can attack you now, and you them.[/color]" % n.capitalize())
	for n in _foes.keys():
		_foes[n] -= delta
		if _foes[n] <= 0.0 or _node_named(n) == null:
			_foes.erase(n)
			_grace.erase(n)
			changed = true
			GameLog.log_general("[color=#cccccc]Your fight with %s is over.[/color]" % n.capitalize())
	# the duel
	if not duel_with.is_empty():
		_duel_timer -= delta
		var opp := _node_named(duel_with)
		match duel_state:
			"asking":
				if _duel_timer <= 0.0 or opp == null:
					GameLog.log_general("[color=#cccccc]Your duel challenge went unanswered.[/color]")
					_duel_over(duel_with, "")
			"count":
				if _duel_timer <= 0.0:
					duel_state = "fighting"
					_duel_timer = DUEL_SECONDS
					changed = true
					GameLog.log_general("[color=#ffcc66][b]Fight![/b][/color]")
				else:
					var sec := int(ceil(_duel_timer))
					if sec != int(ceil(_duel_timer + delta)):
						GameLog.log_general("[color=#ffcc66]%d...[/color]" % sec)
			"fighting":
				if opp == null or _duel_timer <= 0.0 or (opp as Node3D).global_position.distance_to((player as Node3D).global_position) > DUEL_LEASH:
					var why := "time" if _duel_timer <= 0.0 else "left"
					if opp != null:
						_send(opp, "_rpc_duel_over", ["", why])
					_duel_over(duel_with, why)
	if changed:
		_refresh()


# The duel is over: `winner` ("" = nobody).
func _duel_over(opponent: String, why: String) -> void:
	var was_fighting := duel_state == "fighting"
	duel_with = ""
	duel_state = ""
	_refresh()
	if was_fighting:
		match why:
			"time":
				GameLog.log_general("[color=#cccccc]The duel is over: time is up.[/color]")
			"left":
				GameLog.log_general("[color=#cccccc]The duel is over: you're too far apart.[/color]")
	var t = player.get("current_target")
	if is_instance_valid(t) and str(t.get("player_name")).to_lower() == opponent and not is_foe(opponent):
		player.set("autoattack_enabled", false)
		GameLog.set_autoattack(false)


# ── Hits ──
# The attacker's side: send a blow to the victim's own machine.
func send_hit(target: Node, amount: int) -> void:
	if amount <= 0:
		return
	var n := _name(target)
	if _foes.has(n):
		_foes[n] = PVP_MINUTES * 60.0   # trading blows keeps it going
	if not (duel_state == "fighting" and duel_with == n):
		Crime.commit(player, "assault", n)   # PvP in town is a crime, if a guard sees it (a duel is consensual: not one)
	_send(target, "_rpc_hit", [amount])


# The victim's side: take it only from a foe, close by. A duel stops at 1 health.
func receive_hit(attacker: Node, amount: int) -> void:
	if attacker == null or not is_instance_valid(attacker) or player.get("dying"):
		return
	var n := _name(attacker)
	if not is_foe(n) or (attacker as Node3D).global_position.distance_to((player as Node3D).global_position) > HIT_RANGE:
		return
	if _foes.has(n):
		_foes[n] = PVP_MINUTES * 60.0
	var cn: CombatNode = player.combat_node
	if duel_state == "fighting" and duel_with == n and cn.current_hp - amount <= 0:
		cn.current_hp = 1
		GameLog.log_combat("[color=#ffcc66]%s beats you in the duel.[/color]" % TargetFrame.display_name(attacker))
		_send(attacker, "_rpc_duel_over", [str(attacker.get("player_name")), "won"])
		_duel_over(n, "lost")
		return
	player.take_damage(amount, attacker)   # the attacker's own line reaches everyone nearby, you included


# ── Talking to the other player's machine ──
# Calls `method` on the target's Versus node: over the network when it's someone else's player, directly otherwise.
func _send(target: Node, method: String, args: Array) -> void:
	var their: Node = target.get_node_or_null("Versus")
	if their == null:
		return
	if multiplayer.has_multiplayer_peer() and not target.is_multiplayer_authority():
		their.callv("rpc_id", [target.get_multiplayer_authority(), method] + args)
	else:
		their._local_sender = player
		their.callv(method, args)
		their._local_sender = null


var _local_sender: Node = null   # who called us, when it wasn't over the network (tests, one machine)


func _sender() -> Node:
	if _local_sender != null:
		return _local_sender
	return TargetFrame.peer_id_to_player_node(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_duel_request() -> void:
	var from := _sender()
	if from == null or not player.is_multiplayer_authority():
		return
	if not duel_with.is_empty():
		_send(from, "_rpc_duel_answer", [false])
		return
	var n := _name(from)
	var popup: Node = load("res://Scenes/group_invite_popup.tscn").instantiate()
	player.get_tree().root.add_child(popup)
	popup.ask("%s challenges you to a duel!\nFirst to fall to 1 health loses. No one dies." % TargetFrame.display_name(from), "Accept", "Decline",
			func(yes: bool): _answer_duel(n, yes))
	player.get_tree().create_timer(DUEL_ASK_SECONDS).timeout.connect(func():
		if is_instance_valid(popup):
			popup.expire())


func _answer_duel(challenger: String, yes: bool) -> void:
	var from := _node_named(challenger)
	if from == null:
		return
	_send(from, "_rpc_duel_answer", [yes])
	if yes and duel_with.is_empty():
		_start_duel(challenger)
	elif not yes:
		GameLog.log_general("You decline the duel.")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_duel_answer(yes: bool) -> void:
	var from := _sender()
	if from == null or duel_state != "asking" or duel_with != _name(from):
		return
	if yes:
		_start_duel(duel_with)
	else:
		GameLog.log_general("[color=#cccccc]%s declines your duel.[/color]" % TargetFrame.display_name(from))
		_duel_over(duel_with, "")


func _start_duel(opponent: String) -> void:
	duel_with = opponent
	duel_state = "count"
	_duel_timer = DUEL_COUNTDOWN
	GameLog.log_general("[color=#ffcc66]A duel with %s! %d...[/color]" % [opponent.capitalize(), int(DUEL_COUNTDOWN)])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_duel_over(winner: String, why: String) -> void:
	var from := _sender()
	if from == null or duel_with != _name(from):
		return
	if why == "won" or why == "yielded":
		GameLog.log_combat("[color=#ffdd44]You win the duel against %s![/color]" % TargetFrame.display_name(from))
	_duel_over(duel_with, why)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pvp_declared() -> void:
	var from := _sender()
	if from == null or not player.is_multiplayer_authority():
		return
	var n := _name(from)
	_foes[n] = PVP_MINUTES * 60.0
	_grace[n] = PVP_GRACE
	_refresh()
	GameLog.log_general("[color=#ff5544][b]%s has declared PvP on you![/b] In %d seconds they can attack you, and you them.[/color]" % [TargetFrame.display_name(from), int(PVP_GRACE)])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hit(amount: int) -> void:
	var from := _sender()
	if from == null or not player.is_multiplayer_authority():
		return
	receive_hit(from, clampi(amount, 0, 5000))


# ── Names ──
static func _name(n: Node) -> String:
	return str(n.get("player_name")).to_lower()


func _node_named(name_lower: String) -> Node:
	for p in player.get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and _name(p) == name_lower:
			return p
	return null
