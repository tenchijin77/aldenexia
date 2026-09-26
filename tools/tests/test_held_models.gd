# The held models (2026-09-26 art drop, tools/blender/fix_held_model.py): every item that names a held_model has it; the
# new weapon types exist as items; two-handed weapons keep the off hand empty; a lit torch or lantern (else the bow) shows
# in an empty left hand, a quiver on the back; guards carry a weapon and the Wardens' tower shield.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://Data/items.json"))
	var missing := []
	for k in items:
		var it = items[k]
		if typeof(it) == TYPE_DICTIONARY and str(it.get("held_model", "")) != "" \
				and not ResourceLoader.exists("res://models/Weapons/%s.glb" % it["held_model"]):
			missing.append("%s->%s" % [k, it["held_model"]])
	check(missing.is_empty(), "every held_model exists (%s)" % str(missing))
	for k in ["copper_mace", "copper_warhammer", "knotted_club", "copper_greataxe", "copper_maul", "copper_great_hammer",
			"great_club", "bronze_greatsword", "fir_quarterstaff", "apprentice_wand", "light_crossbow", "fishing_pole"]:
		check(items.has(k) and str(items[k].get("held_model", "")) != "", "%s exists and shows" % k)
	for k in ["torch", "copper_lantern", "miners_pick", "woodcutters_axe", "fir_shortbow", "quiver_of_fir_arrows"]:
		check(str(items[k].get("held_model", "")) != "", "%s has its model now" % k)
	check(bool(items["fir_staff"].get("two_handed", false)) and bool(items["copper_greataxe"].get("two_handed", false)), "staves and the greataxe are two-handed")
	check(ResourceLoader.exists("res://models/Environmental/treasure_chest.glb"), "the locked chest model is in")

	# two hands
	var p = await make_player({"player_name": "Zozuur", "player_class": "Voidknight"})
	Inventory.equipped["offhand"] = Inventory.get_item_definition("tin_shield").duplicate()
	Inventory.equipped["offhand"]["item_id"] = "tin_shield"
	var greataxe: Dictionary = Inventory.get_item_definition("copper_greataxe").duplicate()
	greataxe["item_id"] = "copper_greataxe"
	eq(Inventory._equip_item(greataxe, "none"), false, "a greataxe won't go on with a shield in the off hand")
	Inventory.equipped.erase("offhand")
	Inventory.equipped["primary"] = greataxe
	var shield: Dictionary = Inventory.get_item_definition("tin_shield").duplicate()
	shield["item_id"] = "tin_shield"
	eq(Inventory._equip_item(shield, "none"), false, "nor a shield with a greataxe in hand")
	Inventory.equipped.erase("primary")

	# what shows
	eq(HeldGear.encode("copper_mace", "", "torch"), "copper_mace||torch", "a third field: the left hand")
	eq(HeldGear.encode("a", "", "", "quiver_of_fir_arrows"), "a|||quiver_of_fir_arrows", "a fourth: the back")
	var ch: Node3D = p.get_node("Character")
	HeldGear.apply(ch, "copper_mace||torch|quiver_of_fir_arrows")
	var sk: Skeleton3D = ch.find_children("*", "Skeleton3D", true, false)[0]
	check(sk.get_node_or_null("Held_one_handed_mace") != null, "the mace in the right hand")
	check(sk.get_node_or_null("Held_hand_torch") != null, "a lit torch in the empty left hand")
	check(sk.get_node_or_null("Held_quiver") != null, "the quiver on the back")
	HeldGear.apply(ch, "copper_mace|tin_shield|torch")
	check(sk.get_node_or_null("Held_hand_torch") == null and sk.get_node_or_null("Held_buckler") != null, "a shield takes the left hand before the torch")
	p.queue_free()

	# guards
	var g = load("res://Scenes/guard_npc.tscn").instantiate()
	g.npc_name = "Guard Reyna"
	add_child(g)
	await frames(4)
	var gsk: Skeleton3D = g.get_node("Character").find_children("*", "Skeleton3D", true, false)[0]
	var held := gsk.get_children().filter(func(c): return c.is_in_group(HeldGear.GROUP)).map(func(c): return String(c.name))
	check(held.has("Held_tower_shield") and held.size() >= 2, "a guard carries a weapon and the tower shield (%s)" % str(held))
	g.queue_free()
	await frames(2)
