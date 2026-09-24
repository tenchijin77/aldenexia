# chat_tabs.gd — The chat window's tabs and their filters (used by game_log_window.gd).
#
# Every message has a CATEGORY (GameLog.classify(): say, tell, party, zone, npc, loot, xp, skill, quest, system; combat and combat_other come
# from the combat log). Each tab lists the categories it shows, so a tab is just a filter: a message appears in EVERY tab that shows its
# category (adding a Tell tab does not take tells out of General). A history of the last messages lets a tab be rebuilt when its filter
# changes ("show me what this would have shown").
#   "+"             adds a tab (starts with the chat channels: say, tell, party, zone)
#   right-click a tab: Rename, Filters (tick the categories it shows), Detach to its own window, Clear, Close (your own tabs)
#   an unread tab's name flashes until you look at it
# Tabs, names, filters and detached windows are saved per character (Global.player_data["chat_tabs"]).
# No class_name on purpose: game_log_window.gd preloads it (a brand-new class name is unknown to Godot until its class cache is rebuilt).
extends Node

const CATEGORIES := [
	["system", "General / system"], ["say", "Say"], ["tell", "Tell"], ["party", "Party"], ["zone", "Zone (shout)"],
	["npc", "NPC speech"], ["loot", "Loot & coin"], ["xp", "Experience & levels"], ["skill", "Skill-ups"], ["quest", "Quests"],
	["combat", "Combat: you"], ["combat_other", "Combat: others nearby"],
]
const DEFAULT_GENERAL := ["system", "say", "tell", "party", "zone", "npc", "loot", "xp", "skill", "quest"]
const DEFAULT_COMBAT := ["combat", "combat_other"]
const DEFAULT_NEW := ["say", "tell", "party", "zone"]
const HISTORY_MAX := 1500
const MAX_LINES := 200
const FLASH_SECONDS := 0.6
const DRAG_BAR_H := 22.0
const MENU_RENAME := 1
const MENU_DETACH := 3
const MENU_CLEAR := 4
const MENU_CLOSE := 5
const FILTER_ALL := 100
const FILTER_NONE := 101

var cfgs: Array = []          # {id, title, cats (Dictionary category -> true), custom, control, log, unread, detached, window}
var _win: Node = null         # the GameLogWindow
var _tabs: TabContainer = null
var _panel: Control = null
var _history: Array = []      # {cat, text, stamp}
var _flash_on := false
var _tab_menu: PopupMenu = null
var _filter_menu: PopupMenu = null
var _menu_cfg: Dictionary = {}
var _rename_edit: LineEdit = null
var _rename_cfg: Dictionary = {}
var _next_id := 1
var _loading := false


# general / combat: {"control": Control, "log": RichTextLabel} — the two tabs the scene already has.
func setup(window: Node, tabs: TabContainer, panel: Control, general: Dictionary, combat: Dictionary) -> void:
	_win = window
	_tabs = tabs
	_panel = panel
	cfgs.append(_make_cfg("general", "General", DEFAULT_GENERAL, false, general["control"], general["log"]))
	cfgs.append(_make_cfg("combat", "Combat", DEFAULT_COMBAT, false, combat["control"], combat["log"]))
	_build_ui()
	_loading = true
	_load()
	_loading = false
	_refresh_titles()


func _make_cfg(id: String, title: String, cats: Array, custom: bool, control: Control, log: RichTextLabel) -> Dictionary:
	var set_of := {}
	for c in cats:
		set_of[c] = true
	return {"id": id, "title": title, "cats": set_of, "custom": custom, "control": control, "log": log, "unread": false, "detached": false, "window": null}


func _build_ui() -> void:
	var plus := Button.new()
	plus.text = "+"
	plus.tooltip_text = "Add a chat tab (right-click a tab to rename it, pick what it shows, or detach it)"
	plus.focus_mode = Control.FOCUS_NONE
	plus.add_theme_font_size_override("font_size", 13)
	plus.anchor_left = 1.0
	plus.anchor_right = 1.0
	plus.offset_left = -28.0
	plus.offset_right = -6.0
	plus.offset_top = DRAG_BAR_H + 5.0
	plus.offset_bottom = DRAG_BAR_H + 26.0
	plus.pressed.connect(func() -> void: add_tab())
	_panel.add_child(plus)

	_tab_menu = PopupMenu.new()
	_tab_menu.add_item("Rename", MENU_RENAME)
	_filter_menu = PopupMenu.new()
	_filter_menu.name = "Filters"
	_filter_menu.hide_on_checkable_item_selection = false   # stays open while you tick several
	for i in CATEGORIES.size():
		_filter_menu.add_check_item(CATEGORIES[i][1], i)
	_filter_menu.add_separator()
	_filter_menu.add_item("Show everything", FILTER_ALL)
	_filter_menu.add_item("Show nothing", FILTER_NONE)
	_filter_menu.id_pressed.connect(_on_filter_pressed)
	_tab_menu.add_child(_filter_menu)
	_tab_menu.add_submenu_node_item("Filters", _filter_menu)
	_tab_menu.add_item("Detach to its own window", MENU_DETACH)
	_tab_menu.add_item("Clear this tab", MENU_CLEAR)
	_tab_menu.add_item("Close tab", MENU_CLOSE)
	_tab_menu.id_pressed.connect(_on_menu_pressed)
	_panel.add_child(_tab_menu)

	_rename_edit = LineEdit.new()
	_rename_edit.visible = false
	_rename_edit.max_length = 20
	_rename_edit.add_theme_font_size_override("font_size", 12)
	_rename_edit.text_submitted.connect(_finish_rename)
	_rename_edit.focus_exited.connect(func() -> void: _finish_rename(_rename_edit.text))
	_panel.add_child(_rename_edit)

	var bar := _tabs.get_tab_bar()
	bar.gui_input.connect(_on_tab_bar_input)
	_tabs.tab_changed.connect(_on_tab_changed)

	var timer := Timer.new()
	timer.wait_time = FLASH_SECONDS
	timer.timeout.connect(_on_flash)
	add_child(timer)
	timer.start()


# ── Messages in ──
func route(category: String, text: String, stamp: String) -> void:
	_history.append({"cat": category, "text": text, "stamp": stamp})
	if _history.size() > HISTORY_MAX:
		_history = _history.slice(_history.size() - HISTORY_MAX)
	var current: Control = _tabs.get_current_tab_control()
	for cfg in cfgs:
		if not cfg["cats"].has(category):
			continue
		_append_line(cfg["log"], stamp, text)
		if cfg["control"] != current and not cfg["detached"]:
			cfg["unread"] = true


func _append_line(log: RichTextLabel, stamp: String, text: String) -> void:
	if log.get_paragraph_count() > MAX_LINES:
		log.clear()
	log.append_text(stamp + text + "\n")


func _rebuild(cfg: Dictionary) -> void:
	var log: RichTextLabel = cfg["log"]
	log.clear()
	var matching: Array = _history.filter(func(e): return cfg["cats"].has(e["cat"]))
	if matching.size() > MAX_LINES:
		matching = matching.slice(matching.size() - MAX_LINES)
	for e in matching:
		log.append_text(e["stamp"] + e["text"] + "\n")


func apply_font_size(size: int) -> void:
	for cfg in cfgs:
		if cfg["custom"] and is_instance_valid(cfg["log"]):
			cfg["log"].add_theme_font_size_override("normal_font_size", size)


# ── Tabs ──
func add_tab(title: String = "", cats: Array = DEFAULT_NEW, id: String = "", select: bool = true) -> Dictionary:
	if id.is_empty():
		id = "chat%d" % _next_id
		while _id_taken(id):
			_next_id += 1
			id = "chat%d" % _next_id
	_next_id += 1
	if title.is_empty():
		title = "Chat %d" % (cfgs.size() - 1)
	var control := Control.new()
	control.name = id
	var log := RichTextLabel.new()
	log.bbcode_enabled = true
	log.scroll_following = true
	log.focus_mode = Control.FOCUS_NONE
	GameLogWindow.make_copyable(log)
	log.set_anchors_preset(Control.PRESET_FULL_RECT)
	log.add_theme_font_size_override("normal_font_size", int(_win.get("_font_size")))
	if _win.has_method("_on_meta_clicked"):
		log.meta_clicked.connect(_win._on_meta_clicked)
	control.add_child(log)
	_tabs.add_child(control)
	var cfg := _make_cfg(id, title, cats, true, control, log)
	cfgs.append(cfg)
	_rebuild(cfg)
	if select:
		_tabs.current_tab = _tabs.get_tab_idx_from_control(control)   # (just added, so it is a child)
	_refresh_titles()
	_save()
	return cfg


func _id_taken(id: String) -> bool:
	for cfg in cfgs:
		if cfg["id"] == id:
			return true
	return false


func find(id: String) -> Dictionary:
	for cfg in cfgs:
		if cfg["id"] == id:
			return cfg
	return {}


func close_tab(cfg: Dictionary) -> void:
	if not cfg["custom"]:
		return
	if cfg["detached"]:
		reattach(cfg)
	_tabs.remove_child(cfg["control"])
	cfg["control"].queue_free()
	cfgs.erase(cfg)
	_save()


func rename_tab(cfg: Dictionary, title: String) -> void:
	var clean := title.strip_edges()
	if clean.is_empty():
		return
	cfg["title"] = clean.substr(0, 20)
	if cfg["window"] != null:
		cfg["window"]["title"].text = cfg["title"]
	_refresh_titles()
	_save()


func set_categories(cfg: Dictionary, cats: Array) -> void:
	var set_of := {}
	for c in cats:
		set_of[c] = true
	cfg["cats"] = set_of
	_rebuild(cfg)
	_save()


# ── Flashing ──
func _on_flash() -> void:
	_flash_on = not _flash_on
	_refresh_titles()


func _on_tab_changed(_idx: int) -> void:
	var current: Control = _tabs.get_current_tab_control()
	for cfg in cfgs:
		if cfg["control"] == current:
			cfg["unread"] = false
	_refresh_titles()


func title_shown(cfg: Dictionary) -> String:
	return "» %s «" % cfg["title"] if (cfg["unread"] and _flash_on) else str(cfg["title"])


# The tab's position in the tab bar, -1 when it is popped out into its own window.
func _idx_of(cfg: Dictionary) -> int:
	return _tabs.get_tab_idx_from_control(cfg["control"]) if cfg["control"].get_parent() == _tabs else -1


func _refresh_titles() -> void:
	for cfg in cfgs:
		var idx := _idx_of(cfg)
		if idx >= 0:
			_tabs.set_tab_title(idx, title_shown(cfg))
		else:
			cfg["unread"] = false   # not in the tab bar (popped out): nothing to flash


# ── Right-click menu ──
func _on_tab_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var idx := _tabs.get_tab_bar().get_tab_idx_at_point(event.position)
		if idx >= 0:
			var control := _tabs.get_tab_control(idx)
			for cfg in cfgs:
				if cfg["control"] == control:
					show_menu(cfg, event.global_position)
					return


func show_menu(cfg: Dictionary, at: Vector2) -> void:
	_menu_cfg = cfg
	for i in CATEGORIES.size():
		_filter_menu.set_item_checked(_filter_menu.get_item_index(i), cfg["cats"].has(CATEGORIES[i][0]))
	var custom: bool = cfg["custom"]
	_tab_menu.set_item_disabled(_tab_menu.get_item_index(MENU_DETACH), not custom or cfg["detached"])
	_tab_menu.set_item_disabled(_tab_menu.get_item_index(MENU_CLOSE), not custom)
	_tab_menu.position = Vector2i(at)
	_tab_menu.popup()


func _on_menu_pressed(id: int) -> void:
	var cfg := _menu_cfg
	if cfg.is_empty():
		return
	match id:
		MENU_RENAME:
			_start_rename(cfg)
		MENU_DETACH:
			detach(cfg)
		MENU_CLEAR:
			cfg["log"].clear()
		MENU_CLOSE:
			close_tab(cfg)


func _on_filter_pressed(id: int) -> void:
	var cfg := _menu_cfg
	if cfg.is_empty():
		return
	if id == FILTER_ALL or id == FILTER_NONE:
		var cats: Array = []
		if id == FILTER_ALL:
			for c in CATEGORIES:
				cats.append(c[0])
		set_categories(cfg, cats)
	else:
		var category: String = CATEGORIES[id][0]
		var cats: Array = cfg["cats"].keys()
		if cfg["cats"].has(category):
			cats.erase(category)
		else:
			cats.append(category)
		set_categories(cfg, cats)
	for i in CATEGORIES.size():
		_filter_menu.set_item_checked(_filter_menu.get_item_index(i), cfg["cats"].has(CATEGORIES[i][0]))


# ── Rename (edited in place, over the tab) ──
func _start_rename(cfg: Dictionary) -> void:
	_rename_cfg = cfg
	var idx := _idx_of(cfg)
	var bar := _tabs.get_tab_bar()
	var where := bar.global_position + (bar.get_tab_rect(idx).position if idx >= 0 else Vector2.ZERO)
	_rename_edit.global_position = where
	_rename_edit.size = Vector2(maxf(bar.get_tab_rect(idx).size.x if idx >= 0 else 90.0, 100.0), 22.0)
	_rename_edit.text = cfg["title"]
	_rename_edit.visible = true
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _finish_rename(text: String) -> void:
	if not _rename_edit.visible:
		return
	_rename_edit.visible = false
	if not _rename_cfg.is_empty():
		rename_tab(_rename_cfg, text)
	_rename_cfg = {}
	_rename_edit.release_focus()


# ── Detached windows (your own tabs) ──
func detach(cfg: Dictionary, restore: bool = false) -> void:
	if not cfg["custom"] or cfg["detached"]:
		return
	cfg["detached"] = true
	_tabs.remove_child(cfg["control"])
	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.add_to_group("game_hud")   # part of the HUD (Escape must not close it as if it were a modal window)
	_win.get_tree().root.add_child(layer)
	var panel := Panel.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 500.0
	panel.offset_top = -210.0
	panel.offset_right = 780.0
	panel.offset_bottom = -10.0
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	var saved: Array = ui.get("chat_tab_" + cfg["id"], [])
	if saved.size() == 4:
		panel.offset_left = saved[0]; panel.offset_top = saved[1]; panel.offset_right = saved[2]; panel.offset_bottom = saved[3]
	panel.add_theme_stylebox_override("panel", Global.window_bg_style())
	layer.add_child(panel)
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 4.0
	content.offset_top = DRAG_BAR_H + 4.0
	content.offset_right = -4.0
	content.offset_bottom = -4.0
	panel.add_child(content)
	cfg["control"].get_child(0).reparent(content, false)
	var title := Label.new()
	title.text = cfg["title"]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color(0.75, 0.70, 0.55))
	title.anchor_right = 1.0
	title.offset_bottom = DRAG_BAR_H
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(title)
	var reattach_btn := Button.new()
	reattach_btn.text = "Reattach"
	reattach_btn.add_theme_font_size_override("font_size", 10)
	reattach_btn.focus_mode = Control.FOCUS_NONE
	reattach_btn.anchor_left = 1.0
	reattach_btn.anchor_right = 1.0
	reattach_btn.offset_left = -68.0
	reattach_btn.offset_top = 1.0
	reattach_btn.offset_right = -2.0
	reattach_btn.offset_bottom = DRAG_BAR_H - 1.0
	reattach_btn.pressed.connect(func() -> void: reattach(cfg))
	panel.add_child(reattach_btn)
	var handle := Label.new()
	handle.text = "◢"
	handle.add_theme_font_size_override("font_size", 14)
	handle.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	handle.anchor_left = 1.0; handle.anchor_top = 1.0; handle.anchor_right = 1.0; handle.anchor_bottom = 1.0
	handle.offset_left = -18.0; handle.offset_top = -18.0
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	panel.add_child(handle)
	var state := {"drag": false, "resize": false}
	title.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			state["drag"] = event.pressed
			if not event.pressed:
				_save_window(cfg)
		elif event is InputEventMouseMotion and state["drag"]:
			panel.offset_left += event.relative.x; panel.offset_top += event.relative.y
			panel.offset_right += event.relative.x; panel.offset_bottom += event.relative.y)
	handle.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			state["resize"] = event.pressed
			if not event.pressed:
				_save_window(cfg)
		elif event is InputEventMouseMotion and state["resize"]:
			if panel.offset_right + event.relative.x - panel.offset_left >= 180.0:
				panel.offset_right += event.relative.x
			if panel.offset_bottom + event.relative.y - panel.offset_top >= 80.0:
				panel.offset_bottom += event.relative.y)
	cfg["window"] = {"layer": layer, "panel": panel, "title": title, "content": content}
	cfg["unread"] = false
	if not restore:
		_save_window(cfg)
	_save()


func reattach(cfg: Dictionary) -> void:
	if not cfg["detached"]:
		return
	var window: Dictionary = cfg["window"]
	var log: RichTextLabel = window["content"].get_child(0)
	log.reparent(cfg["control"], false)
	_tabs.add_child(cfg["control"])
	if is_instance_valid(window["layer"]):
		window["layer"].queue_free()
	cfg["window"] = null
	cfg["detached"] = false
	_refresh_titles()
	_save()


func _save_window(cfg: Dictionary) -> void:
	var panel: Panel = cfg["window"]["panel"] if cfg["window"] != null else null
	if panel == null or Global.player_data.is_empty():
		return
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	ui["chat_tab_" + cfg["id"]] = [panel.offset_left, panel.offset_top, panel.offset_right, panel.offset_bottom]
	Global.player_data["ui_positions"] = ui
	Global.save_player_data_to_file()


# ── Saved with the character ──
func _save() -> void:
	if _loading or Global.player_data.is_empty():
		return
	var out: Array = []
	for cfg in cfgs:
		out.append({"id": cfg["id"], "title": cfg["title"], "cats": cfg["cats"].keys(), "custom": cfg["custom"], "detached": cfg["detached"]})
	Global.player_data["chat_tabs"] = out
	Global.save_player_data_to_file()


func _load() -> void:
	var saved = Global.player_data.get("chat_tabs", [])
	if typeof(saved) != TYPE_ARRAY:
		return
	for entry in saved:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var cfg := find(str(entry.get("id", "")))
		if not cfg.is_empty() and not cfg["custom"]:
			cfg["title"] = str(entry.get("title", cfg["title"]))
			var set_of := {}
			for c in entry.get("cats", []):
				set_of[str(c)] = true
			cfg["cats"] = set_of
		elif cfg.is_empty() and bool(entry.get("custom", false)):
			var created := add_tab(str(entry.get("title", "Chat")), entry.get("cats", DEFAULT_NEW), str(entry.get("id", "")), false)
			if bool(entry.get("detached", false)):
				detach.call_deferred(created, true)
