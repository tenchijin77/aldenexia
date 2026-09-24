#backpack_ui.gd - displays the player backpack page. This is created by the player adding bags to their 12 original inventory slots in the character_sheet panel.
extends CanvasLayer

const SLOT_SIZE := Vector2(48, 48)

var slot_buttons: Array = []
var visible_slots: Array = []
var _dragging := false

@onready var search_bar = $Panel/MarginContainer/VBoxContainer/SearchBar
@onready var slot_count_label = $Panel/MarginContainer/VBoxContainer/SlotCountLabel
@onready var slot_container = $Panel/MarginContainer/VBoxContainer/ScrollContainer/SlotGrid

const TITLE_H := 24.0
const CONTENT_MARGIN := 8
const POSITION_KEY := "backpack"
const RESIZE_MARGIN := 16.0
var _resizing := false

func _ready():
	$Panel.add_theme_stylebox_override("panel", Global.window_bg_style())
	$Panel.gui_input.connect(_on_panel_gui_input)
	$Panel.resized.connect(_on_panel_resized)
	WindowPosition.load_full_into(POSITION_KEY, $Panel)

	# Title bar
	var title_lbl := Label.new()
	title_lbl.text = "Backpack"
	title_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_lbl.offset_bottom = TITLE_H
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Panel.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.anchor_left   = 1.0
	close_btn.anchor_right  = 1.0
	close_btn.offset_left   = -24.0
	close_btn.offset_right  = -2.0
	close_btn.offset_top    = 2.0
	close_btn.offset_bottom = TITLE_H - 2.0
	close_btn.pressed.connect(func():
		queue_free()
		Global.restore_mouse_mode()
	)
	$Panel.add_child(close_btn)

	# Push content below title bar, with a margin all round so nothing touches the frame
	$Panel/MarginContainer.offset_top = TITLE_H
	for side in ["left", "right", "bottom"]:
		$Panel/MarginContainer.add_theme_constant_override("margin_" + side, CONTENT_MARGIN)

	if search_bar:
		search_bar.text_changed.connect(_on_search_text_changed)
		# Sort, next to the search box (same as the character sheet's Sort button).
		var row := HBoxContainer.new()
		search_bar.get_parent().add_child(row)
		search_bar.get_parent().move_child(row, search_bar.get_index())
		search_bar.reparent(row)
		search_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sort_btn := Button.new()
		sort_btn.text = "Sort"
		sort_btn.tooltip_text = "Put crafting materials into your crafting bags (kits, Large Crafting Bag) and join split stacks."
		sort_btn.pressed.connect(func():
			var moved := Inventory.sort_pack()
			GameLog.log_general("You tidy your pack%s." % ((": %d item%s into your crafting bags" % [moved, "" if moved == 1 else "s"]) if moved > 0 else "")))
		row.add_child(sort_btn)
	if Inventory.inventory_changed.is_connected(_on_inventory_changed) == false:
		Inventory.inventory_changed.connect(_on_inventory_changed)
	refresh_backpack()
	call_deferred("_on_panel_resized")

func refresh_backpack():
	clear_slots()
	var total_slots = Inventory.calculate_total_bag_slots()
	slot_count_label.text = "Bag Slots: %d" % total_slots
	create_slots(total_slots)
	populate_slots()

func clear_slots():
	for s in slot_buttons:
		if is_instance_valid(s):
			s.queue_free()
	slot_buttons.clear()
	visible_slots.clear()

func create_slots(count: int):
	for i in range(count):
		var slot_button = load("res://Scripts/slot_button.gd").new()
		slot_button.custom_minimum_size = SLOT_SIZE
		slot_button.ignore_texture_size = true
		slot_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		slot_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# (slot_button.gd draws its own background/border in _draw() —
		# a "normal" stylebox override here has no visible effect.)

		slot_button.slot_type = "bag"
		slot_button.slot_index = i
		slot_button.bag_slot = -1
		slot_button.item_index = -1
		slot_button.item_data = {}

		slot_container.add_child(slot_button)
		slot_buttons.append(slot_button)
		visible_slots.append(slot_button)

func populate_slots():
	var slot_index = 0

	for bag_slot in range(Inventory.BASIC_INVENTORY_SIZE):
		var bag = Inventory.basic_inventory[bag_slot]
		if bag == null or not Inventory.is_bag(bag):
			continue

		var bag_items = Inventory.get_bag_contents(bag_slot)

		for item_i in range(bag_items.size()):
			if slot_index >= slot_buttons.size():
				return

			var item = bag_items[item_i]
			var slot = slot_buttons[slot_index]

			slot.slot_type = "bag"
			slot.bag_slot = bag_slot
			slot.slot_index = slot_index
			slot.item_index = item_i
			slot.item_data = item

			slot.texture_normal = ItemIcon.texture(item)
			slot.tooltip_text = ItemIcon.tooltip(item)

			# (the stack count is drawn by slot_button.gd itself — a second label here showed it twice)

			slot_index += 1

func _on_search_text_changed(new_text: String):
	var term = new_text.to_lower()

	for slot in visible_slots:
		if slot.item_data == {}:
			slot.visible = true
			continue

		var name = slot.item_data.get("name", "").to_lower()
		slot.visible = term in name

func _on_inventory_changed():
	refresh_backpack()
	
func _on_panel_gui_input(event: InputEvent) -> void:
	var panel := $Panel
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos = event.position
			if pos.x > panel.size.x - RESIZE_MARGIN and pos.y > panel.size.y - RESIZE_MARGIN:
				_resizing = true
			elif pos.y < TITLE_H:
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


# Recomputes the slot grid's column count from the panel's current width so
# the grid actually fills the available space (was previously a hardcoded 4
# columns regardless of window size — the "only using half the window"
# report) and keeps filling it correctly as the player resizes the window.
func _on_panel_resized() -> void:
	if not slot_container:
		return
	var available_width: float = $Panel.size.x - CONTENT_MARGIN * 2 - 14.0  # margins + scrollbar allowance
	var cell_width: float = SLOT_SIZE.x + slot_container.get_theme_constant("h_separation")
	var columns: int = max(1, int(available_width / cell_width))
	if slot_container.columns != columns:
		slot_container.columns = columns
