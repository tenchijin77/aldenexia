# tradeskill_window.gd — generic crafting window shared by every tradeskill
# station (campfire cooking, the basic alchemy kit, and whatever's added
# later — a stove, a forge, etc. all reuse this same window). Recipes live in
# Data/tradeskill_recipes.json (generated from the crafting workbook by
# tools/export_crafting.py), each listing the station ids it can be made at;
# this script never needs to know what a station actually makes.
# Rules (Crafting.xlsx, Rules tab): success = base + 1% per skill point above
# the recipe's min skill (max 98%); a success can crit for the crit yield; a
# failure uses up the ingredients; skill-ups stop at the recipe's max level
# and a failed craft trains at a quarter of the usual chance. setup() is called once right after
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

const MAX_SUCCESS := 0.98
const FAIL_GAIN_MULT := 0.25

var _station_id: String = ""
var _recipes: Array = []          # [{id, recipe}] — every recipe that can be made at this station
var _groups: Dictionary = {}      # ingredient group id (e.g. cooked_meat_any) -> Array of item ids it accepts
var _dragging := false
var _resizing := false
var _crafting := false
var _craft_elapsed := 0.0        # seconds into the item being made right now
var _craft_recipe: Dictionary = {}
var _craft_recipe_id := ""
var _craft_uses: Dictionary = {}  # {staged item id: qty per craft} for the recipe being made
var _craft_multiplier := 1       # how many items this batch makes in total
var _craft_done := 0             # how many are finished so far
var _craft_started_msec := 0     # when the batch began (an attack after this interrupts it)
var _action_label := ""

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
	# Whatever is still in the ingredient slots goes back to the bags when the window closes — however it closes (the ✕,
	# walking away, logging out, even mid-batch: a batch only uses up one set per item as each one finishes). If the bags
	# are full, the rest is put down at your feet in a pouch (world_items.gd) instead of being lost.
	var player := TargetFrame.local_player() as Node3D
	if _crafting and is_instance_valid(player) and player.has_method("clear_task_progress"):
		player.clear_task_progress()
	var dropped: Array = []
	for slot in slot_row.get_children():
		if slot is TradeskillSlot and not slot.is_empty():
			if not Inventory.add_item(slot.held_item_id, slot.held_quantity):
				dropped.append(Inventory.create_item_instance(slot.held_item_id, slot.held_quantity))
	var world_items := get_tree().get_first_node_in_group("world_items") if is_inside_tree() else null
	for item in dropped:
		if world_items != null and is_instance_valid(player):
			world_items.drop(item, player.global_position, str(player.get("player_name")))
			GameLog.log_general("[color=#ff8866]Your bags are full — you set %s down at your feet.[/color]" % str(item.get("name", "it")))


func setup(station_id: String, title: String, action_label: String) -> void:
	_station_id = station_id
	title_label.text = title
	_action_label = action_label
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
	if typeof(data) != TYPE_DICTIONARY:
		return
	_groups = data.get("ingredient_groups", {})
	var all_recipes: Dictionary = data.get("recipes", {})
	for recipe_id in all_recipes:
		var recipe: Dictionary = all_recipes[recipe_id]
		if _station_id in recipe.get("stations", []):
			_recipes.append({"id": recipe_id, "recipe": recipe})


func _staged_ingredients() -> Dictionary:
	var staged: Dictionary = {}
	for slot in slot_row.get_children():
		if slot is TradeskillSlot and not slot.is_empty():
			staged[slot.held_item_id] = staged.get(slot.held_item_id, 0) + slot.held_quantity
	return staged


# Returns {"id", "recipe", "multiplier", "uses": {item_id: qty per craft}} for the first recipe whose ingredients exactly
# cover what's staged (no extra/missing item types), where multiplier is how many times it divides evenly into the staged
# amounts — a stack of 4 raw meat against a 1-raw-meat recipe crafts all 4. A group ingredient (cooked_meat_any) is
# filled by any ONE staged item type from its group. Empty dict if nothing matches.
func _find_best_recipe() -> Dictionary:
	var staged := _staged_ingredients()
	if staged.is_empty():
		return {}
	for entry in _recipes:
		var uses := _resolve_ingredients(entry["recipe"].get("ingredients", {}), staged)
		if uses.is_empty():
			continue
		var multiplier := _compute_multiplier(uses, staged)
		if multiplier > 0:
			return {"id": entry["id"], "recipe": entry["recipe"], "multiplier": multiplier, "uses": uses}
	return {}


# Maps a recipe's ingredient keys onto the staged item ids ({staged_item_id: qty per craft}), or {} if they don't
# line up one-to-one. JSON numbers arrive as floats, hence the int() casts.
func _resolve_ingredients(ingredients: Dictionary, staged: Dictionary) -> Dictionary:
	if ingredients.size() != staged.size():
		return {}
	var uses: Dictionary = {}
	for key in ingredients:
		var need: int = int(ingredients[key])
		if need <= 0:
			return {}
		if staged.has(key) and not uses.has(key):
			uses[key] = need
			continue
		var matched := ""
		for item_id in _groups.get(key, []):
			if staged.has(item_id) and not uses.has(item_id):
				matched = item_id
				break
		if matched.is_empty():
			return {}
		uses[matched] = need
	return uses if uses.size() == staged.size() else {}


func _compute_multiplier(uses: Dictionary, staged: Dictionary) -> int:
	var multiplier := -1
	for item_id in uses:
		var this_multiplier: int = int(staged[item_id]) / int(uses[item_id])
		if this_multiplier <= 0:
			return 0
		multiplier = this_multiplier if multiplier == -1 else mini(multiplier, this_multiplier)
	return maxi(multiplier, 0)


# Why the local player can't make a matched recipe ("" if they can): not learned yet, or skill too low.
func _blocked_reason(recipe_id: String, recipe: Dictionary) -> String:
	var player := TargetFrame.local_player()
	if not is_instance_valid(player):
		return ""
	if player.has_method("knows_recipe") and not player.knows_recipe(recipe_id, recipe):
		return "You haven't learned how to make %s yet." % recipe.get("name", "that")
	var skill_name: String = str(recipe.get("skill", ""))
	var have: int = int(player.skill_levels.get(skill_name, 0)) if "skill_levels" in player else 0
	var need: int = int(recipe.get("min_skill", 0))
	if have < need:
		return "You need %s %d to make %s (you have %d)." % [skill_name.capitalize(), need, recipe.get("name", "that"), have]
	return ""


func _refresh_status() -> void:
	if _crafting:
		return
	var found := _find_best_recipe()
	var blocked := "" if found.is_empty() else _blocked_reason(found["id"], found["recipe"])
	action_btn.disabled = found.is_empty() or not blocked.is_empty()
	if _staged_ingredients().is_empty():
		status_label.text = "Drag items in to combine them."
	elif found.is_empty():
		status_label.text = "You don't know a way to combine these items."
	elif not blocked.is_empty():
		status_label.text = blocked
	elif found.get("multiplier", 1) > 1:
		status_label.text = "Ready to make %d %s." % [found["multiplier"], found["recipe"].get("name", "")]
	else:
		status_label.text = "Ready to make %s." % found["recipe"].get("name", "")


func _on_action_pressed() -> void:
	if _crafting:
		_stop_crafting("You stop.")  # the button reads "Stop" while a batch is running
		return
	var found := _find_best_recipe()
	if found.is_empty():
		return
	if not _blocked_reason(found["id"], found["recipe"]).is_empty():
		return
	_craft_recipe = found["recipe"]
	_craft_recipe_id = found["id"]
	_craft_uses = found["uses"]
	_craft_multiplier = found["multiplier"]
	_crafting = true
	_craft_elapsed = 0.0
	_craft_done = 0
	_craft_started_msec = Time.get_ticks_msec()
	action_btn.text = "Stop"
	close_btn.disabled = true
	progress_bar.visible = true
	progress_bar.value = 0.0
	_update_batch_status()


# A batch is made ONE ITEM AT A TIME, each taking the recipe's craft_time: 11 raw meat is 11 x the time to cook one, and every item
# made is its own chance to raise the skill (before, the whole stack was made in a single craft_time with a single skill roll, so
# crafting in bulk could not level you up). The bar shows the whole batch.
func _process(delta: float) -> void:
	if not _crafting:
		return
	var player := TargetFrame.local_player()
	if is_instance_valid(player) and "last_attacked_msec" in player and player.last_attacked_msec > _craft_started_msec:
		_stop_crafting("You are attacked and lose your concentration.")
		return
	_craft_elapsed += delta
	var craft_time: float = maxf(float(_craft_recipe.get("craft_time", 3.0)), 0.1)
	progress_bar.value = (float(_craft_done) + clampf(_craft_elapsed / craft_time, 0.0, 1.0)) / float(_craft_multiplier) * 100.0
	if is_instance_valid(player) and player.has_method("set_task_progress"):
		var title: String = str(_craft_recipe.get("name", "Crafting"))
		if _craft_multiplier > 1:
			title += " (%d/%d)" % [_craft_done + 1, _craft_multiplier]
		player.set_task_progress(title, _craft_elapsed / craft_time, craft_time - _craft_elapsed)
	if _craft_elapsed >= craft_time:
		_craft_elapsed -= craft_time
		if not _make_one():
			return
		_craft_done += 1
		if _craft_done >= _craft_multiplier:
			_stop_crafting("")
		else:
			_update_batch_status()


func _update_batch_status() -> void:
	status_label.text = "Working... %d of %d" % [_craft_done + 1, _craft_multiplier] if _craft_multiplier > 1 else "Working..."


# Makes one: uses up one set of ingredients and rolls the craft. Success gives the yield (or the crit yield), failure
# gives nothing — the ingredients are gone either way. False (and the batch stops) if the bags are full.
func _make_one() -> bool:
	var output: String = _craft_recipe.get("output", "")
	var player := TargetFrame.local_player()
	var skill_name: String = str(_craft_recipe.get("skill", ""))
	var skill: int = int(player.skill_levels.get(skill_name, 0)) if is_instance_valid(player) and "skill_levels" in player else 0
	var success := randf() < success_chance(_craft_recipe, skill)
	var crit := success and randf() < float(_craft_recipe.get("crit_chance", 0.0))
	var output_qty: int = int(_craft_recipe.get("crit_yield" if crit else "yield", 1))
	if success and not output.is_empty() and not Inventory.add_item(output, output_qty):
		_stop_crafting("Your inventory is full, so you stop.")
		return false
	var left: Dictionary = _craft_uses.duplicate()  # one set, even when an ingredient is split across two slots
	for slot in slot_row.get_children():
		if slot is TradeskillSlot and not slot.is_empty():
			var take: int = mini(int(left.get(slot.held_item_id, 0)), slot.held_quantity)
			if take > 0:
				left[slot.held_item_id] = int(left[slot.held_item_id]) - take
				slot.remove_quantity(take)
	var display_name: String = Inventory.get_item_definition(output).get("name", output)
	if not success:
		GameLog.log_general("[color=#ff8866]You fail to make %s. The ingredients are ruined.[/color]" % display_name)
	elif crit:
		GameLog.log_general("[color=#ffdd44]Excellent work! You create [b]%d %s[/b].[/color]" % [output_qty, display_name])
	else:
		GameLog.log_general("[color=#88ffaa]You create [b]%d %s[/b].[/color]" % [output_qty, display_name])
	if success and _craft_done == 0 and not str(_craft_recipe.get("craft_message", "")).is_empty():
		GameLog.log_general("[color=#b8b0a0]%s[/color]" % _craft_recipe["craft_message"])
	if success and is_instance_valid(player) and player.has_method("record_craft"):
		player.record_craft(_craft_recipe_id, display_name)
	_tick_tradeskill(skill, 1.0 if success else FAIL_GAIN_MULT)  # one skill roll per item made
	return true


# Chance to succeed: the recipe's base chance + 1% per skill point above its min skill, capped at 98%.
static func success_chance(recipe: Dictionary, skill: int) -> float:
	var above: int = maxi(skill - int(recipe.get("min_skill", 0)), 0)
	return minf(float(recipe.get("base_success", 1.0)) + 0.01 * above, MAX_SUCCESS)


# Ends the batch (finished, stopped by the player, interrupted, or the bags filled). What is already made is kept and the
# ingredients not yet used stay in the slots.
func _stop_crafting(message: String) -> void:
	if not _crafting:
		return
	_crafting = false
	_craft_recipe = {}
	_craft_uses = {}
	var player := TargetFrame.local_player()
	if is_instance_valid(player) and player.has_method("clear_task_progress"):
		player.clear_task_progress()
	_craft_multiplier = 1
	_craft_done = 0
	_craft_elapsed = 0.0
	action_btn.text = _action_label
	close_btn.disabled = false
	progress_bar.visible = false
	if not message.is_empty():
		GameLog.log_general("[color=#ffaa66]%s[/color]" % message)
	_refresh_status()


# Every craft attempt is a chance to raise the recipe's skill (player3d.gd's _tick_skill(), the same "use it to level it"
# roll every combat skill uses) — until the skill reaches the recipe's max level, when the recipe is trivial.
func _tick_tradeskill(skill: int, gain_mult: float) -> void:
	var skill_name: String = str(_craft_recipe.get("skill", ""))
	if skill_name.is_empty() or skill >= int(_craft_recipe.get("max_level", 9999)):
		return
	var player := TargetFrame.local_player()
	if is_instance_valid(player) and player.has_method("_tick_skill"):
		player._tick_skill(skill_name, gain_mult)


func _on_close_pressed() -> void:
	if _crafting:
		return  # press Stop first
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
