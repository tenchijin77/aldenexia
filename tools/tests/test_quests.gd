# Quests: multi-item hand-ins, "have enough", old saves, find objectives (the foundation stone), repeatables, Kenji's
# journal mirror, and the guards' hail hooks.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var p = await make_player()
	Global.player_data["quests"] = {}
	Quests.definition("")
	Quests._data["zz_multi"] = {"name": "Zz", "giver": "Guard Reyna", "short": "x", "objective": {"type": "hand_in", "items": {"rat_tail": 2, "bat_wing": 1}}, "rewards": {"xp": 1}, "texts": {}}
	Quests.start("zz_multi")
	Inventory.add_item("rat_tail", 3)
	eq(Quests.try_hand_in("Guard Reyna", "rat_tail", p)["result"], "progress", "part hand-in")
	eq(ItemHelper.count("rat_tail"), 1, "only what is owed is taken")
	eq(Quests.try_hand_in("Guard Reyna", "rat_tail", p)["result"], "have_enough", "have enough")
	Inventory.add_item("bat_wing", 1)
	eq(Quests.try_hand_in("Guard Reyna", "bat_wing", p)["result"], "complete", "multi-item complete")
	Quests._data.erase("zz_multi")
	# Old save format (only "progress")
	Global.player_data["quests"]["release_the_hollowed"] = {"state": "active", "progress": 2}
	eq(Quests.progress("release_the_hollowed"), 2, "old save progress read")
	# Repeatable
	Global.player_data["quests"]["goblin_bounty"] = {"state": "active", "progress": 0}
	Inventory.add_item("goblin_ear", 20)
	Quests.try_hand_in("Sergeant Bryn", "goblin_ear", p)
	eq(ItemHelper.count("recipe_smith_bronzeguard_breastplate"), 1, "bounty first time: breastplate scroll")
	Quests.try_hand_in("Sergeant Bryn", "goblin_ear", p)
	eq(ItemHelper.count("recipe_smith_bronzeguard_breastplate"), 1, "bounty again: no second scroll")
	eq(int(Quests._entry("goblin_bounty").get("times", 0)), 2, "bounty done twice")
	# Find objective via the night-only stone
	Quests.start("guildmasters_note")
	var stone := WorldNote.new()
	var cfg := {"title": "Stone", "give_item": "aelrics_letter", "night_only": false, "note_text": "x"}
	for f in cfg:
		stone.set(f, cfg[f])
	add_child(stone)
	stone.read(p)
	await frames(2)
	eq(Quests.state("guildmasters_note"), "complete", "foundation stone completes the note quest")
	eq(ItemHelper.count("scroll_of_high_arcanum_basics"), 1, "High Arcanum primer rewarded")
	# Kenji's mirror
	Quests.sync_progress("kenjis_rat_tails", "rat_tail", 4)
	eq(Quests.item_progress_text("kenjis_rat_tails"), "4 / 10", "Kenji journal progress")
	# Hail hooks: Reyna offers the wagon when it isn't started
	var reyna = load("res://Scenes/guard_npc.tscn").instantiate()
	reyna.npc_name = "Guard Reyna"
	add_child(reyna)
	await frames(3)
	Global.player_data["quests"].erase("wagon_crash")
	check(reyna._hail_hook_line().contains("wagon"), "Reyna's hail offers the wagon")
