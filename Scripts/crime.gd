# crime.gd — crime and punishment in town (designed 2026-09-25, built 2026-09-26; the user: "they'll just kill you and
# take the money. jail makes no sense in an mmo unless we have a quest there" / "attacking another player in town is a
# crime"). Skyrim-style, no jail:
#   - A crime in town (Lumora, or inside the Outskirts' walls: the spawn file's no_monster_zones) that a guard witnesses
#     (one within WITNESS_RANGE) adds its fine to your Lumora bounty and costs standing with the faction it wronged.
#     First crime: striking another player in PvP (a duel is consensual, so it isn't one). Others to come: pickpocketing
#     townsfolk, attacking guards or townsfolk.
#   - A guard who sees someone with a bounty demands it (guard_npc.gd): Pay (the bounty is cleared) or Resist. Can't pay?
#     Settle it at the courthouse; the guards ask again in a while.
#   - Resisting (Player3D.resisting, replicated): every guard attacks you on sight. Killed by a guard, the fine comes out of
#     your purse; whatever you couldn't pay stays as bounty.
#   - The Magistrate at the Lumora courthouse (magistrate_npc.gd) takes a bounty, and sells back the standing crimes cost
#     (only that: other standing is earned in the world).
# The bounty and the standing it cost live in the character's save ("bounty", "crime_standing"); Player3D.wanted mirrors
# the bounty (replicated) so the server's guards know.
class_name Crime

const WITNESS_RANGE := 40.0
const REPEAT_SECONDS := 60.0          # the same crime against the same victim counts once a minute
const REGION := "Lumora"
# kind -> [fine in copper, {faction: standing change}, how the log names it]
const CRIMES := {
	"assault": [50, {"Wardens of the Sacred Flame": -15}, "assault"],
}
const AMENDS_COPPER_PER_POINT := 2    # the Magistrate: 2 copper buys back 1 point of standing a crime cost

static var _last := {}


# Is `node` in town, where the law holds?
static func in_town(node: Node3D) -> bool:
	if node == null:
		return false
	return ZoneInfo.current_id() == "lumora" or Monster.in_no_monster_zone(node.global_position)


static func bounty() -> int:
	return int(Global.player_data.get("bounty", 0))


static func standing_lost() -> Dictionary:
	var d = Global.player_data.get("crime_standing", {})
	return d if typeof(d) == TYPE_DICTIONARY else {}


# A guard close enough to have seen it (alive), or null.
static func witness(at: Node3D) -> Node:
	for g in at.get_tree().get_nodes_in_group("npc_guard"):
		var cn = g.get("combat_node")
		if g is Node3D and (g as Node3D).global_position.distance_to(at.global_position) <= WITNESS_RANGE \
				and (cn == null or (cn as CombatNode).is_alive()):
			return g
	return null


# The local player just did `kind` to `victim` (a name). True if it was a crime someone saw (and it's now on the books).
static func commit(player: Node3D, kind: String, victim: String) -> bool:
	if not CRIMES.has(kind) or not in_town(player):
		return false
	var key := "%s|%s" % [kind, victim.to_lower()]
	if Time.get_ticks_msec() - int(_last.get(key, -1000000)) < int(REPEAT_SECONDS * 1000.0):
		return false
	var seen_by := witness(player)
	if seen_by == null:
		return false   # nobody saw
	_last[key] = Time.get_ticks_msec()
	var c: Array = CRIMES[kind]
	set_bounty(player, bounty() + int(c[0]))
	var lost := standing_lost()
	for faction in c[1]:
		var change := int(c[1][faction])
		if player.has_method("adjust_standing"):
			player.adjust_standing(faction, change)
		lost[faction] = int(lost.get(faction, 0)) - change   # kept as a positive number of points lost
	Global.player_data["crime_standing"] = lost
	GameLog.log_general("[color=#ff5544]%s saw that! %s in town: your bounty in %s is now %s.[/color]" % [
			str(seen_by.get("npc_name")) if seen_by.get("npc_name") else "A guard", str(c[2]).capitalize(), REGION, coins(bounty())])
	Global.save_player_data_to_file()
	return true


static func set_bounty(player: Node, amount: int) -> void:
	amount = maxi(amount, 0)
	Global.player_data["bounty"] = amount
	if is_instance_valid(player) and "wanted" in player:
		player.wanted = amount
	if amount == 0 and is_instance_valid(player) and "resisting" in player:
		player.resisting = false


# Paying a guard (or the Magistrate) the whole bounty. False if the purse is short.
static func pay(player: Node) -> bool:
	var owed := bounty()
	if owed <= 0:
		return true
	if not Global.can_afford(owed):
		return false
	Global.spend_currency_copper(owed)
	set_bounty(player, 0)
	GameLog.log_general("[color=#ffdd88]You pay your fine of %s. Your record in %s is clear.[/color]" % [coins(owed), REGION])
	Global.save_player_data_to_file()
	return true


# The player chose to fight: every guard attacks them on sight until they pay or fall.
static func resist(player: Node) -> void:
	if "resisting" in player:
		player.resisting = true
	GameLog.log_general("[color=#ff4444]You resist arrest! The guards will attack you on sight.[/color]")


# Killed by a guard: the fine comes out of the purse; what couldn't be paid stays on the books.
static func on_killed_by_guard(player: Node) -> void:
	var owed := bounty()
	if "resisting" in player:
		player.resisting = false
	if owed <= 0:
		return
	var taken := mini(owed, Global.get_total_copper())
	if taken > 0:
		Global.spend_currency_copper(taken)
	set_bounty(player, owed - taken)
	if owed - taken > 0:
		GameLog.log_general("[color=#ff8866]The guards take %s from your purse. %s of your bounty remains.[/color]" % [coins(taken), coins(owed - taken)])
	else:
		GameLog.log_general("[color=#ff8866]The guards take your fine of %s from your purse. Your record is clear.[/color]" % coins(taken))
	Global.save_player_data_to_file()


# The Magistrate: buy back the standing crimes cost. Returns [points restored, copper cost] (0, 0 if nothing to restore or
# the purse is short).
static func amends_cost() -> int:
	var points := 0
	for f in standing_lost():
		points += int(standing_lost()[f])
	return points * AMENDS_COPPER_PER_POINT


static func make_amends(player: Node) -> bool:
	var cost := amends_cost()
	if cost <= 0 or not Global.can_afford(cost):
		return false
	Global.spend_currency_copper(cost)
	for f in standing_lost():
		if player.has_method("adjust_standing"):
			player.adjust_standing(f, int(standing_lost()[f]))
	Global.player_data["crime_standing"] = {}
	Global.save_player_data_to_file()
	return true


static func coins(copper: int) -> String:
	return load("res://Scripts/trade_window.gd").coins_text(copper)
