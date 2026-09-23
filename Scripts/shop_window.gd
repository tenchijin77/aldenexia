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
const MIN_PANEL_HEIGHT := 200.0
const MAX_LIST_HEIGHT := 200.0  # each of the two lists, before it scrolls instead of growing the window
const POSITION_KEY := "shop_window"
const RESIZE_MARGIN := 16.0
var _resizing := false
# Once anything's been saved for this window (a drag OR a resize), stop
# auto-fitting the panel to content on every rebuild — otherwise
# _resize_to_content() (called every time the buy/sell list rebuilds: stock
# change, "usable only" toggle, inventory change) would snap a manually
# resized window straight back to its auto-fit size the next time the player
# so much as picks up an item.
var _user_resized := false

var _vendor: Node = null
var _player: Node = null

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/TitleBar/TitleLabel
@onready var vbox: VBoxContainer = $Panel/Margin/VBox
@onready var coin_label: Label = $Panel/Margin/VBox/CoinLabel
@onready var usable_only_check: CheckBox = $Panel/Margin/VBox/UsableOnlyCheck
@onready var search_box: LineEdit = $Panel/Margin/VBox/SearchBox
@onready var buy_scroll: ScrollContainer = $Panel/Margin/VBox/BuyScroll
@onready var buy_list: VBoxContainer = $Panel/Margin/VBox/BuyScroll/BuyList
@onready var sell_scroll: ScrollContainer = $Panel/Margin/VBox/SellScroll
@onready var sell_list: VBoxContainer = $Panel/Margin/VBox/SellScroll/SellList

var _dragging := false


func _ready() -> void:
	panel.gui_input.connect(_on_panel_gui_input)
	$Panel/Margin/VBox/TitleBar/CloseBtn.pressed.connect(queue_free)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_user_resized = Global.player_data.get("ui_positions", {}).get(POSITION_KEY, []).size() == 4
	WindowPosition.load_full_into(POSITION_KEY, panel)
	Global.currency_changed.connect(_refresh_coin_label)
	Inventory.inventory_changed.connect(_rebuild_sell_list)
	usable_only_check.toggled.connect(func(_pressed: bool): _rebuild_buy_list())
	search_box.text_changed.connect(func(_text: String): _rebuild_buy_list())
	_player = TargetFrame.local_player()


func _exit_tree() -> void:
	Global.restore_mouse_mode()


# A vendor that can leave (the traveling merchant) takes the shop with him: the window closes when he is gone or has stopped
# trading, instead of sitting open on a vendor that no longer exists.
func _process(_delta: float) -> void:
	if _vendor == null:
		return
	if not is_instance_valid(_vendor):
		queue_free()
	elif _vendor.has_method("can_trade") and not _vendor.can_trade():
		GameLog.log_general("%s has stopped trading." % _vendor.get_vendor_display_name())
		queue_free()


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

	var stock: Array = _vendor.get_shop_stock()
	if usable_only_check.button_pressed:
		stock = stock.filter(func(entry): return _is_usable_by_player(entry["item_def"]))
	# Search box: keeps items whose name contains what's typed (any case).
	var search: String = search_box.text.strip_edges().to_lower()
	if not search.is_empty():
		stock = stock.filter(func(entry): return search in str(entry["item_def"].get("name", "")).to_lower())

	if stock.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No items match your search." if not search.is_empty() else "Nothing here you can use."
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		buy_list.add_child(empty_lbl)
	else:
		for entry in stock:
			buy_list.add_child(_make_buy_row(entry))
	_resize_to_content()


# "Usable" = your class/race is allowed to wear/wield/learn it — items.json's
# own class/race arrays already carry exactly this (["all"] or a specific
# list, e.g. a spell scroll's ["voidknight"]), so this reuses that instead of
# inventing a second eligibility system.
func _is_usable_by_player(item_def: Dictionary) -> bool:
	if not is_instance_valid(_player):
		return true
	var player_class: String = str(_player.get("player_class")).to_lower() if "player_class" in _player else ""
	var player_race: String = str(_player.get("player_race")).to_lower() if "player_race" in _player else ""

	var class_list: Array = item_def.get("class", ["all"])
	var class_ok := "all" in class_list or player_class in class_list.map(func(c): return str(c).to_lower())

	var race_list: Array = item_def.get("race", ["all"])
	var race_ok := "all" in race_list or player_race in race_list.map(func(r): return str(r).to_lower())

	return class_ok and race_ok


# Right-click a row (For Sale or Your Items) to see the item's properties and how it compares with what you have equipped.
func _connect_inspect(row: Control, item_def: Dictionary) -> void:
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			row.accept_event()
			ItemInspector.open(item_def, row.get_global_mouse_position(), get_tree()))


func _make_buy_row(entry: Dictionary) -> Control:
	var item_def: Dictionary = entry["item_def"]
	var price: int = entry["price"]

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 38)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.13, 0.92)
	style.set_border_width_all(1)
	style.border_color = Color(0.32, 0.32, 0.32)
	row.add_theme_stylebox_override("panel", style)
	row.tooltip_text = item_def.get("description", "")
	_connect_inspect(row, item_def)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	hbox.add_child(ItemIcon.make_rect(ItemIcon.texture(item_def)))

	var name_lbl := Label.new()
	name_lbl.text = item_def.get("name", entry["item_id"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)

	if ItemInspector.teaches_known_spell(item_def):
		name_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.62))
		var known_lbl := Label.new()
		known_lbl.text = "✔ known"
		known_lbl.tooltip_text = "You already know this spell."
		known_lbl.add_theme_font_size_override("font_size", 11)
		known_lbl.add_theme_color_override("font_color", Color(0.45, 0.85, 0.5))
		known_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(known_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "%d cp" % price
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(price_lbl)

	# Quantity only really matters for stackable items (buying 1 of a weapon
	# at a time is the norm), but there's no harm letting it apply generically
	# — Inventory.add_item() already just adds N separate instances for a
	# non-stackable item_id if asked to.
	var qty_spin := SpinBox.new()
	qty_spin.min_value = 1
	qty_spin.max_value = 99
	qty_spin.value = 1
	qty_spin.custom_minimum_size = Vector2(56, 0)
	hbox.add_child(qty_spin)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size = Vector2(48, 0)
	buy_btn.disabled = not Global.can_afford(price)
	buy_btn.pressed.connect(func(): _buy(entry, int(qty_spin.value)))
	hbox.add_child(buy_btn)

	return row


func _buy(entry: Dictionary, qty: int) -> void:
	var unit_price: int = entry["price"]
	var total_price: int = unit_price * qty
	var item_id: String = entry["item_id"]
	var item_def: Dictionary = entry["item_def"]

	if not Global.can_afford(total_price):
		GameLog.log_general("You can't afford that.")
		return
	if not Inventory.add_item(item_id, qty):
		GameLog.log_general("Your inventory is full.")
		return
	Global.spend_currency_copper(total_price)
	Global.play_coin_sound()  # buying: the same coin sound as selling and looting coin
	var name_str: String = item_def.get("name", item_id) + (" x%d" % qty if qty > 1 else "")
	GameLog.log_general("You purchase %s for %d copper." % [name_str, total_price])
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
	row.custom_minimum_size = Vector2(0, 38)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.13, 0.92)
	style.set_border_width_all(1)
	style.border_color = Color(0.32, 0.32, 0.32)
	row.add_theme_stylebox_override("panel", style)
	_connect_inspect(row, Inventory.get_item_definition(str(item.get("item_id", ""))) if not Inventory.get_item_definition(str(item.get("item_id", ""))).is_empty() else item)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	hbox.add_child(ItemIcon.make_rect(ItemIcon.texture(item)))

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

	# Only a stack of more than one actually needs a quantity picker — a
	# single sword or a lone potion has nothing to pick between.
	var qty_spin: SpinBox = null
	if qty > 1:
		qty_spin = SpinBox.new()
		qty_spin.min_value = 1
		qty_spin.max_value = qty
		qty_spin.value = qty
		qty_spin.custom_minimum_size = Vector2(56, 0)
		hbox.add_child(qty_spin)

	var sell_btn := Button.new()
	sell_btn.text = "Sell"
	sell_btn.custom_minimum_size = Vector2(48, 0)
	sell_btn.pressed.connect(func(): _sell(row_data, int(qty_spin.value) if qty_spin else 1))
	hbox.add_child(sell_btn)

	return row


func _sell(row_data: Dictionary, qty: int) -> void:
	var item: Dictionary = row_data["item"]
	var unit_price: int = _vendor.get_sell_price(item)
	var total_price: int = unit_price * qty

	Inventory.consume_amount(row_data["slot_type"], row_data["slot_index"], row_data["bag_slot"], row_data["item_index"], qty)
	Global.add_currency_copper(total_price)
	Global.play_coin_sound()
	var name_str: String = item.get("name", "an item") + (" x%d" % qty if qty > 1 else "")
	GameLog.log_general("You sell %s for %d copper." % [name_str, total_price])
	# consume_amount() emits inventory_changed, which _rebuild_sell_list is
	# connected to — only the buy list (afford-state) needs a manual refresh.
	_rebuild_buy_list()


# ===== WINDOW SIZING (matches corpse_loot_window.gd's approach) =====

func _resize_to_content() -> void:
	var buy_min: Vector2 = buy_list.get_combined_minimum_size()
	var sell_min: Vector2 = sell_list.get_combined_minimum_size()

	buy_scroll.custom_minimum_size.y = minf(buy_min.y, MAX_LIST_HEIGHT)
	sell_scroll.custom_minimum_size.y = minf(sell_min.y, MAX_LIST_HEIGHT)

	# Once the player's dragged or resized this window, respect that instead
	# of snapping the panel back to its auto-fit size on every list rebuild
	# (stock change, "usable only" toggle, inventory change) — see
	# _user_resized's declaration for why. The scroll min-sizes above still
	# update regardless; they only set each LIST's own floor, which the
	# window's real size (possibly now bigger, via manual resize) simply
	# has room for.
	if _user_resized or not search_box.text.strip_edges().is_empty():
		return  # (and don't shrink the window under the player's cursor on every search keystroke)

	var widest: float = maxf(buy_min.x, sell_min.x)
	var target_width: float = clamp(widest + 32.0, MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
	panel.offset_right = panel.offset_left + target_width

	var vbox_min: Vector2 = vbox.get_combined_minimum_size()
	panel.offset_bottom = panel.offset_top + vbox_min.y + 16.0


# ===== DRAGGABLE / RESIZABLE PANEL =====

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
			panel.offset_left += event.relative.x
			panel.offset_top += event.relative.y
			panel.offset_right += event.relative.x
			panel.offset_bottom += event.relative.y
