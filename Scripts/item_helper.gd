# item_helper.gd — Counting and removing an item across every bag and basic slot the player carries (the same logic
# KenjiNPC uses for his hand-in, made reusable for the quest piece).
class_name ItemHelper
extends RefCounted


static func count(item_id: String) -> int:
	return KenjiNPC.count_item(item_id)


static func consume(item_id: String, amount: int) -> void:
	KenjiNPC.consume_item(item_id, amount)


# The best gathering tool the player carries for a gathering skill ("prospecting" / "woodworking"), or {} if none —
# any item with a matching "gather_tool" (Data/crafting_items.json), highest "tool_tier" wins. Tools work from any bag.
static func best_gather_tool(skill: String) -> Dictionary:
	var best: Dictionary = {}
	var carried: Array = []
	for it in Inventory.basic_inventory:
		if it is Dictionary:
			carried.append(it)
	for key in Inventory.bag_contents:
		for it in Inventory.bag_contents[key]:
			if it is Dictionary:
				carried.append(it)
	for it in carried:
		if str(it.get("gather_tool", "")) != skill:
			continue
		if best.is_empty() or int(it.get("tool_tier", 1)) > int(best.get("tool_tier", 1)):
			best = it
	return best
