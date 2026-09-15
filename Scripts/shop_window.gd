# shop_window.gd — Draggable merchant window opened by right-clicking a
# VendorNPC in range (player3d.gd's _try_open_shop_or_loot()). Two lists:
# "For Sale" (the vendor's stock, Buy buttons) and "Your Items" (everything
# sellable currently in the player's basic inventory slots + bag contents,
# Sell buttons). Prices come from VendorNPC.get_shop_stock()/get_sell_price(),
# which derive from each item's own items.json "value" (see
# Global.item_value_in_copper()) — no separate price data to keep in sync.
extends CanvasLayer

const MIN_PANEL_WIDTH := 260.0
const MAX_PANEL_WIDTH := 420.0
const MAX_LIST_HEIGHT := 200.0  # each of the two lists, before it scrolls instead of growing the window
const POSITION_KEY := "shop_window"

var _vendor: Node = null

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/TitleBar/TitleLabel
@onready var vbox: VBoxContainer = $Panel/Margin/VBox
@onready var coin_label: Label = $Panel/Margin/VBox/CoinLabel
@onready var buy_scroll: ScrollContainer = $Panel/Margin/VBox/BuyScroll
@onready var buy_list: VBoxContainer = $Panel/Margin/VBox/BuyScroll/BuyList
@onready var sell_scroll: ScrollContainer = $Panel/Margin/VBox/SellScroll
@onready var sell_list: VBoxContainer = $Panel/Margin/VBox/SellScroll/SellList

var _dragging := false


func _ready() -> void:
	panel.gui_input.connect(_on_panel_gui_input)
	$Panel/Margin/VBox/TitleBar/CloseBtn.pressed.connect(queue_free)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	WindowPosition.load_position_into(POSITION_KEY, panel)
	Global.currency_changed.connect(_refresh_coin_label)
	Inventory.inventory_changed.connect(_rebuild_sell_list)


func _exit_tree() -> void:
	Global.restore_mouse_mode()


func setup(vendor: Node) -> void:
	_vendor = vendor
	title_label.text = "🛒  %s" % _vendor.get_vendor_display_name()
	_refresh_coin_label()
	_rebuild_buy_list()
	_rebuild_sell_list()


func _refresh_coin_label() -> void:
	var plat: int = Global.player_data.get("platinum", 0)
	var gold: int = Global.player_data.get("gold", 0)
	var silver: int = Global.player_data.get("silver", 0)
	var copper: int = Global.player_data.get("copper", 0)
	coin_label.text = "You have: %dpp %dgp %dsp %dcp" % [plat, gold, silver, copper]


# ===== BUY LIST =====

func _rebuild_buy_list() -> void:
	for child in buy_list.get_children():
		buy_list.remove_child(child)
		child.queue_free()

	if not is_instance_valid(_vendor):
		return

	for entry in _vendor.get_shop_stock():
		buy_list.add_child(_make_buy_row(entry))
	_resize_to_content()


func _make_buy_row(entry: Dictionary) -> Control:
	var item_def: Dictionary = entry["item_def"]
	var price: int = entry["price"]

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.13, 0.92)
	style.set_border_width_all(1)
	style.border_color = Color(0.32, 0.32, 0.32)
	row.add_theme_stylebox_override("panel", style)
	row.tooltip_text = item_def.get("description", "")

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var name_lbl := Label.new()
	name_lbl.text = item_def.get("name", entry["item_id"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "%d cp" % price
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(price_lbl)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size = Vector2(48, 0)
	buy_btn.disabled = not Global.can_afford(price)
	buy_btn.pressed.connect(_buy.bind(entry))
	hbox.add_child(buy_btn)

	return row


func _buy(entry: Dictionary) -> void:
	var price: int = entry["price"]
	var item_id: String = entry["item_id"]
	var item_def: Dictionary = entry["item_def"]

	if not Global.can_afford(price):
		GameLog.log_general("You can't afford that.")
		return
	if not Inventory.add_item(item_id):
		GameLog.log_general("Your inventory is full.")
		return
	Global.spend_currency_copper(price)
	GameLog.log_general("You purchase %s for %d copper." % [item_def.get("name", item_id), price])
	_rebuild_buy_list()  # add_item() emits inventory_changed itself, which refreshes the sell list


# ===== SELL LIST =====
# Gathers everything sellable from the player's basic inventory slots (minus
# equipped bags themselves, which would destroy their contents) and every bag's
# contents — same addressing scheme (slot_type/slot_index/bag_slot/item_index)
# slot_button.gd's drag payload and Inventory's remove functions already use.

func _rebuild_sell_list() -> void:
	for child in sell_list.get_children():
		sell_list.remove_child(child)
		child.queue_free()

	if not is_instance_valid(_vendor):
		return

	var rows: Array = []
	for i in range(Inventory.BASIC_INVENTORY_SIZE):
		var item: Dictionary = Inventory.get_basic_inventory_slot(i)
		if item.is_empty() or Inventory.is_bag(item):
			continue
		rows.append({"item": item, "slot_type": "basic", "slot_index": i, "bag_slot": -1, "item_index": -1})

	for bag_slot in range(Inventory.BASIC_INVENTORY_SIZE):
		var bag: Dictionary = Inventory.get_basic_inventory_slot(bag_slot)
		if not Inventory.is_bag(bag):
			continue
		var bag_items := Inventory.get_bag_contents(bag_slot)
		for item_index in range(bag_items.size()):
			rows.append({"item": bag_items[item_index], "slot_type": "bag", "slot_index": -1, "bag_slot": bag_slot, "item_index": item_index})

	if rows.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "You have nothing to sell."
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		sell_list.add_child(empty_lbl)
	else:
		for row_data in rows:
			sell_list.add_child(_make_sell_row(row_data))
	_resize_to_content()


func _make_sell_row(row_data: Dictionary) -> Control:
	var item: Dictionary = row_data["item"]
	var price: int = _vendor.get_sell_price(item)

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.13, 0.92)
	style.set_border_width_all(1)
	style.border_color = Color(0.32, 0.32, 0.32)
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var qty: int = item.get("quantity", 1) if item.get("stackable", false) else 1
	var display_name: String = item.get("name", "Unknown Item")
	if qty > 1:
		display_name += " x%d" % qty

	var name_lbl := Label.new()
	name_lbl.text = display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "%d cp" % price
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(price_lbl)

	var sell_btn := Button.new()
	sell_btn.text = "Sell"
	sell_btn.custom_minimum_size = Vector2(48, 0)
	sell_btn.pressed.connect(_sell.bind(row_data))
	hbox.add_child(sell_btn)

	return row


func _sell(row_data: Dictionary) -> void:
	var item: Dictionary = row_data["item"]
	var price: int = _vendor.get_sell_price(item)

	Inventory.consume_one(row_data["slot_type"], row_data["slot_index"], row_data["bag_slot"], row_data["item_index"])
	Global.add_currency_copper(price)
	Global.play_coin_sound()
	GameLog.log_general("You sell %s for %d copper." % [item.get("name", "an item"), price])
	# consume_one() emits inventory_changed, which _rebuild_sell_list is
	# connected to — only the buy list (afford-state) needs a manual refresh.
	_rebuild_buy_list()


# ===== WINDOW SIZING (matches corpse_loot_window.gd's approach) =====

func _resize_to_content() -> void:
	var buy_min: Vector2 = buy_list.get_combined_minimum_size()
	var sell_min: Vector2 = sell_list.get_combined_minimum_size()
	var widest: float = maxf(buy_min.x, sell_min.x)

	var target_width: float = clamp(widest + 32.0, MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
	panel.offset_right = panel.offset_left + target_width

	buy_scroll.custom_minimum_size.y = minf(buy_min.y, MAX_LIST_HEIGHT)
	sell_scroll.custom_minimum_size.y = minf(sell_min.y, MAX_LIST_HEIGHT)

	var vbox_min: Vector2 = vbox.get_combined_minimum_size()
	panel.offset_bottom = panel.offset_top + vbox_min.y + 16.0


# ===== DRAGGABLE PANEL =====

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not _dragging:
			WindowPosition.save(POSITION_KEY, panel)
	elif event is InputEventMouseMotion and _dragging:
		panel.offset_left += event.relative.x
		panel.offset_top += event.relative.y
		panel.offset_right += event.relative.x
		panel.offset_bottom += event.relative.y
