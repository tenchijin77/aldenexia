# buff_bar.gd — Draggable HUD panel listing the player's active buffs/debuffs
# (stances included), EQ/WoW-style: each row shows a name, what it does, and
# time remaining. Reads directly off combat_node.active_effects (the generic
# effect system in combatnode.gd) rather than tracking its own list, so any
# future apply_effect() call — stance, spell buff/debuff, whatever — shows up
# here automatically with no extra wiring.
#
# Icons: each row reserves a blank bordered square on the left for a spell
# icon. No icon assets exist yet — wire actual textures into the icon_rect
# placeholder in _build_row() once art is available.
extends CanvasLayer
class_name BuffBar

const ICON_SIZE := 28
const POSITION_KEY := "buff_bar"
const RESIZE_MARGIN := 16.0
const MIN_WIDTH := 160.0
const MIN_HEIGHT := 100.0

var _player: Node = null
var _class_stances: Dictionary = {}
var _last_effect_names: Array = []
var _row_time_labels: Dictionary = {}  # effect_name -> Label
var _dragging := false
var _resizing := false

@onready var panel: Panel = $Panel
@onready var buff_list: VBoxContainer = $Panel/Margin/VBox/BuffList


func _ready() -> void:
	panel.gui_input.connect(_on_panel_gui_input)
	WindowPosition.load_full_into(POSITION_KEY, panel)
	var file := FileAccess.open("res://Data/class_stances.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(data) == TYPE_DICTIONARY:
			_class_stances = data


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = TargetFrame.local_player()
		if not is_instance_valid(_player):
			return

	if not ("combat_node" in _player) or not (_player.combat_node is CombatNode):
		return

	var active_effects: Dictionary = _player.combat_node.active_effects
	var effect_names: Array = active_effects.keys()
	effect_names.sort()

	if effect_names != _last_effect_names:
		_last_effect_names = effect_names.duplicate()
		_rebuild_rows(effect_names, active_effects)

	for effect_name in effect_names:
		var label: Label = _row_time_labels.get(effect_name)
		if label:
			label.text = _format_remaining(active_effects[effect_name].get("remaining", 0.0))


func _rebuild_rows(effect_names: Array, active_effects: Dictionary) -> void:
	for child in buff_list.get_children():
		child.queue_free()
	_row_time_labels.clear()

	for effect_name in effect_names:
		var display := _resolve_effect_display(effect_name)
		var remaining: float = active_effects[effect_name].get("remaining", 0.0)
		_build_row(effect_name, display.name, display.description, remaining, display.is_debuff)


func _build_row(effect_name: String, display_name: String, description: String, remaining: float, is_debuff: bool = false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	# Full description only on hover (was always shown inline, cluttering the
	# window per the user's feedback 2026-09-17) — needs MOUSE_FILTER_STOP,
	# since a Container's default filter (IGNORE) never receives the hover
	# events a tooltip needs.
	row.tooltip_text = description
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var icon_box := Panel.new()
	icon_box.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	var icon_style := StyleBoxFlat.new()
	# Debuffs/negative effects get a red-highlighted box so the player has an
	# immediate visual cue something harmful is active, separate from reading
	# each row's name/description.
	if is_debuff:
		icon_style.bg_color = Color(0.35, 0.08, 0.08)
		icon_style.border_color = Color(0.95, 0.25, 0.25)
		icon_style.set_border_width_all(2)
	else:
		icon_style.bg_color = Color(0.12, 0.12, 0.16)
		icon_style.border_color = Color(0.4, 0.4, 0.5)
		icon_style.set_border_width_all(1)
	icon_style.set_corner_radius_all(3)
	icon_box.add_theme_stylebox_override("panel", icon_style)
	row.add_child(icon_box)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 0)
	row.add_child(text_col)

	var name_row := HBoxContainer.new()
	text_col.add_child(name_row)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4) if is_debuff else Color(0.95, 0.85, 0.55))
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(name_label)

	var time_label := Label.new()
	time_label.text = _format_remaining(remaining)
	time_label.add_theme_font_size_override("font_size", 10)
	time_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	name_row.add_child(time_label)
	_row_time_labels[effect_name] = time_label

	buff_list.add_child(row)


func _format_remaining(remaining: float) -> String:
	if remaining == INF:
		return "∞"
	var seconds := maxi(0, int(remaining))
	return "%d:%02d" % [seconds / 60, seconds % 60]


# Non-spell, non-stance effects (environmental buffs, etc.) that still want a
# real description on the buff bar instead of just a titled name.
const ENVIRONMENTAL_EFFECT_DESCRIPTIONS := {
	"campfire_warmth": "Resting by a campfire's warmth. +2 HP/Mana/Stamina regeneration.",
	"well_fed": "Well fed and hydrated. +2 HP/Mana/Stamina regeneration.",
}

# Resolves an active_effects key to a display name + description + is_debuff
# flag by checking, in order: stance data (effect names are
# "stance_<stance_id>", never debuffs), the FULL spell table (_spell_by_name
# is loaded from every spell in player_spells.json, not just known ones — see
# player3d.gd _load_spell_cache() — so this also correctly flags a debuff an
# enemy/other source casts on the player, not just the player's own spells),
# then the environmental-effects table above, falling back to a titled
# version of the raw effect name if nothing matches.
func _resolve_effect_display(effect_name: String) -> Dictionary:
	if effect_name.begins_with("stance_"):
		var stance_id := effect_name.substr(len("stance_"))
		for class_stances in _class_stances.values():
			for stance in class_stances:
				if stance.get("stance_id", "") == stance_id:
					return {"name": stance.get("name", stance_id), "description": stance.get("description", ""), "is_debuff": false}

	if "_spell_by_name" in _player:
		var spell: Dictionary = _player._spell_by_name.get(effect_name, {})
		if not spell.is_empty():
			# target, not spell_type/effect_type, decides red — those two
			# describe the spell's own mechanical shape/polarity (e.g. Aura of
			# the Shadow is effect_type "debuff" because it debuffs nearby
			# ENEMIES, and dozens of clearly-beneficial group buffs are
			# mis-tagged spell_type "detrimental" in the source data) rather
			# than whether landing on the PLAYER specifically is harmful. An
			# effect only ever ends up in the player's own active_effects
			# because they cast a self/group spell on themselves (never
			# harmful by construction) or a hostile "enemy"-target spell
			# resolved onto them (always harmful) — target says which.
			var is_debuff: bool = spell.get("target", "") == "enemy"
			return {"name": Player3D.spell_display_name(effect_name), "description": spell.get("description", ""), "is_debuff": is_debuff}

	if ENVIRONMENTAL_EFFECT_DESCRIPTIONS.has(effect_name):
		return {"name": Player3D.spell_display_name(effect_name), "description": ENVIRONMENTAL_EFFECT_DESCRIPTIONS[effect_name], "is_debuff": false}

	return {"name": Player3D.spell_display_name(effect_name), "description": "", "is_debuff": false}


# ===== DRAGGABLE PANEL =====

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos: Vector2 = event.position
			if pos.x > panel.size.x - RESIZE_MARGIN and pos.y > panel.size.y - RESIZE_MARGIN:
				_resizing = true
			else:
				_dragging = true
		else:
			if _dragging or _resizing:
				WindowPosition.save(POSITION_KEY, panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion and _resizing:
		panel.offset_right  = max(panel.offset_left + MIN_WIDTH, panel.offset_right + event.relative.x)
		panel.offset_bottom = max(panel.offset_top + MIN_HEIGHT, panel.offset_bottom + event.relative.y)
	elif event is InputEventMouseMotion and _dragging:
		panel.offset_left   += event.relative.x
		panel.offset_top    += event.relative.y
		panel.offset_right  += event.relative.x
		panel.offset_bottom += event.relative.y
