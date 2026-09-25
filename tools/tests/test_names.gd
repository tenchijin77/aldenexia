# Character names (one word, letters) and surnames (/surname at level 10, game masters).
extends "res://tools/tests/test_base.gd"


func run() -> void:
	check(Net.valid_character_name("Targon"), "Targon is a valid name")
	check(not Net.valid_character_name("Tar Gon"), "no spaces")
	check(not Net.valid_character_name("Targon2"), "no digits")
	check(Net.valid_surname("O'Dunne") and Net.valid_surname("Stone-Hand"), "apostrophe and hyphen allowed inside")
	check(not Net.valid_surname("-Bad"), "no leading hyphen")
	eq(Net.format_surname("o'dunne"), "O'Dunne", "surname capitalised")
	var p = await make_player({"player_level": 5})
	check(p.set_own_surname("Stonebeard").contains("level 10"), "refused below level 10")
	p.combat_node.level = 10
	p.set_own_surname("stonebeard")
	eq(str(p.surname), "Stonebeard", "set at level 10")
	check(p.set_own_surname("Ironfoot").contains("Only a game master"), "only once")
	eq(TargetFrame.nameplate_name(p), "Ztest Stonebeard", "nameplate shows it")
