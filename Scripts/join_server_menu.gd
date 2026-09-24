# join_server_menu.gd — "Join a Server" screen, reached from the main menu. Unlike the LAN screen the
# characters aren't picked from local saves: they live ON the server, under the player's account (see
# account_relay.gd). The player logs into (or creates) an account, then gets a table of its characters — portrait,
# name, level, class and zone — to enter the world with, create a new one (character_creation.tscn in server mode,
# see Global.server_creation), delete one, or claim a character made before accounts. The server list comes from
# Data/servers.json; any address can also be typed. Each entry shows whether it is online, how many players
# it has and whether its version matches this build (Net.probe_server, one server at a time). When a server runs a
# different build, a "Download update" button fetches the published update from that server's update address
# (GameUpdater, see game_updater.gd) and restarts the game into it.
# See net.gd's "Server-side characters" section.
extends CanvasLayer

const SERVERS_PATH := "res://Data/servers.json"

var panel: Panel
var server_select: OptionButton
var address_input: LineEdit
var account_input: LineEdit
var password_input: LineEdit
var confirm_input: LineEdit
var login_btn: Button
var create_account_btn: Button
var status_label: Label

# The character list (shown once logged in).
const MAX_ROWS_HEIGHT := 360.0
var account_box: VBoxContainer
var list_box: VBoxContainer
var list_title: Label
var list_count: Label
var rows_box: VBoxContainer
var enter_btn: Button
var create_btn: Button
var delete_btn: Button
var attach_btn: Button
var logout_btn: Button
var attach_box: VBoxContainer
var attach_name_input: LineEdit
var attach_password_input: LineEdit
var _row_group := ButtonGroup.new()
var _characters: Array = []       # the listing's rows, from the server
var _max_characters := AccountRelay.MAX_CHARACTERS
var _selected := ""               # name of the selected character
var _pending_session: Dictionary = {}  # a login/create in flight: becomes AccountRelay.session when it succeeds
var _account_errand := false      # an account request is running (vs. a status probe)
var _portraits: Dictionary = {}   # "race/sex" -> Texture2D (or null)

var refresh_btn: Button
var server_status_label: Label
var update_btn: Button
var update_bar: ProgressBar
var _updater: GameUpdater = null
var _updating := false
var _server_builds: Dictionary = {}  # list index -> the build display string a server reported when it needed an update

var _servers: Array = []
var _busy := false
var _delete_dialog: DeleteCharacterDialog = null

# Probing: one entry per listed server plus one for "Other" (the typed address). _probe_index is the entry
# being probed right now (-1 when idle); Net runs only one errand at a time.
const STATUS_COLORS := {
	"unknown": Color(0.6, 0.6, 0.6), "checking": Color(0.6, 0.6, 0.6), "online": Color(0.45, 0.85, 0.45),
	"full": Color(0.95, 0.75, 0.3), "version": Color(0.95, 0.75, 0.3), "offline": Color(0.9, 0.4, 0.35),
}
var _status: Array = []
var _probe_queue: Array = []
var _probe_index := -1
var _dots: Dictionary = {}


func _ready() -> void:
	layer = 10
	_load_servers()
	for state in STATUS_COLORS:
		_dots[state] = _make_dot(STATUS_COLORS[state])
	_build_ui()
	Net.server_request_done.connect(_on_server_request_done)
	if not AccountRelay.session.is_empty():
		# Back from character creation, a failed join or a camp-out: still logged in, so straight to the list.
		_show_list_view()
		_refresh_list()
	else:
		_show_account_view()
		_probe_all()  # after the connect above: a probe can fail instantly and must not go unheard
		if server_select.selected >= _servers.size():
			_probe_typed()
	# A join that failed (or dropped) inside the zone lands back here with the reason.
	if not Net.last_failure_reason.is_empty():
		status_label.text = Net.last_failure_reason
		Net.last_failure_reason = ""


func _load_servers() -> void:
	_servers = []
	var data = JSON.parse_string(FileAccess.get_file_as_string(SERVERS_PATH))
	if typeof(data) == TYPE_DICTIONARY and typeof(data.get("servers")) == TYPE_ARRAY:
		for entry in data["servers"]:
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("address", "")) != "":
				_servers.append(entry)


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.55)
	add_child(overlay)

	panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200.0
	panel.offset_right = 200.0
	panel.offset_top = -290.0
	panel.offset_bottom = 290.0
	panel.add_theme_stylebox_override("panel", Global.opaque_window_bg_style())
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20.0
	vbox.offset_top = 16.0
	vbox.offset_right = -20.0
	vbox.offset_bottom = -16.0
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	var root := vbox
	account_box = VBoxContainer.new()
	account_box.add_theme_constant_override("separation", 8)
	root.add_child(account_box)
	vbox = account_box  # the server picker and the login fields go in the account view

	var title := Label.new()
	title.text = "— Join a Server —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	vbox.add_child(title)

	vbox.add_child(_make_label("Server"))
	var server_row := HBoxContainer.new()
	server_row.add_theme_constant_override("separation", 6)
	vbox.add_child(server_row)
	server_select = OptionButton.new()
	server_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in _servers:
		server_select.add_item(str(entry.get("name", entry["address"])))
		_status.append({"state": "unknown", "text": "Not checked yet"})
	server_select.add_item("Other (type an address)")
	_status.append({"state": "unknown", "text": "Not checked yet — press Enter in the address box, or Refresh"})
	server_select.item_selected.connect(_on_server_selected)
	server_row.add_child(server_select)
	refresh_btn = Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.tooltip_text = "Check which servers are online"
	refresh_btn.pressed.connect(_on_refresh_pressed)
	server_row.add_child(refresh_btn)

	address_input = LineEdit.new()
	address_input.placeholder_text = "Address (e.g. 203.0.113.5 or play.example.com:8910)"
	address_input.text_changed.connect(_on_address_edited)
	address_input.text_submitted.connect(func(_t: String) -> void: _probe_typed())
	address_input.focus_exited.connect(_probe_typed)
	vbox.add_child(address_input)

	server_status_label = Label.new()
	server_status_label.add_theme_font_size_override("font_size", 11)
	server_status_label.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(server_status_label)

	update_btn = _make_button("Download update")
	update_btn.visible = false
	update_btn.pressed.connect(_on_update_pressed)
	vbox.add_child(update_btn)
	update_bar = ProgressBar.new()
	update_bar.visible = false
	update_bar.show_percentage = false
	update_bar.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(update_bar)

	vbox.add_child(HSeparator.new())

	vbox.add_child(_make_label("Account name"))
	account_input = LineEdit.new()
	account_input.placeholder_text = "Letters and numbers, 2-16"
	account_input.max_length = 16
	account_input.text_submitted.connect(func(_t: String) -> void: password_input.grab_focus())
	vbox.add_child(account_input)

	vbox.add_child(_make_label("Password"))
	password_input = LineEdit.new()
	password_input.secret = true
	password_input.placeholder_text = "Your account's password"
	password_input.text_submitted.connect(func(_t: String) -> void: _on_login_pressed())
	vbox.add_child(password_input)

	vbox.add_child(_make_label("Confirm password (only when creating a new account)"))
	confirm_input = LineEdit.new()
	confirm_input.secret = true
	confirm_input.placeholder_text = "Type it again"
	vbox.add_child(confirm_input)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	login_btn = _make_button("Log In")
	login_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	login_btn.pressed.connect(_on_login_pressed)
	row.add_child(login_btn)
	create_account_btn = _make_button("Create Account")
	create_account_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_account_btn.pressed.connect(_on_create_account_pressed)
	row.add_child(create_account_btn)

	_build_list_view(root)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(status_label)

	var back_btn := _make_button("Back")
	back_btn.pressed.connect(_on_back_pressed)
	root.add_child(back_btn)

	# Start on what the player used last time, else the first listed server.
	var last_address := str(Global.settings.get("last_server_address", ""))
	if not last_address.is_empty():
		address_input.text = last_address
		server_select.select(_index_of_address(last_address))
	elif not _servers.is_empty():
		server_select.select(0)
		_on_server_selected(0)
	else:
		server_select.select(0)
	account_input.text = str(Global.settings.get("last_server_account", ""))
	for i in _status.size():
		_apply_status(i, "unknown", str(_status[i]["text"]))


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	return l


func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 32)
	return btn


func _index_of_address(address: String) -> int:
	for i in _servers.size():
		if _entry_address_text(_servers[i]) == address:
			return i
	return _servers.size()  # "Other"


func _entry_address_text(entry: Dictionary) -> String:
	var port := int(entry.get("port", Net.DEFAULT_PORT))
	return str(entry["address"]) if port == Net.DEFAULT_PORT else "%s:%d" % [entry["address"], port]


func _on_server_selected(index: int) -> void:
	if index < _servers.size():
		address_input.text = _entry_address_text(_servers[index])
	else:
		address_input.text = ""
		address_input.grab_focus()
	_refresh_status_label()


# Typing an address that isn't the selected list entry's switches the selection to "Other".
func _on_address_edited(text: String) -> void:
	var selected := server_select.selected
	if selected < _servers.size() and text.strip_edges() != _entry_address_text(_servers[selected]):
		server_select.select(_servers.size())
		_apply_status(_servers.size(), "unknown", "Not checked yet — press Enter in the address box, or Refresh")


# ── Server status (online / players / version) ──
func _make_dot(color: Color) -> ImageTexture:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 12:
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(6, 6)) <= 5.0:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


func _target_for(index: int) -> Array:
	if index < _servers.size():
		return [str(_servers[index]["address"]), int(_servers[index].get("port", Net.DEFAULT_PORT))]
	return _parse_address()


func _probe_all() -> void:
	_probe_queue.clear()
	for i in _servers.size():
		_probe_queue.append(i)
	_probe_next()


func _probe_typed() -> void:
	var index := _servers.size()
	if server_select.selected != index:
		return  # a listed server is selected; its own probe covers it
	if (_parse_address()[0] as String).is_empty():
		_apply_status(index, "unknown", "Type the server's address")
		return
	if _probe_index != index and not _probe_queue.has(index):
		_probe_queue.append(index)
	_probe_next()


func _probe_next() -> void:
	if _probe_index >= 0 or _probe_queue.is_empty():
		return
	_probe_index = _probe_queue.pop_front()
	var target := _target_for(_probe_index)
	_apply_status(_probe_index, "checking", "Checking...")
	Net.probe_server(target[0], target[1])


# Stops probing so a real action (join, create, delete) can use the connection.
func _cancel_probes() -> void:
	_probe_queue.clear()
	if _probe_index >= 0:
		Net.cancel_menu_request()
		_apply_status(_probe_index, "unknown", "Not checked yet")
		_probe_index = -1


func _on_refresh_pressed() -> void:
	if _busy:
		return
	_cancel_probes()
	_probe_all()
	if server_select.selected >= _servers.size():
		_probe_typed()


func _apply_probe_result(index: int, ok: bool, kind: String, reason: String, info: Dictionary) -> void:
	if ok:
		var players := int(info.get("players", 0))
		var cap := int(info.get("max_players", 0))
		if cap > 0 and players >= cap:
			_apply_status(index, "full", "Full — %d/%d players — %s" % [players, cap, info.get("version", "")], "(full)")
		else:
			_apply_status(index, "online", "Online — %d/%d players — %s" % [players, cap, info.get("version", "")], "(%d/%d)" % [players, cap])
	elif kind == "version":
		_server_builds[index] = str(info.get("version", ""))
		_apply_status(index, "version", "Update needed — this server runs %s" % info.get("version", "another version"), "(update needed)")
	elif kind == "offline":
		_apply_status(index, "offline", "Offline or unreachable", "(offline)")
		_offer_update_if_published(index)
	else:
		_apply_status(index, "offline", reason, "(unavailable)")


# A build that is behind can be unable to complete the server's handshake at all (Godot refuses RPCs whose lists differ between the two
# sides), so its probe reads "offline" and the "Update needed" state never comes. So when a server looks offline, also ask its update address
# (plain HTTP, no game connection) whether a different build is published, and if so offer the update button.
func _offer_update_if_published(index: int) -> void:
	if _updating or not is_inside_tree():
		return
	if _updater == null:
		_updater = GameUpdater.new()
		_updater.progress.connect(_on_update_progress)
		add_child(_updater)
	var checked: Dictionary = await _updater.check(_update_url_for(index))
	if _updating or not is_inside_tree() or checked.get("status", "") != "available":
		return
	if index >= _status.size() or _status[index]["state"] != "offline":
		return  # something else answered in the meantime
	_apply_status(index, "version", "Can't reach the server, and a different build is published (%s). Try updating." % _updater.entry_stamp(), "(update?)")


# Records a server's state and paints it on its dropdown item (a colored dot + short suffix) and, if it is
# the selected one, on the status line.
func _apply_status(index: int, state: String, text: String, suffix: String = "") -> void:
	if index < 0 or index >= _status.size():
		return
	_status[index] = {"state": state, "text": text}
	var base := "Other (type an address)" if index >= _servers.size() else str(_servers[index].get("name", _servers[index]["address"]))
	server_select.set_item_text(index, base if suffix.is_empty() else "%s   %s" % [base, suffix])
	server_select.set_item_icon(index, _dots[state])
	_refresh_status_label()


func _refresh_status_label() -> void:
	var index := server_select.selected
	if index < 0 or index >= _status.size():
		server_status_label.text = ""
		return
	server_status_label.text = str(_status[index]["text"])
	server_status_label.add_theme_color_override("font_color", STATUS_COLORS[_status[index]["state"]])
	update_btn.visible = _status[index]["state"] == "version" and not _updating


# "host" or "host:port" -> [host, port]; an empty host means nothing was entered.
func _parse_address() -> Array:
	var text := address_input.text.strip_edges()
	var port := Net.DEFAULT_PORT
	var colon := text.rfind(":")
	if colon > 0 and text.count(":") == 1:
		port = int(text.substr(colon + 1))
		text = text.substr(0, colon)
	return [text, port]


# ── Character list view ──
func _build_list_view(root: VBoxContainer) -> void:
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 8)
	list_box.visible = false
	root.add_child(list_box)

	list_title = Label.new()
	list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_title.add_theme_font_size_override("font_size", 15)
	list_title.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	list_box.add_child(list_title)
	list_count = _make_label("")
	list_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_count.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
	list_box.add_child(list_count)

	# Column headings, lined up with the rows below (same widths as _make_row).
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	list_box.add_child(header)
	for column in [["", 64], ["Name", 130], ["Level", 44], ["Race / Class", 170], ["Zone", 0]]:
		var h := _make_label(column[0])
		h.add_theme_color_override("font_color", Color(0.75, 0.68, 0.48))
		h.custom_minimum_size = Vector2(column[1], 0)
		if column[1] == 0:
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(h)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, MAX_ROWS_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_box.add_child(scroll)
	rows_box = VBoxContainer.new()
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override("separation", 4)
	scroll.add_child(rows_box)

	enter_btn = _make_button("Enter World")
	enter_btn.pressed.connect(_on_enter_pressed)
	list_box.add_child(enter_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	list_box.add_child(row)
	create_btn = _make_button("+ Create New Character")
	create_btn.pressed.connect(_on_create_pressed)
	delete_btn = _make_button("Delete Character")
	delete_btn.pressed.connect(_on_delete_pressed)
	attach_btn = _make_button("Add Existing Character")
	attach_btn.tooltip_text = "Bring a character made before accounts into this account (needs its old password)"
	attach_btn.pressed.connect(func() -> void: attach_box.visible = not attach_box.visible)
	logout_btn = _make_button("Log Out")
	logout_btn.pressed.connect(_on_logout_pressed)
	for b in [create_btn, delete_btn, attach_btn, logout_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)

	attach_box = VBoxContainer.new()
	attach_box.visible = false
	attach_box.add_theme_constant_override("separation", 6)
	list_box.add_child(attach_box)
	attach_box.add_child(_make_label("Add a character made before accounts: its name and its old password."))
	var attach_row := HBoxContainer.new()
	attach_row.add_theme_constant_override("separation", 8)
	attach_box.add_child(attach_row)
	attach_name_input = LineEdit.new()
	attach_name_input.placeholder_text = "Character name"
	attach_name_input.max_length = 16
	attach_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attach_row.add_child(attach_name_input)
	attach_password_input = LineEdit.new()
	attach_password_input.secret = true
	attach_password_input.placeholder_text = "Its password"
	attach_password_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attach_password_input.text_submitted.connect(func(_t: String) -> void: _on_attach_pressed())
	attach_row.add_child(attach_password_input)
	var add_btn := _make_button("Add")
	add_btn.pressed.connect(_on_attach_pressed)
	attach_row.add_child(add_btn)


func _set_panel_size(half_width: float, half_height: float) -> void:
	panel.offset_left = -half_width
	panel.offset_right = half_width
	panel.offset_top = -half_height
	panel.offset_bottom = half_height


func _show_account_view() -> void:
	account_box.visible = true
	list_box.visible = false
	_set_panel_size(200.0, 290.0)


func _show_list_view() -> void:
	account_box.visible = false
	list_box.visible = true
	attach_box.visible = false
	_set_panel_size(340.0, 330.0)
	list_title.text = "— %s —" % str(AccountRelay.session.get("account", ""))
	if _characters.is_empty():
		list_count.text = "Loading characters from %s..." % _session_label()
	_update_list_buttons()


func _session_label() -> String:
	var port := int(AccountRelay.session.get("port", Net.DEFAULT_PORT))
	var address := str(AccountRelay.session.get("address", ""))
	return address if port == Net.DEFAULT_PORT else "%s:%d" % [address, port]


func _portrait_for(race: String, sex: String) -> Texture2D:
	var cache_key := race + "/" + sex
	if _portraits.has(cache_key):
		return _portraits[cache_key]
	var texture: Texture2D = null
	var races: Dictionary = Global.character_options.get("races", {})
	var portraits = races.get(race, {}).get("portrait", {})
	if typeof(portraits) == TYPE_DICTIONARY and not portraits.is_empty():
		var path := str(portraits.get(sex, portraits.values()[0]))
		if ResourceLoader.exists(path):
			texture = load(path)
	_portraits[cache_key] = texture
	return texture


# Fills the table from a listing ({"account", "characters": [...], "max"}).
func _populate(info: Dictionary) -> void:
	_characters = info.get("characters", []) if typeof(info.get("characters")) == TYPE_ARRAY else []
	_max_characters = int(info.get("max", AccountRelay.MAX_CHARACTERS))
	for child in rows_box.get_children():
		child.queue_free()
	_row_group = ButtonGroup.new()
	list_count.text = "%d / %d characters on %s" % [_characters.size(), _max_characters, _session_label()]
	if _characters.is_empty():
		var empty := _make_label("You have no characters on this server yet.")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 40)
		rows_box.add_child(empty)
		var first := _make_button("+ Create Your First Character")
		first.custom_minimum_size = Vector2(0, 44)
		first.pressed.connect(_on_create_pressed)
		rows_box.add_child(first)
		_selected = ""
	else:
		var names: Array = _characters.map(func(c: Dictionary) -> String: return str(c.get("name", "")))
		if not names.has(_selected):
			var last := str(Global.settings.get("last_server_character", ""))
			_selected = last if names.has(last) else str(names[0])
		for character in _characters:
			rows_box.add_child(_make_row(character))
	_update_list_buttons()


func _make_row(character: Dictionary) -> Button:
	var character_name := str(character.get("name", ""))
	var row := Button.new()
	row.toggle_mode = true
	row.button_group = _row_group
	row.custom_minimum_size = Vector2(0, 72)
	row.button_pressed = character_name == _selected
	row.toggled.connect(func(on: bool) -> void:
		if on:
			_selected = character_name
			_update_list_buttons()
	)
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			_selected = character_name
			_on_enter_pressed.call_deferred()
	)
	var cells := HBoxContainer.new()
	cells.set_anchors_preset(Control.PRESET_FULL_RECT)
	cells.offset_left = 4.0
	cells.offset_right = -8.0
	cells.add_theme_constant_override("separation", 10)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cells)

	var portrait := TextureRect.new()
	portrait.texture = _portrait_for(str(character.get("race", "")), str(character.get("sex", "")))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cells.add_child(portrait)

	var name_cell := VBoxContainer.new()
	name_cell.custom_minimum_size = Vector2(130, 0)
	name_cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cells.add_child(name_cell)
	var name_label := Label.new()
	name_label.text = str(character.get("display", character_name.capitalize()))
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65))
	name_cell.add_child(name_label)
	if character.get("online", false):
		var online := Label.new()
		online.text = "● in the world"
		online.add_theme_font_size_override("font_size", 10)
		online.add_theme_color_override("font_color", STATUS_COLORS["online"])
		name_cell.add_child(online)

	var race_text := Global.race_display_name(str(character.get("race", "")))
	var cell_texts := [
		[str(int(character.get("level", 0))), 44, false],
		[("%s %s" % [race_text, str(character.get("class", ""))]).strip_edges(), 170, false],
		[str(character.get("zone", "")), 0, true],
	]
	for cell in cell_texts:
		var l := Label.new()
		l.text = cell[0]
		l.add_theme_font_size_override("font_size", 12)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(cell[1], 0)
		if cell[2]:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cells.add_child(l)
	for child in cells.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			for sub in child.get_children():
				(sub as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


func _update_list_buttons() -> void:
	if enter_btn == null:
		return
	var none := _selected.is_empty()
	enter_btn.disabled = _busy or none
	delete_btn.disabled = _busy or none
	create_btn.disabled = _busy or _characters.size() >= _max_characters
	create_btn.tooltip_text = "This account has %d characters, the most allowed. Delete one first." % _max_characters if _characters.size() >= _max_characters else ""
	attach_btn.disabled = _busy
	logout_btn.disabled = _busy
	enter_btn.text = "Enter World" if none else "Enter World as %s" % _display_of(_selected)


func _display_of(character_name: String) -> String:
	for c in _characters:
		if str(c.get("name", "")) == character_name:
			return str(c.get("display", character_name.capitalize()))
	return character_name.capitalize()


# ── Account requests ──
# Shared checks; returns true when the address and account name are usable, else says what is wrong.
func _inputs_ok() -> bool:
	if (_parse_address()[0] as String).is_empty():
		status_label.text = "Enter the server's address."
		return false
	if Net.sanitize_name(account_input.text).is_empty():
		status_label.text = "Account names use letters and numbers only, 2 to 16 characters."
		return false
	return true


func _remember() -> void:
	Global.settings["last_server_address"] = address_input.text.strip_edges()
	Global.settings["last_server_account"] = account_input.text.strip_edges().to_lower()
	Global.save_settings()


func _set_busy(busy: bool) -> void:
	_busy = busy
	for b in [login_btn, create_account_btn]:
		b.disabled = busy
	_update_list_buttons()


# Runs one account request against the session's server (or, while logging in, the pending one).
func _account_request(action: String, args: Dictionary, working_text: String) -> void:
	var target: Dictionary = _pending_session if not _pending_session.is_empty() else AccountRelay.session
	args["account"] = target["account"]
	args["password"] = target["password"]
	_cancel_probes()
	_account_errand = true
	_set_busy(true)
	status_label.text = working_text
	Net.accounts().request(str(target["address"]), int(target["port"]), action, args)


func _begin_session(action: String) -> void:
	var target := _parse_address()
	_remember()
	_pending_session = {"address": target[0], "port": target[1], "account": Net.sanitize_name(account_input.text), "password": password_input.text}
	_account_request(action, {}, "Logging in..." if action == "login" else "Creating your account...")


func _on_login_pressed() -> void:
	if _busy or not _inputs_ok():
		return
	if password_input.text.is_empty():
		status_label.text = "Enter your account's password."
		return
	_begin_session("login")


func _on_create_account_pressed() -> void:
	if _busy or not _inputs_ok():
		return
	if password_input.text.length() < Net.MIN_PASSWORD_LENGTH:
		status_label.text = "Choose a password of at least %d characters for the new account." % Net.MIN_PASSWORD_LENGTH
		return
	if password_input.text != confirm_input.text:
		status_label.text = "The two passwords don't match."
		return
	_begin_session("create")


func _refresh_list() -> void:
	_account_request("login", {}, "")


func _on_logout_pressed() -> void:
	if _busy:
		return
	AccountRelay.session = {}
	_characters = []
	_selected = ""
	password_input.text = ""
	confirm_input.text = ""
	status_label.text = ""
	_show_account_view()
	_probe_all()


func _on_enter_pressed() -> void:
	if _busy or _selected.is_empty() or AccountRelay.session.is_empty():
		return
	Global.settings["last_server_character"] = _selected
	Global.save_settings()
	var s := AccountRelay.session
	status_label.text = "Loading zone, then connecting to %s..." % _session_label()
	_set_busy(true)
	# The zone loads first and connects from inside itself — see Net.begin_join().
	Net.begin_join_server(str(s["address"]), int(s["port"]), _selected, AccountRelay.pack(str(s["account"]), str(s["password"])))


# New characters are designed on the normal creation screen (in server mode), which then hands the finished
# character straight to the server under this account.
func _on_create_pressed() -> void:
	if _busy or AccountRelay.session.is_empty():
		return
	if _characters.size() >= _max_characters:
		status_label.text = "This account already has %d characters. Delete one first." % _max_characters
		return
	var s := AccountRelay.session
	Global.server_creation = {"address": s["address"], "port": s["port"], "password": AccountRelay.pack(str(s["account"]), str(s["password"]))}
	Global.return_to_join_server_menu = true
	get_tree().change_scene_to_file("res://Scenes/character_creation.tscn")


func _on_delete_pressed() -> void:
	if _busy or _selected.is_empty():
		return
	var character := _selected
	_delete_dialog = DeleteCharacterDialog.open(self, _display_of(character), "the server")
	_delete_dialog.confirmed.connect(func(_password: String) -> void:
		_delete_dialog.set_busy(true)
		_account_request("delete", {"character": character}, "Deleting %s..." % _display_of(character))
	)


func _on_attach_pressed() -> void:
	if _busy:
		return
	var character := Net.sanitize_name(attach_name_input.text)
	if character.is_empty():
		status_label.text = "Type the character's name."
		return
	if attach_password_input.text.is_empty():
		status_label.text = "Type that character's old password."
		return
	_account_request("attach", {"character": character, "character_password": attach_password_input.text}, "Adding %s..." % character.capitalize())


func _on_server_request_done(ok: bool, kind: String, reason: String, info: Dictionary) -> void:
	if _probe_index >= 0 and not _account_errand:  # the answer to a status probe
		var probed := _probe_index
		_probe_index = -1
		_apply_probe_result(probed, ok, kind, reason, info)
		_probe_next()
		return
	_account_errand = false
	_set_busy(false)
	if ok:
		if not _pending_session.is_empty():
			AccountRelay.session = _pending_session
			_pending_session = {}
			password_input.text = ""
			confirm_input.text = ""
		if is_instance_valid(_delete_dialog):
			_delete_dialog.close()
		if kind == "attached":
			attach_name_input.text = ""
			attach_password_input.text = ""
			attach_box.visible = false
		_show_list_view()
		_populate(info)
		status_label.text = reason
		return
	_pending_session = {}
	if is_instance_valid(_delete_dialog):
		_delete_dialog.set_status(reason)  # stay open so the player can read why
		status_label.text = ""
		return
	status_label.text = reason
	if list_box.visible and kind in ["bad_password", "no_account", "locked", "version", "offline"] and _characters.is_empty():
		# The saved login no longer works (or the server is gone): back to the login form.
		AccountRelay.session = {}
		_show_account_view()
		_probe_all()


# ── Game updates ──
# Where a server publishes its updates: an explicit "update_url" in servers.json, else http://<address>:<update_port or 8911>.
func _update_url_for(index: int) -> String:
	var target := _target_for(index)
	if index < _servers.size():
		return GameUpdater.url_for(str(target[0]), int(_servers[index].get("update_port", GameUpdater.DEFAULT_PORT)), str(_servers[index].get("update_url", "")))
	return GameUpdater.url_for(str(target[0]))


# "v0.4.0 (2aff48e)" -> "2aff48e"; "" when there is no build id in it.
static func _stamp_of(display: String) -> String:
	var open := display.find("(")
	var close := display.find(")", open)
	return display.substr(open + 1, close - open - 1) if open >= 0 and close > open else ""


func _on_update_pressed() -> void:
	if _updating or _busy:
		return
	var index := server_select.selected
	if index < 0 or (index >= _servers.size() and (_parse_address()[0] as String).is_empty()):
		return
	_cancel_probes()
	_updating = true
	_set_busy(true)
	update_btn.visible = false
	status_label.text = "Checking for the update..."
	if _updater == null:
		_updater = GameUpdater.new()
		_updater.progress.connect(_on_update_progress)
		add_child(_updater)
	var checked: Dictionary = await _updater.check(_update_url_for(index))
	if checked.status != "available":
		# Already at the published build but the server still differs: the server has not been updated (or is newer).
		var message: String = checked.message
		if checked.status == "up_to_date":
			message += " This server runs %s, so ask the host to update the server." % _server_builds.get(index, "another build")
		_finish_update(message)
		return
	var published: String = _updater.entry_stamp()
	var server_stamp := _stamp_of(str(_server_builds.get(index, "")))
	if not server_stamp.is_empty() and server_stamp != published:
		_finish_update("The latest published update is %s but this server runs %s. Ask the host to update the server (or publish again)." % [published, server_stamp])
		return
	status_label.text = "Downloading update %s..." % published
	update_bar.value = 0
	update_bar.visible = true
	var got: Dictionary = await _updater.download()
	if not got.ok:
		_finish_update(got.message)
		return
	status_label.text = got.message
	await get_tree().create_timer(1.5).timeout
	GameUpdater.restart(get_tree())


func _on_update_progress(received: int, total: int) -> void:
	update_bar.max_value = maxi(total, 1)
	update_bar.value = received
	status_label.text = "Downloading update... %.1f / %.1f MB" % [received / 1048576.0, total / 1048576.0]


func _finish_update(message: String) -> void:
	_updating = false
	_set_busy(false)
	update_bar.visible = false
	status_label.text = message
	_refresh_status_label()


func _on_back_pressed() -> void:
	Net.disconnect_game()
	queue_free()
