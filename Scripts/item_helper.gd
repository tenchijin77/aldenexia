# item_helper.gd — Counting and removing an item across every bag and basic slot the player carries (the same logic
# KenjiNPC uses for his hand-in, made reusable for the quest piece).
class_name ItemHelper
extends RefCounted


static func count(item_id: String) -> int:
	return KenjiNPC.count_item(item_id)


static func consume(item_id: String, amount: int) -> void:
	KenjiNPC.consume_item(item_id, amount)
