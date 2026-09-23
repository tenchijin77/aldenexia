#character_sheet.gd - player's stats/equipment/inventory display
# Rebuilt 2026-09-14 into three tabs (Stats / Equipment / Inventory) behind a
# persistent identity+vitals strip, replacing the old single scrolling column
# of ~25 raw Labels. All tab content is still built in code (same pattern the
# old equipment paperdoll already used via _init_equipment_slots()) — the
# .tscn only lays out the structural containers (identity_strip, tab_rail,
# the three per-tab ScrollContainers).
extends CanvasLayer

const DRAG_BAR_HEIGHT := 24.0
const POSITION_KEY := "character_sheet"
const RESIZE_MARGIN := 16.0

@onready var main_panel: Panel = $main_panel
@onready var identity_strip: VBoxContainer = $main_panel/identity_strip
@onready var body: HBoxContainer = $main_panel/body
@onready var tab_rail: VBoxContainer = $main_panel/body/tab_rail
@onready var stats_scroll: ScrollContainer = $main_panel/body/panel_area/stats_scroll
@onready var stats_panel: VBoxContainer = $main_panel/body/panel_area/stats_scroll/stats_panel
@onready var equipment_scroll: ScrollContainer = $main_panel/body/panel_area/equipment_scroll
@onready var equipment_panel: VBoxContainer = $main_panel/body/panel_area/equipment_scroll/equipment_panel
@onready var inventory_scroll: ScrollContainer = $main_panel/body/panel_area/inventory_scroll
@onready var inventory_panel: VBoxContainer = $main_panel/body/panel_area/inventory_scroll/inventory_panel

var _player: Node = null
var _dragging := false
var _resizing := false

# key -> Label, filled by the _make_*() builders below, read back by
# set_character_data()/_process() instead of dozens of individual @onready paths.
var _stat_labels: Dictionary = {}
var _vitals: Dictionary = {}  # key -> {"bar": ProgressBar, "label": Label}
var xp_bar: ProgressBar

var equipment_slots: Dictionary = {}
var storage_slots: Array = []
var _bag_sections: VBoxContainer

var _tab_buttons: Dictionary = {}
var _tab_panels: Dictionary = {}
var _active_tab: String = "stats"


func _ready() -> void:
	main_panel.add_theme_stylebox_override("panel", Global.window_bg_style())
	main_panel.gui_input.connect(_on_panel_gui_input)
	WindowPosition.load_full_into(POSITION_KEY, main_panel)

	_build_title_bar()
	_build_identity_strip()

	# identity_strip's real height isn't known until after a layout pass, so
	# body's top offset is finalized in _position_body_below_identity() below
	# (called deferred) rather than guessed here.
	identity_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	identity_strip.offset_top = DRAG_BAR_HEIGHT
	identity_strip.offset_left = 8
	identity_strip.offset_right = -8
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	call_deferred("_position_body_below_identity")

	_build_tab_rail()
	_build_stats_panel()
	_build_equipment_panel()
	_build_inventory_panel()
	_select_tab("stats")

	if Inventory.inventory_changed.is_connected(_on_inventory_changed) == false:
		Inventory.inventory_changed.connect(_on_inventory_changed)
	if Inventory.equipment_changed.is_connected(_on_equipment_changed) == false:
		Inventory.equipment_changed.connect(_on_equipment_changed)
	if Global.currency_changed.is_connected(_on_currency_changed) == false:
		Global.currency_changed.connect(_on_currency_changed)

	refresh_storage_slots()
	refresh_equipment_slots()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# identity_strip's real height is only known after one layout pass (its rows
# are built in the same _ready() call, so their sizes aren't settled yet) —
# push body below it once that's actually true instead of guessing a pixel value.
func _position_body_below_identity() -> void:
	body.offset_top = DRAG_BAR_HEIGHT + identity_strip.size.y + 4


func _build_title_bar() -> void:
	var title_lbl := Label.new()
	title_lbl.text = "Character Sheet"
	title_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_lbl.offset_bottom = DRAG_BAR_HEIGHT
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_panel.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.anchor_left   = 1.0
	close_btn.anchor_right  = 1.0
	close_btn.offset_left   = -24.0
	close_btn.offset_right  = -2.0
	close_btn.offset_top    = 2.0
	close_btn.offset_bottom = DRAG_BAR_HEIGHT - 2.0
	close_btn.pressed.connect(func():
		queue_free()
		Global.restore_mouse_mode()
	)
	main_panel.add_child(close_btn)


# ===== IDENTITY STRIP (persistent across tabs) =====

const VITAL_COLORS := {
	"hp":    Color(0.75, 0.1, 0.1),
	"mp":    Color(0.1, 0.25, 0.85),
	"sta":   Color(0.85, 0.75, 0.1),
	"food":  Color(0.75, 0.45, 0.15),
	"water": Color(0.15, 0.65, 0.75),
	"xp":    Color(0.45, 0.25, 0.75),
}

func _build_identity_strip() -> void:
	var name_row := HBoxContainer.new()
	identity_strip.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.name = "name_label"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	name_row.add_child(name_lbl)
	_stat_labels["name"] = name_lbl

	var level_lbl := Label.new()
	level_lbl.add_theme_font_size_override("font_size", 11)
	level_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	name_row.add_child(level_lbl)
	_stat_labels["level"] = level_lbl

	var sub_lbl := Label.new()
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	identity_strip.add_child(sub_lbl)
	_stat_labels["subtitle"] = sub_lbl

	var vitals_box := VBoxContainer.new()
	vitals_box.add_theme_constant_override("separation", 2)
	identity_strip.add_child(vitals_box)

	_make_vital_row(vitals_box, "hp", "HP")
	_make_vital_row(vitals_box, "mp", "MP")
	_make_vital_row(vitals_box, "sta", "STA")
	_make_vital_row(vitals_box, "food", "Food")
	_make_vital_row(vitals_box, "water", "Water")
	_make_vital_row(vitals_box, "xp", "XP")   # the experience bar lives with the other bars, under Water, on every tab
	xp_bar = _vitals["xp"]["bar"]
	_stat_labels["xp"] = _vitals["xp"]["label"]


func _make_vital_row(parent: Control, key: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 14)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(36, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.bg_color = VITAL_COLORS[key]
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)

	var val := Label.new()
	val.custom_minimum_size = Vector2(70, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 10)
	row.add_child(val)

	_vitals[key] = {"bar": bar, "label": val}


# ===== TAB RAIL =====

func _build_tab_rail() -> void:
	var off_style := StyleBoxFlat.new()
	off_style.bg_color = Color(0.14, 0.14, 0.16)
	off_style.border_color = Color(0.35, 0.35, 0.4)
	off_style.set_border_width_all(1)
	off_style.set_corner_radius_all(4)
	off_style.content_margin_left = 8
	off_style.content_margin_top = 5
	off_style.content_margin_bottom = 5

	var on_style := StyleBoxFlat.new()
	on_style.bg_color = Color(0.22, 0.19, 0.1)
	on_style.border_color = Color(0.75, 0.65, 0.35)
	on_style.set_border_width_all(1)
	on_style.set_corner_radius_all(4)
	on_style.content_margin_left = 8
	on_style.content_margin_top = 5
	on_style.content_margin_bottom = 5

	for tab_name in ["stats", "equipment", "inventory"]:
		var btn := Button.new()
		btn.text = tab_name.capitalize()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_stylebox_override("normal", off_style)
		btn.add_theme_stylebox_override("hover", off_style)
		btn.add_theme_stylebox_override("pressed", on_style)
		btn.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
		btn.add_theme_color_override("font_hover_color", Color(0.9, 0.9, 0.92))
		btn.pressed.connect(_select_tab.bind(tab_name))
		tab_rail.add_child(btn)
		_tab_buttons[tab_name] = {"button": btn, "off": off_style, "on": on_style}


func _select_tab(tab_name: String) -> void:
	_active_tab = tab_name
	for key in _tab_buttons:
		var entry: Dictionary = _tab_buttons[key]
		var active: bool = key == tab_name
		entry["button"].add_theme_stylebox_override("normal", entry["on"] if active else entry["off"])
		entry["button"].add_theme_color_override("font_color", Color(0.95, 0.85, 0.55) if active else Color(0.75, 0.75, 0.78))
	for key in _tab_panels:
		_tab_panels[key].visible = key == tab_name


# ===== STATS TAB =====

func _build_stats_panel() -> void:
	_tab_panels["stats"] = stats_scroll

	var attr_grid := GridContainer.new()
	attr_grid.columns = 4
	attr_grid.add_theme_constant_override("h_separation", 6)
	attr_grid.add_theme_constant_override("v_separation", 6)
	stats_panel.add_child(_make_section("Attributes", attr_grid))
	for key_label in [["strength", "Strength"], ["constitution", "Constitution"], ["dexterity", "Dexterity"],
			["intelligence", "Intelligence"], ["wisdom", "Wisdom"], ["charisma", "Charisma"], ["luck", "Luck"]]:
		_make_stat_tile(attr_grid, key_label[0], key_label[1])

	var combat_list := VBoxContainer.new()
	combat_list.add_theme_constant_override("separation", 1)
	stats_panel.add_child(_make_section("Combat", combat_list))
	for key_label in [["armor_class", "Armor Class"], ["attack", "Attack"], ["crit_chance", "Crit Chance"],
			["spell_power", "Spell Power"], ["weight", "Carry Weight"]]:
		_make_kv_row(combat_list, key_label[0], key_label[1])

	# HFlowContainer instead of HBoxContainer — 10 badges (up from 5) won't
	# reliably fit on one line at every window width, so this wraps onto a
	# second row instead of clipping/overflowing.
	var resist_row := HFlowContainer.new()
	resist_row.add_theme_constant_override("h_separation", 6)
	resist_row.add_theme_constant_override("v_separation", 4)
	resist_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_panel.add_child(_make_section("Resistances", resist_row))
	# All 10 finalized damage types — see game_flow.txt's "Spell
	# Classification" section (2026-09-19) for why Psychic/Spirit stay
	# separate despite similar surface flavor.
	for key_label_color in [
			["fire", "Fire", Color(0.85, 0.44, 0.24)], ["cold", "Cold", Color(0.37, 0.72, 0.85)],
			["acid", "Acid", Color(0.56, 0.68, 0.29)], ["lightning", "Lightning", Color(0.92, 0.85, 0.35)],
			["poison", "Poison", Color(0.42, 0.62, 0.32)], ["disease", "Disease", Color(0.55, 0.50, 0.30)],
			["magic", "Magic", Color(0.54, 0.32, 0.85)], ["divine", "Divine", Color(0.90, 0.82, 0.55)],
			["psychic", "Psychic", Color(0.79, 0.37, 0.68)], ["spirit", "Spirit", Color(0.60, 0.60, 0.95)]]:
		_make_badge(resist_row, key_label_color[0], key_label_color[1], key_label_color[2])

	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 12)
	stats_panel.add_child(_make_section("Currency", coin_row))
	for key_label_color in [["platinum", "pp", Color(0.75, 0.8, 0.85)], ["gold", "gp", Color(0.85, 0.7, 0.25)],
			["silver", "sp", Color(0.68, 0.68, 0.72)], ["copper", "cp", Color(0.7, 0.45, 0.25)]]:
		_make_coin(coin_row, key_label_color[0], key_label_color[1], key_label_color[2])


func _make_section(title: String, content: Control) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.add_theme_color_override("font_color", Color(0.7, 0.6, 0.35))
	wrap.add_child(title_lbl)
	var sep := HSeparator.new()
	wrap.add_child(sep)
	wrap.add_child(content)
	return wrap


func _make_stat_tile(parent: GridContainer, key: String, label: String) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.13, 0.92)
	style.set_border_width_all(1)
	style.border_color = Color(0.32, 0.32, 0.32)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	var k := Label.new()
	k.text = label
	k.add_theme_font_size_override("font_size", 9)
	k.add_theme_color_override("font_color", Color(0.6, 0.6, 0.62))
	vbox.add_child(k)

	var v := Label.new()
	v.add_theme_font_size_override("font_size", 15)
	vbox.add_child(v)
	_stat_labels[key] = v


func _make_kv_row(parent: VBoxContainer, key: String, label: String) -> void:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.13, 0.92) if parent.get_child_count() % 2 == 0 else Color(0.16, 0.16, 0.16, 0.92)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", style)
	parent.add_child(row)

	var hbox := HBoxContainer.new()
	row.add_child(hbox)
	var k := Label.new()
	k.text = label
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.add_theme_font_size_override("font_size", 11)
	k.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	hbox.add_child(k)
	var v := Label.new()
	v.add_theme_font_size_override("font_size", 11)
	hbox.add_child(v)
	_stat_labels[key] = v


func _make_badge(parent: Container, key: String, label: String, dot_color: Color) -> void:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.13, 0.92)
	style.set_border_width_all(1)
	style.border_color = Color(0.32, 0.32, 0.32)
	style.set_corner_radius_all(100)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	box.add_theme_stylebox_override("panel", style)
	parent.add_child(box)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	box.add_child(hbox)

	var dot := ColorRect.new()
	dot.color = dot_color
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(dot)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	hbox.add_child(lbl)

	var v := Label.new()
	v.add_theme_font_size_override("font_size", 10)
	hbox.add_child(v)
	_stat_labels[key] = v


func _make_coin(parent: HBoxContainer, key: String, suffix: String, dot_color: Color) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	parent.add_child(hbox)

	var dot := ColorRect.new()
	dot.color = dot_color
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(dot)

	var v := Label.new()
	v.add_theme_font_size_override("font_size", 12)
	hbox.add_child(v)
	_stat_labels[key + "_coin"] = v

	var s := Label.new()
	s.text = suffix
	s.add_theme_font_size_override("font_size", 10)
	s.add_theme_color_override("font_color", Color(0.6, 0.6, 0.62))
	hbox.add_child(s)


# ===== EQUIPMENT TAB (paperdoll — same slot layout as before) =====

const _SLOT_LABELS: Dictionary = {
	"ear1": "Earring", "ear2": "Earring", "neck": "Neck", "face": "Face",
	"head": "Head", "finger1": "Ring", "finger2": "Ring",
	"wrist1": "Wrist", "wrist2": "Wrist", "arms": "Arms",
	"hands": "Hands", "shoulders": "Shoulder", "chest": "Chest",
	"back": "Back", "waist": "Belt", "legs": "Legs", "feet": "Feet",
	"trinket1": "Trinket", "trinket2": "Trinket",
	"primary": "Primary", "offhand": "Off Hand", "ranged": "Ranged",
	"ammo": "Ammo", "charm": "Charm", "focus": "Focus", "light": "Light",
}

var _pending_slot_cfg: Array = []
var _light_status_label: Label

func _build_equipment_panel() -> void:
	_tab_panels["equipment"] = equipment_scroll
	_pending_slot_cfg.clear()
	equipment_panel.add_theme_constant_override("separation", 14)

	# Same section style as the Stats tab; slot names live inside the empty
	# tiles (see slot_button.gd's placeholder) instead of tiny labels below.
	var paperdoll := VBoxContainer.new()
	paperdoll.add_theme_constant_override("separation", 5)
	paperdoll.add_child(_build_3col("ear1",      "head",    "ear2"))
	paperdoll.add_child(_build_3col("",          "neck",    ""))
	paperdoll.add_child(_build_3col("shoulders", "face",    "back"))
	paperdoll.add_child(_build_3col("wrist1",    "chest",   "wrist2"))
	paperdoll.add_child(_build_3col("",          "arms",    ""))
	paperdoll.add_child(_build_3col("charm",     "waist",   "focus"))
	paperdoll.add_child(_build_3col("finger1",   "hands",   "finger2"))
	paperdoll.add_child(_build_3col("",          "legs",    ""))
	paperdoll.add_child(_build_3col("",          "feet",    ""))
	equipment_panel.add_child(_make_section("ARMOR & JEWELRY", paperdoll))

	equipment_panel.add_child(_make_section("WEAPONS", _build_row(["primary", "offhand", "ranged", "ammo"])))
	equipment_panel.add_child(_make_section("ACCESSORIES", _build_row(["trinket1", "trinket2"])))
	equipment_panel.add_child(_make_section("LIGHT SOURCE", _build_light_row()))

	for cfg in _pending_slot_cfg:
		var btn = cfg[0]
		var sn: String = cfg[1]
		btn.slot_type = "equipment"
		btn.slot_name = sn
		btn.slot_index = -1
		btn.bag_slot = -1
		btn.item_index = -1
		btn.item_data = {}
		btn.placeholder = _SLOT_LABELS.get(sn, sn.capitalize())
		btn.tooltip_text = _SLOT_LABELS.get(sn, sn.capitalize())
		equipment_slots[sn] = btn


func _build_3col(left: String, center: String, right: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_make_slot_or_spacer(left))
	row.add_child(_make_slot_or_spacer(center))
	row.add_child(_make_slot_or_spacer(right))
	return row

func _make_slot_or_spacer(slot_name: String) -> Control:
	if slot_name == "":
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(48, 48)
		return spacer
	return _make_slot_vbox(slot_name)

func _build_row(slots: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for sn in slots:
		row.add_child(_make_slot_vbox(sn))
	return row

func _make_slot_vbox(slot_name: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var btn = load("res://Scripts/slot_button.gd").new()
	vbox.add_child(btn)
	_pending_slot_cfg.append([btn, slot_name])
	return vbox

# The Light slot: a tile plus a live status line ("Torch — lit, 8:42 left").
func _build_light_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_make_slot_vbox("light"))

	var info := VBoxContainer.new()
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 2)
	_light_status_label = Label.new()
	_light_status_label.text = "No light equipped"
	_light_status_label.add_theme_font_size_override("font_size", 12)
	_light_status_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	info.add_child(_light_status_label)
	var hint := Label.new()
	hint.text = "Use a torch from your bags to light it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(170, 0)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.58))
	info.add_child(hint)
	row.add_child(info)
	return row


# ===== INVENTORY TAB =====
# The 12 basic_inventory slots ARE the player's primary inventory (matches
# the approved mockup / the user's own framing: "that is the main players'
# inventory system until you find some real bags") — a bag equipped into one
# of those slots expands storage, shown as its own nested section right
# below rather than pointing off to a separate window.

func _build_inventory_panel() -> void:
	_tab_panels["inventory"] = inventory_scroll

	var root_grid := GridContainer.new()
	root_grid.columns = 6
	root_grid.add_theme_constant_override("h_separation", 6)
	root_grid.add_theme_constant_override("v_separation", 6)
	inventory_panel.add_child(_make_section("Inventory Slots", root_grid))

	storage_slots.clear()
	for i in range(Inventory.BASIC_INVENTORY_SIZE):
		var slot = load("res://Scripts/slot_button.gd").new()
		slot.custom_minimum_size = Vector2(44, 44)
		slot.ignore_texture_size = true
		slot.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		root_grid.add_child(slot)
		storage_slots.append(slot)

	_bag_sections = VBoxContainer.new()
	_bag_sections.add_theme_constant_override("separation", 10)
	inventory_panel.add_child(_bag_sections)


func refresh_storage_slots() -> void:
	for i in range(Inventory.BASIC_INVENTORY_SIZE):
		var slot = storage_slots[i]
		slot.slot_type = "basic"
		slot.slot_index = i
		slot.bag_slot = -1
		slot.item_index = -1

		var item = Inventory.basic_inventory[i]
		if item == null:
			slot.item_data = {}
			slot.texture_normal = null
			slot.tooltip_text = ""
		else:
			slot.item_data = item
			slot.texture_normal = ItemIcon.texture(item)
			var holds_text := Inventory.bag_holds_text(item)
			slot.tooltip_text = ItemIcon.tooltip(item) + (("\n(%d-slot bag%s)" % [Inventory.get_bag_size(item), (" for " + holds_text) if not holds_text.is_empty() else ""]) if Inventory.is_bag(item) else "")
		slot.queue_redraw()

	_rebuild_bag_sections()


# One nested section per equipped bag, each with its own capacity-sized slot
# grid (slot_type "bag", correct bag_slot on every slot — including empty
# ones — so dropping an item from Inventory Slots directly into a bag works).
func _rebuild_bag_sections() -> void:
	if not is_instance_valid(_bag_sections):
		return
	for child in _bag_sections.get_children():
		_bag_sections.remove_child(child)
		child.queue_free()

	for bag_slot in range(Inventory.BASIC_INVENTORY_SIZE):
		var bag: Dictionary = Inventory.get_basic_inventory_slot(bag_slot)
		if not Inventory.is_bag(bag):
			continue

		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 4)

		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.text = bag.get("name", "Bag")
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		header.add_child(name_lbl)

		var bag_items := Inventory.get_bag_contents(bag_slot)
		var capacity: int = Inventory.get_bag_size(bag)
		var cap_lbl := Label.new()
		var holds := Inventory.bag_holds_text(bag)
		cap_lbl.text = "%d / %d slots used%s" % [bag_items.size(), capacity, ("  •  holds %s only" % holds) if not holds.is_empty() else ""]
		cap_lbl.add_theme_font_size_override("font_size", 9)
		cap_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
		header.add_child(cap_lbl)
		section.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		section.add_child(grid)

		for item_index in range(capacity):
			var slot = load("res://Scripts/slot_button.gd").new()
			slot.custom_minimum_size = Vector2(40, 40)
			slot.ignore_texture_size = true
			slot.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			slot.slot_type = "bag"
			slot.bag_slot = bag_slot

			if item_index < bag_items.size():
				var item: Dictionary = bag_items[item_index]
				slot.item_index = item_index
				slot.item_data = item
				slot.texture_normal = ItemIcon.texture(item)
				slot.tooltip_text = ItemIcon.tooltip(item)
			else:
				slot.item_index = -1
				slot.item_data = {}

			grid.add_child(slot)

		_bag_sections.add_child(section)


# ===== DATA REFRESH =====

func set_character_data(data: Dictionary) -> void:
	_stat_labels["name"].text = data.get("player_name", "").capitalize()
	_stat_labels["level"].text = "Lv %d" % data.get("player_level", 1)
	_stat_labels["subtitle"].text = "%s %s" % [
		data.get("player_race", "").capitalize(), data.get("player_class", "").capitalize()
	]

	var stats: Dictionary = data.get("stats", {})
	for key in ["strength", "constitution", "dexterity", "intelligence", "wisdom", "charisma", "luck"]:
		_stat_labels[key].text = str(stats.get(key, 0))

	_vitals["hp"]["bar"].max_value = data.get("max_hp", 0)
	_vitals["hp"]["bar"].value = data.get("current_hp", 0)
	_vitals["hp"]["label"].text = "%d / %d" % [data.get("current_hp", 0), data.get("max_hp", 0)]
	_vitals["mp"]["bar"].max_value = data.get("max_mana", 0)
	_vitals["mp"]["bar"].value = data.get("current_mana", 0)
	_vitals["mp"]["label"].text = "%d / %d" % [data.get("current_mana", 0), data.get("max_mana", 0)]
	_vitals["sta"]["bar"].max_value = data.get("max_stamina", 0)
	_vitals["sta"]["bar"].value = data.get("current_stamina", 0)
	_vitals["sta"]["label"].text = "%d / %d" % [data.get("current_stamina", 0), data.get("max_stamina", 0)]
	_vitals["food"]["bar"].max_value = 100
	_vitals["food"]["bar"].value = data.get("satiety", 100)
	_vitals["food"]["label"].text = "%d / 100" % data.get("satiety", 100)
	_vitals["water"]["bar"].max_value = 100
	_vitals["water"]["bar"].value = data.get("thirst", 100)
	_vitals["water"]["label"].text = "%d / 100" % data.get("thirst", 100)

	_stat_labels["spell_power"].text = str(data.get("spell_power", 0))
	_stat_labels["crit_chance"].text = "%.1f%%" % data.get("crit_chance", 0)
	_stat_labels["armor_class"].text = str(data.get("armor_class", 0) + Inventory.get_equipped_armor_class())
	var weapon := Inventory.get_equipped_weapon()
	_stat_labels["attack"].text = str(data.get("attack", 0) + weapon.get("damage", 0))
	_stat_labels["weight"].text = str(data.get("max_weight", 0))

	var xp_cur: int = data.get("xp", 0)
	var xp_next: int = data.get("xp_next_level", 100)
	xp_bar.max_value = xp_next
	xp_bar.value = xp_cur
	_stat_labels["xp"].text = "%d / %d" % [xp_cur, xp_next]

	var res: Dictionary = data.get("resistances", {})
	for key in ["fire", "cold", "acid", "lightning", "poison", "disease", "magic", "divine", "psychic", "spirit"]:
		_stat_labels[key].text = str(res.get(key, 0))

	_stat_labels["platinum_coin"].text = str(data.get("platinum", 0))
	_stat_labels["gold_coin"].text = str(data.get("gold", 0))
	_stat_labels["silver_coin"].text = str(data.get("silver", 0))
	_stat_labels["copper_coin"].text = str(data.get("copper", 0))

	refresh_storage_slots()
	refresh_equipment_slots()


func refresh_equipment_slots() -> void:
	for slot_name in equipment_slots:
		var btn = equipment_slots[slot_name]
		var item: Variant = Inventory.equipped.get(slot_name, null)
		if item != null:
			btn.item_data = item
			btn.texture_normal = ItemIcon.texture(item)
			btn.tooltip_text = ItemIcon.tooltip(item)
		else:
			btn.item_data = {}
			btn.texture_normal = null
			btn.tooltip_text = _SLOT_LABELS.get(slot_name, slot_name.capitalize())
		btn.queue_redraw()


func set_player(p: Node) -> void:
	_player = p


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var cn = _player.get("combat_node")
	if cn == null:
		return

	_vitals["hp"]["bar"].max_value = cn.max_hp
	_vitals["hp"]["bar"].value = cn.current_hp
	_vitals["hp"]["label"].text = "%d / %d" % [cn.current_hp, cn.max_hp]
	_vitals["mp"]["bar"].max_value = cn.max_mana
	_vitals["mp"]["bar"].value = cn.current_mana
	_vitals["mp"]["label"].text = "%d / %d" % [cn.current_mana, cn.max_mana]

	var sta := float(_player.current_stamina if "current_stamina" in _player else 0.0)
	var max_sta := float(_player.max_stamina if "max_stamina" in _player else 100.0)
	_vitals["sta"]["bar"].max_value = max_sta
	_vitals["sta"]["bar"].value = sta
	_vitals["sta"]["label"].text = "%d / %d" % [int(sta), int(max_sta)]

	var food := int(_player.satiety if "satiety" in _player else 100)
	_vitals["food"]["bar"].max_value = 100
	_vitals["food"]["bar"].value = food
	_vitals["food"]["label"].text = "%d / 100" % food

	var water := int(_player.thirst if "thirst" in _player else 100)
	_vitals["water"]["bar"].max_value = 100
	_vitals["water"]["bar"].value = water
	_vitals["water"]["label"].text = "%d / 100" % water

	if _light_status_label and _player.has_method("light_status_text"):
		_light_status_label.text = _player.light_status_text()
		var light_btn = equipment_slots.get("light")
		var light_item: Variant = Inventory.equipped.get("light", null)
		if light_btn and light_item is Dictionary:
			light_btn.tooltip_text = ItemIcon.tooltip(light_item)

	var xp_cur: int = Global.player_data.get("xp", 0)
	var xp_next: int = Global.player_data.get("xp_next_level", 100)
	_stat_labels["xp"].text = "%d / %d" % [xp_cur, xp_next]
	_stat_labels["level"].text = "Lv %d" % Global.player_data.get("player_level", 1)
	if xp_bar:
		xp_bar.max_value = xp_next
		xp_bar.value = xp_cur


func _on_inventory_changed() -> void:
	refresh_storage_slots()

func _on_equipment_changed() -> void:
	refresh_equipment_slots()

func _on_currency_changed() -> void:
	if not _stat_labels.has("platinum_coin"):
		return
	_stat_labels["platinum_coin"].text = str(Global.player_data.get("platinum", 0))
	_stat_labels["gold_coin"].text = str(Global.player_data.get("gold", 0))
	_stat_labels["silver_coin"].text = str(Global.player_data.get("silver", 0))
	_stat_labels["copper_coin"].text = str(Global.player_data.get("copper", 0))


# ===== DRAGGABLE / RESIZABLE PANEL (unchanged) =====

func _on_panel_gui_input(event: InputEvent) -> void:
	var panel = main_panel
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos = event.position
			if pos.x > panel.size.x - RESIZE_MARGIN and pos.y > panel.size.y - RESIZE_MARGIN:
				_resizing = true
			elif pos.y < DRAG_BAR_HEIGHT:
				_dragging = true
		else:
			if _dragging or _resizing:
				WindowPosition.save(POSITION_KEY, panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _dragging:
			panel.offset_left += event.relative.x
			panel.offset_top += event.relative.y
			panel.offset_right += event.relative.x
			panel.offset_bottom += event.relative.y
		elif _resizing:
			panel.offset_right = max(panel.offset_left + 300, panel.offset_right + event.relative.x)
			panel.offset_bottom = max(panel.offset_top + 260, panel.offset_bottom + event.relative.y)
