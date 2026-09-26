# Duels and PvP (player_versus.gd): /duel and /pvp, targeted or by name. Two players on one machine, talking through the
# same calls the network uses.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	make_floor(200.0)
	var a = await make_player({"player_name": "Zozuur", "player_class": "Voidknight", "player_level": 10})
	var b = await make_player({"player_name": "Maedianie", "player_class": "Wildspeaker", "player_level": 10})
	a.global_position = Vector3(0, 1, 0)
	b.global_position = Vector3(2, 1, 0)
	var va: PlayerVersus = a.get_node("Versus")
	var vb: PlayerVersus = b.get_node("Versus")
	var lines: Array = []
	var grab := func(t): lines.append(str(t))
	GameLog.general_message.connect(grab)

	# friends by default
	check(not va.is_foe("maedianie") and a.hostile_to.is_empty(), "players aren't foes until they choose to be")

	# a duel: challenge, accept, a 3-second count, fight
	va.challenge_duel(b)
	eq(va.duel_state, "asking", "Zozuur challenges")
	await frames(2)
	vb._answer_duel("zozuur", true)
	eq(vb.duel_state, "count", "Maedianie accepts: the count begins")
	eq(va.duel_state, "count", "on both sides")
	check(not va.is_foe("maedianie"), "no blows during the count")
	for i in 4:
		va._process(1.0)
		vb._process(1.0)
	eq(va.duel_state, "fighting", "Fight!")
	check(va.is_foe("maedianie") and vb.is_foe("zozuur"), "now they're foes, both ways")
	check(a.hostile_to.has("maedianie") and b.hostile_to.has("zozuur"), "and everyone sees it (replicated)")
	var hp: int = b.combat_node.current_hp
	va.send_hit(b, 10)
	eq(b.combat_node.current_hp, hp - 10, "a blow lands on the foe")
	va.send_hit(b, 99999)
	eq(b.combat_node.current_hp, 1, "a duel stops at 1 health")
	check(not b.dying, "no one dies in a duel")
	check(va.duel_with.is_empty() and vb.duel_with.is_empty(), "and it's over for both")
	check(not va.is_foe("maedianie"), "friends again")
	hp = b.combat_node.current_hp
	va.send_hit(b, 5)
	eq(b.combat_node.current_hp, hp, "a blow from a non-foe does nothing")
	b.combat_node.current_hp = b.combat_node.max_hp

	# yielding, and walking away
	va.challenge_duel(b)
	vb._answer_duel("zozuur", true)
	for i in 4:
		va._process(1.0)
		vb._process(1.0)
	vb.yield_duel()
	check(va.duel_with.is_empty() and vb.duel_with.is_empty(), "/yield ends it")
	va.challenge_duel(b)
	vb._answer_duel("zozuur", true)
	for i in 4:
		va._process(1.0)
		vb._process(1.0)
	b.global_position = Vector3(80, 1, 0)
	va._process(0.1)
	check(va.duel_with.is_empty(), "too far apart: the duel is over")
	b.global_position = Vector3(2, 1, 0)
	vb.duel_with = ""
	vb.duel_state = ""
	vb._refresh()

	# PvP: level rules
	a.combat_node.level = 3
	lines.clear()
	va.declare_pvp(b)
	check(lines.any(func(l): return l.contains("level %d" % PlayerVersus.PVP_MIN_LEVEL)) and not va._foes.has("maedianie"), "no PvP below level %d" % PlayerVersus.PVP_MIN_LEVEL)
	a.combat_node.level = 20
	lines.clear()
	va.declare_pvp(b)
	check(lines.any(func(l): return l.contains("too far from your level")), "nor more than %d levels apart" % PlayerVersus.PVP_LEVEL_RANGE)
	a.combat_node.level = 12

	# PvP: declared, a grace, then a fight to the death
	lines.clear()
	va.declare_pvp(b)
	check(lines.any(func(l): return l.contains("declared PvP on you")), "the target is warned")
	check(not vb.is_foe("zozuur"), "and gets a grace first")
	hp = b.combat_node.current_hp
	va.send_hit(b, 10)
	eq(b.combat_node.current_hp, hp, "no blows land during the grace")
	for i in 6:
		vb._process(1.0)
	check(vb.is_foe("zozuur") and va.is_foe("maedianie"), "then they're foes")
	va.send_hit(b, 99999)
	check(b.dying, "PvP is to the death (normal death rules)")
	b.global_position = Vector3(300, 1, 0)   # far enough that the foe list ends with the fight over time
	for i in 1:
		va._process(PlayerVersus.PVP_MINUTES * 60.0 + 1.0)
	check(not va.is_foe("maedianie"), "the feud fades after %d minutes without blows" % int(PlayerVersus.PVP_MINUTES))

	# the chat commands: /duel and /dual, /pvp, /yield; targeting helpers
	var chat := FileAccess.get_file_as_string("res://Scripts/game_log_window.gd")
	check(chat.contains('"/duel", "/pvp":') and chat.contains('"/dual": "/duel"') and chat.contains('"/yield":'), "/duel (or /dual), /pvp and /yield, by target or by name")
	check(FileAccess.get_file_as_string("res://Scripts/player3d.gd").contains("me.get_node(\"Versus\").send_hit(self, amount)"), "a spell on a foe lands on their own machine")
	GameLog.general_message.disconnect(grab)
	a.queue_free()
	b.queue_free()
	await frames(2)
