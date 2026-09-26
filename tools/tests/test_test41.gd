# Test 41 (Zozuur, Maedianie): the whole group shares a kill's XP; old characters get their class's starting weapon; pets
# wield their gear; a pet in Assist fights what the owner's /focus tank is fighting, sticks with its target until it dies,
# then goes straight on to the owner's next one.
extends "res://tools/tests/test_base.gd"


var _n := 0


func _monster(name: String, at: Vector3) -> Node3D:
	var m = load("res://Scenes/monster_template.tscn").instantiate()
	m.monster_name = name
	_n += 1
	m.name = "%s_%d" % [name, _n]   # unique, as spawned monsters are (a target key is the node's name)
	add_child(m)
	m.global_position = at
	await frames(3)
	return m


func run() -> void:
	make_floor(300.0)

	# group XP: split evenly with a bonus per member
	eq(Monster.group_xp_share(100, 1), 100, "alone: all of it")
	eq(Monster.group_xp_share(100, 2), 55, "two: 55 each (10% group bonus)")
	eq(Monster.group_xp_share(100, 3), 40, "three: 40 each")
	var killer = await make_player({"player_name": "Zozuur", "player_class": "Voidknight"})
	var healer = await make_player({"player_name": "Maedianie", "player_class": "Wildspeaker"})
	var far = await make_player({"player_name": "Tenchijin", "player_class": "Arcanist"})
	killer.global_position = Vector3(0, 1, 0)
	healer.global_position = Vector3(20, 1, 0)   # standing back, healing
	far.global_position = Vector3(250, 1, 0)
	healer.set_multiplayer_authority(900)   # other players' own machines (one machine here: give them their ids)
	far.set_multiplayer_authority(901)
	killer.group_members = [killer.get_multiplayer_authority(), 900, 901]
	var rat := await _monster("rat", Vector3(2, 1, 0))
	var got: Array = rat.xp_recipients(killer)
	check(got.has(killer) and got.has(healer), "the killer and the healer standing back both share it")
	check(not got.has(far), "someone %d m away doesn't" % int(Monster.XP_SHARE_RANGE))
	# on a server the groups come from the world link, by name, across zones
	killer.group_members = [killer.get_multiplayer_authority()]
	var link := preload("res://Scripts/world_link.gd").new()
	add_child(link)
	link.add_to_group("world_link")
	link.groups = {"zozuur": {"leader": "Zozuur", "members": ["Zozuur", "Maedianie", "Tenchijin"]}}
	got = rat.xp_recipients(killer)
	check(got.has(healer) and not got.has(far), "on a server: the group from the world link, the near ones share")
	link.queue_free()
	rat.queue_free()
	far.queue_free()

	# the starting weapon, once, for a character made before theirs existed
	var old_char = await make_player({"player_name": "Zold", "player_class": "Wildspeaker"})
	Global.player_data.erase("starter_weapon_checked")
	eq(ItemHelper.count("fir_staff"), 0, "an old Wildspeaker without her staff")
	old_char._grant_missing_starter_weapon()
	eq(ItemHelper.count("fir_staff"), 1, "gets it at login")
	Global.player_data.erase("starter_weapon_checked")
	old_char._grant_missing_starter_weapon()
	eq(ItemHelper.count("fir_staff"), 1, "never twice")
	check(FileAccess.get_file_as_string("res://Scripts/character_creation.gd").contains('"starter_weapon_checked": true'), "new characters start with theirs (and aren't given a second)")
	old_char.queue_free()

	# a pet wields its gear
	killer._summon_pet("spectral_minion")
	await frames(10)
	var pet = killer.active_pet
	check(is_instance_valid(pet), "a pet")
	if is_instance_valid(pet):
		killer.pet_equipment["primary"] = Inventory.get_item_definition("copper_sword").duplicate()
		killer.pet_equipment["primary"]["item_id"] = "copper_sword"
		killer.pet_equipment["offhand"] = Inventory.get_item_definition("bronze_shield").duplicate()
		killer.pet_equipment["offhand"]["item_id"] = "bronze_shield"
		killer._apply_pet_gear_bonus()
		eq(pet.held_gear, "copper_sword|bronze_shield", "the pet's gear is what it holds (replicated)")
		var sk: Skeleton3D = pet.get_node("Character").find_children("*", "Skeleton3D", true, false)[0]
		check(sk.get_node_or_null("Held_shortsword") != null and sk.get_node_or_null("Held_kite_shield") != null, "sword and shield in its hands")
		check(FileAccess.get_file_as_string("res://Scripts/summoned_pet.gd").contains("HeldGear.apply(character, held_gear)"), "summoned humanoid pets wield theirs too")

		# Assist with a /focus tank: the pet fights what the tank fights
		pet.command = PetMinion.PetState.ASSIST
		pet._standing_command = PetMinion.PetState.ASSIST
		var tank = healer   # Zozuur's pet assists Maedianie, standing in as the tank
		killer.focus_target = tank
		var goblin := await _monster("desert_goblin", Vector3(24, 1, 0))
		tank.current_target = goblin
		tank.target_key = TargetFrame.target_key_of(goblin)
		killer.last_attack_time_ms = -100000   # the owner hasn't swung at anything
		pet._auto_engage_timer = 10.0
		pet._process_auto_engage(0.1, true)
		check(pet.attack_target == goblin, "Assist + a focus tank: the pet joins the tank's fight")

		# it sticks with that target even when the owner turns to another
		var second := await _monster("desert_goblin", Vector3(-10, 1, 0))
		killer.current_target = second
		killer.last_attack_time_ms = Time.get_ticks_msec()
		for i in 5:
			pet._physics_process(0.1)
		check(pet.attack_target == goblin, "and stays on it when the owner switches (it may be fleeing low)")
		# when it dies, straight on to the owner's target, no swing needed
		killer.focus_target = null
		killer.last_attack_time_ms = -100000
		goblin.combat_node.current_hp = 0
		pet._physics_process(0.1)
		pet._process_auto_engage(0.1, true)
		check(pet.attack_target == second, "its target dead, it goes straight on to the owner's")
		goblin.queue_free()
		second.queue_free()
	killer.queue_free()
	healer.queue_free()
	await frames(2)
