# abilities_book.gd — Draggable window showing known spells and skills
extends CanvasLayer
class_name AbilitiesBook

var _player: Node = null

const WIN_W := 340
const WIN_H := 420


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
	tb_style.bg_color = Color(0.12, 0.1, 0.18)
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

	# Tab container below title bar
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

	# Spells tab
	var spells_scroll := ScrollContainer.new()
	spells_scroll.name = "Spells"
	spells_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(spells_scroll)

	var spells_vbox := VBoxContainer.new()
	spells_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spells_vbox.name = "SpellsVBox"
	spells_scroll.add_child(spells_vbox)

	# Skills tab
	var skills_scroll := ScrollContainer.new()
	skills_scroll.name = "Skills"
	skills_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(skills_scroll)

	var skills_vbox := VBoxContainer.new()
	skills_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_vbox.name = "SkillsVBox"
	skills_scroll.add_child(skills_vbox)

	# Make window draggable via title bar
	title_bar.gui_input.connect(_on_title_gui_input.bind(panel))


var _drag_offset := Vector2.ZERO
var _dragging_window := false

func _on_title_gui_input(event: InputEvent, panel: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_window = event.pressed
		_drag_offset = panel.get_global_rect().position - get_viewport().get_mouse_position()
	elif event is InputEventMouseMotion and _dragging_window:
		var new_pos := get_viewport().get_mouse_position() + _drag_offset
		panel.set_global_position(new_pos)


func _populate() -> void:
	if not _player:
		return

	_fill_spells()
	_fill_skills()


func _fill_spells() -> void:
	var vbox := get_node_or_null("BookPanel/Tabs/Spells/SpellsVBox")
	if not vbox:
		return
	for c in vbox.get_children():
		c.queue_free()

	var spells: Array = _player.get("known_spells") if "known_spells" in _player else []
	var spell_data: Dictionary = _player.get("_spell_by_name") if "_spell_by_name" in _player else {}

	if spells.is_empty():
		var lbl := Label.new()
		lbl.text = "No spells known."
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		vbox.add_child(lbl)
		return

	for spell_name in spells:
		var info: Dictionary = spell_data.get(spell_name, {})
		vbox.add_child(_make_entry("spell", spell_name, info.get("description", ""), info.get("mana_cost", 0)))


func _fill_skills() -> void:
	var vbox := get_node_or_null("BookPanel/Tabs/Skills/SkillsVBox")
	if not vbox:
		return
	for c in vbox.get_children():
		c.queue_free()

	var skills: Array = _player.get("known_skills") if "known_skills" in _player else []
	var skill_descs: Dictionary = _player.get("_skill_data") if "_skill_data" in _player else {}

	if skills.is_empty():
		var lbl := Label.new()
		lbl.text = "No skills known."
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		vbox.add_child(lbl)
		return

	for skill_name in skills:
		var desc: String = skill_descs.get(skill_name, "")
		vbox.add_child(_make_entry("skill", skill_name, desc, 0))


func _make_entry(type: String, ability_name: String, desc: String, mana_cost: float) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, 52)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	bg.border_color = Color(0.3, 0.3, 0.4)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	row.add_theme_stylebox_override("panel", bg)

	var name_lbl := Label.new()
	name_lbl.text = ability_name.replace("_", " ").capitalize()
	name_lbl.position = Vector2(8, 4)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.position = Vector2(8, 24)
	desc_lbl.size = Vector2(WIN_W - 40, 22)
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_lbl.clip_text = true
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(desc_lbl)

	if mana_cost > 0:
		var cost_lbl := Label.new()
		cost_lbl.text = "%d mp" % int(mana_cost)
		cost_lbl.anchor_right = 1.0
		cost_lbl.offset_right = -8.0
		cost_lbl.offset_top = 4.0
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost_lbl.add_theme_font_size_override("font_size", 10)
		cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
		cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cost_lbl)

	# Drag data
	var drag_type := type
	var drag_name := ability_name
	row.set_meta("drag_type", drag_type)
	row.set_meta("drag_name", drag_name)
	row.gui_input.connect(_on_entry_gui_input.bind(row, drag_type, drag_name, bg))

	return row


func _on_entry_gui_input(event: InputEvent, row: Control, drag_type: String, drag_name: String, bg: StyleBoxFlat) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			bg.bg_color = Color(0.2, 0.2, 0.3, 0.9)
			# Start drag
			var drag_data := {"type": drag_type, "name": drag_name}
			var preview := Label.new()
			preview.text = drag_name.replace("_", " ").capitalize()
			preview.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
			preview.add_theme_font_size_override("font_size", 12)
			row.set_drag_preview(preview)
			row.force_drag(drag_data, preview)
		else:
			bg.bg_color = Color(0.1, 0.1, 0.15, 0.85)
