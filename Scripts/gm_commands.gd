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
const COMMANDS := ["weather", "raid", "announce", "maintenance", "ban", "unban", "bans", "surname", "kill", "give"]


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
		_set_gm(player, true, message == RESTORED)
	elif not message.is_empty():
		GameLog.log_general(message)


# The server restoring a game master's mode after they zone (gm_relay.gd): quietly, it was never switched off.
const RESTORED := "@restored"


static func _set_gm(player: Node, on: bool, quiet: bool = false) -> void:
	player.is_game_master = on
	if not is_joined_client(player.get_tree()):   # single-player / host: remembered in the save
		Global.player_data["is_game_master"] = on
		Global.save_player_data_to_file()
	if not quiet:
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


# /surname <player> <Surname | clear>: set or remove anyone's surname (online players only). Runs where the players live (the
# server, or the host / single-player); the player's own machine applies and saves it (Player3D.receive_surname()).
static func _surname(arg: String, tree: SceneTree) -> String:
	var words := arg.split(" ", false)
	if words.size() != 2:
		return "Usage: /surname <player> <Surname>   or   /surname <player> clear"
	var target: Node = null
	for node in tree.get_nodes_in_group("player"):
		if is_instance_valid(node) and str(node.get("player_name")).to_lower() == words[0].to_lower():
			target = node
			break
	if target == null:
		return "No player named %s is in the world." % words[0]
	var value := "" if words[1].to_lower() == "clear" else Net.format_surname(words[1])
	if not value.is_empty() and not Net.valid_surname(value):
		return "A surname is one word: letters (an apostrophe or hyphen inside is fine), 2 to 20."
	if target.is_multiplayer_authority():
		target._apply_surname(value)   # host / single-player: it is this machine's own player
	else:
		target.receive_surname.rpc_id(target.get_multiplayer_authority(), value)
	var who := str(target.get("player_name"))
	return "[color=#88ccff]%s[/color]" % ("%s is now %s %s." % [who, who, value] if not value.is_empty() else "%s's surname is removed." % who)


# /kill: the chat window sends the target's key (TargetFrame.target_key_of: "p:<peer>", "m:<monster>", "n:<npc>").
# A monster dies here (the server owns monsters) without experience or loot; a player dies on their own machine.
static func _kill(key: String) -> String:
	var target := TargetFrame.resolve_target_key(key)
	if target == null:
		return "Target something to kill (or /kill me)."
	var who := TargetFrame.display_name(target)
	if target.is_in_group("player"):
		if target.is_multiplayer_authority():
			target.gm_kill()
		else:
			target.gm_kill.rpc_id(target.get_multiplayer_authority())
		return "[color=#88ccff]%s is struck down.[/color]" % who
	if target.is_in_group("monsters") and target.has_method("die"):
		if not target.is_multiplayer_authority():
			return "That monster isn't this server's to kill."
		if target.get("current_state") == target.State.DEAD:
			return "%s is already dead." % who
		target.die(false, false)
		return "[color=#88ccff]%s is struck down (no experience or loot).[/color]" % who
	return "%s can't be killed that way." % who


# /give <item name or id> [count]: into the game master's own bags. A name matches exactly, or by the start of it when
# only one item fits ("/give tin shi" = Tin Shield). The player's own machine adds it (Player3D.gm_receive_item()).
static func _give(arg: String, gm: Node) -> String:
	if arg.is_empty():
		return "Usage: /give <item name> [count]"
	var words := arg.split(" ", false)
	var count := 1
	if words.size() > 1 and words[-1].is_valid_int():
		count = clampi(int(words[-1]), 1, 1000)
		words.remove_at(words.size() - 1)
	var found := find_item(" ".join(words))
	if found.size() != 1:
		if found.is_empty():
			return "No item called '%s'." % " ".join(words)
		return "'%s' could be: %s" % [" ".join(words), ", ".join(found.slice(0, 8).map(func(i): return str(Inventory.item_data[i].get("name", i))))]
	if not is_instance_valid(gm):
		return "Nobody to give it to."
	if gm.is_multiplayer_authority():
		gm.gm_receive_item(found[0], count)
	else:
		gm.gm_receive_item.rpc_id(gm.get_multiplayer_authority(), found[0], count)
	return "[color=#88ccff]Given: %s x%d.[/color]" % [str(Inventory.item_data[found[0]].get("name", found[0])), count]


# Item ids matching a typed name: the exact id or name (a leading "a"/"an"/"the" ignored) wins; else every name that
# starts with it.
static func find_item(text: String) -> Array:
	var want := text.strip_edges().to_lower()
	for article in ["a ", "an ", "the "]:
		want = want.trim_prefix(article)
	if want.is_empty():
		return []
	var starts: Array = []
	for id in Inventory.item_data:
		if typeof(Inventory.item_data[id]) != TYPE_DICTIONARY:
			continue   # the file's comments
		var name := str(Inventory.item_data[id].get("name", "")).to_lower()
		for article in ["a ", "an ", "the "]:
			name = name.trim_prefix(article)
		if str(id).to_lower() == want or name == want or str(id).to_lower() == want.replace(" ", "_"):
			return [id]
		if name.begins_with(want):
			starts.append(id)
	return starts


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
	if command in ["ban", "unban", "bans"]:
		return _bans(command, arg.strip_edges(), _player)
	if command == "surname":
		return _surname(arg.strip_edges(), tree)
	if command == "kill":
		return _kill(arg.strip_edges())
	if command == "give":
		return _give(arg.strip_edges(), _player)
	if command == "announce" or command == "maintenance":
		var notice := tree.get_first_node_in_group("server_notice")
		if notice == null:
			return "There is no notice board in this area."
		if command == "announce":
			if arg.strip_edges().is_empty():
				return "Usage: /announce <text>: a red message in the middle of everyone's screen."
			notice.broadcast(arg.strip_edges())
			var link := tree.get_first_node_in_group("world_link")
			if link != null:
				link.share_notice(arg.strip_edges())   # every zone (world_link.gd)
			return "[color=#88ccff]Announced.[/color]"
		var word := arg.strip_edges().to_lower()
		if word == "cancel":
			return notice.cancel_maintenance()
		var minutes: float = word.to_float() if word.is_valid_float() else 5.0
		return notice.start_maintenance(minutes)
	return "Unknown GM command: /%s" % command


# /ban <ip | player name> — refuse that address from now on and disconnect anyone on it (a player's name bans the address
# they are connected from). /unban <ip>. /bans lists them. Kept in the server's banned_ips file (Net.banned_ips_file) —
# one address per line with a note, editable by hand. Everyone behind the same home router shares one address.
static func _bans(command: String, arg: String, gm: Node) -> String:
	match command:
		"bans":
			var list: Array = Net.banned_ips()
			return "Banned addresses: %s" % (", ".join(list) if not list.is_empty() else "none")
		"unban":
			if arg.is_empty():
				return "Usage: /unban <ip address>"
			if Net.unban_ip(arg):
				Net._audit("UNBAN", arg, "", "by %s" % (str(gm.get("player_name")) if is_instance_valid(gm) else "a game master"))
				return "[color=#88ccff]Unbanned %s.[/color]" % arg
			return "%s isn't banned." % arg
	if arg.is_empty():
		return "Usage: /ban <ip address | player name>"
	var ip := arg
	var who := ""
	if not arg.is_valid_ip_address():
		var peer := Net.peer_for_character(arg)
		if peer == 0:
			return "No player named '%s' is online (to ban an address, give the IP)." % arg
		ip = Net.peer_ip(peer)
		who = arg.capitalize()
	var by := str(gm.get("player_name")) if is_instance_valid(gm) else "a game master"
	var note := "banned by %s on %s%s" % [by, Time.get_date_string_from_system(), (" (was playing %s)" % who) if not who.is_empty() else ""]
	var kicked := Net.ban_ip(ip, note)
	Net._slog("Ban: %s — %s." % [ip, note])
	Net._audit("BAN", ip, who, note)
	return "[color=#88ccff]Banned %s%s; %d disconnected.[/color]" % [ip, (" (%s)" % who) if not who.is_empty() else "", kicked]
