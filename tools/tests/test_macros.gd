# Macros (macros.gd): cleaning a save's list, %t/%T/%s, /cast name matching, /pause, running a macro through the chat
# window (a failed line stops it, /pause waits), shared macros, and the server putting the account's list into the save.
extends "res://tools/tests/test_base.gd"


func run() -> void:
	# sanitize: always the right number, lines cut to size, junk ignored
	var clean := Macros.sanitize([{"name": "A very long macro name here", "lines": ["x".repeat(500), "two"]}, "junk"], 24)
	eq(clean.size(), 24, "24 character macros")
	eq(str(clean[0]["name"]).length(), Macros.MAX_NAME_LENGTH, "name cut to size")
	eq(str(clean[0]["lines"][0]).length(), Macros.MAX_LINE_LENGTH, "line cut to size")
	eq(clean[0]["lines"].size(), Macros.MAX_LINES, "always five lines")
	check(Macros.is_empty_macro(clean[1]), "junk entry becomes an empty macro")
	eq(Macros.sanitize("not a list", 3).size(), 3, "a bad list becomes empty macros")
	check(not Macros.is_empty_macro({"name": "", "lines": ["/say hi"]}), "a macro with only a line is not empty")

	eq(Macros.pause_seconds(" 2"), 2.0, "/pause 2")
	eq(Macros.pause_seconds("99"), Macros.MAX_PAUSE, "/pause capped")
	eq(Macros.pause_seconds("3, /cast x"), 3.0, "EQ-style '/pause 3, ...'")
	eq(Macros.pause_seconds("soon"), -1.0, "/pause needs a number")

	var p = await make_player()
	var spell := ""
	for key in p._spell_by_name:
		var info: Dictionary = p._spell_by_name[key]
		if info.get("class_level_requirements", {}).has("Blademaster") and not info.get("passive", false):
			spell = str(key)
			break
	check(not spell.is_empty(), "found a Blademaster spell for the tests")
	p.known_spells = [spell]
	eq(Macros.resolve_spell(Player3D.spell_display_name(spell).to_upper(), p, false), spell, "/cast by shown name, any case")
	eq(Macros.resolve_spell(spell, p, false), spell, "/cast by key")
	eq(Macros.resolve_spell(Player3D.spell_display_name(spell).left(3), p, false), spell, "/cast by the start of the name")
	eq(Macros.resolve_spell("zzzz nothing", p, false), "", "unknown spell")

	# %t %T %s
	eq(Macros.substitute("Casting on %t", p), "Casting on nothing", "%t with no target")
	p.current_target = p
	eq(Macros.substitute("%s heals %t", p), "Ztest heals Ztest", "%s and %t")
	check(Macros.substitute("%T", p).contains("level 5") and Macros.substitute("%T", p).contains("% health"), "%T has level and health")
	p.current_target = null

	# Character macros live in the save
	Macros.set_macro("c2", {"name": "Hi", "icon": spell, "lines": ["/say hello"]})
	eq(str(Global.player_data["macros"][2]["name"]), "Hi", "character macro saved into the character")
	eq(Macros.icon_spell(Macros.get_macro("c2"), p), spell, "chosen icon")
	eq(Macros.icon_spell({"lines": ["/say x", "/cast " + Player3D.spell_display_name(spell)]}, p), spell, "automatic icon: the first /cast")
	eq(Macros.icon_spell({"lines": ["/say x"]}, p), "", "no icon without a /cast")

	# Shared macros with no server: a file every local character reads
	var backup := FileAccess.get_file_as_string(Macros.SHARED_FILE) if FileAccess.file_exists(Macros.SHARED_FILE) else ""
	Macros.set_macro("s0", {"name": "Shared", "lines": ["/say shared"]})
	eq(str(Macros.shared_list()[0]["name"]), "Shared", "shared macro stored")
	Global.player_data["macros"] = []
	eq(str(Macros.get_macro("s0")["name"]), "Shared", "another character sees it")
	if backup.is_empty():
		DirAccess.remove_absolute(Macros.SHARED_FILE)
	else:
		var f := FileAccess.open(Macros.SHARED_FILE, FileAccess.WRITE)
		f.store_string(backup)
		f.close()

	# Running through the chat window
	var win := get_tree().get_first_node_in_group("game_log_window")
	if win == null:
		win = load("res://Scenes/game_log_window.tscn").instantiate()
		get_tree().root.add_child(win)
		await frames(3)
		win.player = p
	check(win != null, "chat window exists")
	eq(win.run_macro_line("/cast zzzz nothing"), false, "a failed /cast reports failure")
	eq(win._resolve_command("/g"), "/party", "/g is group chat, not /gm")
	eq(win._resolve_command("/pa"), "/party", "/pa still means /party")
	eq(win._resolve_command("/ca"), "/camp", "/ca still means /camp")
	Macros.set_macro("c0", {"name": "Stop", "lines": ["/cast zzzz nothing", "/target Ztest"]})
	await win.run_macro("c0")
	check(p.current_target == null, "a failed /cast stops the macro (the /target after it never ran)")
	Macros.set_macro("c1", {"name": "Wait", "lines": ["/pause 0.3", "/target Ztest"]})
	win.run_macro("c1")
	await frames(2)
	check(p.current_target == null, "/pause waits")
	win.run_macro("c1")   # pressed again while running: ignored
	await get_tree().create_timer(0.6).timeout
	check(p.current_target == p, "after the pause the next line runs (/target)")
	check(not win._macro_running, "macro finished")

	# The Macros tab: edit and save a macro, then put it on the action bar
	p.toggle_abilities_book_tab("Macros")
	await frames(3)
	var book = p.abilities_book_instance
	var tabs: TabContainer = book.get_node("BookPanel/Tabs")
	eq(str(tabs.get_current_tab_control().name), "Macros", "/macro opens the Macros tab")
	var panel = tabs.get_node("Macros").get_child(0)
	eq(panel._grid.get_child_count(), Macros.CHARACTER_SLOTS, "24 macro buttons")
	panel._select("c5")
	panel._name_edit.text = "Pull"
	panel._line_edits[0].text = "/g Pulling %t"
	panel._line_edits[1].text = "/cast " + Player3D.spell_display_name(spell)
	panel._save()
	eq(str(Macros.get_macro("c5")["lines"][0]), "/g Pulling %t", "saved from the tab")
	check(panel._grid.get_child(5).icon != null or SpellInfo.icon_texture(p._spell_by_name[spell]) == null, "button shows the spell icon")
	check(panel._grid.get_child(5)._get_drag_data(Vector2.ZERO) == {"type": "macro", "name": "c5"}, "dragging gives a macro slot")
	panel._page_shared.button_pressed = true
	panel._show_page(true)
	eq(str(panel._grid.get_child(0).ref), "s0", "shared page")
	var bar = load("res://Scripts/action_bar.gd").new()
	add_child(bar)
	await frames(2)
	bar._player = p
	bar._on_slot_drop(3, {"type": "macro", "name": "c5"})
	eq(p.action_bar_slots[3], {"type": "macro", "name": "c5"}, "macro placed on the bar")
	eq(bar._slots[3]["type_lbl"].text, "M", "macro badge")
	eq(bar._macro_spell.get(3, ""), spell, "slot shows the macro's spell recast")
	p.toggle_abilities_book()
	bar.queue_free()

	# Server: the account's list goes into the character text; a repeated key is overridden by the last one
	var text: String = Net.append_json_key('{\n\t"player_name": "Ztest",\n\t"shared_macros": []\n}', "shared_macros", '[{"name":"X"}]')
	var parsed = JSON.parse_string(text)
	check(typeof(parsed) == TYPE_DICTIONARY, "appended text is still valid JSON")
	eq(str(parsed["shared_macros"][0]["name"]), "X", "the appended (account) list wins")
	eq(Net.append_json_key("{}", "a", "1"), "{\n\t\"a\": 1\n}", "appending to an empty object")
	if win.get_parent() == get_tree().root and not win.is_in_group("game_hud"):
		win.queue_free()
