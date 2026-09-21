# gm_commands.gd — Game-master commands (2026-09-21). A player is a game master while Player3D.is_game_master is on (saved in the
# character; replicated, so the server sees it; shown as "<game master>" on the nameplate). `/gm enable` / `/gm disable` toggles it,
# for now open to anyone (a real gate, e.g. a server-side list, comes later). GM commands (/weather, /raid, and more as we make them)
# do nothing for anyone else.
#
# How a command runs: the chat window calls request(). On the host / single-player it runs right there; on a dedicated server (or any
# other client) it goes to the SERVER over the zone's GMRelay node (gm_relay.gd), which looks up the sender's player, checks THEIR GM flag, runs it and sends
# the answer back. Every command lives in run(): add a match arm and a line in the help (pause_menu.gd) and a GM can use it anywhere.
extends RefCounted   # no class_name on purpose: net.gd (an autoload) uses it, and a brand-new class name is not known to Godot until its class cache is rebuilt; users preload() it instead

const DENIED := "[color=red]Only game masters can do that.[/color]"
const COMMANDS := ["weather", "raid", "announce", "maintenance"]


static func is_gm(player: Node) -> bool:
	return is_instance_valid(player) and "is_game_master" in player and bool(player.is_game_master)


# /gm enable | disable | (nothing: the status). Applies to the local player and is saved with the character.
static func set_mode(player: Node, arg: String) -> void:
	match arg.strip_edges().to_lower():
		"enable", "on":
			_set_gm(player, true)
		"disable", "off":
			_set_gm(player, false)
		_:
			GameLog.log_general("You are %s a game master. (/gm enable | disable)" % ("now" if is_gm(player) else "not"))


static func _set_gm(player: Node, on: bool) -> void:
	player.is_game_master = on
	Global.player_data["is_game_master"] = on
	Global.save_player_data_to_file()
	GameLog.log_general("[color=#88ccff]Game master mode %s.[/color]" % ("enabled" if on else "disabled"))


# Called from the chat window by whoever typed the command.
static func request(player: Node, command: String, arg: String, tree: SceneTree) -> void:
	if not is_gm(player):
		GameLog.log_general(DENIED)
		return
	var mp := tree.get_multiplayer()
	if not Net.is_multiplayer_game or not mp.has_multiplayer_peer() or mp.is_server():
		var reply := run(player, command, arg, tree)
		if not reply.is_empty():
			GameLog.log_general(reply)
	else:
		var relay := tree.get_first_node_in_group("gm_relay")
		if relay == null:
			GameLog.log_general("Game master commands are not available here.")
		else:
			relay.send(command, arg)


# Runs a command for `player` where the game world is authoritative (host, single-player, or the dedicated server). Returns the
# text to show that player. The GM check is repeated here because on a server this is the only check that counts.
static func run(player: Node, command: String, arg: String, tree: SceneTree) -> String:
	if not is_gm(player):
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
