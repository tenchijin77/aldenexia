# macro_panel.gd — the abilities book's "Macros" tab (macros.gd has the rules). Two pages of 24 buttons: this character's
# macros and the shared ones every character on the account sees. Click a button to edit it below; drag it to the action
# bar to use it. No class_name: abilities_book.gd preloads it.
extends VBoxContainer

const BUTTON_SIZE := 44
const COLUMNS := 6

# A macro button: clicking selects it for editing, dragging it gives the action bar {"type": "macro", "name": ref}.
class MacroButton extends Button:
	var panel = null
	var ref := ""

	func _get_drag_data(_at: Vector2) -> Variant:
		var macro := Macros.get_macro(ref)
		if macro.is_empty() or Macros.is_empty_macro(macro):
			return null
		var preview := Button.new()
		preview.icon = icon
		preview.text = text
		preview.expand_icon = true
		preview.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		preview.modulate = Color(1, 1, 1, 0.85)
		set_drag_preview(preview)
		return {"type": "macro", "name": ref}


var _player: Node = null
var _shared := false
var _selected := ""
var _grid: GridContainer = null
var _page_char: Button = null
var _page_shared: Button = null
var _editing_lbl: Label = null
var _name_edit: LineEdit = null
var _icon_pick: OptionButton = null
var _line_edits: Array[LineEdit] = []
var _icon_keys: Array = []   # OptionButton index -> spell key ("" = automatic)


func setup(player: Node) -> void:
	_player = player
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pages := HBoxContainer.new()
	var group := ButtonGroup.new()
	_page_char = _page_button("This character", group, false)
	_page_shared = _page_button("Shared (account)", group, true)
	pages.add_child(_page_char)
	pages.add_child(_page_shared)
	add_child(pages)

	var hint := Label.new()
	hint.text = "Click a macro to edit it. Drag it to the action bar to use it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	add_child(hint)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	add_child(_grid)

	add_child(HSeparator.new())
	_editing_lbl = Label.new()
	_editing_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	add_child(_editing_lbl)

	var name_row := HBoxContainer.new()
	name_row.add_child(_small_label("Name"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = Macros.MAX_NAME_LENGTH
	_name_edit.placeholder_text = "Root call"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	add_child(name_row)

	var icon_row := HBoxContainer.new()
	icon_row.add_child(_small_label("Icon"))
	_icon_pick = OptionButton.new()
	_icon_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon_pick.fit_to_longest_item = false
	_icon_pick.add_theme_constant_override("icon_max_width", 20)
	_icon_pick.get_popup().add_theme_constant_override("icon_max_width", 20)
	icon_row.add_child(_icon_pick)
	add_child(icon_row)

	for i in Macros.MAX_LINES:
		var le := LineEdit.new()
		le.max_length = Macros.MAX_LINE_LENGTH
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.placeholder_text = ["/party Rooting %t — don't break it!", "/cast Entangling Roots", "", "", ""][i]
		_line_edits.append(le)
		add_child(le)

	var buttons := HBoxContainer.new()
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_save)
	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(_clear)
	var run_btn := Button.new()
	run_btn.text = "Try it"
	run_btn.pressed.connect(func(): if not _selected.is_empty(): _player.run_macro(_selected))
	buttons.add_child(save_btn)
	buttons.add_child(clear_btn)
	buttons.add_child(run_btn)
	add_child(buttons)

	var help := Label.new()
	help.text = "%t your target · %T target, level and health · %s you\n" \
			+ "/cast <spell> · /target <name> · /pause <seconds> · /g /say /tell ... any chat command.\n" \
			+ "A /cast that fails stops the macro."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 10)
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	add_child(help)

	_fill_icon_choices()
	_page_char.button_pressed = true
	_show_page(false)


func _page_button(text: String, group: ButtonGroup, shared: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _show_page(shared))
	return b


func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(40, 0)
	l.add_theme_font_size_override("font_size", 11)
	return l


# Automatic, then every spell this character knows (a shared macro may name one another class knows; it keeps its icon).
func _fill_icon_choices() -> void:
	_icon_pick.clear()
	_icon_keys.clear()
	_icon_pick.add_item("Automatic (first /cast spell)")
	_icon_keys.append("")
	var spells: Dictionary = _player.get("_spell_by_name") if "_spell_by_name" in _player else {}
	var known: Array = (_player.get("known_spells") if "known_spells" in _player else []).duplicate()
	known.sort_custom(func(a, b): return Player3D.spell_display_name(str(a)) < Player3D.spell_display_name(str(b)))
	for key in known:
		var tex := SpellInfo.icon_texture(spells.get(key, {}))
		if tex == null:
			continue
		_icon_pick.add_icon_item(tex, Player3D.spell_display_name(str(key)))
		_icon_keys.append(str(key))


func _show_page(shared: bool) -> void:
	_shared = shared
	_refresh_grid()
	_select(("s" if shared else "c") + "0")


func _refresh_grid() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var list := Macros.shared_list() if _shared else Macros.character_list()
	for i in list.size():
		var b := MacroButton.new()
		b.panel = self
		b.ref = ("s" if _shared else "c") + str(i)
		b.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 9)
		_dress_button(b, list[i])
		b.pressed.connect(_select.bind(b.ref))
		_grid.add_child(b)


func _dress_button(b: Button, macro: Dictionary) -> void:
	b.icon = null
	b.text = ""
	b.tooltip_text = ""
	if Macros.is_empty_macro(macro):
		b.modulate = Color(1, 1, 1, 0.45)
		return
	b.modulate = Color.WHITE
	var key := Macros.icon_spell(macro, _player)
	var spells: Dictionary = _player.get("_spell_by_name") if "_spell_by_name" in _player else {}
	var tex := SpellInfo.icon_texture(spells.get(key, {})) if not key.is_empty() else null
	if tex != null:
		b.icon = tex
		b.expand_icon = true
	else:
		b.text = Macros.label(macro)
	b.tooltip_text = tooltip(macro)


static func tooltip(macro: Dictionary) -> String:
	var lines: Array = [Macros.label(macro)]
	for line in macro.get("lines", []):
		if not str(line).strip_edges().is_empty():
			lines.append("  " + str(line))
	return "\n".join(lines)


func _select(ref: String) -> void:
	_selected = ref
	var macro := Macros.get_macro(ref)
	var idx := int(ref.substr(1)) + 1
	_editing_lbl.text = ("Shared macro %d (every character on your account)" if _shared else "Macro %d") % idx
	_name_edit.text = str(macro.get("name", ""))
	var lines: Array = macro.get("lines", [])
	for i in _line_edits.size():
		_line_edits[i].text = str(lines[i]) if i < lines.size() else ""
	var icon_key := str(macro.get("icon", ""))
	var pick := _icon_keys.find(icon_key)
	if pick < 0 and not icon_key.is_empty():
		# A shared macro's icon from another class's spell: offer it so saving doesn't drop it.
		var spells: Dictionary = _player.get("_spell_by_name") if "_spell_by_name" in _player else {}
		var tex := SpellInfo.icon_texture(spells.get(icon_key, {}))
		if tex != null:
			_icon_pick.add_icon_item(tex, Player3D.spell_display_name(icon_key))
			_icon_keys.append(icon_key)
			pick = _icon_keys.size() - 1
	_icon_pick.select(maxi(pick, 0))
	for b in _grid.get_children():
		if b is Button:
			b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if b.ref == ref else Color(0.9, 0.9, 0.9))
			b.flat = false
			b.self_modulate = Color(1.3, 1.2, 0.8) if b.ref == ref else Color.WHITE


func _save() -> void:
	if _selected.is_empty():
		return
	var lines: Array = []
	for le in _line_edits:
		lines.append(le.text.strip_edges())
	var macro := {"name": _name_edit.text.strip_edges(), "icon": _icon_keys[_icon_pick.selected] if _icon_pick.selected >= 0 else "",
			"lines": lines}
	if str(macro["name"]).is_empty() and not Macros.is_empty_macro(macro):
		macro["name"] = "Macro %d" % (int(_selected.substr(1)) + 1)
		_name_edit.text = macro["name"]
	Macros.set_macro(_selected, macro)
	GameLog.log_general("[color=#88ccff]Macro saved: %s.[/color]" % Macros.label(macro))
	_after_change()


func _clear() -> void:
	if _selected.is_empty():
		return
	Macros.set_macro(_selected, Macros.empty_macro())
	_select(_selected)
	_after_change()


func _after_change() -> void:
	var keep := _selected
	_refresh_grid()
	_select(keep)
	for bar in get_tree().get_nodes_in_group("action_bar"):
		bar.refresh_macros()
