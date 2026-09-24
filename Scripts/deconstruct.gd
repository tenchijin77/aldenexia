# deconstruct.gd — taking old gear apart for crafting materials, at a crafting kit or a town station (tradeskill_window.gd's
# Deconstruct button). Rules (user, 2026-09-24):
#   - Gear made by a recipe gives back half of each ingredient (rounded down), at least one of the biggest.
#   - Gear with no recipe (loot, starting clothes) gives a basic material by what it is made of: cloth -> linen cloth and
#     thread (Tailoring), leather -> leather scraps (Leatherworking), metal armour / weapons / metal shields -> scrap metal
#     (Blacksmithing), a bow -> fir planks (Woodworking).
#   - It is done with the trade that works the material, so only at that trade's kit or station.
#   - No skill-ups. Quest items can't be taken apart; worn items can't be put in the crafting slots in the first place.
class_name Deconstruct
extends RefCounted

const RECIPES_PATH := "res://Data/tradeskill_recipes.json"
const BY_MATERIAL := {
	"cloth": {"skill": "tailoring", "items": {"linen_cloth": 1, "thread": 1}},
	"leather": {"skill": "leatherworking", "items": {"leather_scrap": 2}},
	"metal": {"skill": "blacksmithing", "items": {"scrap_metal": 2}},
	"wood": {"skill": "woodworking", "items": {"fir_planks": 1}},
}
const TRADE_STATIONS := {"tailoring": "a tailoring kit or the Tailor's Bench", "leatherworking": "a leatherworking kit or the Tannery",
	"blacksmithing": "the Forge", "woodworking": "a woodworking kit or the Woodworking Station",
	"jewelcrafting": "a jewelcrafting kit or the Jewelcrafting Station", "tinkering": "a tinkering kit or the Tinkering Bench",
	"fletching": "a fletching kit or the Fletching Station"}

static var _made_by: Dictionary = {}   # output item id -> recipe


static func _recipe_for(item_id: String) -> Dictionary:
	if _made_by.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(RECIPES_PATH))
		var recipes: Dictionary = parsed.get("recipes", {}) if typeof(parsed) == TYPE_DICTIONARY else {}
		for id in recipes:
			_made_by[str(recipes[id].get("output", ""))] = recipes[id]
		_made_by["_loaded"] = {}
	return _made_by.get(item_id, {})


# What taking one of this item apart gives: {"skill": trade, "items": {id: qty}}, or {} if it can't be taken apart.
static func returns(item_id: String) -> Dictionary:
	var def: Dictionary = Inventory.get_item_definition(item_id)
	if def.is_empty() or str(def.get("type", "")) == "quest" or bool(def.get("no_deconstruct", false)):
		return {}
	var slot := str(def.get("slot", "none"))
	if slot in ["none", "", "light", "ammo"] or str(def.get("type", "")) == "bag":
		return {}   # only gear: armour, weapons, jewellery, shields (not materials, food, lights or quivers)
	var recipe := _recipe_for(item_id)
	if not recipe.is_empty():
		var items := {}
		var biggest := ""
		for ing in recipe.get("ingredients", {}):
			if str(ing).ends_with("_any"):
				continue
			var half := int(recipe["ingredients"][ing]) / 2
			if half > 0:
				items[ing] = half
			if biggest.is_empty() or int(recipe["ingredients"][ing]) > int(recipe["ingredients"].get(biggest, 0)):
				biggest = ing
		if items.is_empty() and not biggest.is_empty():
			items[biggest] = 1
		return {"skill": str(recipe.get("skill", "")), "items": items} if not items.is_empty() else {}
	var material := _material(def)
	return BY_MATERIAL.get(material, {}).duplicate(true)


static func _material(def: Dictionary) -> String:
	var armor_type := str(def.get("armor_type", ""))
	match armor_type:
		"cloth", "leather":
			return armor_type
		"chain", "plate":
			return "metal"
		"shield":
			return "metal" if str(def.get("shield_material", "")) == "metal" else ""
	if str(def.get("type", "")) == "weapon":
		return "wood" if str(def.get("slot", "")) == "ranged" else "metal"
	return ""


# "2 Linen Cloth, 1 Thread"
static func describe(items: Dictionary) -> String:
	var parts: Array = []
	for id in items:
		parts.append("%d %s" % [int(items[id]), Inventory.get_item_definition(id).get("name", id)])
	return ", ".join(parts)


static func where(skill: String) -> String:
	return TRADE_STATIONS.get(skill, "the right crafting station")
