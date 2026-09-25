# server_trust.gd — the dedicated server's check on every character save a client uploads (net.gd _rpc_save_character()).
# Players' machines run their own characters, so a save could say anything; the server compares it with the save it
# already holds and keeps the stored value for anything that could not have happened in the time since, logging it:
#   - who you are never changes: name, race, class, sex, base stats, birthday;
#   - XP may rise only by what the server itself awarded for kills since the last save (Net's kill-XP ledger), plus the
#     XP of quests the save newly completes (Kenji's included), plus a small margin; your level must match your XP;
#   - coin may rise only at a generous rate (COIN_PER_MINUTE) plus quest coin rewards;
#   - skills never above their cap (combat_balance.json skill_cap_per_level x level, or what you already had); spells must exist and be your class's;
#     recipes must exist; languages at most 100 and at most one point per LANGUAGE_SECONDS;
#   - a surname only at level 10 (or from a game master).
# Game masters are trusted (their tools grant things). Item changes are reported (telemetry), not refused — yet.
# Pure functions: no scene, no network — the regression suite (tools/tests) calls check() directly.
class_name ServerTrust
extends RefCounted

const IMMUTABLE := ["player_name", "player_class", "player_race", "player_sex", "stats", "character_creation"]
const XP_MARGIN := 50                 # rounding, a tick of XP the ledger missed
const COIN_PER_MINUTE := 200          # copper; selling loot and gear, coin drops (2 silver a minute is a lot at level 1-10)
const COIN_BASE := 1000               # copper a character's coin allowance starts with at login
const COIN_BUCKET_MAX := COIN_PER_MINUTE * 60   # the allowance refills over time but never holds more than an hour's worth
const LANGUAGE_SECONDS := 4.0         # Languages.PRACTICE_COOLDOWN_MS
const COPPER := {"copper": 1, "silver": 10, "gold": 100, "platinum": 1000}


# Returns {"data": the save to write (fixed where needed), "anomalies": [strings], "changed": bool}.
#   stored   the save the server holds ({} for a brand-new character)
#   incoming the save the client sent
#   kill_xp  XP the server awarded this character since the stored save
#   elapsed  seconds since the stored save (or since login)
#   coin_allowance  copper the character may have gained (net.gd's per-character allowance, which refills with time so
#                   saving often gains nothing); -1 = work it out from `elapsed` (the tests)
# The result also has "coin_gained" (copper actually accepted), so the caller can spend the allowance.
static func check(stored: Dictionary, incoming: Dictionary, kill_xp: int, elapsed: float, is_gm: bool,
		quests_def: Dictionary, xp_table: Dictionary, spells: Dictionary, recipes: Dictionary, coin_allowance: int = -1) -> Dictionary:
	var data: Dictionary = incoming.duplicate(true)
	var anomalies: Array = []
	if stored.is_empty() or is_gm:
		return {"data": data, "anomalies": anomalies, "changed": false, "coin_gained": 0}

	for field in IMMUTABLE:
		if stored.has(field) and JSON.stringify(data.get(field)) != JSON.stringify(stored[field]):
			anomalies.append("%s changed (kept the stored value)" % field)
			data[field] = stored[field]

	# XP and level
	var quest_xp := 0
	var quest_coin := 0
	for q in newly_completed(stored, data):
		var rewards: Dictionary = quests_def.get(q["id"], {}).get("rewards", {})
		if q["repeat"] and quests_def.get(q["id"], {}).has("repeat_rewards"):
			rewards = quests_def[q["id"]]["repeat_rewards"]
		quest_xp += int(rewards.get("xp", 0)) * int(q["times"])
		quest_coin += coin_value(rewards.get("coin", {})) * int(q["times"])
	var old_xp := int(stored.get("xp", 0))
	# The margin covers rounding on XP that was really earned — never XP out of nothing (a save can be sent at any rate).
	var allowed_xp := old_xp + kill_xp + quest_xp + (XP_MARGIN if kill_xp + quest_xp > 0 else 0)
	if int(data.get("xp", 0)) > allowed_xp:
		anomalies.append("xp %d -> %d, only %d possible (kills %d, quests %d)" % [old_xp, int(data.get("xp", 0)), allowed_xp, kill_xp, quest_xp])
		data["xp"] = maxi(old_xp, allowed_xp)
	var level_ok := level_for_xp(int(data.get("xp", 0)), xp_table)
	if int(data.get("player_level", 1)) > level_ok:
		anomalies.append("level %d with only %d XP (kept level %d)" % [int(data.get("player_level", 1)), int(data.get("xp", 0)), level_ok])
		data["player_level"] = level_ok
		var next := int(xp_table.get(str(level_ok + 1), 0))
		data["xp_next_level"] = next if next > 0 else 999999

	# Coin
	var old_coin := coin_value(stored)
	var new_coin := coin_value(data)
	var allowance := coin_allowance if coin_allowance >= 0 else COIN_BASE + int(COIN_PER_MINUTE * elapsed / 60.0)
	var allowed_coin := old_coin + allowance + quest_coin
	if new_coin > allowed_coin:
		anomalies.append("coin %d -> %d copper, only %d possible in %d s" % [old_coin, new_coin, allowed_coin, int(elapsed)])
		for field in COPPER:
			data[field] = stored.get(field, 0)

	# Skills
	var level := int(data.get("player_level", 1))
	var skills: Dictionary = data.get("skill_levels", {}) if typeof(data.get("skill_levels")) == TYPE_DICTIONARY else {}
	var old_skills: Dictionary = stored.get("skill_levels", {}) if typeof(stored.get("skill_levels")) == TYPE_DICTIONARY else {}
	# The game's own cap (Data/combat_balance.json skill_cap_per_level, as Player3D.skill_cap_for() uses; 0 = no cap).
	var per_level := int(CombatBalance.num("skill_cap_per_level"))
	for skill in skills:
		if per_level <= 0:
			break
		var cap := maxi(level * per_level, int(old_skills.get(skill, 0)))
		if int(skills[skill]) > cap:
			anomalies.append("skill %s %d above its cap %d" % [skill, int(skills[skill]), cap])
			skills[skill] = cap

	# Spells: must exist and be this class's
	var my_class := str(data.get("player_class", ""))
	var old_spells: Array = stored.get("known_spells", []) if typeof(stored.get("known_spells")) == TYPE_ARRAY else []
	if typeof(data.get("known_spells")) == TYPE_ARRAY:
		var kept: Array = []
		for sp in data["known_spells"]:
			var info: Dictionary = spells.get(str(sp), {})
			if old_spells.has(sp) or (not info.is_empty() and info.get("class_level_requirements", {}).has(my_class)):
				kept.append(sp)
			else:
				anomalies.append("spell %s is not a %s spell (removed)" % [sp, my_class])
		data["known_spells"] = kept

	# Recipes must exist
	if typeof(data.get("known_recipes")) == TYPE_ARRAY:
		var kept_r: Array = []
		for r in data["known_recipes"]:
			if recipes.has(str(r)):
				kept_r.append(r)
			else:
				anomalies.append("unknown recipe %s (removed)" % r)
		data["known_recipes"] = kept_r

	# Languages
	var langs: Dictionary = data.get("languages", {}) if typeof(data.get("languages")) == TYPE_DICTIONARY else {}
	var old_langs: Dictionary = stored.get("languages", {}) if typeof(stored.get("languages")) == TYPE_DICTIONARY else {}
	var max_gain := floorf(elapsed / LANGUAGE_SECONDS) + (1.0 if elapsed >= 1.0 else 0.0)   # saves are at least 1 s apart (REMOTE_SAVE_DELAY)
	if old_langs.is_empty():
		langs = {}   # a character from before languages gets its race's starting languages on its first login: not a gain
	for lang in langs:
		var before := float(old_langs.get(lang, 0.0))
		var limit := minf(100.0, maxf(before, 1.0) + max_gain) if before > 0.0 else 1.0   # a new language starts at 1 (primer)
		if float(langs[lang]) > limit:
			anomalies.append("language %s %.0f -> %.0f too fast" % [lang, before, float(langs[lang])])
			langs[lang] = limit if before > 0.0 else 1.0

	# Surname: level 10 (net.gd lets a game master through before calling check())
	if str(data.get("surname", "")) != str(stored.get("surname", "")) and level < 10:
		anomalies.append("surname below level 10 (kept the stored one)")
		data["surname"] = str(stored.get("surname", ""))

	return {"data": data, "anomalies": anomalies, "changed": not anomalies.is_empty(),
			"coin_gained": maxi(0, coin_value(data) - old_coin - quest_coin)}


# Quests the new save has completed that the old one hadn't (or completed more times: repeatables):
# [{id, times, repeat}].
static func newly_completed(old: Dictionary, new: Dictionary) -> Array:
	var out: Array = []
	var oq: Dictionary = old.get("quests", {}) if typeof(old.get("quests")) == TYPE_DICTIONARY else {}
	var nq: Dictionary = new.get("quests", {}) if typeof(new.get("quests")) == TYPE_DICTIONARY else {}
	for id in nq:
		var n: Dictionary = nq[id] if typeof(nq[id]) == TYPE_DICTIONARY else {}
		var o: Dictionary = oq.get(id, {}) if typeof(oq.get(id)) == TYPE_DICTIONARY else {}
		var n_times := int(n.get("times", 1 if str(n.get("state", "")) == "complete" else 0))
		var o_times := int(o.get("times", 1 if str(o.get("state", "")) == "complete" else 0))
		if n_times > o_times:
			out.append({"id": str(id), "times": n_times - o_times, "repeat": o_times > 0})
	return out


static func coin_value(d: Dictionary) -> int:
	var total := 0
	for field in COPPER:
		total += int(d.get(field, 0)) * int(COPPER[field])
	return total


static func level_for_xp(xp: int, xp_table: Dictionary) -> int:
	var level := 1
	var top := int(xp_table.get("max_level", 20))
	for lvl in range(2, top + 1):
		if xp >= int(xp_table.get(str(lvl), 1 << 30)):
			level = lvl
	return level


# Everything counted by item id across the character's bags, character sheet, equipment and bank.
static func item_counts(d: Dictionary) -> Dictionary:
	var counts := {}
	var inv: Dictionary = d.get("inventory_data", {}) if typeof(d.get("inventory_data")) == TYPE_DICTIONARY else {}
	var lists: Array = []
	lists.append(inv.get("basic_inventory", []))
	for k in inv.get("bag_contents", {}):
		lists.append(inv["bag_contents"][k])
	lists.append(inv.get("equipped", {}).values() if typeof(inv.get("equipped")) == TYPE_DICTIONARY else [])
	for k in inv.get("bank_storage", {}):
		lists.append([inv["bank_storage"][k]])
	for lst in lists:
		if typeof(lst) != TYPE_ARRAY:
			continue
		for it in lst:
			if typeof(it) == TYPE_DICTIONARY and it.has("item_id"):
				var id := str(it["item_id"])
				counts[id] = int(counts.get(id, 0)) + int(it.get("quantity", 1))
	return counts


# What changed between two saves, for the telemetry log.
static func delta(old: Dictionary, new: Dictionary) -> Dictionary:
	var gained := {}
	var lost := {}
	var a := item_counts(old)
	var b := item_counts(new)
	for id in b:
		var diff := int(b[id]) - int(a.get(id, 0))
		if diff > 0:
			gained[id] = diff
	for id in a:
		var diff := int(a[id]) - int(b.get(id, 0))
		if diff > 0:
			lost[id] = diff
	return {
		"xp": int(new.get("xp", 0)) - int(old.get("xp", 0)),
		"level": int(new.get("player_level", 1)),
		"levels_gained": int(new.get("player_level", 1)) - int(old.get("player_level", 1)),
		"coin": coin_value(new) - coin_value(old),
		"deaths": int(new.get("deaths", 0)) - int(old.get("deaths", 0)),
		"death_by": str(new.get("last_death_by", "")) if int(new.get("deaths", 0)) > int(old.get("deaths", 0)) else "",
		"quests_completed": newly_completed(old, new).map(func(q): return q["id"]),
		"items_gained": gained,
		"items_lost": lost,
	}
