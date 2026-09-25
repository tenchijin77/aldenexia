# Data integrity: every id the game refers to exists.
extends "res://tools/tests/test_base.gd"


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func run() -> void:
	var items: Dictionary = Inventory.item_data
	check(items.size() > 600, "items loaded (%d)" % items.size())
	# Vendors
	for shop_id in _json("res://Data/vendor_shop.json"):
		var shop = _json("res://Data/vendor_shop.json")[shop_id]
		if typeof(shop) != TYPE_DICTIONARY:
			continue
		for id in shop.get("stock", []):
			check(items.has(id), "shop %s sells unknown item %s" % [shop_id, id])
	# Recipes
	var recipes: Dictionary = _json("res://Data/tradeskill_recipes.json")["recipes"]
	for rid in recipes:
		var r: Dictionary = recipes[rid]
		check(items.has(r["output"]), "recipe %s makes unknown %s" % [rid, r["output"]])
		for ing in r["ingredients"]:
			check(items.has(ing) or ing == "cooked_meat_any", "recipe %s needs unknown %s" % [rid, ing])
		if r.has("scroll"):
			check(items.has(r["scroll"]), "recipe %s scroll %s missing" % [rid, r["scroll"]])
	# Quests: hand-in and reward items exist, givers named
	Quests.definition("")
	for qid in Quests._data:
		var q = Quests._data[qid]
		if typeof(q) != TYPE_DICTIONARY:
			continue
		for id in Quests.requirements(qid):
			check(items.has(id), "quest %s wants unknown %s" % [qid, id])
		for rw in q.get("rewards", {}).get("items", []):
			check(items.has(rw["id"]), "quest %s rewards unknown %s" % [qid, rw["id"]])
		check(not str(q.get("giver", "")).is_empty(), "quest %s has a giver" % qid)
	# Spell scrolls teach real spells
	var spells := {}
	for sp in _json("res://Data/player_spells.json"):
		spells[sp["spell_name"]] = true
	for id in items:
		if typeof(items[id]) == TYPE_DICTIONARY and items[id].has("teaches_spell"):
			check(spells.has(items[id]["teaches_spell"]), "%s teaches unknown spell %s" % [id, items[id]["teaches_spell"]])
	# Armour sets: 9 pieces each, all typed
	var counts := {}
	for id in items:
		if typeof(items[id]) == TYPE_DICTIONARY and items[id].has("armor_set"):
			counts[items[id]["armor_set"]] = int(counts.get(items[id]["armor_set"], 0)) + 1
			check(not str(items[id].get("armor_type", "")).is_empty(), "%s set piece without armour type" % id)
	for set_id in ArmorTypes.sets():
		if set_id != "_comment":
			eq(int(counts.get(set_id, 0)), 9, "set %s pieces" % set_id)
	# Ley-lines and world objects reference real things
	var outskirts_ley: Dictionary = _json(PlayerTravel.LEY_LINES_PATH).get("lumora_outskirts", {})
	eq(outskirts_ley.get("nodes", []).size(), 0, "no ley-line sites in the Outskirts (the first is in Dustwind)")
	check(outskirts_ley.has("zone_entrance"), "the Outskirts still has an evacuation point")
	for obj in _json("res://Data/world_objects.json").get("lumora_outskirts", []):
		if obj.has("give_item"):   # (the mirror gives nothing)
			check(items.has(obj.get("give_item", "")), "world object gives unknown %s" % obj.get("give_item"))
