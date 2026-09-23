# quest_journal.gd — the quest journal (J, player3d.gd toggle_quest_journal()). Lists every quest the character has been
# given (Quests.journal_entries() — a quest is added the moment an NPC or a note starts it, so nothing needs tracking by
# hand), split into Pending and Completed tabs: pending newest first, completed most recently finished first. Selecting a
# quest shows who gave it, its lore, the objective and progress, the rewards, and for a finished quest how it ended.
# Refreshes itself while open when quest progress changes.
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
var _detail: RichTextLabel


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
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 13)
	split.add_child(_detail)
	_rebuild()


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
		_detail.text = ""
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
			_detail.text = _describe(entry)


# The detail pane for one quest, as BBCode.
func _describe(entry: Dictionary) -> String:
	var def: Dictionary = entry["def"]
	var done: bool = entry["state"] == "complete"
	var t := "[font_size=17][color=#ffdd88]%s[/color][/font_size]\n" % def.get("name", entry["id"])
	t += "[color=#aaaaaa]Given by %s  •  %s[/color]\n\n" % [def.get("giver", "someone"), "[color=#88cc88]Completed[/color]" if done else "[color=#ffdd44]In progress[/color]"]
	t += "[i]%s[/i]\n\n" % def.get("summary", def.get("short", ""))
	t += "[color=#e8dcc0][b]Objective[/b][/color]\n"
	var objective: Dictionary = def.get("objective", {})
	var goal := str(def.get("short", ""))
	if str(objective.get("type", "")) == "hand_in":
		var item_name := str(Inventory.get_item_definition(str(objective.get("item", ""))).get("name", objective.get("item", "")))
		var have := int(entry["needed"]) if done else int(entry["progress"])
		t += "  • %s\n  • %s given to %s: [b]%d / %d[/b]\n" % [goal, item_name, def.get("giver", "the quest giver"), have, int(entry["needed"])]
	else:
		t += "  • %s\n" % goal
	var rewards := _rewards_text(def.get("rewards", {}))
	if not rewards.is_empty():
		t += "\n[color=#e8dcc0][b]Rewards[/b][/color]\n  %s\n" % rewards
	if done and not str(def.get("texts", {}).get("complete", "")).is_empty():
		t += "\n[color=#e8dcc0][b]Outcome[/b][/color]\n[color=#cfc6b0]%s[/color]\n" % def["texts"]["complete"]
	return t


func _rewards_text(rewards: Dictionary) -> String:
	var parts: Array = []
	if int(rewards.get("xp", 0)) > 0:
		parts.append("%d experience" % int(rewards["xp"]))
	for coin in rewards.get("coin", {}):
		parts.append("%d %s" % [int(rewards["coin"][coin]), coin])
	for item in rewards.get("items", []):
		var name := str(Inventory.get_item_definition(str(item.get("id", ""))).get("name", item.get("id", "")))
		parts.append("%s%s" % [name, (" x%d" % int(item.get("qty", 1))) if int(item.get("qty", 1)) > 1 else ""])
	return ", ".join(parts)
