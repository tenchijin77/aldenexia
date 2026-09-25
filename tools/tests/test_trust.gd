# Server trust (server_trust.gd): what the server accepts from a character save and what it corrects.
extends "res://tools/tests/test_base.gd"


func _save(extra: Dictionary = {}) -> Dictionary:
	var d := {"player_name": "Ztest", "player_class": "Voidknight", "player_race": "troll", "player_sex": "male",
		"stats": {"strength": 16}, "character_creation": {"t": 1}, "xp": 1000, "player_level": 3, "xp_next_level": 2100,
		"copper": 50, "silver": 2, "gold": 0, "platinum": 0, "skill_levels": {"slashing_weapons": 10},
		"known_spells": ["life_siphon"], "known_recipes": ["smith_tin_ingot"], "languages": {"grommish": 100.0, "common": 15.0},
		"quests": {}, "surname": ""}
	d.merge(extra, true)
	return d


func _check(old: Dictionary, new: Dictionary, kill_xp: int = 0, elapsed: float = 60.0, gm: bool = false) -> Dictionary:
	Quests.definition("")
	var spells := {}
	for sp in JSON.parse_string(FileAccess.get_file_as_string("res://Data/player_spells.json")):
		spells[sp["spell_name"]] = sp
	var recipes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/tradeskill_recipes.json"))["recipes"]
	return ServerTrust.check(old, new, kill_xp, elapsed, gm, Quests._data, Global.xp_table, spells, recipes)


func run() -> void:
	var old := _save()
	# An honest save passes untouched
	var r := _check(old, _save({"xp": 1100, "copper": 90}), 100)
	eq(r["anomalies"], [], "honest save: no anomalies")
	# XP beyond the kill XP the server awarded is capped
	r = _check(old, _save({"xp": 5000, "player_level": 5}), 100)
	check(int(r["data"]["xp"]) <= 1000 + 100 + ServerTrust.XP_MARGIN, "xp inflated: capped (got %s)" % r["data"]["xp"])
	eq(int(r["data"]["player_level"]), 3, "level 5 claimed with 1150 xp: corrected to level 3")
	# Quest XP is allowed for a newly completed quest
	r = _check(old, _save({"xp": 1000 + 130, "quests": {"wagon_crash": {"state": "complete"}}}), 0)
	eq(r["anomalies"], [], "quest xp (The Wreck, 130) accepted")
	# A repeatable quest pays its repeat rewards the second time
	var bounty_once := _save({"quests": {"goblin_bounty": {"state": "complete", "times": 1}}})
	r = _check(bounty_once, _save({"xp": 1000 + 60, "quests": {"goblin_bounty": {"state": "complete", "times": 2}}}), 0)
	eq(r["anomalies"], [], "repeat bounty xp (60) accepted")
	# Identity can't change
	r = _check(old, _save({"player_class": "Arcanist", "stats": {"strength": 30}}))
	eq(str(r["data"]["player_class"]), "Voidknight", "class change reverted")
	eq(r["data"]["stats"], {"strength": 16}, "stats change reverted")
	# Coin flood
	r = _check(old, _save({"platinum": 50}), 0, 60.0)
	eq(int(r["data"]["platinum"]), 0, "50 platinum in a minute: reverted")
	r = _check(old, _save({"silver": 3}), 0, 60.0)
	eq(int(r["data"]["silver"]), 3, "a silver in a minute: fine")
	# Skills above the cap (level 3 x 4 = 12)
	r = _check(old, _save({"skill_levels": {"slashing_weapons": 40}}))
	eq(int(r["data"]["skill_levels"]["slashing_weapons"]), 12, "skill capped at level x 4")
	# Spells of another class are removed; own class kept
	r = _check(old, _save({"known_spells": ["life_siphon", "fireball", "shadow_aura"]}))
	eq(r["data"]["known_spells"], ["life_siphon", "shadow_aura"], "foreign spell removed")
	# Unknown recipe removed
	r = _check(old, _save({"known_recipes": ["smith_tin_ingot", "smith_mithril_everything"]}))
	eq(r["data"]["known_recipes"], ["smith_tin_ingot"], "unknown recipe removed")
	# Languages: a jump beyond one point per 4 s is capped
	r = _check(old, _save({"languages": {"grommish": 100.0, "common": 90.0}}), 0, 8.0)
	check(float(r["data"]["languages"]["common"]) <= 18.0, "common 15 -> 90 in 8 s capped (got %s)" % r["data"]["languages"]["common"])
	# A primer starts a new language at 1
	r = _check(old, _save({"languages": {"grommish": 100.0, "common": 15.0, "djhanid": 1.0}}))
	eq(r["anomalies"], [], "new language at 1 point accepted")
	# Surname below level 10 kept as stored
	r = _check(old, _save({"surname": "Bonecrusher"}))
	eq(str(r["data"]["surname"]), "", "surname below level 10 reverted")
	# Game masters are trusted
	r = _check(old, _save({"platinum": 50}), 0, 60.0, true)
	eq(int(r["data"]["platinum"]), 50, "game master save untouched")
	# Pre-language characters getting their race languages is not a gain
	r = _check(_save({"languages": {}}), _save({"languages": {"grommish": 100.0, "common": 15.0}}))
	eq(r["anomalies"], [], "first login race languages accepted")
	# No XP out of nothing (the margin only rounds XP really earned)
	r = _check(old, _save({"xp": 1040}), 0)
	eq(int(r["data"]["xp"]), 1000, "no kill/quest XP: not even the margin")
	# A spent coin allowance allows nothing more
	Quests.definition("")
	var spells := {}
	for sp in JSON.parse_string(FileAccess.get_file_as_string("res://Data/player_spells.json")):
		spells[sp["spell_name"]] = sp
	var rec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/tradeskill_recipes.json"))["recipes"]
	r = ServerTrust.check(old, _save({"silver": 5}), 0, 1.0, false, Quests._data, Global.xp_table, spells, rec, 0)
	eq(int(r["data"]["silver"]), 2, "no allowance left: coin gain refused")
	# Rapid saves don't farm language points
	r = _check(old, _save({"languages": {"grommish": 100.0, "common": 16.0}}), 0, 0.5)
	eq(float(r["data"]["languages"]["common"]), 15.0, "a save 0.5 s later can't add a language point")
	# Telemetry delta
	var d := ServerTrust.delta(old, _save({"xp": 1100, "deaths": 1, "last_death_by": "a sand viper"}))
	eq(int(d["xp"]), 100, "delta xp")
	eq(str(d["death_by"]), "a sand viper", "delta death cause")
