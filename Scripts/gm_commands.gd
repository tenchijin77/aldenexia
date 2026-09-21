# gm_commands.gd — Game-master commands (2026-09-21). A player is a game master while Player3D.is_game_master is on (shown as
# "<Name>" in orange on the nameplate); the flag is only for the local UI: what really counts is the SERVER's own list of logged-in game
# masters (gm_relay.gd). GM commands (/weather, /raid, /announce, /maintenance ...) do nothing for anyone else.
#
# GETTING IN. On a dedicated server: /gm enable <password>. The server compares it with the first line of its password file (Net.gm_password_file,
# default <server user folder>/gm_password, or --gm-password-file=; tools/set_gm_password.sh writes it). The file is read at every attempt, so the
# password can be changed while the server runs. No file = nobody can become a game master. Five wrong tries and that connection is locked out
# until it reconnects. Being a game master lasts for the session (it is not saved: log in again next time). In single-player and as the
# host of your own game there is no password: /gm enable just works.
#
# How a command runs: the chat window calls request(). On the host / single-player it runs right there; on a dedicated server (or any
# other client) it goes to the SERVER over the zone's GMRelay node (gm_relay.gd), which checks ITS list, runs it and sends the answer back.
# Every command lives in run(): add a match arm and a line in the help (pause_menu.gd) and a GM can use it anywhere.
extends RefCounted   # no class_name on purpose: net.gd (an autoload) uses it, and a brand-new class name is not known to Godot until its class cache is rebuilt; users preload() it instead

const DENIED := "[color=red]Only game masters can do that.[/color]"
const COMMANDS := ["weather", "raid", "announce", "maintenance"]


static func is_gm(player: Node) -> bool:
	return is_instance_valid(player) and "is_game_master" in player and bool(player.is_game_master)


# A joined client (dedicated server, or someone else's game): game master mode has to be granted by that server.
static func is_joined_client(tree: SceneTree) -> bool:
	var mp := tree.get_multiplayer()
	return Net.is_multiplayer_game and mp.has_multiplayer_peer() and not mp.is_server()


# /gm enable [password] | disable | (nothing: the status).
static func set_mode(player: Node, arg: String) -> void:
	var words := arg.strip_edges().split(" ", false, 1)
	var word := words[0].to_lower() if words.size() > 0 else ""
	var password := words[1].strip_edges() if words.size() > 1 else ""
	var tree := player.get_tree()
	match word:
		"enable", "on":
			if not is_joined_client(tree):
				_set_gm(player, true)
				return
			var relay := tree.get_first_node_in_group("gm_relay")
			if relay == null:
				GameLog.log_general("Game master mode is not available here.")
			elif password.is_empty():
				GameLog.log_general("This server needs the game master password: /gm enable <password>")
			else:
				relay.login(password)
		"disable", "off":
			if is_joined_client(tree):
				var relay := tree.get_first_node_in_group("gm_relay")
				if relay != null:
					relay.logout()
			_set_gm(player, false)
		_:
			GameLog.log_general("You are %s a game master. (/gm enable | disable)" % ("now" if is_gm(player) else "not"))


# The server said yes (or no) to a password.
static func apply_login_result(player: Node, ok: bool, message: String) -> void:
	if ok and is_instance_valid(player):
		_set_gm(player, true)
	elif not message.is_empty():
		GameLog.log_general(message)


static func _set_gm(player: Node, on: bool) -> void:
	player.is_game_master = on
	if not is_joined_client(player.get_tree()):   # on a server it is granted per session, never remembered
		Global.player_data["is_game_master"] = on
		Global.save_player_data_to_file()
	GameLog.log_general("[color=#88ccff]Game master mode %s.[/color]" % ("enabled" if on else "disabled"))


# SERVER: is this password right? Returns "" when it is, otherwise the reason. The file is read fresh every time.
static func check_password(password: String) -> String:
	var path: String = Net.gm_password_file
	if not FileAccess.file_exists(path):
		return "Game master access is not set up on this server."
	var expected := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var clean := line.strip_edges()
		if not clean.is_empty() and not clean.begins_with("#"):
			expected = clean
			break
	if expected.is_empty():
		return "Game master access is not set up on this server."
	if password.length() > 200 or not _same_text(password, expected):
		return "[color=red]Wrong password.[/color]"
	return ""


# Compares every byte whatever the outcome, so the time it takes does not tell how much of a guess was right.
static func _same_text(a: String, b: String) -> bool:
	var x := a.to_utf8_buffer()
	var y := b.to_utf8_buffer()
	var diff := x.size() ^ y.size()
	for i in range(maxi(x.size(), y.size())):
		diff |= (x[i] if i < x.size() else 0) ^ (y[i] if i < y.size() else 0)
	return diff == 0


# Called from the chat window by whoever typed the command.
static func request(player: Node, command: String, arg: String, tree: SceneTree) -> void:
	if not is_gm(player):
		GameLog.log_general(DENIED)
		return
	var mp := tree.get_multiplayer()
	if not Net.is_multiplayer_game or not mp.has_multiplayer_peer() or mp.is_server():
		var reply := run(player, command, arg, tree, is_gm(player))
		if not reply.is_empty():
			GameLog.log_general(reply)
	else:
		var relay := tree.get_first_node_in_group("gm_relay")
		if relay == null:
			GameLog.log_general("Game master commands are not available here.")
		else:
			relay.send(command, arg)


# Runs a command for `player` where the game world is authoritative (host, single-player, or the dedicated server). Returns the
# text to show that player. `authorized` is the caller's verdict: the host's own flag, or on a dedicated server whether that peer logged in
# with the password (never the flag the client reports, which anyone could fake).
static func run(_player: Node, command: String, arg: String, tree: SceneTree, authorized: bool) -> String:
	if not authorized:
		return DENIED
	match command:
		"weather":
			var wm := tree.get_first_node_in_group("weather_manager")
			if wm == null:
				return "There is no weather in this area."
			match arg.strip_edges().to_lower():
				"rain", "on", "start":
					wm.set_weather(true)
					return "[color=#88ccff]Rain started.[/color]"
				"clear", "off", "stop":
					wm.set_weather(false)
					return "[color=#88ccff]Rain stopped.[/color]"
				_:
					return "Usage: /weather rain | clear"
		"raid":
			var rm := tree.get_first_node_in_group("gate_raid_manager")
			if rm == null:
				return "There are no raids in this area."
			if rm.is_raid_active():
				return "A raid is already under way."
			if not rm.start_raid(arg.strip_edges().to_lower()):
				return "Usage: /raid [bandits | goblins]"
			return "[color=#88ccff]Raid started.[/color]"
	if command == "announce" or command == "maintenance":
		var notice := tree.get_first_node_in_group("server_notice")
		if notice == null:
			return "There is no notice board in this area."
		if command == "announce":
			if arg.strip_edges().is_empty():
				return "Usage: /announce <text>: a red message in the middle of everyone's screen."
			notice.broadcast(arg.strip_edges())
			return "[color=#88ccff]Announced.[/color]"
		var word := arg.strip_edges().to_lower()
		if word == "cancel":
			return notice.cancel_maintenance()
		var minutes: float = word.to_float() if word.is_valid_float() else 5.0
		return notice.start_maintenance(minutes)
	return "Unknown GM command: /%s" % command
