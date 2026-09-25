# Factions (2026-09-25): every faction in Data/factions.json, standing that changes with kills and ripples to allies and
# rivals, races that start liked or distrusted, and monsters that attack on sight / leave you be by your standing (the Djhanid).
extends "res://tools/tests/test_base.gd"


func run() -> void:
	var factions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://Data/factions.json"))["factions"]
	var by_name := {}
	for f in factions:
		by_name[f["name"]] = f
	var start: Array = JSON.parse_string(FileAccess.get_file_as_string("res://Data/player_faction.json"))["factions"]
	var start_names: Array = start.map(func(s): return s["name"])
	for f in factions:
		if f["type"] == "player":
			check(start_names.has(f["name"]), "%s has a starting standing in player_faction.json" % f["name"])
			check(int(f["hostile_threshold"]) < int(f["friendly_threshold"]), "%s: hostile below friendly" % f["name"])
			for other in f.get("relations", {}):
				check(by_name.has(other), "%s's relation '%s' is a faction" % [f["name"], other])
	for s in start_names:
		check(by_name.has(s), "starting standing '%s' is a faction" % s)
	for name in ["Luminar Covenant", "The Moribund Order", "Tenebrae Obscurium", "Lirael's Concord", "Djhanid Clans", "Covenant of the Dark Kris"]:
		check(by_name.has(name), "%s is in the game" % name)
	for old in ["Umbral Talon", "Twilight Accord", "Echoes of the Deep"]:
		check(not by_name.has(old), "the old name %s is gone" % old)
		for f in ["dialogue.json", "dialogue_lumora.json", "deities.json", "race_faction_affiliations.json"]:
			check(not FileAccess.get_file_as_string("res://Data/" + f).to_lower().contains(old.to_lower()), "%s doesn't say %s" % [f, old])
	var races: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/race_faction_affiliations.json"))["races"]
	for r in races:
		check(Global.character_options.get("races", {}).has(r), "race_faction_affiliations: %s is a race" % r)
		for f in races[r]["standing_modifiers"]:
			check(by_name.has(f), "%s's modifier '%s' is a faction" % [r, f])

	# A human: the Covenant likes them a little more; the Order a little less
	var p = await make_player({"player_race": "human"})
	var covenant_base := int(p.faction_standing.get("Luminar Covenant", 0))
	eq(p.get_faction_standing("Luminar Covenant"), covenant_base + 10 + p.race_faction_offset, "a human starts in the Covenant's favour")
	eq(Player3D.faction_display_name("The Moribund Order"), "The Moribund Order", "names with their own 'The' keep it")
	for f in factions:
		if f["type"] == "order":
			check(by_name.has(str(f.get("parent", ""))) and by_name[f["parent"]]["type"] == "player", "order %s sits within a player faction" % f["name"])
			check(not start_names.has(f["name"]), "order %s has no standing of its own" % f["name"])
	eq(Player3D.faction_display_name("Djhanid Clans"), "the Djhanid Clans", "the others get 'the'")

	# Ripple: helping the Covenant pleases the Wardens and angers the Order
	var wardens := int(p.faction_standing["Wardens of the Sacred Flame"])
	var order := int(p.faction_standing["The Moribund Order"])
	p.adjust_standing("Luminar Covenant", 20)
	eq(int(p.faction_standing["Luminar Covenant"]), covenant_base + 20, "the change itself")
	eq(int(p.faction_standing["Wardens of the Sacred Flame"]), wardens + 10, "allies share half")
	eq(int(p.faction_standing["The Moribund Order"]), order - 10, "rivals lose half")
	eq(int(Global.player_data["faction_standing"]["The Moribund Order"]), order - 10, "the ripple is saved with the character")
	p.adjust_standing("Luminar Covenant", 500)
	eq(int(p.faction_standing["Luminar Covenant"]), Player3D.STANDING_MAX, "standing tops out")
	eq(Player3D.standing_name("Circle of Thorns"), "The Verdant Kin", "the Circle of Thorns shares the Verdant Kin's standing")
	var kin := int(p.faction_standing["The Verdant Kin"])
	p.adjust_standing("Circle of Thorns", -5)
	eq(int(p.faction_standing["The Verdant Kin"]), kin - 5, "angering the Circle angers the Verdant Kin")
	eq(p.get_faction_standing("Hands of the Eternal Forge"), p.get_faction_standing("Ironclad Brotherhood"), "the Forge-priests read the Brotherhood's standing")

	# The Djhanid: wary at the start, hate you after a few killings, allies once you've earned it
	check(not p.kos_factions.has("Djhanid") and not p.ally_factions.has("Djhanid"), "the Djhanid are wary of a newcomer")
	var nomad = load("res://Scenes/monster_template.tscn").instantiate()
	nomad.monster_name = "djhanid_nomad"
	add_child(nomad)
	await frames(3)
	check(nomad.wary, "the nomad is wary (monsters.json)")
	eq(nomad.faction, "Djhanid", "the nomad's faction")
	eq(int(nomad.kill_standing.get("Djhanid Clans", 0)), -15, "killing one costs standing")
	nomad.player = p
	nomad.global_position = p.global_position + Vector3(1, 0, 0)
	check(not nomad.can_see_player(), "a wary nomad next to you doesn't start a fight")
	for i in 3:
		p.receive_standing_changes(JSON.stringify(nomad.kill_standing))
	check(p.kos_factions.has("Djhanid"), "after three killings the Djhanid attack on sight (standing %d)" % p.get_faction_standing("Djhanid Clans"))
	check(nomad.can_see_player(), "so the nomad goes for you")
	nomad.global_position = p.global_position + Vector3(4, 0, 0)
	check(nomad.can_see_player(), "from further off too")
	eq(TargetFrame.faction_status(nomad), "Enemy", "their con says so")
	p.adjust_standing("Djhanid Clans", 200)
	check(p.ally_factions.has("Djhanid") and not p.kos_factions.has("Djhanid"), "treat them well and they're allies")
	check(not nomad.can_see_player(), "an ally never starts a fight")
	nomad.queue_free()
	p.queue_free()
	await frames(2)
