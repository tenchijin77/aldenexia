# corpse_loot_window.gd
# Draggable popup that shows a dead monster's loot.
# Right-click or "Take" button loots individual items.
# "Loot All" takes everything at once.
# Non-currency items can be dragged directly to inventory/bag slots.
extends CanvasLayer

const CURRENCY_MAP: Dictionary = {
	"copper_coin":   "copper",
	"silver_coin":   "silver",
	"gold_coin":     "gold",
	"platinum_coin": "platinum"
}

const CURRENCY_LABELS: Dictionary = {
	"copper_coin":   "Copper",
	"silver_coin":   "Silver",
	"gold_coin":     "Gold",
	"platinum_coin": "Platinum"
}

var pending_loot: Array = []
var _dragging := false

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/TitleBar/TitleLabel
@onready var loot_list: VBoxContainer = $Panel/Margin/VBox/Scroll/LootList
@onready var loot_all_btn: Button = $Panel/Margin/VBox/Footer/LootAllBtn

func _ready() -> void:
	panel.gui_input.connect(_on_panel_gui_input)
	$Panel/Margin/VBox/TitleBar/CloseBtn.pressed.connect(queue_free)
	loot_all_btn.pressed.connect(_loot_all)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func setup(display_name: String, loot: Array) -> void:
	pending_loot = loot.duplicate(true)
	title_label.text = "☠  %s" % display_name
	_rebuild_list()

# Called by slot_button when an item is successfully drag-dropped into inventory.
func consume_loot(drop: Dictionary) -> void:
	pending_loot.erase(drop)
	_rebuild_list()

# ===== LIST BUILDING =====

func _rebuild_list() -> void:
	for child in loot_list.get_children():
		child.queue_free()

	if pending_loot.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Nothing left to loot."
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		loot_list.add_child(empty_lbl)
		loot_all_btn.disabled = true
		return

	loot_all_btn.disabled = false
	for drop in pending_loot:
		loot_list.add_child(_make_row(drop))

func _make_row(drop: Dictionary) -> Control:
	var item_id: String = drop["item"]
	var qty: int       = drop["quantity"]
	var is_currency    := CURRENCY_MAP.has(item_id)

	var display_name: String
	if is_currency:
		display_name = "%d %s" % [qty, CURRENCY_LABELS[item_id]]
	else:
		display_name = item_id.replace("_", " ").capitalize()
		if qty > 1:
			display_name += " x%d" % qty

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 34)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.13, 0.92)
	style.set_border_width_all(1)
	style.border_color = Color(0.32, 0.32, 0.32)
	row.add_theme_stylebox_override("panel", style)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var name_lbl := Label.new()
	name_lbl.text = display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_currency:
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	hbox.add_child(name_lbl)

	var take_btn := Button.new()
	take_btn.text = "Take"
	take_btn.custom_minimum_size = Vector2(52, 0)
	take_btn.pressed.connect(_take.bind(drop))
	hbox.add_child(take_btn)

	# Right-click on the row = take
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_RIGHT \
				and event.pressed:
			_take(drop)
	)

	# Drag support for non-currency items only
	if not is_currency:
		row.set_drag_forwarding(
			func(_at: Vector2) -> Variant:
				var preview := Label.new()
				preview.text = drop["item"].replace("_", " ").capitalize()
				row.set_drag_preview(preview)
				return {
					"slot_type":   "loot",
					"item_id":     drop["item"],
					"item_data":   Inventory.get_item_definition(drop["item"]),
					"loot_window": self,
					"loot_drop":   drop,
				},
			Callable(),
			Callable()
		)

	return row

# ===== LOOT ACTIONS =====

func _take(drop: Dictionary) -> void:
	_apply_drop(drop)
	pending_loot.erase(drop)
	_rebuild_list()

func _loot_all() -> void:
	for drop in pending_loot.duplicate():
		_apply_drop(drop)
	pending_loot.clear()
	_rebuild_list()

func _apply_drop(drop: Dictionary) -> void:
	var item_id: String = drop["item"]
	var qty: int        = drop["quantity"]
	if CURRENCY_MAP.has(item_id):
		Global.grant_currency(CURRENCY_MAP[item_id], qty)
		print("💰 +%d %s" % [qty, CURRENCY_MAP[item_id]])
	elif Inventory.get_item_definition(item_id).is_empty():
		print("⚠️ %s not yet in items.json" % item_id)
	else:
		Inventory.add_to_basic_inventory(item_id)

# ===== DRAGGABLE PANEL =====

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		panel.offset_left  += event.relative.x
		panel.offset_top   += event.relative.y
		panel.offset_right += event.relative.x
		panel.offset_bottom += event.relative.y
