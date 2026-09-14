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

var _player: Node = null
var _class_stances: Dictionary = {}
var _last_effect_names: Array = []
var _row_time_labels: Dictionary = {}  # effect_name -> Label
var _dragging := false

@onready var panel: Panel = $Panel
@onready var buff_list: VBoxContainer = $Panel/Margin/VBox/BuffList


func _ready() -> void:
	panel.gui_input.connect(_on_panel_gui_input)
	WindowPosition.load_position_into(POSITION_KEY, panel)
	var file := FileAccess.open("res://Data/class_stances.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(data) == TYPE_DICTIONARY:
			_class_stances = data


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		_player = players[0]

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
		_build_row(effect_name, display.name, display.description, remaining)


func _build_row(effect_name: String, display_name: String, description: String, remaining: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var icon_box := Panel.new()
	icon_box.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	var icon_style := StyleBoxFlat.new()
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
	name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	name_row.add_child(name_label)

	var time_label := Label.new()
	time_label.text = _format_remaining(remaining)
	time_label.add_theme_font_size_override("font_size", 10)
	time_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	name_row.add_child(time_label)
	_row_time_labels[effect_name] = time_label

	if not description.is_empty():
		var desc_label := Label.new()
		desc_label.text = description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", 9)
		desc_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		text_col.add_child(desc_label)

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

# Resolves an active_effects key to a display name + description by checking,
# in order: stance data (effect names are "stance_<stance_id>"), the player's
# own spell cache (apply_effect's effect_name matches spell_name for every
# spell-driven buff/debuff in player3d.gd), then the environmental-effects
# table above, falling back to a titled version of the raw effect name if
# nothing matches.
func _resolve_effect_display(effect_name: String) -> Dictionary:
	if effect_name.begins_with("stance_"):
		var stance_id := effect_name.substr(len("stance_"))
		for class_stances in _class_stances.values():
			for stance in class_stances:
				if stance.get("stance_id", "") == stance_id:
					return {"name": stance.get("name", stance_id), "description": stance.get("description", "")}

	if "_spell_by_name" in _player:
		var spell: Dictionary = _player._spell_by_name.get(effect_name, {})
		if not spell.is_empty():
			return {"name": Player3D.spell_display_name(effect_name), "description": spell.get("description", "")}

	if ENVIRONMENTAL_EFFECT_DESCRIPTIONS.has(effect_name):
		return {"name": Player3D.spell_display_name(effect_name), "description": ENVIRONMENTAL_EFFECT_DESCRIPTIONS[effect_name]}

	return {"name": Player3D.spell_display_name(effect_name), "description": ""}


# ===== DRAGGABLE PANEL =====

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not _dragging:
			WindowPosition.save(POSITION_KEY, panel)
	elif event is InputEventMouseMotion and _dragging:
		panel.offset_left   += event.relative.x
		panel.offset_top    += event.relative.y
		panel.offset_right  += event.relative.x
		panel.offset_bottom += event.relative.y
