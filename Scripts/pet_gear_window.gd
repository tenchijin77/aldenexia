# pet_gear_window.gd — Small paperdoll window for the pet's own gear
# (PET_EQUIPMENT_SLOTS on player3d.gd). Equipping happens from the regular
# inventory's right-click popup ("Equip to Pet" — see slot_button.gd);
# right-clicking a slot here offers "Unequip" via the same popup, since these
# slots are plain slot_button.gd instances with slot_type "pet_equipment".
# Opened/closed by pet_frame.gd's "Gear" button.
extends CanvasLayer
class_name PetGearWindow

const SLOT_LABELS := {
	"primary": "Weapon", "offhand": "Off Hand", "head": "Head", "chest": "Chest",
	"arms": "Arms", "hands": "Hands", "legs": "Legs", "feet": "Feet",
}

var _player: Node = null
var _panel: Panel = null
var _slots: Dictionary = {}  # slot name -> slot_button instance
var _dragging := false


func _ready() -> void:
	layer = 4
	_build_ui()


func _build_ui() -> void:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(220, 150)
	panel.anchor_left   = 0.0
	panel.anchor_top    = 0.0
	panel.offset_left   = 250
	panel.offset_top    = 150
	panel.offset_right  = 250 + 220
	panel.offset_bottom = 150 + 150
	panel.gui_input.connect(_on_panel_gui_input)
	_panel = panel
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  8
	vbox.offset_top    =  6
	vbox.offset_right  = -8
	vbox.offset_bottom = -6
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Pet Gear"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))
	vbox.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	for slot_name in SLOT_LABELS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)

		var slot = load("res://Scripts/slot_button.gd").new()
		slot.custom_minimum_size = Vector2(40, 40)
		slot.ignore_texture_size = true
		slot.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		slot.slot_type = "pet_equipment"
		slot.slot_name = slot_name
		col.add_child(slot)
		_slots[slot_name] = slot

		var lbl := Label.new()
		lbl.text = SLOT_LABELS[slot_name]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 9)
		col.add_child(lbl)

		grid.add_child(col)

	_load_position()


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not _dragging:
			_save_position()
	elif event is InputEventMouseMotion and _dragging:
		_panel.offset_left   += event.relative.x
		_panel.offset_top    += event.relative.y
		_panel.offset_right  += event.relative.x
		_panel.offset_bottom += event.relative.y


func _save_position() -> void:
	if Global.player_data.is_empty():
		return
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	ui["pet_gear_window"] = [_panel.offset_left, _panel.offset_top, _panel.offset_right, _panel.offset_bottom]
	Global.player_data["ui_positions"] = ui
	Global.save_player_data_to_file()


func _load_position() -> void:
	var pos: Array = Global.player_data.get("ui_positions", {}).get("pet_gear_window", [])
	if pos.size() == 4:
		_panel.offset_left   = pos[0]
		_panel.offset_top    = pos[1]
		_panel.offset_right  = pos[2]
		_panel.offset_bottom = pos[3]


func set_player(p: Node) -> void:
	_player = p
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_player):
		return
	var pet_equipment: Dictionary = _player.get("pet_equipment")
	if typeof(pet_equipment) != TYPE_DICTIONARY:
		return
	for slot_name in _slots:
		var slot = _slots[slot_name]
		var item: Variant = pet_equipment.get(slot_name, null)
		if item != null:
			slot.item_data = item
			var icon_path: String = item.get("icon", "")
			slot.texture_normal = load(icon_path) if icon_path != "" and FileAccess.file_exists(icon_path) else null
			slot.tooltip_text = item.get("name", slot_name)
		else:
			slot.item_data = {}
			slot.texture_normal = null
			slot.tooltip_text = SLOT_LABELS.get(slot_name, slot_name.capitalize())
		slot.queue_redraw()
