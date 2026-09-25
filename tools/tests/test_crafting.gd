# Crafting: the recipe picker (Tin Dagger vs Tin Shield), How many, splitting stacks, Deconstruct, bags inside bags.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var p = await make_player({"player_class": "Voidknight", "known_recipes": ["smith_tin_shield"], "skill_levels": {"blacksmithing": 10}})
	var w = load("res://Scenes/tradeskill_window.tscn").instantiate()
	add_child(w)
	await frames(2)
	w.setup("forge", "Forge", "Forge")
	var slots: Array = w.slot_row.get_children()
	slots[0].held_item_id = "tin_ingot"; slots[0].held_quantity = 2
	slots[1].held_item_id = "fir_planks"; slots[1].held_quantity = 1
	w._refresh_status()
	eq(str(w._find_best_recipe().get("id", "")), "smith_tin_shield", "2 tin + 1 fir makes a Tin Shield")
	slots[0].held_quantity = 20; slots[1].held_quantity = 20
	w._refresh_status()
	eq(int(w._count_spin.max_value), 10, "20 + 20: up to 10 shields")
	w._count_spin.value = 1
	eq(w._chosen_count(w._find_best_recipe()), 1, "How many = 1")
	for s in slots:
		s.held_item_id = ""; s.held_quantity = 0
	# Split
	Inventory.initialize_basic_inventory()
	Inventory.add_item("tin_ingot", 20)
	var idx := -1
	for i in Inventory.BASIC_INVENTORY_SIZE:
		if Inventory.basic_inventory[i] != null and Inventory.basic_inventory[i].get("item_id") == "tin_ingot":
			idx = i
	check(Inventory.split_stack("basic", idx, -1, -1, 2), "split 2 off 20")
	check(not Inventory.split_stack("basic", idx, -1, -1, 18), "can't split the whole stack")
	# Deconstruct
	eq(Deconstruct.returns("ragged_tunic").get("items", {}), {"linen_cloth": 1, "thread": 1}, "ragged tunic -> linen + thread")
	eq(Deconstruct.returns("tin_shield").get("items", {}), {"tin_ingot": 1}, "tin shield -> 1 tin ingot")
	eq(Deconstruct.returns("faded_note"), {}, "quest item can't be taken apart")
	# A looted bag fits into a bag that already holds things (it used to need an empty one)
	Inventory.initialize_basic_inventory()
	Inventory.basic_inventory[0] = Inventory.create_item_instance("traveler_pack")
	Inventory.bag_contents["0"] = [Inventory.create_item_instance("rat_tail")]
	for i in range(1, Inventory.BASIC_INVENTORY_SIZE):
		Inventory.basic_inventory[i] = Inventory.create_item_instance("tin_ingot")
	check(Inventory.add_item("small_bag", 1), "looted bag goes into a part-full pack")
