#slot_button.gd - creates the drag and drop bag slots
extends TextureButton

var slot_type: String = ""
var slot_name: String = ""
var slot_index: int = -1
var bag_slot: int = -1
var item_index: int = -1
var item_data: Dictionary = {}

func _ready():
	custom_minimum_size = Vector2(48, 48)
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.15, 0.15, 0.9))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.5, 0.5, 1.0), false, 1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed and not item_data.is_empty():
		_show_inspect_popup()


func _learn_from_scroll() -> void:
	var spell_name: String = item_data.get("teaches_spell", "")
	if spell_name.is_empty():
		return

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player := players[0]

	var known: Array = player.get("known_spells") if "known_spells" in player else []
	if spell_name in known:
		GameLog.log_general("You already know [b]%s[/b]." % spell_name.replace("_", " ").capitalize())
		return

	# Learn the spell
	known.append(spell_name)
	player.known_spells = known
	Global.player_data["known_spells"] = known

	# Remove the scroll from inventory
	if slot_type == "basic":
		Inventory.remove_from_basic_inventory(slot_index)
	elif slot_type == "bag":
		Inventory.remove_from_bag(bag_slot, item_index)

	Global.save_player_data_to_file()

	GameLog.log_general("[color=#ffdd44]You have learned [b]%s[/b]![/color]" % spell_name.replace("_", " ").capitalize())

	# Refresh the abilities book if it's open
	for node in get_tree().root.get_children():
		if node is AbilitiesBook:
			node.set_player(player)
			break

func _show_inspect_popup() -> void:
	var root = get_tree().root
	var existing = root.get_node_or_null("ItemInspectLayer")
	if existing:
		existing.queue_free()

	var layer := CanvasLayer.new()
	layer.name = "ItemInspectLayer"
	layer.layer = 15

	var popup := Panel.new()
	popup.custom_minimum_size = Vector2(280, 80)

	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.08, 0.07, 0.06, 0.97)
	bg.border_color = Color(0.45, 0.38, 0.25)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	vbox.add_theme_constant_override("separation", 6)

	# Item name
	var title := Label.new()
	title.text = item_data.get("name", "Unknown Item")
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(title)

	# Stats line (damage / armor / value)
	var stats_parts: Array = []
	if item_data.get("damage", 0) > 0:
		stats_parts.append("Dmg: %d" % item_data["damage"])
	if item_data.get("armor_class", 0) > 0:
		stats_parts.append("AC: %d" % item_data["armor_class"])
	if item_data.get("value", 0) > 0:
		stats_parts.append("Value: %d cp" % item_data["value"])
	if not stats_parts.is_empty():
		var stats_lbl := Label.new()
		stats_lbl.text = "  ".join(stats_parts)
		stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		stats_lbl.add_theme_font_size_override("font_size", 11)
		vbox.add_child(stats_lbl)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = item_data.get("description", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.80))
	vbox.add_child(desc_lbl)

	# Lore (if any)
	if item_data.has("lore") and item_data["lore"] != "":
		var lore_lbl := Label.new()
		lore_lbl.text = item_data["lore"]
		lore_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lore_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.55))
		lore_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(lore_lbl)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Action buttons row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	# Equip button (equippable items only)
	var equip_slot: String = Inventory.ITEM_SLOT_MAP.get(item_data.get("slot", ""), "")
	if not equip_slot.is_empty():
		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.pressed.connect(func():
			layer.queue_free()
			Inventory.equip_item(item_data, slot_type, slot_index, bag_slot, item_index)
		)
		btn_row.add_child(equip_btn)

	# Learn button (scrolls only)
	if item_data.get("type") == "scroll" and item_data.has("teaches_spell"):
		var learn_btn := Button.new()
		learn_btn.text = "Learn"
		learn_btn.pressed.connect(func():
			layer.queue_free()
			_learn_from_scroll()
		)
		btn_row.add_child(learn_btn)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): layer.queue_free())
	btn_row.add_child(close_btn)

	popup.add_child(vbox)
	popup.position = get_global_mouse_position() + Vector2(10, 10)
	layer.add_child(popup)
	root.add_child(layer)

func _get_drag_data(at_position: Vector2) -> Variant:
	if item_data.is_empty():
		return null
	var payload := {
		"item_data": item_data,
		"slot_type": slot_type,
		"slot_name": slot_name,
		"slot_index": slot_index,
		"bag_slot": bag_slot,
		"item_index": item_index
	}
	var preview := TextureRect.new()
	if item_data.has("icon") and item_data.get("icon") is String and FileAccess.file_exists(item_data.get("icon", "")):
		preview.texture = load(item_data.get("icon"))
	preview.custom_minimum_size = Vector2(48, 48)
	preview.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(preview)
	return payload

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.get("slot_type") == "loot":
		return not data.get("item_id", "").is_empty()
	if slot_type == "equipment":
		var item: Dictionary = data.get("item_data", {})
		var target: String = Inventory.ITEM_SLOT_MAP.get(item.get("slot", "none"), "")
		return target == slot_name
	return data.has("item_data")

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if data.get("slot_type") == "loot":
		var item_id: String = data.get("item_id", "")
		if item_id.is_empty():
			return
		if Inventory.add_to_basic_inventory(item_id):
			var window = data.get("loot_window")
			if is_instance_valid(window):
				window.consume_loot(data.get("loot_drop"))
	elif slot_type == "equipment":
		Inventory.equip_item(
			data.get("item_data", {}),
			data.get("slot_type", ""),
			data.get("slot_index", -1),
			data.get("bag_slot", -1),
			data.get("item_index", -1)
		)
	elif data.get("slot_type") == "equipment":
		Inventory.unequip_item(data.get("slot_name", ""))
	else:
		Inventory.move_item_between_slots(self, data)
