# game_log_window.gd — The chat window: tabbed message log (General, Combat and your own filtered tabs — see chat_tabs.gd), chat box, channel dropdown
extends CanvasLayer
class_name GameLogWindow

@onready var general_log: RichTextLabel = $Panel/VBox/Tabs/General/GeneralLog
@onready var combat_log:  RichTextLabel = $Panel/VBox/Tabs/Combat/CombatLog
@onready var combat_tab:  Control = $Panel/VBox/Tabs/Combat
@onready var tabs: TabContainer = $Panel/VBox/Tabs
@onready var chat_input:  LineEdit = $Panel/VBox/ChatInput
# Not index 0 — with a remote puppet already in the "player" group by the
# time this HUD spawns (it's spawned by the LOCAL player's own _ready(), so
# that player already exists, but so might an earlier-joined remote one),
# index 0 can silently grab someone else's character instead of mine.
@onready var player := TargetFrame.local_player()

const ChatTabsScript := preload("res://Scripts/chat_tabs.gd")
const MAX_LINES  := 200
const DRAG_BAR_H := 22.0
const MIN_WIDTH  := 180.0
const MIN_HEIGHT := 80.0
const FONT_SIZES := [10, 11, 12, 13, 14, 16, 18]

var _autoattack_dot: Label
var _dot_tween:  Tween
var _dragging  := false
var _resizing  := false
var _font_size: int = 12
var _font_menu: PopupMenu
var chat_tabs: Node = null   # the tab manager (chat_tabs.gd): filters, right-click menu, flashing, detached tabs

# Chat channel the box currently talks in (see ChatChannels). Sticky: it only changes when you
# pick another one from the dropdown or type a channel command (/say /party /zone /tell), so
# plain text keeps going to the last channel you used.
var _channel: int = ChatChannels.SAY
var _tell_target := ""  # who the Tell channel talks to — set by "/tell <name>"
var _channel_menu: OptionButton

# Detached Combat window (Panel lives outside the main Tabs while detached)
var _combat_window: CanvasLayer = null
var _combat_window_panel: Panel = null
var _combat_detached := false
var _combat_window_dragging := false
var _combat_window_resizing := false


func _ready() -> void:
	add_to_group("game_log_window")   # macros (action bar, hotkeys) run their lines through run_macro()
	GameLog.message_categorized.connect(_on_message)
	GameLog.combat_message.connect(_on_combat)
	GameLog.autoattack_changed.connect(_on_autoattack_changed)
	_setup_font_menu()
	_setup_autoattack_dot()
	_setup_drag_bar()
	_setup_resize_handle()
	_setup_detach_button()
	chat_tabs = ChatTabsScript.new()
	add_child(chat_tabs)
	chat_tabs.setup(self, tabs, $Panel, {"control": $Panel/VBox/Tabs/General, "log": general_log}, {"control": combat_tab, "log": combat_log})
	_on_message("system", "[color=#888888]— Welcome to Aldenexia —[/color]")
	tabs.focus_mode = Control.FOCUS_NONE
	general_log.focus_mode = Control.FOCUS_NONE
	make_copyable(general_log)
	make_copyable(combat_log)
	general_log.meta_clicked.connect(_on_meta_clicked)  # clicking a highlighted keyword in an NPC's line says it
	combat_log.focus_mode  = Control.FOCUS_NONE
	# Up/Down aren't meaningful to a single-line field, so without this Godot's
	# default focus-traversal grabs them instead and hands focus off to some
	# other focusable control while the chat box is active.
	chat_input.focus_neighbor_top    = chat_input.get_path()
	chat_input.focus_neighbor_bottom = chat_input.get_path()
	_setup_channel_dropdown()
	chat_input.text_submitted.connect(_on_chat_input_submitted)
	chat_input.gui_input.connect(_on_chat_input_gui_input)
	set_process_unhandled_input(true)

	if Global.player_data.get("ui_positions", {}).get("chat_combat_detached", false):
		call_deferred("_detach_combat")


# ── Font size menu ────────────────────────────────────────────────────────────

func _setup_font_menu() -> void:
	_font_menu = PopupMenu.new()
	for i in FONT_SIZES.size():
		_font_menu.add_item("Font size %d" % FONT_SIZES[i], i)
	_font_menu.id_pressed.connect(_on_font_size_chosen)
	add_child(_font_menu)


func _on_font_size_chosen(id: int) -> void:
	for i in FONT_SIZES.size():
		_font_menu.set_item_checked(i, i == id)
	_font_size = FONT_SIZES[id]
	_apply_font_size()
	_save_position()


func _apply_font_size() -> void:
	general_log.add_theme_font_size_override("normal_font_size", _font_size)
	combat_log.add_theme_font_size_override("normal_font_size", _font_size)
	if chat_tabs != null:
		chat_tabs.apply_font_size(_font_size)


# ── Drag bar (title + drag handle + right-click menu trigger) ─────────────────

func _setup_drag_bar() -> void:
	var bar := Label.new()
	bar.text = "Chat"
	bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	bar.add_theme_font_size_override("font_size", 10)
	bar.add_theme_color_override("font_color", Color(0.75, 0.70, 0.55))
	bar.anchor_right  = 1.0
	bar.anchor_bottom = 0.0
	bar.offset_top    = 0.0
	bar.offset_bottom = DRAG_BAR_H
	bar.mouse_filter  = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_drag_bar_input)
	$Panel.add_child(bar)
	$Panel/VBox.offset_top = DRAG_BAR_H
	_load_position()


func _on_drag_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if not _dragging:
				_save_position()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_font_menu(event.global_position)
	elif event is InputEventMouseMotion and _dragging:
		var panel: Panel = $Panel
		panel.offset_left   += event.relative.x
		panel.offset_top    += event.relative.y
		panel.offset_right  += event.relative.x
		panel.offset_bottom += event.relative.y


func _show_font_menu(at: Vector2) -> void:
	# Mark currently active size
	for i in FONT_SIZES.size():
		_font_menu.set_item_checked(i, FONT_SIZES[i] == _font_size)
	_font_menu.position = Vector2i(at)
	_font_menu.reset_size()
	_font_menu.popup()


# ── Resize handle (bottom-right corner) ──────────────────────────────────────

func _setup_resize_handle() -> void:
	var handle := Label.new()
	handle.text = "◢"
	handle.add_theme_font_size_override("font_size", 14)
	handle.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50, 0.70))
	handle.anchor_left   = 1.0
	handle.anchor_top    = 1.0
	handle.anchor_right  = 1.0
	handle.anchor_bottom = 1.0
	handle.offset_left   = -18.0
	handle.offset_top    = -18.0
	handle.offset_right  = 0.0
	handle.offset_bottom = 0.0
	handle.mouse_filter  = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	handle.gui_input.connect(_on_resize_input)
	$Panel.add_child(handle)


func _on_resize_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		if not _resizing:
			_save_position()
	elif event is InputEventMouseMotion and _resizing:
		var panel: Panel = $Panel
		var motion := event as InputEventMouseMotion
		var new_right:  float = panel.offset_right  + motion.relative.x
		var new_bottom: float = panel.offset_bottom + motion.relative.y
		if new_right - panel.offset_left >= MIN_WIDTH:
			panel.offset_right = new_right
		if new_bottom - panel.offset_top >= MIN_HEIGHT:
			panel.offset_bottom = new_bottom


# ── Detachable Combat window ──────────────────────────────────────────────────

func _setup_detach_button() -> void:
	var btn := Button.new()
	btn.text = "Detach"
	btn.tooltip_text = "Pop the Combat log out into its own window"
	btn.add_theme_font_size_override("font_size", 11)
	btn.anchor_left   = 1.0
	btn.anchor_right  = 1.0
	btn.offset_left   = -64.0
	btn.offset_top    = 3.0
	btn.offset_right  = -4.0
	btn.offset_bottom = 25.0
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_detach_combat)
	combat_tab.add_child(btn)


func _detach_combat() -> void:
	if _combat_detached:
		return
	_combat_detached = true

	tabs.remove_child(combat_tab)
	combat_log.reparent(_build_combat_window(), false)
	_load_combat_window_position()
	_save_position()


func _reattach_combat() -> void:
	if not _combat_detached:
		return
	_combat_detached = false

	combat_log.reparent(combat_tab, false)
	tabs.add_child(combat_tab)
	if is_instance_valid(_combat_window):
		_combat_window.queue_free()
	_combat_window = null
	_combat_window_panel = null
	_save_position()


func _build_combat_window() -> Control:
	var window := CanvasLayer.new()
	window.layer = 5
	# Persistent HUD, same as the main chat window it detached from — without
	# this, player3d.gd's Escape handler (which closes every CanvasLayer NOT
	# in this group) was treating the detached combat log as just another
	# modal window and closing it.
	window.add_to_group("game_hud")
	get_tree().root.add_child(window)
	_combat_window = window

	var panel := Panel.new()
	panel.offset_left   = 500.0
	panel.offset_top    = -210.0
	panel.offset_right  = 780.0
	panel.offset_bottom = -10.0
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	window.add_child(panel)
	_combat_window_panel = panel

	# Plain Control (not a container) so the reparented RichTextLabel's own
	# manual anchors (anchors_preset=15, full rect) behave exactly as they
	# did inside the original Tabs/Combat Control.
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left   = 4.0
	content.offset_top    = DRAG_BAR_H + 4.0
	content.offset_right  = -4.0
	content.offset_bottom = -4.0
	panel.add_child(content)

	var bar := Label.new()
	bar.text = "Combat"
	bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	bar.add_theme_font_size_override("font_size", 10)
	bar.add_theme_color_override("font_color", Color(0.75, 0.70, 0.55))
	bar.anchor_right  = 1.0
	bar.anchor_bottom = 0.0
	bar.offset_top    = 0.0
	bar.offset_bottom = DRAG_BAR_H
	bar.mouse_filter  = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_combat_window_drag_bar_input)
	panel.add_child(bar)

	var reattach_btn := Button.new()
	reattach_btn.text = "Reattach"
	reattach_btn.tooltip_text = "Reattach to the main log window"
	reattach_btn.add_theme_font_size_override("font_size", 10)
	reattach_btn.anchor_left   = 1.0
	reattach_btn.anchor_right  = 1.0
	reattach_btn.offset_left   = -68.0
	reattach_btn.offset_top    = 1.0
	reattach_btn.offset_right  = -2.0
	reattach_btn.offset_bottom = DRAG_BAR_H - 1.0
	reattach_btn.focus_mode = Control.FOCUS_NONE
	reattach_btn.pressed.connect(_reattach_combat)
	panel.add_child(reattach_btn)

	var handle := Label.new()
	handle.text = "◢"
	handle.add_theme_font_size_override("font_size", 14)
	handle.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50, 0.70))
	handle.anchor_left   = 1.0
	handle.anchor_top    = 1.0
	handle.anchor_right  = 1.0
	handle.anchor_bottom = 1.0
	handle.offset_left   = -18.0
	handle.offset_top    = -18.0
	handle.offset_right  = 0.0
	handle.offset_bottom = 0.0
	handle.mouse_filter  = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	handle.gui_input.connect(_on_combat_window_resize_input)
	panel.add_child(handle)

	combat_tab.focus_mode = Control.FOCUS_NONE
	return content


func _on_combat_window_drag_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_combat_window_dragging = event.pressed
			if not _combat_window_dragging:
				_save_position()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_font_menu(event.global_position)
	elif event is InputEventMouseMotion and _combat_window_dragging:
		_combat_window_panel.offset_left   += event.relative.x
		_combat_window_panel.offset_top    += event.relative.y
		_combat_window_panel.offset_right  += event.relative.x
		_combat_window_panel.offset_bottom += event.relative.y


func _on_combat_window_resize_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_combat_window_resizing = event.pressed
		if not _combat_window_resizing:
			_save_position()
	elif event is InputEventMouseMotion and _combat_window_resizing:
		var panel := _combat_window_panel
		var motion := event as InputEventMouseMotion
		var new_right:  float = panel.offset_right  + motion.relative.x
		var new_bottom: float = panel.offset_bottom + motion.relative.y
		if new_right - panel.offset_left >= MIN_WIDTH:
			panel.offset_right = new_right
		if new_bottom - panel.offset_top >= MIN_HEIGHT:
			panel.offset_bottom = new_bottom


func _load_combat_window_position() -> void:
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	var pos: Array = ui.get("chat_combat", [])
	if pos.size() == 4 and is_instance_valid(_combat_window_panel):
		_combat_window_panel.offset_left   = pos[0]
		_combat_window_panel.offset_top    = pos[1]
		_combat_window_panel.offset_right  = pos[2]
		_combat_window_panel.offset_bottom = pos[3]


# ── Persistence ───────────────────────────────────────────────────────────────

func _save_position() -> void:
	if Global.player_data.is_empty():
		return
	var p: Panel = $Panel
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	ui["chat"]           = [p.offset_left, p.offset_top, p.offset_right, p.offset_bottom]
	ui["chat_font_size"] = _font_size
	ui["chat_combat_detached"] = _combat_detached
	if _combat_detached and is_instance_valid(_combat_window_panel):
		var cp: Panel = _combat_window_panel
		ui["chat_combat"] = [cp.offset_left, cp.offset_top, cp.offset_right, cp.offset_bottom]
	Global.player_data["ui_positions"] = ui
	Global.save_player_data_to_file()


func _load_position() -> void:
	var ui: Dictionary = Global.player_data.get("ui_positions", {})
	var pos: Array = ui.get("chat", [])
	if pos.size() == 4:
		var p: Panel = $Panel
		p.offset_left   = pos[0]
		p.offset_top    = pos[1]
		p.offset_right  = pos[2]
		p.offset_bottom = pos[3]
	_font_size = ui.get("chat_font_size", 12)
	_apply_font_size()


# ── Autoattack indicator ──────────────────────────────────────────────────────

func _setup_autoattack_dot() -> void:
	_autoattack_dot = Label.new()
	_autoattack_dot.text = "⬤"
	_autoattack_dot.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1))
	_autoattack_dot.add_theme_font_size_override("font_size", 10)
	_autoattack_dot.anchor_left   = 1.0
	_autoattack_dot.anchor_top    = 0.0
	_autoattack_dot.anchor_right  = 1.0
	_autoattack_dot.anchor_bottom = 0.0
	_autoattack_dot.offset_left   = -22.0
	_autoattack_dot.offset_top    = 5.0
	_autoattack_dot.offset_right  = -6.0
	_autoattack_dot.offset_bottom = 20.0
	_autoattack_dot.visible = false
	$Panel.add_child(_autoattack_dot)


func _on_autoattack_changed(active: bool) -> void:
	if _dot_tween:
		_dot_tween.kill()
	_autoattack_dot.modulate.a = 1.0
	_autoattack_dot.visible = active
	if active:
		_dot_tween = create_tween().set_loops()
		_dot_tween.tween_property(_autoattack_dot, "modulate:a", 0.15, 0.45)
		_dot_tween.tween_property(_autoattack_dot, "modulate:a", 1.0,  0.45)


# ── Chat input ────────────────────────────────────────────────────────────────

# Enter opens the chat box for typing when nothing else has focus. If chat_input
# (or any other Control) is already focused, it consumes Enter itself during
# GUI input processing, so this never even sees the event in that case.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		chat_input.grab_focus()
		get_viewport().set_input_as_handled()


func _on_chat_input_submitted(text: String) -> void:
	chat_input.text = ""
	# Sending a message (or just pressing Enter on an empty box) hands focus
	# back to the game — otherwise the player stays locked out of movement
	# (see player3d.gd's chat_focused check) until they click the box again.
	chat_input.release_focus()
	text = text.strip_edges()
	if text == "":
		return
	if text.begins_with("/"):
		_handle_slash_command(text)
	else:
		_send_on_channel(_channel, text)


# ── Chat channels ─────────────────────────────────────────────────────────────

# A row of [channel dropdown][chat box] in place of the bare chat box. The dropdown never takes
# keyboard focus (click only) so it can't steal movement keys or trap Tab/Space.
func _setup_channel_dropdown() -> void:
	var box_parent := chat_input.get_parent()
	var index := chat_input.get_index()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	_channel_menu = OptionButton.new()
	_channel_menu.focus_mode = Control.FOCUS_NONE
	_channel_menu.add_theme_font_size_override("font_size", 12)
	_channel_menu.tooltip_text = "Chat channel — plain text goes here. Type /say /party /zone or /tell to switch."
	for ch in ChatChannels.NAMES.size():
		_channel_menu.add_icon_item(_color_swatch(ChatChannels.color(ch)), ChatChannels.NAMES[ch], ch)
	_channel_menu.item_selected.connect(func(idx: int) -> void: _set_channel(idx))
	row.add_child(_channel_menu)

	# Which language you speak (Languages): every language you know any of, with your skill. Rebuilt each time it opens,
	# since a scroll or practice changes the list.
	_language_menu = OptionButton.new()
	_language_menu.focus_mode = Control.FOCUS_NONE
	_language_menu.add_theme_font_size_override("font_size", 12)
	_language_menu.tooltip_text = "The language you speak. Others understand it as well as they know it. /language to switch or list."
	_language_menu.get_popup().about_to_popup.connect(_fill_language_menu)
	_language_menu.item_selected.connect(func(idx: int) -> void:
		Languages.set_speaking(str(_language_menu.get_item_metadata(idx)))
		_fill_language_menu()
	)
	row.add_child(_language_menu)
	_fill_language_menu.call_deferred()

	box_parent.remove_child(chat_input)
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(chat_input)
	box_parent.add_child(row)
	box_parent.move_child(row, index)
	_set_channel(ChatChannels.SAY)


var _language_menu: OptionButton


func _fill_language_menu() -> void:
	if _language_menu == null:
		return
	_language_menu.clear()
	var speaking := Languages.speaking()
	for id in Languages.speakable():
		_language_menu.add_item("%s (%d)" % [Languages.display(str(id)), int(Languages.skill(str(id)))])
		_language_menu.set_item_metadata(_language_menu.item_count - 1, str(id))
		if str(id) == speaking:
			_language_menu.select(_language_menu.item_count - 1)
	if _language_menu.item_count == 0:
		_language_menu.add_item("Common")
		_language_menu.set_item_metadata(0, "common")
	# The closed button shows just the name; the list shows skills.
	var shown := _language_menu.selected
	if shown >= 0:
		_language_menu.text = Languages.display(str(_language_menu.get_item_metadata(shown)))


# /language — list your languages; /language <name> — speak that one.
func _language_command(arg: String) -> void:
	if arg.is_empty():
		var lines: Array = []
		var all: Array = Languages.skills().keys()
		all.sort_custom(func(a, b): return Languages.skill(str(a)) > Languages.skill(str(b)))
		for id in all:
			if Languages.exists(str(id)):
				lines.append("%s %d%s" % [Languages.display(str(id)), int(Languages.skill(str(id))), "  (speaking)" if str(id) == Languages.speaking() else ""])
		GameLog.log_general("Your languages: " + ", ".join(lines))
		return
	var id := Languages.find(arg)
	if id.is_empty():
		GameLog.log_general("[color=red]No language called '%s'.[/color]" % arg)
		return
	if Languages.skill(id) < 1.0:
		GameLog.log_general("You don't know any %s yet. A scribe sells a scroll of its basics." % Languages.display(id))
		return
	Languages.set_speaking(id)
	_fill_language_menu()
	GameLog.log_general("You are now speaking %s." % Languages.display(id))


# Chat text can be selected with the mouse and copied from the right-click menu (Copy / Select All) — handy for pasting
# test logs. The log still never takes keyboard focus, so movement keys keep working.
static func make_copyable(log: RichTextLabel) -> void:
	log.selection_enabled = true
	log.context_menu_enabled = true
	log.deselect_on_focus_loss_enabled = false


static func _color_swatch(color: Color) -> ImageTexture:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _set_channel(channel: int, tell_target: String = "") -> void:
	_channel = channel
	if channel == ChatChannels.TELL and not tell_target.is_empty():
		_tell_target = tell_target
	var color := ChatChannels.color(channel)
	_channel_menu.select(channel)
	_channel_menu.set_item_text(ChatChannels.TELL, "Tell: %s" % _tell_target if not _tell_target.is_empty() else "Tell")
	_channel_menu.add_theme_color_override("font_color", color)
	_channel_menu.add_theme_color_override("font_hover_color", color)
	_channel_menu.add_theme_color_override("font_focus_color", color)
	chat_input.add_theme_color_override("font_color", color)  # what you type previews the color it will appear in
	chat_input.add_theme_color_override("caret_color", color)
	chat_input.placeholder_text = _placeholder_for(channel)


func _placeholder_for(channel: int) -> String:
	match channel:
		ChatChannels.PARTY:
			return "Party chat... (or /loc)"
		ChatChannels.ZONE:
			return "Shout to the whole zone... (or /loc)"
		ChatChannels.TELL:
			return ("Tell %s..." % _tell_target) if not _tell_target.is_empty() else "/tell <name> to pick who to talk to"
	return "Say something nearby... (or /loc)"


func _send_on_channel(channel: int, message: String) -> void:
	match channel:
		ChatChannels.SAY:
			player.send_say(message)
		ChatChannels.PARTY:
			player.send_party_message(message)
		ChatChannels.ZONE:
			player.send_zone(message)
		ChatChannels.TELL:
			if _tell_target.is_empty():
				GameLog.log_general("[color=red]Use /tell <name> to choose who to talk to.[/color]")
			else:
				player.send_tell(_tell_target, message)


# /say, /party and /zone: switch to the channel, and send the rest of the line if there is one.
func _channel_command(channel: int, arg: String) -> void:
	_set_channel(channel)
	if not arg.is_empty():
		_send_on_channel(channel, arg)


# /tell <name> [message]: the name becomes the Tell channel's target, so later plain text keeps
# going to them; without a message it only switches.
func _tell_command(arg: String) -> void:
	var tell_parts := arg.split(" ", false, 1)
	if tell_parts.is_empty():
		if _tell_target.is_empty():
			GameLog.log_general("[color=red]Usage: /tell <name> [message][/color]")
		else:
			_set_channel(ChatChannels.TELL)
		return
	var target_name: String = tell_parts[0]
	if Net.is_multiplayer_game and player._find_player_by_name(target_name) == null:
		GameLog.log_general("[color=red]No player named '%s' is currently online.[/color]" % target_name)
		return
	_set_channel(ChatChannels.TELL, target_name)
	if tell_parts.size() > 1:
		player.send_tell(target_name, tell_parts[1])


# Lets Escape back out of an accidental click into the chat box without
# sending anything — same "give movement back" reasoning as submitting.
func _on_chat_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		chat_input.text = ""
		chat_input.release_focus()


# Canonical / commands. Typing any unambiguous prefix of one of these works
# too (Linux-style abbreviation) — see _resolve_command() below. e.g. "/loc"
# and "/location" both resolve to "/location" since no other command starts
# with "loc"; "/f" would be ambiguous if two commands both started with "f".
const GMCommandsScript := preload("res://Scripts/gm_commands.gd")
const COMMANDS := ["/location", "/hail", "/appraise", "/time", "/follow", "/camp", "/exit", "/log", "/invite", "/disband", "/say", "/tell", "/party", "/zone", "/played", "/resetui", "/who", "/weather", "/pet", "/quests", "/compass", "/raid", "/gm", "/focus", "/assist", "/announce", "/maintenance", "/trade", "/ban", "/unban", "/bans", "/language", "/surname", "/stuck", "/cast", "/target", "/pause", "/macro", "/kill", "/give", "/teleport"]


# /surname            what yours is
# /surname Name       choose yours (level 10; only once unless you are a game master)
# /surname clear      a game master clears their own
# /surname who Name   game masters: set anyone's (or "clear")
func _surname_command(arg: String) -> void:
	var words := arg.split(" ", false)
	match words.size():
		0:
			if str(player.surname).is_empty():
				GameLog.log_general("You have no surname. At level 10, choose one with /surname <Name>.")
			else:
				GameLog.log_general("You are %s %s." % [player.player_name, player.surname])
		1:
			if words[0].to_lower() == "clear" and GMCommandsScript.is_gm(player):
				player._apply_surname("")
				GameLog.log_general("[color=#88ccff]Your surname is removed.[/color]")
			else:
				GameLog.log_general(player.set_own_surname(words[0]))
		_:
			GMCommandsScript.request(player, "surname", arg, get_tree())


# Returns false only when the command plainly failed in a way a macro should stop for (a /cast that didn't start).
func _handle_slash_command(text: String) -> bool:
	var parts := text.split(" ", false)
	var typed_cmd := parts[0].to_lower()
	var arg := text.substr(parts[0].length()).strip_edges()

	var cmd := _resolve_command(typed_cmd)
	if cmd.is_empty():
		return false  # _resolve_command already logged unknown/ambiguous

	match cmd:
		"/cast":
			if arg.is_empty():
				GameLog.log_general("Usage: /cast <spell name> (the start of the name is enough)")
				return false
			var spell_key := Macros.resolve_spell(arg, player)
			return not spell_key.is_empty() and player.cast_spell(spell_key)
		"/target":
			return _target_command(arg)
		"/pause":
			GameLog.log_general("/pause <seconds> only works inside a macro.")
		"/macro":
			player.toggle_abilities_book_tab("Macros")
		"/who":
			# on a server: everyone in every zone (world_link.gd); otherwise this world's players
			var link := get_tree().get_first_node_in_group("world_link")
			if Net.remote_character_mode and link != null:
				link.request_who()
			else:
				WorldAnnouncer.print_who(player)
		"/pet":
			player.try_pet_nearby()
		"/focus":
			player.cmd_focus(arg)
		"/assist":
			player.assist_target()
		"/gm":
			GMCommandsScript.set_mode(player, arg)
		"/kill":
			# Game masters: your target, or yourself (/kill me). The server does it (gm_commands.gd).
			var victim: Node = player if arg.to_lower() in ["me", "self", "myself"] else player.current_target
			if not is_instance_valid(victim):
				GameLog.log_general("Usage: /kill (your target)   or   /kill me")
				return false
			GMCommandsScript.request(player, "kill", TargetFrame.target_key_of(victim), get_tree())
		"/give":
			GMCommandsScript.request(player, "give", arg, get_tree())
		"/teleport":
			return _teleport_command(arg)
		"/weather", "/raid", "/announce", "/maintenance", "/ban", "/unban", "/bans":
			# Game masters only (/gm enable). On a dedicated server the command is sent to the server.
			GMCommandsScript.request(player, cmd.substr(1), arg, get_tree())
		"/location":
			var pos: Vector3 = player.global_position
			GameLog.log_general("[color=green]Your location: X=%.2f Y=%.2f Z=%.2f[/color]" % [pos.x, pos.y, pos.z])
		"/hail":
			player.try_hail_nearby_npc()
		"/appraise":
			player.try_appraise_target()
		"/follow":
			player.try_follow(arg)
		"/camp":
			match arg.to_lower():
				"", "menu":
					start_camp_sequence()  # camp out to the main menu
				"desktop", "desk", "quit", "exit":
					_save_and_quit()       # camp out and close the game
				_:
					GameLog.log_general("Usage: /camp (back to the main menu) or /camp desktop (exit the game)")
		"/exit":
			_save_and_quit()  # same as /camp desktop
		"/log":
			_toggle_file_logging()
		"/invite":
			if arg.is_empty():
				player.invite_to_group(player.current_target)
			else:
				player.invite_to_group_by_name(arg)
		"/trade":
			if arg.is_empty():
				player.request_trade(player.current_target)
			else:
				player.request_trade_by_name(arg)
		"/disband":
			if arg.is_empty():
				player.disband_or_kick_from_group(player.current_target)
			else:
				player.disband_from_group_by_name(arg)
		"/say":
			_channel_command(ChatChannels.SAY, arg)
		"/zone":
			_channel_command(ChatChannels.ZONE, arg)
		"/party":
			_channel_command(ChatChannels.PARTY, arg)
		"/tell":
			_tell_command(arg)
		"/played":
			_show_played()
		"/language":
			_language_command(arg)
		"/surname":
			_surname_command(arg)
		"/stuck":
			player.cmd_stuck()
		"/compass":
			player.toggle_compass()
		"/quests":
			var quest_lines := Quests.journal_lines()
			if quest_lines.is_empty():
				GameLog.log_general("[color=#cccccc]You have no quests.[/color]")
			for quest_line in quest_lines:
				GameLog.log_general(quest_line)
		"/resetui":
			player.reset_ui()
		"/time":
			GameLog.log_general("[color=green]%s[/color]" % Global.format_full_date())
			var day_night_nodes := get_tree().get_nodes_in_group("day_night_cycle")
			var day_night = day_night_nodes[0] if day_night_nodes.size() > 0 else null
			if day_night:
				var next_label := "sunset" if day_night.is_day() else "sunrise"
				var remaining := int(day_night.seconds_until_next_phase())
				GameLog.log_general("[color=green]Sky: %s (%s in %dm %ds)[/color]" % [
					"Daytime" if day_night.is_day() else "Nighttime", next_label, remaining / 60, remaining % 60])
			var d := Time.get_datetime_dict_from_system(false)
			var hour12: int = d.hour % 12
			if hour12 == 0:
				hour12 = 12
			var ampm := "AM" if d.hour < 12 else "PM"
			GameLog.log_general("[color=green]Real time: %d:%02d %s[/color]" % [hour12, d.minute, ampm])
	return true


# /teleport <zone>: game masters go straight to a zone's arrival spot (its spawn point). Any start of the zone's name or
# id works ("/teleport dust"). The server accepts a game master's zone change from anywhere (net.gd _check_zone_change()).
func _teleport_command(arg: String) -> bool:
	if not GMCommandsScript.is_gm(player):
		GameLog.log_general(GMCommandsScript.DENIED)
		return false
	var want := arg.strip_edges().to_lower()
	var hits: Array = []
	for id in ZoneInfo.zones():
		var shown := ZoneInfo.name_for(id).to_lower()
		if want == str(id) or want == shown:
			hits = [id]
			break
		if not want.is_empty() and (str(id).begins_with(want.replace(" ", "_")) or shown.begins_with(want)):
			hits.append(id)
	if hits.size() != 1:
		GameLog.log_general("Usage: /teleport <zone>: %s" % ", ".join(ZoneInfo.zones().keys().map(func(z): return ZoneInfo.name_for(z))))
		return false
	if hits[0] == ZoneInfo.current_id():
		player.global_position = get_tree().current_scene.get("spawn_position") if get_tree().current_scene.get("spawn_position") is Vector3 else player.global_position
		GameLog.log_general("[color=#88ccff]You return to %s's arrival point.[/color]" % ZoneInfo.name_for(hits[0]))
		return true
	GameLog.log_general("[color=#88ccff]Teleporting to %s...[/color]" % ZoneInfo.name_for(hits[0]))
	Net.zone_travel(hits[0], "@spawn")
	return true


# /target <name>: the nearest living monster, NPC, player or pet whose name starts with it ("/target rat", "/target Grep").
func _target_command(arg: String) -> bool:
	var want := arg.strip_edges().to_lower()
	if want.is_empty():
		GameLog.log_general("Usage: /target <name> (the start of the name is enough)")
		return false
	var best: Node3D = null
	var best_d := INF
	for group in ["monsters", "npc_guard", "npc_vendor", "player", "pets"]:
		for node in get_tree().get_nodes_in_group(group):
			if not (node is Node3D) or not player._is_targetable_alive(node):
				continue
			var shown := TargetFrame.display_name(node).to_lower()
			if not (shown.begins_with(want) or shown.contains(" " + want)):
				continue
			var d: float = player.global_position.distance_to(node.global_position)
			if d < best_d and d <= 200.0:
				best = node
				best_d = d
	if best == null:
		GameLog.log_general("[color=red]You don't see '%s' nearby.[/color]" % arg.strip_edges())
		return false
	player.current_target = best
	player._announce_target(best)
	return true


# ── Macros (macros.gd) ────────────────────────────────────────────────────────

var _macro_running := false


# Runs a macro's lines top to bottom (ref "c3" / "s3"). Pressing it again while it runs does nothing.
func run_macro(ref: String) -> void:
	var macro := Macros.get_macro(ref)
	if macro.is_empty() or Macros.is_empty_macro(macro) or not is_instance_valid(player):
		return
	if _macro_running:
		GameLog.log_general("[color=#cccccc]A macro is already running.[/color]")
		return
	_macro_running = true
	for raw in macro.get("lines", []):
		var line := str(raw).strip_edges()
		if line.is_empty():
			continue
		if line.to_lower().begins_with("/pause"):
			var secs := Macros.pause_seconds(line.substr(6))
			if secs < 0.0:
				GameLog.log_general("[color=red]Macro %s: /pause needs a number of seconds.[/color]" % Macros.label(macro))
				break
			await get_tree().create_timer(secs).timeout
			if not is_instance_valid(player):
				break
			continue
		if not run_macro_line(Macros.substitute(line, player)):
			break
	_macro_running = false


# One line as if typed into the chat box (a plain line goes to the current chat channel). False = stop the macro.
func run_macro_line(text: String) -> bool:
	if text.begins_with("/"):
		return _handle_slash_command(text)
	_send_on_channel(_channel, text)
	return true


# 15-second channel shared by /camp, /exit, and the pause menu's "Save and
# Exit" button alike — without it, any of the three is a free instant escape
# from a bad pull or a fight gone wrong. Interrupted (not just delayed) by
# taking any damage during the channel, same idea as EQ's camp timer
# resetting on a hit. Public (no leading underscore) since pause_menu.gd
# calls this cross-script — see its _on_save_and_exit().
var _camping := false
const CAMP_CHANNEL_MS := 15000

# Returns true once the channel completes undisturbed, false if interrupted
# (damage) or the player node disappears out from under it — callers only
# proceed with their own save/quit/return-to-menu step on true.
func start_camp_channel() -> bool:
	if _camping:
		GameLog.log_general("[color=#ffaa66]You are already trying to camp.[/color]")
		return false
	if not is_instance_valid(player):
		return false
	_camping = true
	var start_ms := Time.get_ticks_msec()
	var start_damage_ms: int = player.last_damage_time_ms
	var start_attacked_ms: int = player.last_attacked_msec
	player.is_sitting = true
	GameLog.log_general("[color=#ffdd88]You begin to prepare your camp.[/color]")

	# A countdown in the chat: "15 seconds remaining" ... "1 second remaining", then the player camps out. Announced
	# whenever the whole seconds left change (the loop ticks 4x a second), so no second is skipped or repeated.
	var announced := 0
	while Time.get_ticks_msec() - start_ms < CAMP_CHANNEL_MS:
		var remaining := ceili((CAMP_CHANNEL_MS - (Time.get_ticks_msec() - start_ms)) / 1000.0)
		if remaining != announced and remaining > 0:
			announced = remaining
			GameLog.log_general("[color=#ffdd88]%d second%s remaining[/color]" % [remaining, "" if remaining == 1 else "s"])
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(player):
			_camping = false
			return false
		if player.last_damage_time_ms > start_damage_ms or player.last_attacked_msec > start_attacked_ms:
			GameLog.log_general("[color=#ff6666]You abandon your camp preparations.[/color]")
			player.is_sitting = false  # attacked: you are on your feet, whether or not you were sitting before you began
			_camping = false
			return false

	_camping = false
	GameLog.log_general("[color=#88cc88]You finish breaking camp.[/color]")
	return true


# Public (no leading underscore) since pause_menu.gd's "Save and Exit" button
# fires this too, the same fire-and-forget way "/camp" does here — the await
# needs to live on this long-lived HUD node, not on the pause menu, which
# queue_free()s itself right after triggering this.
func start_camp_sequence() -> void:
	if await start_camp_channel():
		save_and_return_to_menu()


# Same save-and-tear-down sequence as pause_menu.gd's "Save and Exit" button —
# frees every CanvasLayer on root (HUD, character sheet, backpack, pet frame,
# etc.) before switching scenes, since none of those free themselves on their
# own when the zone scene changes out from under them. Public since
# pause_menu.gd calls this too, once its own start_camp_channel() succeeds.
func save_and_return_to_menu() -> void:
	# Gameplay can leave the mouse captured/hidden for mouselook (see
	# global.gd/camera_controller.gd) — switching to main_menu.tscn without
	# resetting this left the cursor unusable on the menu (invisible and/or
	# locked in place), with no way to click anything short of force-quitting.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Global.save_player_data_to_file()
	# Leave the multiplayer session too (flushing a server-stored character first). Without this the
	# connection lingered behind the menu, and a dedicated server kept the character "already online".
	Net.disconnect_game()
	for node in get_tree().root.get_children():
		if node is CanvasLayer:
			node.queue_free()
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")


func _save_and_quit() -> void:
	if await start_camp_channel():
		Global.save_player_data_to_file()
		Net.disconnect_game()  # uploads the character to a dedicated server before the process exits
		get_tree().quit()


# Resolves a typed command to a canonical one from COMMANDS, allowing any
# unambiguous prefix (e.g. "/fol" -> "/follow") the same way Linux shells
# tab-complete unique abbreviations. Logs "Unknown"/"Ambiguous" itself and
# returns "" in either failure case, so callers can just bail on empty.
# Short forms that must keep working when a new command shares their first letters (/s was /say before /surname existed).
# /g and /gsay are EverQuest's group chat (without them /g meant /gm); /pa and /ca kept their old meaning when /pause and
# /cast arrived.
const COMMAND_ALIASES := {"/s": "/say", "/g": "/party", "/gsay": "/party", "/pa": "/party", "/ca": "/camp", "/tel": "/tell"}


func _resolve_command(typed: String) -> String:
	if COMMANDS.has(typed):
		return typed
	if COMMAND_ALIASES.has(typed):
		return COMMAND_ALIASES[typed]
	var matches: Array = []
	for c in COMMANDS:
		if c.begins_with(typed):
			matches.append(c)
	if matches.size() == 1:
		return matches[0]
	if matches.size() > 1:
		GameLog.log_general("[color=red]Ambiguous command '%s' — did you mean: %s?[/color]" % [typed, ", ".join(matches)])
		return ""
	GameLog.log_general("[color=red]Unknown command: %s[/color]" % typed)
	return ""


# /played — the character's birthday (when it was created, in-world and real dates) and the time
# spent in game. The total is banked into the save (Global.save_player_data_to_file()).
func _show_played() -> void:
	var creation: Dictionary = Global.player_data.get("character_creation", {})
	var who: String = str(player.player_name)
	if not creation.has("game_time"):
		GameLog.log_general("[color=green]%s's birthday is lost to history.[/color]" % who)
	else:
		GameLog.log_general("[color=green]%s was born on %s (in-game).[/color]" % [who, Global.format_birthday_ingame(creation)])
		var age := Global.format_real_age(creation)
		GameLog.log_general("[color=green]In the real world: %s%s.[/color]" % [Global.format_birthday_real(creation), (" — " + age) if not age.is_empty() else ""])
	GameLog.log_general("[color=green]Total time played: %s. This session: %s.[/color]" % [
		Global.format_playtime(Global.get_total_playtime()), Global.format_playtime(Global.get_session_playtime())])


# A highlighted word in an NPC's line ("kw:<word>", see npc_conversation.gd) was clicked: say it, exactly as if typed.
func _on_meta_clicked(meta: Variant) -> void:
	var text := str(meta)
	if text.begins_with("kw:") and is_instance_valid(player):
		player.send_say(text.substr(3))


# ── Log output ────────────────────────────────────────────────────────────────

func _on_message(category: String, text: String) -> void:
	chat_tabs.route(category, text, _timestamp())
	_write_to_log_file("GENERAL", text)


const COMBAT_VISIBILITY_RANGE := 10.0

func _on_combat(text: String, has_position: bool, position: Vector3) -> void:
	# The file log is for balance/metrics review, so it captures every combat
	# message unconditionally (e.g. a distant guard fight) — the 10m range
	# above only gates what's actually shown on screen.
	_write_to_log_file("COMBAT", text)
	if has_position and is_instance_valid(player) \
			and player.global_position.distance_to(position) > COMBAT_VISIBILITY_RANGE:
		return
	chat_tabs.route("combat_other" if has_position else "combat", text, _timestamp())


# ===== /log — dumps chat + combat to a plain-text file for balance review =====

var _log_file: FileAccess = null
const LOG_DIR := "user://logs"

func _toggle_file_logging() -> void:
	if _log_file != null:
		_log_file.close()
		_log_file = null
		GameLog.log_general("[color=#88cc88]Logging stopped.[/color]")
		return

	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var d := Time.get_datetime_dict_from_system(false)
	var stamp := "%04d-%02d-%02d_%02d-%02d-%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
	var file_path := "%s/session_%s.txt" % [LOG_DIR, stamp]
	_log_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _log_file:
		var real_path := ProjectSettings.globalize_path(file_path)
		GameLog.log_general("[color=#88cc88]Logging chat and combat to:[/color] %s" % real_path)
	else:
		GameLog.log_general("[color=#ff6666]Couldn't open a log file to write to.[/color]")


func _write_to_log_file(channel: String, text: String) -> void:
	if _log_file == null:
		return
	var d := Time.get_datetime_dict_from_system(false)
	_log_file.store_line("[%02d:%02d:%02d] [%s] %s" % [d.hour, d.minute, d.second, channel, _strip_bbcode(text)])
	_log_file.flush()  # write-through so a crash or force-quit doesn't lose a buffered tail


func _exit_tree() -> void:
	if _log_file != null:
		_log_file.close()
		_log_file = null


func _strip_bbcode(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[[^\\]]*\\]")
	return regex.sub(text, "", true)


func _timestamp() -> String:
	var d := Time.get_datetime_dict_from_system(false)
	var hour12: int = d.hour % 12
	if hour12 == 0:
		hour12 = 12
	var ampm := "AM" if d.hour < 12 else "PM"
	return "[color=#666666][%02d:%02d %s][/color] " % [hour12, d.minute, ampm]
