# quest_journal.gd — the quest journal (J, player3d.gd toggle_quest_journal()). Lists every quest the character has been
# given (Quests.journal_entries() — a quest is added the moment an NPC or a note starts it, so nothing needs tracking by
# hand), split into Pending and Completed tabs: pending newest first, completed most recently finished first. Selecting a
# quest shows who gave it, its lore, the objective and progress, the rewards, and for a finished quest how it ended.
# A hand-in quest lists every item it asks for as an icon with the number you are carrying on it (dimmed when you have
# none), how many you have handed in, and a tick when that item is done. Refreshes while open when quest progress or
# your bags change.
extends GameWindow
class_name QuestJournal

const POSITION_KEY := "quest_journal"
const REFRESH_SECONDS := 1.0

var _tab := "active"          # "active" (Pending) or "complete" (Completed)
var _selected := ""
var _signature := ""
var _refresh := 0.0
var _pending_btn: Button
var _completed_btn: Button
var _list: VBoxContainer
var _detail_top: RichTextLabel      # name, giver, lore, objective line
var _items_box: VBoxContainer       # one row per item the quest asks for
var _detail_bottom: RichTextLabel   # rewards, outcome

const TILE_SIZE := 40


func _ready() -> void:
	build_frame("Quest Journal", POSITION_KEY, Vector2(640, 420), Vector2(460, 280))
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	_pending_btn = _tab_button("Pending", "active")
	_completed_btn = _tab_button("Completed", "complete")
	tabs.add_child(_pending_btn)
	tabs.add_child(_completed_btn)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 210
	body.add_child(split)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(190, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(detail_scroll)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	detail_scroll.add_child(detail)
	_detail_top = _rich()
	detail.add_child(_detail_top)
	_items_box = VBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 4)
	detail.add_child(_items_box)
	_detail_bottom = _rich()
	detail.add_child(_detail_bottom)
	# What you carry changes the item rows, not just quest progress.
	Inventory.inventory_changed.connect(func(): _signature = "")
	_rebuild()


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 13)
	return r


func _set_detail(top: String, items: Array, bottom: String) -> void:
	_detail_top.text = top
	_detail_bottom.text = bottom
	for child in _items_box.get_children():
		_items_box.remove_child(child)
		child.queue_free()
	for row in items:
		_items_box.add_child(row)


func _tab_button(text: String, tab: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.text = text
	b.pressed.connect(func():
		_tab = tab
		_selected = ""
		_rebuild())
	return b


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_SECONDS
	if JSON.stringify(Global.player_data.get("quests", {})) != _signature:
		_rebuild()


func _rebuild() -> void:
	_signature = JSON.stringify(Global.player_data.get("quests", {}))
	var entries: Array = Quests.journal_entries()
	var pending := entries.filter(func(e): return e["state"] == "active")
	var done := entries.filter(func(e): return e["state"] == "complete")
	pending.sort_custom(func(a, b): return a["started"] > b["started"])
	done.sort_custom(func(a, b): return a["completed"] > b["completed"])
	_pending_btn.text = "Pending (%d)" % pending.size()
	_completed_btn.text = "Completed (%d)" % done.size()
	_pending_btn.button_pressed = _tab == "active"
	_completed_btn.button_pressed = _tab == "complete"

	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var shown: Array = pending if _tab == "active" else done
	if shown.is_empty():
		var none := Label.new()
		none.text = "No pending quests. Talk to people — someone always needs something." if _tab == "active" else "No completed quests yet."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_list.add_child(none)
		_set_detail("", [], "")
		return
	if _selected.is_empty() or not shown.any(func(e): return e["id"] == _selected):
		_selected = shown[0]["id"]
	for entry in shown:
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = entry["id"] == _selected
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		var def: Dictionary = entry["def"]
		b.text = str(def.get("name", entry["id"]))
		if entry["state"] == "active" and int(entry["needed"]) > 0:
			b.text += "  (%d/%d)" % [int(entry["progress"]), int(entry["needed"])]
		var id: String = entry["id"]
		b.pressed.connect(func():
			_selected = id
			_rebuild())
		_list.add_child(b)
		if entry["id"] == _selected:
			_describe(entry)


# Fills the detail pane for one quest.
func _describe(entry: Dictionary) -> void:
	var def: Dictionary = entry["def"]
	var done: bool = entry["state"] == "complete"
	var t := "[font_size=17][color=#ffdd88]%s[/color][/font_size]\n" % def.get("name", entry["id"])
	t += "[color=#aaaaaa]Given by %s  •  %s[/color]\n\n" % [def.get("giver", "someone"), "[color=#88cc88]Completed[/color]" if done else "[color=#ffdd44]In progress[/color]"]
	t += "[i]%s[/i]\n\n" % def.get("summary", def.get("short", ""))
	t += "[color=#e8dcc0][b]Objective[/b][/color]\n"
	var objective: Dictionary = def.get("objective", {})
	var goal := str(def.get("short", ""))
	t += "  • %s\n" % goal
	var rows: Array = []
	var reqs: Dictionary = entry.get("requirements", {})
	if str(objective.get("type", "")) == "hand_in" and not reqs.is_empty():
		t += "  • Bring to %s (drag onto them):" % def.get("giver", "the quest giver")
		for item_id in reqs:
			var need := int(reqs[item_id])
			var given := need if done else int(entry.get("given", {}).get(item_id, 0))
			rows.append(_item_row(str(item_id), given, need, done))
	var b := ""
	var rewards := _rewards_text(def.get("rewards", {}))
	if not rewards.is_empty():
		b += "[color=#e8dcc0][b]Rewards[/b][/color]\n  %s\n" % rewards
	if done and not str(def.get("texts", {}).get("complete", "")).is_empty():
		b += "\n[color=#e8dcc0][b]Outcome[/b][/color]\n[color=#cfc6b0]%s[/color]\n" % def["texts"]["complete"]
	_set_detail(t, rows, b)


# One required item: its icon with the number you carry in the corner (dimmed if none), then its name and
# "given N / M · carrying K" — green with a tick once enough has been handed in.
func _item_row(item_id: String, given: int, need: int, quest_done: bool) -> Control:
	var def: Dictionary = Inventory.get_item_definition(item_id)
	var carrying := 0 if quest_done else ItemHelper.count(item_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tile := Control.new()
	tile.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.tooltip_text = str(def.get("name", item_id))
	var icon := ItemIcon.make_rect(ItemIcon.texture(def), TILE_SIZE)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	if carrying <= 0 and given < need:
		icon.modulate = Color(1, 1, 1, 0.35)
	tile.add_child(icon)
	if carrying > 0:
		var qty := Label.new()
		qty.text = str(carrying)
		qty.add_theme_font_size_override("font_size", 12)
		qty.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		qty.add_theme_constant_override("outline_size", 4)
		qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		qty.grow_vertical = Control.GROW_DIRECTION_BEGIN
		qty.position = Vector2(TILE_SIZE - 4, TILE_SIZE - 2)
		tile.add_child(qty)
	row.add_child(tile)
	var text := Label.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 13)
	var finished := given >= need
	var status := "given %d / %d" % [given, need]
	if not finished and not quest_done:
		status += "  ·  carrying %d" % carrying
		if carrying >= need - given:
			status += " — enough"
	text.text = "%s%s\n%s" % ["✔ " if finished else "", def.get("name", item_id), status]
	var colour := Color(0.55, 0.85, 0.55) if finished else (Color(0.95, 0.85, 0.45) if carrying >= need - given else Color(0.82, 0.82, 0.82))
	text.add_theme_color_override("font_color", colour)
	row.add_child(text)
	return row


func _rewards_text(rewards: Dictionary) -> String:
	var parts: Array = []
	if int(rewards.get("xp", 0)) > 0:
		parts.append("%d experience" % int(rewards["xp"]))
	if not str(rewards.get("note", "")).is_empty():
		parts.append(str(rewards["note"]))
	for coin in rewards.get("coin", {}):
		parts.append("%d %s" % [int(rewards["coin"][coin]), coin])
	for item in rewards.get("items", []):
		var name := str(Inventory.get_item_definition(str(item.get("id", ""))).get("name", item.get("id", "")))
		parts.append("%s%s" % [name, (" x%d" % int(item.get("qty", 1))) if int(item.get("qty", 1)) > 1 else ""])
	return ", ".join(parts)
