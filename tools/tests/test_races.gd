# Racial traits (player3d.gd apply_racial_modifiers() / apply_racial_traits()).
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var p = await make_player({"player_race": "dwarf"})
	eq(p.effective_skill("blacksmithing"), 15, "Dwarf +15 Blacksmithing when used")
	eq(int(p.skill_levels.get("blacksmithing", 0)), 0, "…but not trained")
	p.queue_free()
	await frames(2)
	p = await make_player({"player_race": "lizardkin", "stats": {"charisma": 8}})
	var ac: int = p.combat_node.get_ac()
	p.combat_node.gear_ac = 0
	p.combat_node._stats_dirty = true
	p.combat_node.recalculate_derived_stats()
	eq(p.combat_node.get_ac(), ac, "Lizardkin AC survives an equipment change")
	eq(p.combat_node.race_ac_bonus, 2, "Lizardkin +2 natural AC")
	p.queue_free()
	await frames(2)
	p = await make_player({"player_race": "gnome"})
	eq(p.combat_node.race_spell_crit_chance, 0.05, "Gnome 5% spell crit")
	eq(p.combat_node.race_crit_bonus, 0, "Gnome has no melee crit bonus")
	p.queue_free()
	await frames(2)
	p = await make_player({"player_race": "human"})
	eq(p.race_faction_offset, 10, "Human +10 faction")
	check(p.race_skill_gain_mult > 1.0, "Human skills grow faster")
