# tradeskill_window.gd — generic crafting window shared by every tradeskill
# station (campfire cooking, the basic alchemy kit, and whatever's added
# later — a stove, a forge, etc. all reuse this same window). Recipes live in
# Data/tradeskill_recipes.json keyed by station_id; this script never needs
# to know what a station actually makes. setup() is called once right after
# instantiation with the station's id, display title (the name of the
# specific item/node that opened it, per the user's spec — different fire
# types will show different titles even though they might share a station_id
# or not), and the action button's label ("Cook"/"Mix"/etc).
extends CanvasLayer
class_name TradeskillWindow

const SLOT_COUNT := 4
const POSITION_KEY_PREFIX := "tradeskill_"
const RECIPES_PATH := "res://Data/tradeskill_recipes.json"
const RESIZE_MARGIN := 16.0
const MIN_WIDTH := 240.0
const MIN_HEIGHT := 180.0

var _station_id: String = ""
var _recipes: Array = []
var _dragging := false
var _resizing := false
var _crafting := false
var _craft_elapsed := 0.0
var _craft_recipe: Dictionary = {}
var _craft_multiplier := 1

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/TitleBar/TitleLabel
@onready var close_btn: Button = $Panel/Margin/VBox/TitleBar/CloseBtn
@onready var slot_row: HBoxContainer = $Panel/Margin/VBox/SlotRow
@onready var action_btn: Button = $Panel/Margin/VBox/ActionBtn
@onready var progress_bar: ProgressBar = $Panel/Margin/VBox/ProgressBar
@onready var status_label: Label = $Panel/Margin/VBox/StatusLabel


func _ready() -> void:
	panel.gui_input.connect(_on_panel_gui_input)
	close_btn.pressed.connect(_on_close_pressed)
	action_btn.pressed.connect(_on_action_pressed)
	progress_bar.visible = false
	for slot in slot_row.get_children():
		slot.contents_changed.connect(_refresh_status)


func _exit_tree() -> void:
	# Crafting is blocked from closing (see _on_close_pressed), but if the
	# window is force-freed some other way, refund whatever's staged rather
	# than silently destroying the player's items.
	if not _crafting:
		for slot in slot_row.get_children():
			if slot is TradeskillSlot and not slot.is_empty():
				Inventory.add_item(slot.held_item_id, slot.held_quantity)


func setup(station_id: String, title: String, action_label: String) -> void:
	_station_id = station_id
	title_label.text = title
	action_btn.text = action_label
	WindowPosition.load_full_into(POSITION_KEY_PREFIX + station_id, panel)
	_load_recipes()
	_refresh_status()


func _load_recipes() -> void:
	var file := FileAccess.open(RECIPES_PATH, FileAccess.READ)
	if not file:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) == TYPE_DICTIONARY:
		_recipes = data.get(_station_id, [])


func _staged_ingredients() -> Dictionary:
	var staged: Dictionary = {}
	for slot in slot_row.get_children():
		if slot is TradeskillSlot and not slot.is_empty():
			staged[slot.held_item_id] = staged.get(slot.held_item_id, 0) + slot.held_quantity
	return staged


# Returns {"recipe": {...}, "multiplier": N} for the first recipe whose
# ingredient TYPES exactly match what's staged (no extra/missing items,
# same as before), where N is how many times it divides evenly into the
# staged amounts — a stack of 4 raw meat against a 1-raw-meat recipe crafts
# all 4 at once instead of requiring an exact 1:1 amount. Empty dict if
# nothing matches.
func _find_best_recipe() -> Dictionary:
	var staged := _staged_ingredients()
	if staged.is_empty():
		return {}
	for recipe in _recipes:
		var ingredients: Dictionary = recipe.get("ingredients", {})
		var multiplier := _compute_multiplier(ingredients, staged)
		if multiplier > 0:
			return {"recipe": recipe, "multiplier": multiplier}
	return {}


# JSON.parse_string() always produces floats for whole numbers (e.g. a JSON
# "1" becomes 1.0), hence the int() casts throughout rather than relying on
# == to coerce them the way scalar comparisons would.
func _compute_multiplier(recipe_ingredients: Dictionary, staged: Dictionary) -> int:
	if recipe_ingredients.size() != staged.size():
		return 0
	var multiplier := -1
	for key in recipe_ingredients:
		if not staged.has(key):
			return 0
		var need: int = int(recipe_ingredients[key])
		if need <= 0:
			return 0
		var this_multiplier: int = int(staged[key]) / need
		if this_multiplier <= 0:
			return 0
		multiplier = this_multiplier if multiplier == -1 else mini(multiplier, this_multiplier)
	return maxi(multiplier, 0)


func _refresh_status() -> void:
	if _crafting:
		return
	var found := _find_best_recipe()
	action_btn.disabled = found.is_empty()
	if _staged_ingredients().is_empty():
		status_label.text = "Drag items in to combine them."
	elif found.is_empty():
		status_label.text = "You don't know a way to combine these items."
	elif found.get("multiplier", 1) > 1:
		status_label.text = "Ready to make %d." % found["multiplier"]
	else:
		status_label.text = "Ready."


func _on_action_pressed() -> void:
	var found := _find_best_recipe()
	if found.is_empty() or _crafting:
		return
	_craft_recipe = found["recipe"]
	_craft_multiplier = found["multiplier"]
	_crafting = true
	_craft_elapsed = 0.0
	action_btn.disabled = true
	close_btn.disabled = true
	progress_bar.visible = true
	progress_bar.value = 0.0
	status_label.text = "Working..."


func _process(delta: float) -> void:
	if not _crafting:
		return
	_craft_elapsed += delta
	var craft_time: float = float(_craft_recipe.get("craft_time", 3.0))
	progress_bar.value = clampf(_craft_elapsed / craft_time, 0.0, 1.0) * 100.0
	if _craft_elapsed >= craft_time:
		_finish_craft()


func _finish_craft() -> void:
	var output: String = _craft_recipe.get("output", "")
	var output_qty: int = int(_craft_recipe.get("output_quantity", 1)) * _craft_multiplier
	var ingredients: Dictionary = _craft_recipe.get("ingredients", {})
	for slot in slot_row.get_children():
		if slot is TradeskillSlot and not slot.is_empty():
			var consume: int = int(ingredients.get(slot.held_item_id, 0)) * _craft_multiplier
			if consume > 0:
				slot.remove_quantity(consume)
	if not output.is_empty():
		if Inventory.add_item(output, output_qty):
			var display_name: String = Inventory.get_item_definition(output).get("name", output)
			GameLog.log_general("[color=#88ffaa]You create [b]%d %s[/b].[/color]" % [output_qty, display_name])
		else:
			GameLog.log_general("[color=#ff8866]Your inventory is full — the result is lost![/color]")
	_crafting = false
	_craft_recipe = {}
	_craft_multiplier = 1
	close_btn.disabled = false
	progress_bar.visible = false
	_refresh_status()


func _on_close_pressed() -> void:
	if _crafting:
		return
	queue_free()


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
				WindowPosition.save(POSITION_KEY_PREFIX + _station_id, panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _resizing:
			panel.offset_right  = max(panel.offset_left + MIN_WIDTH, panel.offset_right + event.relative.x)
			panel.offset_bottom = max(panel.offset_top + MIN_HEIGHT, panel.offset_bottom + event.relative.y)
		elif _dragging:
			panel.offset_left   += event.relative.x
			panel.offset_top    += event.relative.y
			panel.offset_right  += event.relative.x
			panel.offset_bottom += event.relative.y
