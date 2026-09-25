# Data/monsters.json is the source of truth for every monster: these checks keep it, the spawn files and the code agreeing.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/monsters.json"))
	monsters.erase("_comment")
	var loot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/solgrave_expanse_loot.json")).get("zone_loot_tables", {})
	var has_loot := func(id: String) -> bool:
		for z in loot.values():
			if z.has(id):
				return true
		return false
	var modelled: Array = Monster.HUMANOID_MOB_TYPES + Monster.CRITTER_MODELS.keys()
	for id in monsters:
		var m: Dictionary = monsters[id]
		for field in ["description", "health", "damage", "armor_class", "speed", "xp_gain", "category", "level"]:
			check(m.has(field), "%s has %s" % [id, field])
		var lo := int(m.get("level_min", m.get("level", 1)))
		var hi := int(m.get("level_max", m.get("level", 1)))
		check(lo <= hi and lo >= 1, "%s: level range %d-%d" % [id, lo, hi])
		var look := str(m.get("model_from", id))
		check(modelled.has(look), "%s has a model (its own, or model_from a monster that has one): %s" % [id, look])
		if m.has("loot_from"):
			check(monsters.has(m["loot_from"]) and has_loot.call(str(m["loot_from"])), "%s: loot_from %s has a loot table" % [id, m["loot_from"]])
		if m.has("on_hit_effect"):
			var e: Dictionary = m["on_hit_effect"]
			check(Player3D.MONSTER_AILMENTS.has(str(e.get("name", ""))), "%s: on-hit ailment '%s' is known (cures remove it, it shows on the status window)" % [id, e.get("name")])
			check(str(e.get("message", "%s")).contains("%s"), "%s: on-hit message names the monster" % id)
		if str(m.get("behavior_type", "")) == "passive" and float(m.get("aggro_range", 1)) == 0.0:
			check(m.get("faction", "None") != "None", "%s: a peaceful monster belongs to a faction" % id)

	# every built zone's spawn file names real monsters, and spawn points don't set levels (monsters.json does)
	for zone_id in ZoneInfo.zones():   # zones in Data/zones.json (other *_spawns.json files are old drafts for unbuilt zones)
		var file := "%s_spawns.json" % zone_id
		if not FileAccess.file_exists("res://Data/" + file):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://Data/" + file))
		check(typeof(data) == TYPE_DICTIONARY and data.has("spawns"), "%s is valid" % file)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for s in data.get("spawns", []):
			check(monsters.has(str(s.get("mob_type", ""))), "%s: %s is in monsters.json" % [file, s.get("mob_type")])
			check(not s.has("min_level") and not s.has("max_level"), "%s: %s doesn't set levels (monsters.json does)" % [file, s.get("mob_type")])
			check(typeof(s.get("position")) == TYPE_ARRAY and s["position"].size() == 3, "%s: %s has a position" % [file, s.get("mob_type")])

	# every Dustwind monster loads its stats and a look
	for id in ["plateau_spider", "djhanid_nomad", "spider_broodmother", "grave_abomination", "dustwalker_warlord"]:
		var mob = load("res://Scenes/monster_template.tscn").instantiate()
		mob.monster_name = id
		add_child(mob)
		await frames(2)
		check(mob.level >= int(monsters[id]["level_min"]) and mob.level <= int(monsters[id]["level_max"]), "%s spawns inside its level range (%d)" % [id, mob.level])
		check(mob.max_health > 0 and mob.monster_description == str(monsters[id]["description"]), "%s loads its stats" % id)
		mob.queue_free()
	await frames(2)
