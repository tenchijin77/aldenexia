# trade_window.gd — the window two players trade in (trade_relay.gd brokers it). Left: your offer — drag items here from
# your bags (a stack asks how many), click an offered item to take it back, and set any coin. Right: what the other player
# offers. Accept when you're happy; the trade happens once both have accepted, and any change to either side clears both
# Accepts. Closing the window (or Cancel) calls the trade off.
extends GameWindow

const POSITION_KEY := "trade"
const SLOT := Vector2(44, 44)
const COIN_NAMES := ["platinum", "gold", "silver", "copper"]
const COIN_COPPER := [1000, 100, 10, 1]

var _relay: Node = null
var _partner := ""
var _my_items: Array = []          # [{item_id, quantity}] as last sent
var _my_grid: GridContainer
var _their_grid: GridContainer
var _coin_boxes: Array = []        # SpinBoxes, platinum -> copper
var _their_coin: Label
var _status: Label
var _accept_btn: Button
var _suppress_coin_signal := false
var _closing_by_server := false


# "3 gold, 5 silver" from a copper total.
static func coins_text(copper: int) -> String:
	var parts: Array = []
	var left := copper
	for i in COIN_NAMES.size():
		var n := left / int(COIN_COPPER[i])
		left -= n * int(COIN_COPPER[i])
		if n > 0:
			parts.append("%d %s" % [n, COIN_NAMES[i]])
	return ", ".join(parts) if not parts.is_empty() else "no coin"


func setup(relay: Node, partner_name: String) -> void:
	_relay = relay
	_partner = partner_name


func _ready() -> void:
	build_frame("Trade with %s" % _partner, POSITION_KEY, Vector2(560, 360), Vector2(520, 330))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	body.add_child(columns)

	# Your side
	var mine := VBoxContainer.new()
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(mine)
	mine.add_child(header("Your offer (drag items here)"))
	_my_grid = _grid()
	mine.add_child(_my_grid)
	# Anywhere on your side takes a dropped item, not just the tiles.
	mine.set_drag_forwarding(Callable(), _can_drop_offer, _drop_offer)
	_my_grid.set_drag_forwarding(Callable(), _can_drop_offer, _drop_offer)
	mine.add_child(header("Your coin"))
	var coins := GridContainer.new()
	coins.columns = 4  # two rows: platinum, gold / silver, copper — each a name and a number box
	coins.add_theme_constant_override("h_separation", 6)
	mine.add_child(coins)
	for i in COIN_NAMES.size():
		var coin_label := Label.new()
		coin_label.text = str(COIN_NAMES[i]).capitalize()
		coin_label.add_theme_font_size_override("font_size", 12)
		coins.add_child(coin_label)
		var box := SpinBox.new()
		box.min_value = 0
		box.max_value = 99999
		box.tooltip_text = str(COIN_NAMES[i]).capitalize()
		box.custom_minimum_size = Vector2(80, 0)
		box.value_changed.connect(func(_v: float): _on_coin_changed())
		coins.add_child(box)
		_coin_boxes.append(box)

	# Their side
	var theirs := VBoxContainer.new()
	theirs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(theirs)
	theirs.add_child(header("%s offers" % _partner))
	_their_grid = _grid()
	theirs.add_child(_their_grid)
	_their_coin = Label.new()
	_their_coin.text = "Coin: none"
	_their_coin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_their_coin.custom_minimum_size = Vector2(190, 0)
	theirs.add_child(_their_coin)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(300, 0)
	_status.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	body.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(buttons)
	_accept_btn = Button.new()
	_accept_btn.text = "Accept"
	_accept_btn.toggle_mode = true
	_accept_btn.toggled.connect(func(on: bool): _relay.set_accepted(on))
	buttons.add_child(_accept_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(queue_free)
	buttons.add_child(cancel_btn)
	show_state([], 0, [], 0, false, false)


# Closing the window any way at all (Cancel, the ✕, Escape) calls the trade off — unless the server already ended it.
func _exit_tree() -> void:
	if is_instance_valid(_relay) and _relay.window == self:
		_relay.window = null
		_relay.cancel()


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


# The server's view of the trade (after every change).
func show_state(my_items: Array, my_copper: int, their_items: Array, their_copper: int, i_accepted: bool, they_accepted: bool) -> void:
	_my_items = my_items
	_fill(_my_grid, my_items, true)
	_fill(_their_grid, their_items, false)
	_their_coin.text = "Coin: %s" % coins_text(their_copper)
	_set_coin_boxes(my_copper)
	_accept_btn.set_pressed_no_signal(i_accepted)
	if i_accepted and they_accepted:
		_status.text = "Both accepted — trading..."
	elif they_accepted:
		_status.text = "%s has accepted. Accept to trade." % _partner
	elif i_accepted:
		_status.text = "You have accepted. Waiting for %s..." % _partner
	else:
		_status.text = "Changing either side clears both Accepts."


func _fill(grid: GridContainer, items: Array, mine: bool) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for i in trade_relay_max():
		var tile := Button.new()
		tile.custom_minimum_size = SLOT
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i < items.size():
			var def := Inventory.get_item_definition(str(items[i]["item_id"]))
			tile.icon = ItemIcon.texture(def)
			var qty := int(items[i]["quantity"])
			if qty > 1:  # the count in the corner, over the icon (as text on the button it pushed the icon aside)
				var count := Label.new()
				count.text = str(qty)
				count.add_theme_font_size_override("font_size", 11)
				count.add_theme_constant_override("outline_size", 3)
				count.add_theme_color_override("font_outline_color", Color(0, 0, 0))
				count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
				count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
				count.grow_vertical = Control.GROW_DIRECTION_BEGIN
				count.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tile.add_child(count)
			tile.tooltip_text = "%s%s" % [def.get("name", items[i]["item_id"]), (" x%d" % qty) if qty > 1 else ""]
			if mine:
				tile.tooltip_text += "\n(click to take it back)"
				var index := i
				tile.pressed.connect(func(): _remove_offer(index))
		else:
			tile.disabled = not mine
		if mine:
			tile.set_drag_forwarding(Callable(), _can_drop_offer, _drop_offer)
		grid.add_child(tile)


func trade_relay_max() -> int:
	return 8


# ── Your offer ──
func _can_drop_offer(_pos: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and str(data.get("slot_type", "")) in ["basic", "bag"] and not data.get("item_data", {}).is_empty()


func _drop_offer(_pos: Vector2, data: Variant) -> void:
	var item: Dictionary = data.get("item_data", {})
	if data.get("slot_type") == "basic" and Inventory.is_bag(item) and not Inventory.get_bag_contents(int(data.get("slot_index", -1))).is_empty():
		GameLog.log_general("[color=#ff8866]Empty the %s before trading it.[/color]" % str(item.get("name", "bag")))
		return
	var item_id := str(item.get("item_id", ""))
	var stack := int(item.get("quantity", 1)) if item.get("stackable", false) else 1
	var already := 0
	for entry in _my_items:
		if entry["item_id"] == item_id:
			already += int(entry["quantity"])
	var available := ItemHelper.count(item_id) - already
	if available <= 0:
		GameLog.log_general("You're already offering all of those.")
		return
	stack = mini(stack, available)
	if stack > 1:
		_ask_amount(item_id, str(item.get("name", item_id)), stack)
	else:
		_add_offer(item_id, 1)


func _ask_amount(item_id: String, item_name: String, most: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "How many?"
	dialog.dialog_text = "How many %s do you want to offer?" % item_name
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = most
	spin.value = most
	dialog.add_child(spin)
	dialog.register_text_enter(spin.get_line_edit())
	add_child(dialog)
	dialog.confirmed.connect(func():
		_add_offer(item_id, int(spin.value))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(300, 110))


func _add_offer(item_id: String, qty: int) -> void:
	var items := _my_items.duplicate(true)
	var def := Inventory.get_item_definition(item_id)
	var merged := false
	if def.get("stackable", false):
		for entry in items:
			if entry["item_id"] == item_id:
				entry["quantity"] = int(entry["quantity"]) + qty
				merged = true
	if not merged:
		if items.size() >= trade_relay_max():
			GameLog.log_general("A trade holds at most %d different items." % trade_relay_max())
			return
		items.append({"item_id": item_id, "quantity": qty})
	_relay.set_offer(items, _my_copper())


func _remove_offer(index: int) -> void:
	var items := _my_items.duplicate(true)
	if index < items.size():
		items.remove_at(index)
		_relay.set_offer(items, _my_copper())


func _my_copper() -> int:
	var total := 0
	for i in _coin_boxes.size():
		total += int(_coin_boxes[i].value) * int(COIN_COPPER[i])
	return total


func _set_coin_boxes(copper: int) -> void:
	if copper == _my_copper():
		return
	_suppress_coin_signal = true
	var left := copper
	for i in _coin_boxes.size():
		var n := left / int(COIN_COPPER[i])
		left -= n * int(COIN_COPPER[i])
		_coin_boxes[i].value = n
	_suppress_coin_signal = false


func _on_coin_changed() -> void:
	if _suppress_coin_signal:
		return
	var copper := _my_copper()
	if copper > Global.get_total_copper():
		GameLog.log_general("[color=#ff8866]You only have %s.[/color]" % coins_text(Global.get_total_copper()))
		_set_coin_boxes(Global.get_total_copper())
		copper = Global.get_total_copper()
	_relay.set_offer(_my_items, copper)
