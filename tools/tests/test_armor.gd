# Armour types by class, shields, and armour set bonuses.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var jerkin: Dictionary = Inventory.get_item_definition("leather_jerkin")
	var tin_shield: Dictionary = Inventory.get_item_definition("tin_shield")
	var bone_shield: Dictionary = Inventory.get_item_definition("bone_shield")
	check(not ArmorTypes.can_wear(jerkin, "Gravecaller"), "Gravecaller can't wear leather")
	check(ArmorTypes.can_wear(jerkin, "Voidknight"), "Voidknight wears leather")
	check(ArmorTypes.can_wear(Inventory.get_item_definition("copper_armor_plating"), "Troubadour"), "Troubadour wears plate")
	check(not ArmorTypes.can_wear(tin_shield, "Arcanist"), "Arcanist can't use a shield")
	check(not ArmorTypes.can_wear(tin_shield, "Wildspeaker"), "Wildspeaker: no metal shield")
	check(ArmorTypes.can_wear(bone_shield, "Wildspeaker"), "Wildspeaker: bone shield ok")
	var p = await make_player({"player_class": "Lightsworn", "player_level": 16})
	var ac0: int = p.combat_node.get_ac()
	for id in ["bronzeguard_gauntlets", "bronzeguard_sabatons", "bronzeguard_vambraces", "bronzeguard_girdle", "bronzeguard_helm",
			"bronzeguard_rerebraces", "bronzeguard_pauldrons", "bronzeguard_greaves", "bronzeguard_breastplate"]:
		var it: Dictionary = Inventory.create_item_instance(id)
		Inventory.equipped[Inventory.ITEM_SLOT_MAP[it["slot"]]] = it
	p._apply_equipment_from_inventory()
	p.combat_node.recalculate_derived_stats()
	eq(ArmorTypes.complete_sets(), ["bronzeguard"], "full Bronzeguard set recognised")
	check(p.combat_node.get_ac() >= ac0 + 32 + 5, "set AC plus bonus (%d -> %d)" % [ac0, p.combat_node.get_ac()])
