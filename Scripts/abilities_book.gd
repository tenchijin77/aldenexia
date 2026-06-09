# abilities_book.gd — Two-tab ability window: Class Skills (spells) and General Skills
extends CanvasLayer
class_name AbilitiesBook

var _player: Node = null

const WIN_W := 360
const WIN_H := 440


func _ready() -> void:
	layer = 10
	_build_ui()


func set_player(p: Node) -> void:
	_player = p
	_populate()


func _build_ui() -> void:
	var panel := Panel.new()
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -WIN_W / 2.0
	panel.offset_top    = -WIN_H / 2.0
	panel.offset_right  =  WIN_W / 2.0
	panel.offset_bottom =  WIN_H / 2.0
	panel.name = "BookPanel"
	add_child(panel)

	# Title bar
	var title_bar := Panel.new()
	title_bar.anchor_right  = 1.0
	title_bar.offset_bottom = 28.0
	title_bar.name = "TitleBar"
	var tb_style := StyleBoxFlat.new()
	tb_style.bg_color = Color(0.10, 0.08, 0.16)
	title_bar.add_theme_stylebox_override("panel", tb_style)
	panel.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "Abilities"
	title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_lbl.offset_left = 8
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.anchor_left   = 1.0
	close_btn.anchor_right  = 1.0
	close_btn.offset_left   = -26.0
	close_btn.offset_right  = -2.0
	close_btn.offset_top    = 2.0
	close_btn.offset_bottom = 26.0
	close_btn.pressed.connect(queue_free)
	title_bar.add_child(close_btn)

	# Tab container
	var tabs := TabContainer.new()
	tabs.anchor_right  = 1.0
	tabs.anchor_bottom = 1.0
	tabs.offset_top    = 30.0
	tabs.offset_left   = 4.0
	tabs.offset_right  = -4.0
	tabs.offset_bottom = -4.0
	tabs.focus_mode    = Control.FOCUS_NONE
	tabs.name = "Tabs"
	panel.add_child(tabs)

	# Class Skills tab (spells — draggable to action bar)
	var class_scroll := ScrollContainer.new()
	class_scroll.name = "Class Skills"
	class_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(class_scroll)

	var class_vbox := VBoxContainer.new()
	class_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	class_vbox.name = "ClassVBox"
	class_scroll.add_child(class_vbox)

	# General Skills tab (passive combat skills with levels)
	var gen_scroll := ScrollContainer.new()
	gen_scroll.name = "General Skills"
	gen_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(gen_scroll)

	var gen_vbox := VBoxContainer.new()
	gen_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_vbox.name = "GenVBox"
	gen_scroll.add_child(gen_vbox)

	title_bar.gui_input.connect(_on_title_gui_input.bind(panel))


var _drag_offset    := Vector2.ZERO
var _dragging_window := false

func _on_title_gui_input(event: InputEvent, panel: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_window = event.pressed
		_drag_offset = panel.get_global_rect().position - get_viewport().get_mouse_position()
	elif event is InputEventMouseMotion and _dragging_window:
		panel.set_global_position(get_viewport().get_mouse_position() + _drag_offset)


func _populate() -> void:
	if not _player:
		return
	_fill_class_skills()
	_fill_general_skills()


# ── Class Skills (spells) ─────────────────────────────────────────────────────

func _fill_class_skills() -> void:
	var vbox := get_node_or_null("BookPanel/Tabs/Class Skills/ClassVBox")
	if not vbox:
		return
	for c in vbox.get_children():
		c.queue_free()

	var spells: Array     = _player.get("known_spells")    if "known_spells"    in _player else []
	var spell_db: Dictionary = _player.get("_spell_by_name") if "_spell_by_name" in _player else {}

	if spells.is_empty():
		vbox.add_child(_empty_label("No class abilities known.\nUse a scroll to learn spells."))
		return

	for spell_name in spells:
		var info: Dictionary = spell_db.get(spell_name, {})
		vbox.add_child(_make_spell_row(spell_name, info))


func _make_spell_row(spell_name: String, info: Dictionary) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, 58)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.10, 0.10, 0.18, 0.88)
	bg.border_color = Color(0.35, 0.30, 0.50)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	row.add_theme_stylebox_override("panel", bg)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = spell_name.replace("_", " ").capitalize()
	name_lbl.position = Vector2(8, 4)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	# School badge (top-right)
	var school: String = info.get("spell_school", "")
	if not school.is_empty():
		var school_lbl := Label.new()
		school_lbl.text = school.capitalize()
		school_lbl.anchor_right  = 1.0
		school_lbl.offset_right  = -8.0
		school_lbl.offset_top    = 4.0
		school_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		school_lbl.add_theme_font_size_override("font_size", 10)
		school_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 0.55))
		school_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(school_lbl)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = info.get("description", "")
	desc_lbl.position = Vector2(8, 22)
	desc_lbl.size = Vector2(WIN_W - 32, 20)
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	desc_lbl.clip_text = true
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(desc_lbl)

	# Mana cost + recast (bottom row)
	var cost: float = info.get("mana_cost", 0.0)
	var recast: float = info.get("recast_time", 0.0)
	var meta_lbl := Label.new()
	meta_lbl.text = "%d mp  ·  %.0fs recast" % [int(cost), recast] if cost > 0 else ""
	meta_lbl.position = Vector2(8, 40)
	meta_lbl.add_theme_font_size_override("font_size", 10)
	meta_lbl.add_theme_color_override("font_color", Color(0.45, 0.65, 1.0))
	meta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(meta_lbl)

	# Drag hint label (right-bottom)
	var hint := Label.new()
	hint.text = "drag to bar"
	hint.anchor_right  = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_right  = -6.0
	hint.offset_bottom = -4.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hint)

	# Drag to action bar via set_drag_forwarding (correct Godot 4 drag API)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_drag_forwarding(
		func(_at_pos: Vector2) -> Variant:
			var prev := Label.new()
			prev.text = spell_name.replace("_", " ").capitalize()
			prev.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
			prev.add_theme_font_size_override("font_size", 12)
			row.set_drag_preview(prev)
			return {"type": "spell", "name": spell_name},
		Callable(),
		Callable()
	)

	# Hover highlight via gui_input
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			bg.bg_color = Color(0.18, 0.18, 0.30, 0.95) if event.pressed else Color(0.10, 0.10, 0.18, 0.88)
	)

	return row


# ── General Skills ────────────────────────────────────────────────────────────

func _fill_general_skills() -> void:
	var vbox := get_node_or_null("BookPanel/Tabs/General Skills/GenVBox")
	if not vbox:
		return
	for c in vbox.get_children():
		c.queue_free()

	var skills: Array        = _player.get("known_skills")  if "known_skills"  in _player else []
	var skill_db: Dictionary = _player.get("_skill_data")   if "_skill_data"   in _player else {}
	var levels: Dictionary   = _player.get("skill_levels")  if "skill_levels"  in _player else {}

	if skills.is_empty():
		vbox.add_child(_empty_label("No general skills known."))
		return

	for skill_name in skills:
		var desc: String  = skill_db.get(skill_name, "")
		var level: int    = levels.get(skill_name, 0)
		vbox.add_child(_make_skill_row(skill_name, desc, level))


func _make_skill_row(skill_name: String, desc: String, level: int) -> Control:
	const SKILL_MAX := 252

	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, 62)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.10, 0.12, 0.10, 0.88)
	bg.border_color = Color(0.30, 0.40, 0.30)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	row.add_theme_stylebox_override("panel", bg)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = skill_name.replace("_", " ").capitalize()
	name_lbl.position = Vector2(8, 4)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.7, 1.0, 0.65))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	# Level display (top-right)
	var level_lbl := Label.new()
	level_lbl.text = "%d / %d" % [level, SKILL_MAX]
	level_lbl.anchor_right  = 1.0
	level_lbl.offset_right  = -8.0
	level_lbl.offset_top    = 4.0
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_lbl.add_theme_font_size_override("font_size", 11)
	level_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	level_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(level_lbl)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.position = Vector2(8, 22)
	desc_lbl.size = Vector2(WIN_W - 32, 20)
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	desc_lbl.clip_text = true
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(desc_lbl)

	# Progress bar
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = SKILL_MAX
	bar.value     = level
	bar.show_percentage = false
	bar.position = Vector2(8, 44)
	bar.size     = Vector2(WIN_W - 32, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.30, 0.65, 0.30)
	bar.add_theme_stylebox_override("fill", fill)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.18, 0.12)
	bar.add_theme_stylebox_override("background", bar_bg)
	row.add_child(bar)

	return row


# ── Helpers ───────────────────────────────────────────────────────────────────

func _empty_label(msg: String) -> Label:
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl
