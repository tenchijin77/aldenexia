# armor_types.gd — which armour a class can wear. An item's "armor_type" (Data/items.json: cloth / leather / chain / plate;
# shield; none = anyone, e.g. jewellery, lights) against the class's "armor_types" (Data/character_options.json).
# Everyone wears cloth. D&D-style: casters cloth; Woodstalker, Wildspeaker, Aetherfist leather; Shadowblade,
# Spiritweaver chain; the tanks, Troubadour and Lightmender plate. Shields ("armor_type": "shield") are a type of their own:
# the tanks, Lightmender, Troubadour, Spiritweaver and Wildspeaker.
class_name ArmorTypes
extends RefCounted

const ORDER := ["cloth", "leather", "chain", "plate"]


# The armour types a class may wear (class name or key, any case). Unknown class: everything.
static func allowed(player_class: String) -> Array:
	var classes: Dictionary = Global.character_options.get("classes", {})
	var key := player_class.to_lower().replace(" ", "_").replace("'", "")
	if not classes.has(key):
		return ORDER.duplicate()
	return classes[key].get("armor_types", ORDER.duplicate())


static func can_wear(item_def: Dictionary, player_class: String) -> bool:
	var armor_type := str(item_def.get("armor_type", ""))
	if armor_type == "shield" and _no_metal_shields(player_class) and str(item_def.get("shield_material", "")) == "metal":
		return false   # a Wildspeaker (D&D druid) carries wood or bone, never metal
	return armor_type.is_empty() or armor_type in allowed(player_class)


static func _no_metal_shields(player_class: String) -> bool:
	var key := player_class.to_lower().replace(" ", "_").replace("'", "")
	return bool(Global.character_options.get("classes", {}).get(key, {}).get("no_metal_shields", false))


# "Leather armour" / "A shield" / "" for an item with no armour type.
static func label(item_def: Dictionary) -> String:
	var armor_type := str(item_def.get("armor_type", ""))
	if armor_type == "shield":
		return "A shield"
	return "" if armor_type.is_empty() else "%s armour" % armor_type.capitalize()


# Why this class can't use it, as a sentence.
static func refusal(item_def: Dictionary, player_class: String) -> String:
	if str(item_def.get("armor_type", "")) == "shield":
		if _no_metal_shields(player_class) and "shield" in allowed(player_class):
			return "A %s carries wood or bone, never a metal shield." % player_class
		return "A %s can't use a shield." % player_class
	return "A %s can't wear %s — only %s." % [player_class, label(item_def).to_lower(), allowed_text(player_class)]


# "cloth, leather and chain" for a class (armour only, not shields).
static func allowed_text(player_class: String) -> String:
	var types: Array = allowed(player_class).filter(func(t): return t != "shield")
	if types.size() <= 1:
		return ", ".join(types)
	return "%s and %s" % [", ".join(types.slice(0, types.size() - 1)), types[-1]]


# ── Armour sets (Data/armor_sets.json, items' "armor_set") ──
static var _sets: Dictionary = {}


static func sets() -> Dictionary:
	if _sets.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://Data/armor_sets.json"))
		_sets = parsed if typeof(parsed) == TYPE_DICTIONARY else {"_": ""}
	return _sets


# The set an item belongs to ("" for none). Falls back to the item's definition (older saved copies).
static func set_of(item: Dictionary) -> String:
	var id := str(item.get("armor_set", ""))
	if id.is_empty() and item.has("item_id"):
		id = str(Inventory.get_item_definition(str(item["item_id"])).get("armor_set", ""))
	return id


# {set_id: pieces worn} for what is equipped now.
static func worn_counts() -> Dictionary:
	var counts := {}
	for slot in Inventory.EQUIPMENT_SLOTS:
		var item: Variant = Inventory.equipped.get(slot, null)
		if typeof(item) == TYPE_DICTIONARY:
			var id := set_of(item)
			if not id.is_empty():
				counts[id] = int(counts.get(id, 0)) + 1
	return counts


# The sets whose every piece is worn.
static func complete_sets() -> Array:
	var out: Array = []
	var counts := worn_counts()
	for id in counts:
		if sets().has(id) and int(counts[id]) >= int(sets()[id].get("pieces", 9)):
			out.append(id)
	return out


# "+2 AC, +2 Intelligence, +2 Wisdom"
static func bonus_text(set_id: String) -> String:
	var def: Dictionary = sets().get(set_id, {})
	var parts: Array = []
	if int(def.get("ac", 0)) > 0:
		parts.append("+%d AC" % int(def["ac"]))
	for stat in def.get("stats", {}):
		parts.append("+%d %s" % [int(def["stats"][stat]), "Stamina" if stat == "constitution" else stat.capitalize()])
	return ", ".join(parts)
