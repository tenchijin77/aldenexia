# Appearance (2026-09-25): sliders, colours, the lock (set once at creation or the mirror; then only hair), the server
# enforcing it, the models' blend shapes and masks, the editor window and Lumora's mirror.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	# validate: ranges, women's shapes, palettes
	var v := Appearance.validate({"height": 5, "weight": -3, "bust": 0.7, "skin_color": "#123456", "hair_color": Appearance.HAIR_PALETTE[2]}, "male", "human")
	eq(v["height"], 1.0, "height is clamped")
	eq(v["weight"], -0.5, "weight's thin end is -0.5")
	eq(v["bust"], 0.0, "a man has no bust slider")
	eq(v["skin_color"], "", "a colour not in the palette is dropped")
	eq(v["hair_color"], Appearance.HAIR_PALETTE[2], "a palette hair colour is kept")
	eq(Appearance.validate({"bust": 0.7}, "female", "elf")["bust"], 0.7, "a woman's bust slider is kept")
	check(Appearance.skin_palette("dark_elf") != Appearance.skin_palette("human"), "each race has its own skin tones")
	eq(Appearance.validate({"eye_color": Appearance.EYE_PALETTE[0]}, "male", "human")["eye_color"], Appearance.EYE_PALETTE[0] if Appearance.EYE_COLOUR_ENABLED else "", "eye colour only while it's switched on")

	# merge: open before the lock, then only hair
	var first := Appearance.merge(null, {"height": 0.5, "hair_color": Appearance.HAIR_PALETTE[0]}, "female", "human")
	eq(first["appearance"]["height"], 0.5, "an unlocked look is taken whole")
	var locked: Dictionary = first["appearance"].duplicate()
	locked["locked"] = true
	var later := Appearance.merge(locked, {"height": -1.0, "weight": 1.0, "hair_color": Appearance.HAIR_PALETTE[5]}, "female", "human")
	eq(later["appearance"]["height"], 0.5, "once locked, the height stays")
	eq(later["appearance"]["hair_color"], Appearance.HAIR_PALETTE[5], "but the hair colour may change")
	check((later["refused"] as Array).has("height") and (later["refused"] as Array).has("weight"), "and the refused changes are named")

	# the server: a locked look can't be changed by a save; a first look is locked when it arrives
	var stored := {"player_name": "Zlook", "player_race": "human", "player_sex": "female", "xp": 0, "appearance": locked}
	var incoming := stored.duplicate(true)
	incoming["appearance"] = {"height": -1.0, "hair_color": Appearance.HAIR_PALETTE[7], "locked": true}
	var r := ServerTrust.check(stored, incoming, 0, 60.0, false, {}, Global.xp_table, {}, {})
	eq(r["data"]["appearance"]["height"], 0.5, "the server keeps the locked height")
	eq(r["data"]["appearance"]["hair_color"], Appearance.HAIR_PALETTE[7], "and takes the new hair colour")
	check(r["changed"] and (r["anomalies"] as Array).any(func(x): return str(x).contains("appearance")), "and logs the attempt")
	var old_char := {"player_name": "Zold", "player_race": "dwarf", "player_sex": "male", "xp": 0}
	var at_mirror := old_char.duplicate(true)
	at_mirror["appearance"] = {"height": 0.3, "weight": 0.4, "locked": false}
	var r2 := ServerTrust.check(old_char, at_mirror, 0, 60.0, false, {}, Global.xp_table, {}, {})
	check(bool(r2["data"]["appearance"]["locked"]) and is_equal_approx(float(r2["data"]["appearance"]["height"]), 0.3), "an old character's first look (the mirror) is taken and locked")
	var fresh := ServerTrust.check({}, {"player_name": "Znew", "appearance": {"height": 9}}, 0, 0.0, false, {}, Global.xp_table, {}, {})
	eq(fresh["data"]["appearance"]["height"], 1.0, "a new character's look is kept in range")

	# every race model: a rebuilt mesh with its slider shapes, and a colour mask with its colours
	for key in Player3D.CHARACTER_MODELS:
		var info: Dictionary = Player3D.CHARACTER_MODELS[key]
		var scene_path := str(info["scene"])
		var mask := Appearance.mask_for(scene_path)
		check(mask.has("mask") and mask.has("skin"), "%s has a colour mask with its skin colour" % key)
		var res := MeshSmoothing.rebuilt_mesh_path(scene_path)
		if ResourceLoader.exists(res):
			var mesh: Mesh = load(res)
			var names := []
			for i in mesh.get_blend_shape_count():
				names.append(str(mesh.get_blend_shape_name(i)))
			var want: Array = ["bust", "waist", "hips", "weight", "muscle"] if key.ends_with("_female") else ["weight", "muscle"]
			check(want.all(func(n): return names.has(n)), "%s's mesh has the slider shapes %s (has %s)" % [key, str(want), str(names)])

	# apply: blend shapes, height, the recolouring material
	var info: Dictionary = Player3D.CHARACTER_MODELS["half_elf_female"]
	var model: Node3D = load(info["scene"]).instantiate()
	MeshSmoothing.use_rebuilt_mesh(model)
	add_child(model)
	var look := Appearance.validate({"height": 1.0, "bust": 0.6, "weight": -0.3, "hair_color": Appearance.HAIR_PALETTE[0], "eye_color": Appearance.EYE_PALETTE[4]}, "female", "half_elf")
	Appearance.apply(model, info["scene"], info["texture_override"], look, "half_elf", Vector3.ONE)
	var mi := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var bust_i := -1
	for i in mi.mesh.get_blend_shape_count():
		if str(mi.mesh.get_blend_shape_name(i)) == "bust":
			bust_i = i
	check(bust_i >= 0 and is_equal_approx(mi.get_blend_shape_value(bust_i), 0.6), "the bust slider drives the bust shape")
	check(is_equal_approx(model.scale.x, 1.0 + Appearance.height_range("half_elf")), "height scales the model")
	check(mi.get_surface_override_material(0) is ShaderMaterial, "a colour choice uses the recolouring material")
	var plain := Appearance.validate({}, "female", "half_elf")
	Appearance.apply(model, info["scene"], info["texture_override"], plain, "half_elf", Vector3.ONE)
	check(mi.get_surface_override_material(0) is StandardMaterial3D, "no colour choice: the plain texture")
	model.queue_free()

	# the player: the first look locks; after that only the hair changes
	var p = await make_player({"player_race": "human", "player_sex": "female"})
	Global.player_data.erase("appearance")
	p.set_appearance({"height": 0.4, "weight": 0.2})
	check(bool(Global.player_data["appearance"]["locked"]), "the first look is locked")
	p.set_appearance({"height": -0.8, "hair_color": Appearance.HAIR_PALETTE[3]})
	eq(float(Global.player_data["appearance"]["height"]), 0.4, "a second visit can't change the height")
	eq(str(Global.player_data["appearance"]["hair_color"]), Appearance.HAIR_PALETTE[3], "only the hair")
	check(p.appearance_json.contains(Appearance.HAIR_PALETTE[3]), "and everyone sees it (replicated appearance_json)")

	# the editor: full (creation / the mirror's first use) and locked (hair only)
	var done := [null]
	var w := AppearanceEditor.open(self, "human", "female", Player3D.CHARACTER_MODELS["human_female"], {}, "full", func(l): done[0] = l, true)
	await frames(2)
	eq(w._sliders.size(), 6, "a woman gets six body sliders")
	w._sliders["height"].value = 0.5
	w._on_save()
	check(done[0] == null and w._armed, "the mirror's first save asks once more")
	w._on_save()
	await frames(1)
	check(done[0] is Dictionary and is_equal_approx(float(done[0]["height"]), 0.5), "then saves the look")
	var w2 := AppearanceEditor.open(self, "dwarf", "male", Player3D.CHARACTER_MODELS["dwarf_male"], {"locked": true}, "locked", func(_l): pass)
	await frames(2)
	eq(w2._sliders.size(), 0, "locked: no body sliders")
	eq(w2._swatch_rows.keys(), ["hair_color"], "locked: only the hair colour")
	w2.queue_free()
	var w3 := AppearanceEditor.open(self, "dwarf", "male", Player3D.CHARACTER_MODELS["dwarf_male"], {}, "full", func(_l): pass)
	await frames(2)
	eq(w3._sliders.size(), 3, "a man gets height, weight and muscle")
	w3.queue_free()

	# Lumora's mirror
	var mirrors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://Data/world_objects.json"))["lumora_outskirts"].filter(func(o): return o.get("opens", "") == "mirror")
	eq(mirrors.size(), 1, "Lumora has the mirror")
	var mirror := WorldNote.new()
	mirror.opens = "mirror"
	mirror.show_mirror = true
	add_child(mirror)
	mirror.read(p)
	await frames(2)
	var opened := get_tree().root.get_children().filter(func(n): return n is AppearanceEditor)
	check(opened.size() == 1 and opened[0].mode == "locked", "using it opens the window, hair only for a locked look")
	for o in opened:
		o.queue_free()
	mirror.queue_free()
	p.queue_free()
	await frames(2)
