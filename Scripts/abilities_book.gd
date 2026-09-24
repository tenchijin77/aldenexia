# abilities_book.gd — Two-tab ability window: Class Skills (spells) and General Skills
extends CanvasLayer
class_name AbilitiesBook

var _player: Node = null

const WIN_W := 360
const WIN_H := 440
const ICON_SIZE := 40
const POSITION_KEY := "abilities_book"
const RESIZE_MARGIN := 16.0
const MIN_WIDTH := 300.0
const MIN_HEIGHT := 260.0
var _resizing := false
var _panel: Control = null


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
	_panel = panel
	panel.gui_input.connect(_on_panel_gui_input)
	WindowPosition.load_full_into(POSITION_KEY, panel)

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
		if event.pressed:
			_drag_offset = panel.get_global_rect().position - get_viewport().get_mouse_position()
		else:
			WindowPosition.save(POSITION_KEY, panel)
	elif event is InputEventMouseMotion and _dragging_window:
		panel.set_global_position(get_viewport().get_mouse_position() + _drag_offset)


# Bottom-right corner resize, same pattern as backpack_ui.gd — separate from
# the title-bar drag above since the hot-zone lives on the panel's own edge,
# not the title bar.
func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos: Vector2 = event.position
			if pos.x > _panel.size.x - RESIZE_MARGIN and pos.y > _panel.size.y - RESIZE_MARGIN:
				_resizing = true
		else:
			if _resizing:
				WindowPosition.save(POSITION_KEY, _panel)
			_resizing = false
	elif event is InputEventMouseMotion and _resizing:
		_panel.offset_right  = max(_panel.offset_left + MIN_WIDTH, _panel.offset_right + event.relative.x)
		_panel.offset_bottom = max(_panel.offset_top + MIN_HEIGHT, _panel.offset_bottom + event.relative.y)


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

	# Lowest level first, so what you can cast now is at the top; same level: alphabetical.
	var player_class: String = str(_player.get("player_class")) if "player_class" in _player else ""
	var ordered: Array = []
	for spell_name in spells:
		var info: Dictionary = spell_db.get(spell_name, {})
		ordered.append({"name": spell_name, "info": info, "level": SpellInfo.required_level(info, player_class)})
	ordered.sort_custom(func(a, b): return a["level"] < b["level"] or (a["level"] == b["level"] and str(a["name"]) < str(b["name"])))
	for entry in ordered:
		vbox.add_child(_make_spell_row(entry["name"], entry["info"], int(entry["level"])))


func _make_spell_row(spell_name: String, info: Dictionary, required_level: int = 1) -> Control:
	# PanelContainer + an inner VBoxContainer instead of the old
	# fixed-position/fixed-size layout — that hardcoded every label's size
	# (including the description's, clip_text = true) to a fixed row height
	# regardless of how long the text actually was or how wide the window
	# got, which is exactly why long descriptions clipped mid-sentence no
	# matter how the window was resized. This way the description autowraps
	# to the row's real (window-following) width and the row's height grows
	# to fit it, so making the window taller/wider actually helps.
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.10, 0.10, 0.18, 0.88)
	bg.border_color = Color(0.35, 0.30, 0.50)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	bg.content_margin_left   = 8
	bg.content_margin_right  = 8
	bg.content_margin_top    = 4
	bg.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", bg)

	# Icon on the left (spells with no "icon" in player_spells.json just skip
	# it and the text fills the row like before), text column on the right.
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	row.add_child(outer)

	var icon_tex := SpellInfo.icon_texture(info)
	if icon_tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_child(icon_rect)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(vbox)

	# Hover tooltip: name + the description from player_spells.json + cost, and the level it needs.
	var my_level: int = int(_player.combat_node.level) if _player and "combat_node" in _player and _player.combat_node else 1
	var can_cast: bool = my_level >= required_level
	row.tooltip_text = SpellInfo.tooltip(spell_name, info) + ("\n\nRequires level %d." % required_level if can_cast else "\n\nRequires level %d (you are level %d)." % [required_level, my_level])

	var header := HBoxContainer.new()
	vbox.add_child(header)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = Player3D.spell_display_name(spell_name)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5) if can_cast else Color(0.62, 0.55, 0.42))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_lbl)

	# Level badge: green when you can cast it now, red while your level is too low.
	var level_lbl := Label.new()
	level_lbl.text = "Level %d" % required_level
	level_lbl.add_theme_font_size_override("font_size", 10)
	level_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55) if can_cast else Color(0.9, 0.4, 0.4))
	level_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(level_lbl)

	# School badge (top-right)
	var school: String = info.get("spell_school", "")
	if not school.is_empty():
		var school_lbl := Label.new()
		school_lbl.text = school.capitalize()
		school_lbl.add_theme_font_size_override("font_size", 10)
		school_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 0.55))
		school_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(school_lbl)

	# Description — autowraps and takes whatever height it needs, instead of
	# a fixed 20px with clip_text.
	var desc_lbl := Label.new()
	desc_lbl.text = info.get("description", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)

	var meta_row := HBoxContainer.new()
	vbox.add_child(meta_row)

	# Mana cost + recast
	var cost: float = info.get("mana_cost", 0.0)
	var recast: float = info.get("recast_time", 0.0)
	var meta_lbl := Label.new()
	meta_lbl.text = "%d mp  ·  %.0fs recast" % [int(cost), recast] if cost > 0 else ""
	meta_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_lbl.add_theme_font_size_override("font_size", 10)
	meta_lbl.add_theme_color_override("font_color", Color(0.45, 0.65, 1.0))
	meta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_row.add_child(meta_lbl)

	# Drag hint label (right-aligned via the meta_row's own HBox layout)
	var hint := Label.new()
	hint.text = "drag to bar"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_row.add_child(hint)

	# Drag to action bar via set_drag_forwarding (correct Godot 4 drag API)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_drag_forwarding(
		func(_at_pos: Vector2) -> Variant:
			if icon_tex != null:
				var prev_icon := TextureRect.new()
				prev_icon.texture = icon_tex
				prev_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
				prev_icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
				prev_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				row.set_drag_preview(prev_icon)
			else:
				var prev := Label.new()
				prev.text = Player3D.spell_display_name(spell_name)
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

# The set of skill_categories any real spell in the game uses (dodge, parry, bash, mantis_fist, evocation, ...) — every one of
# these skills boosts its OWN abilities' damage/potency via Data/skill_effects.json's "@category" entries (spell_potency_pct,
# ability_damage_pct), on top of whatever it does directly. Built once from the player's own loaded spell database.
var _skill_categories: Dictionary = {}

func _build_skill_categories() -> void:
	_skill_categories.clear()
	var spells: Dictionary = _player.get("_spell_by_name") if "_spell_by_name" in _player else {}
	for spell_name in spells:
		var cat: String = str(spells[spell_name].get("skill_category", ""))
		if not cat.is_empty():
			_skill_categories[cat] = true


func _fill_general_skills() -> void:
	var vbox := get_node_or_null("BookPanel/Tabs/General Skills/GenVBox")
	if not vbox:
		return
	for c in vbox.get_children():
		c.queue_free()

	var skills: Array        = _player.get("known_skills")  if "known_skills"  in _player else []
	var skill_db: Dictionary = _player.get("_skill_data")   if "_skill_data"   in _player else {}
	var levels: Dictionary   = _player.get("skill_levels")  if "skill_levels"  in _player else {}
	var skill_max: int       = _player.get("_skill_max")    if "_skill_max"    in _player else 275
	_build_skill_categories()

	if skills.is_empty():
		vbox.add_child(_empty_label("No general skills known."))
		return

	for skill_name in skills:
		var desc: String  = skill_db.get(skill_name, "")
		var level: int    = levels.get(skill_name, 0)
		var cap: int = int(_player.call("skill_cap_for", level)) if _player.has_method("skill_cap_for") else skill_max
		vbox.add_child(_make_skill_row(skill_name, desc, level, cap))


# What this skill is actually doing right now, at its current level, in the player's own numbers — reads the exact same
# Data/skill_effects.json tables combatnode.gd's skill_bonus() uses, so this can never drift out of sync with the real math.
# Direct effects (skill_name appears as a literal key in some stat's table) are always shown; two conditional ones are added
# on top: "@weapon" (melee_damage_pct) only when this skill is the currently equipped weapon's own skill, and "@category"
# (spell_potency_pct / ability_damage_pct) only when some real spell actually uses this skill as its skill_category — i.e.
# only shown for skills that are genuinely live, never for one that would silently do nothing (see leopard_strike, fixed
# 2026-09-21: it used to be exactly such a dead skill until stunning_fist's skill_category was corrected to point at it).
const _STAT_LABELS := {
	"dodge_chance": "dodge chance", "parry_chance": "parry chance", "block_chance": "block chance",
	"riposte_chance": "riposte chance", "crit_chance": "crit chance", "attack_rating": "attack rating",
	"melee_damage_pct": "melee damage", "spell_potency_pct": "spell potency", "concentration": "concentration",
	"stamina_regen": "stamina regen", "stamina_drain_pct": "stamina drain reduction",
	"bandage_heal_pct": "bandage healing", "double_attack_chance": "double attack chance",
	"triple_attack_chance": "triple attack chance",
}
const _PCT_STATS := {
	"dodge_chance": true, "parry_chance": true, "block_chance": true, "riposte_chance": true, "crit_chance": true,
	"melee_damage_pct": true, "spell_potency_pct": true, "stamina_regen": true, "stamina_drain_pct": true,
	"bandage_heal_pct": true, "double_attack_chance": true, "triple_attack_chance": true,
}

func _skill_effect_summary(skill_name: String, points: int) -> String:
	if points <= 0:
		return ""
	var lines: Array[String] = []
	if skill_name == "perception":
		lines.append("+%d to appraisal checks (I)" % (points / 10))
	for stat in _STAT_LABELS:
		var table: Dictionary = SkillEffects.table(stat)
		if table.has(skill_name):
			var amount: float = points * float(table[skill_name])
			lines.append("+%s %s" % [_fmt_amount(amount, _PCT_STATS.has(stat)), _STAT_LABELS[stat]])

	var weapon_key: String = _player.call("_weapon_skill_key", Inventory.get_equipped_weapon()) if _player.has_method("_weapon_skill_key") else ""
	if skill_name == weapon_key:
		var per_weapon: float = SkillEffects.table("melee_damage_pct").get("@weapon", 0.0)
		if per_weapon > 0.0:
			lines.append("+%s melee damage with your equipped weapon" % _fmt_amount(points * per_weapon, true))

	if _skill_categories.has(skill_name):
		var per_cat_dmg: float = SkillEffects.table("ability_damage_pct").get("@category", 0.0)
		var per_cat_pot: float = SkillEffects.table("spell_potency_pct").get("@category", 0.0)
		var per_cat: float = maxf(per_cat_dmg, per_cat_pot)
		if per_cat > 0.0:
			lines.append("+%s to its own abilities' damage/effect" % _fmt_amount(points * per_cat, true))

	return "  ·  ".join(lines)


func _fmt_amount(amount: float, is_pct: bool) -> String:
	var text := ("%.1f" % amount).rstrip("0").rstrip(".")
	return text + "%" if is_pct else text


func _make_skill_row(skill_name: String, desc: String, level: int, skill_max: int) -> Control:
	# Same fixed-position/fixed-size-to-container fix as _make_spell_row()
	# above — this was the exact row type shown clipped in the bug report
	# ("General skill improving melee weapon damage, accuracy, and critical
	# ch..."), since desc_lbl.size was hardcoded to (WIN_W - 32, 20) with
	# clip_text = true regardless of the actual window size.
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.10, 0.12, 0.10, 0.88)
	bg.border_color = Color(0.30, 0.40, 0.30)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	bg.content_margin_left   = 8
	bg.content_margin_right  = 8
	bg.content_margin_top    = 4
	bg.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	row.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = skill_name.replace("_", " ").capitalize()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.7, 1.0, 0.65))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_lbl)

	# Level display (top-right)
	var level_lbl := Label.new()
	level_lbl.text = "%d / %d" % [level, skill_max]
	level_lbl.add_theme_font_size_override("font_size", 11)
	level_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	level_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(level_lbl)

	# Description — autowraps and takes whatever height it needs.
	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)

	# What it's actually doing for you right now, at this level — blank (and no row added) for a skill with genuinely no
	# effect yet (0 points), or one this build has no numeric hook for at all (a real, if rarer, case: several skills — e.g.
	# tracking, lockpicking, safe_fall — exist as concepts but have no mechanic built yet; the skill still trains
	# normally in case one is added later, it just has nothing to report here today).
	var effect_text := _skill_effect_summary(skill_name, level)
	if not effect_text.is_empty():
		var effect_lbl := Label.new()
		effect_lbl.text = effect_text
		effect_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_lbl.add_theme_font_size_override("font_size", 10)
		effect_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
		effect_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(effect_lbl)

	# Progress bar
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = skill_max
	bar.value     = level
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.30, 0.65, 0.30)
	bar.add_theme_stylebox_override("fill", fill)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.18, 0.12)
	bar.add_theme_stylebox_override("background", bar_bg)
	vbox.add_child(bar)

	return row


# ── Helpers ───────────────────────────────────────────────────────────────────

func _empty_label(msg: String) -> Label:
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl
