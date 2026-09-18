# corpse_loot_window.gd
# Draggable popup that shows a dead monster's loot.
# Right-click or "Take" button loots individual items.
# "Loot All" takes everything at once.
# Non-currency items can be dragged directly to inventory/bag slots.
extends CanvasLayer

signal all_looted

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

const MIN_PANEL_WIDTH := 220.0
const MAX_PANEL_WIDTH := 420.0
const MIN_PANEL_HEIGHT := 150.0
const MAX_LIST_HEIGHT := 260.0  # beyond this many px of rows, the list scrolls instead of the window growing further
const POSITION_KEY := "corpse_loot_window"
const RESIZE_MARGIN := 16.0

var pending_loot: Array = []
var _dragging := false
var _resizing := false
# See shop_window.gd's identical flag — once anything's been saved for this
# window (drag or resize), stop auto-fitting to content on every rebuild.
var _user_resized := false

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/TitleBar/TitleLabel
@onready var vbox: VBoxContainer = $Panel/Margin/VBox
@onready var scroll: ScrollContainer = $Panel/Margin/VBox/Scroll
@onready var loot_list: VBoxContainer = $Panel/Margin/VBox/Scroll/LootList
@onready var loot_all_btn: Button = $Panel/Margin/VBox/Footer/LootAllBtn

func _ready() -> void:
	panel.gui_input.connect(_on_panel_gui_input)
	$Panel/Margin/VBox/TitleBar/CloseBtn.pressed.connect(queue_free)
	loot_all_btn.pressed.connect(_loot_all)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_user_resized = Global.player_data.get("ui_positions", {}).get(POSITION_KEY, []).size() == 4
	WindowPosition.load_full_into(POSITION_KEY, panel)

func _exit_tree() -> void:
	Global.restore_mouse_mode()

func setup(display_name: String, loot: Array) -> void:
	pending_loot = loot  # reference — mutations here deplete the monster's actual loot
	title_label.text = "Modern Loot Manager — %s" % display_name
	_rebuild_list()

# Called by slot_button when an item is successfully drag-dropped into inventory.
func consume_loot(drop: Dictionary) -> void:
	pending_loot.erase(drop)
	_rebuild_list()

# ===== LIST BUILDING =====

func _rebuild_list() -> void:
	for child in loot_list.get_children():
		loot_list.remove_child(child)  # synchronous, unlike queue_free() alone — keeps
		child.queue_free()             # the size read below from counting stale rows

	if pending_loot.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Nothing left to loot."
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		loot_list.add_child(empty_lbl)
		loot_all_btn.disabled = true
		_resize_to_content()
		all_looted.emit()
		return

	loot_all_btn.disabled = false
	for drop in pending_loot:
		loot_list.add_child(_make_row(drop))
	_resize_to_content()


# Grows (or shrinks) the window to fit whatever's actually in the list, up to
# MAX_PANEL_WIDTH/MAX_LIST_HEIGHT — beyond that the list scrolls instead.
# get_combined_minimum_size() is a bottom-up calculation from each row's own
# minimum size, so it's accurate immediately after rebuilding the list, no
# frame delay needed.
func _resize_to_content() -> void:
	var list_min: Vector2 = loot_list.get_combined_minimum_size()
	scroll.custom_minimum_size.y = minf(list_min.y, MAX_LIST_HEIGHT)

	if _user_resized:
		return

	var target_width: float = clamp(list_min.x + 32.0, MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
	panel.offset_right = panel.offset_left + target_width

	var vbox_min: Vector2 = vbox.get_combined_minimum_size()
	panel.offset_bottom = panel.offset_top + vbox_min.y + 16.0  # + top/bottom margin

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

	if not is_currency:
		hbox.add_child(_make_preference_checkboxes(item_id, drop))

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


# Three mutually-exclusive toggle buttons (Loot / Ignore / Sell) that set a
# permanent per-item-id preference (Global.set_loot_preference) and, unlike
# just remembering it for next time, resolve THIS drop immediately too.
#
# Plain toggle-mode Buttons with explicit stylebox overrides rather than
# CheckBox — CheckBox's built-in check glyph wasn't rendering at all in
# testing (just bare text, no box/checkmark, with no theme override to
# explain it), so this draws its own on/off indicator via background color
# instead of depending on a theme icon resource.
func _make_preference_checkboxes(item_id: String, drop: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()

	var off_style := StyleBoxFlat.new()
	off_style.bg_color = Color(0.16, 0.16, 0.18)
	off_style.border_color = Color(0.4, 0.4, 0.45)
	off_style.set_border_width_all(1)
	off_style.set_corner_radius_all(3)
	off_style.content_margin_left = 6
	off_style.content_margin_right = 6
	off_style.content_margin_top = 2
	off_style.content_margin_bottom = 2

	var on_style := StyleBoxFlat.new()
	on_style.bg_color = Color(0.25, 0.5, 0.28)
	on_style.border_color = Color(0.5, 0.95, 0.55)
	on_style.set_border_width_all(1)
	on_style.set_corner_radius_all(3)
	on_style.content_margin_left = 6
	on_style.content_margin_right = 6
	on_style.content_margin_top = 2
	on_style.content_margin_bottom = 2

	for pref in ["loot", "ignore", "sell"]:
		var cb := Button.new()
		cb.text = pref.capitalize()
		cb.toggle_mode = true
		cb.button_group = group
		cb.add_theme_font_size_override("font_size", 10)
		cb.add_theme_stylebox_override("normal", off_style)
		cb.add_theme_stylebox_override("hover", off_style)
		cb.add_theme_stylebox_override("pressed", on_style)
		cb.add_theme_stylebox_override("hover_pressed", on_style)
		cb.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				_set_preference(item_id, pref, drop)
		)
		box.add_child(cb)

	return box


func _set_preference(item_id: String, preference: String, drop: Dictionary) -> void:
	Global.set_loot_preference(item_id, preference)
	if preference == "ignore":
		pending_loot.erase(drop)
	else:  # loot / sell — resolve this drop right now too
		if _apply_drop(drop):
			pending_loot.erase(drop)
	_rebuild_list()


# ===== LOOT ACTIONS =====

func _take(drop: Dictionary) -> void:
	if _apply_drop(drop):
		pending_loot.erase(drop)
	_rebuild_list()

func _loot_all() -> void:
	for drop in pending_loot.duplicate():
		if _apply_drop(drop):
			pending_loot.erase(drop)
	_rebuild_list()

# Returns true only if the drop was actually applied — a full inventory
# leaves the drop on the corpse instead of vanishing (previously this always
# reported success and removed the drop regardless of whether
# add_to_basic_inventory() actually found room, which is why looted items
# could silently disappear).
func _apply_drop(drop: Dictionary) -> bool:
	var item_id: String = drop["item"]
	var qty: int        = drop["quantity"]
	if CURRENCY_MAP.has(item_id):
		Global.grant_currency(CURRENCY_MAP[item_id], qty)
		Global.play_coin_sound()
		GameLog.log_general("[color=#ffd966]You receive %d %s.[/color]" % [qty, CURRENCY_LABELS[item_id]])
		return true
	elif Inventory.get_item_definition(item_id).is_empty():
		print("⚠️ %s not yet in items.json" % item_id)
		return false
	else:
		var display_name: String = item_id.replace("_", " ").capitalize()
		if Inventory.add_item(item_id, qty):
			GameLog.log_general("You receive %s%s." % [display_name, (" x%d" % qty) if qty > 1 else ""])
			return true
		else:
			GameLog.log_general("[color=#ff8866]Your inventory is full — you leave %s behind.[/color]" % display_name)
			return false

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
			if _resizing:
				_user_resized = true
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _resizing:
			panel.offset_right  = max(panel.offset_left + MIN_PANEL_WIDTH, panel.offset_right + event.relative.x)
			panel.offset_bottom = max(panel.offset_top + MIN_PANEL_HEIGHT, panel.offset_bottom + event.relative.y)
		elif _dragging:
			panel.offset_left  += event.relative.x
			panel.offset_top   += event.relative.y
			panel.offset_right += event.relative.x
			panel.offset_bottom += event.relative.y
