# join_server_menu.gd — "Join a Server" screen, reached from the main menu. Unlike the LAN screen the
# character isn't picked from local saves: it lives ON the server, found by name + password. From here
# the player can enter the world, create a new server character (character_creation.tscn in server mode,
# see Global.server_creation) or delete one (needs its password). The server list comes from
# Data/servers.json; any address can also be typed. Each entry shows whether it is online, how many players
# it has and whether its version matches this build (Net.probe_server, one server at a time).
# See net.gd's "Server-side characters" section.
extends CanvasLayer

const SERVERS_PATH := "res://Data/servers.json"

var panel: Panel
var server_select: OptionButton
var address_input: LineEdit
var name_input: LineEdit
var password_input: LineEdit
var confirm_input: LineEdit
var enter_btn: Button
var create_btn: Button
var delete_btn: Button
var status_label: Label

var refresh_btn: Button
var server_status_label: Label

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
	panel.offset_top = -270.0
	panel.offset_bottom = 270.0
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

	vbox.add_child(HSeparator.new())

	vbox.add_child(_make_label("Character name"))
	name_input = LineEdit.new()
	name_input.placeholder_text = "Letters and numbers, 2-16"
	name_input.max_length = 16
	vbox.add_child(name_input)

	vbox.add_child(_make_label("Password"))
	password_input = LineEdit.new()
	password_input.secret = true
	password_input.placeholder_text = "Your character's password"
	password_input.text_submitted.connect(func(_t: String) -> void: _on_enter_pressed())
	vbox.add_child(password_input)

	vbox.add_child(_make_label("Confirm password (only when creating a new character)"))
	confirm_input = LineEdit.new()
	confirm_input.secret = true
	confirm_input.placeholder_text = "Type it again"
	vbox.add_child(confirm_input)

	enter_btn = _make_button("Enter World")
	enter_btn.pressed.connect(_on_enter_pressed)
	vbox.add_child(enter_btn)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	create_btn = _make_button("+ Create New Character")
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_btn.pressed.connect(_on_create_pressed)
	row.add_child(create_btn)
	delete_btn = _make_button("Delete Character")
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_btn.pressed.connect(_on_delete_pressed)
	row.add_child(delete_btn)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(status_label)

	var back_btn := _make_button("Back")
	back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(back_btn)

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
	name_input.text = str(Global.settings.get("last_server_character", ""))
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
		_apply_status(index, "version", "Update needed — this server runs %s" % info.get("version", "another version"), "(update needed)")
	elif kind == "offline":
		_apply_status(index, "offline", "Offline or unreachable", "(offline)")
	else:
		_apply_status(index, "offline", reason, "(unavailable)")


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


# "host" or "host:port" -> [host, port]; an empty host means nothing was entered.
func _parse_address() -> Array:
	var text := address_input.text.strip_edges()
	var port := Net.DEFAULT_PORT
	var colon := text.rfind(":")
	if colon > 0 and text.count(":") == 1:
		port = int(text.substr(colon + 1))
		text = text.substr(0, colon)
	return [text, port]


# Shared checks; returns true when the address and name are usable, else says what is wrong.
func _inputs_ok(need_name: bool) -> bool:
	if (_parse_address()[0] as String).is_empty():
		status_label.text = "Enter the server's address."
		return false
	if need_name and Net.sanitize_name(name_input.text).is_empty():
		status_label.text = "Character names use letters and numbers only, 2 to 16 characters."
		return false
	return true


func _remember() -> void:
	Global.settings["last_server_address"] = address_input.text.strip_edges()
	Global.settings["last_server_character"] = name_input.text.strip_edges()
	Global.save_settings()


func _set_busy(busy: bool) -> void:
	_busy = busy
	for b in [enter_btn, create_btn, delete_btn]:
		b.disabled = busy


func _on_enter_pressed() -> void:
	if _busy or not _inputs_ok(true):
		return
	if password_input.text.is_empty():
		status_label.text = "Enter your character's password."
		return
	_cancel_probes()
	_remember()
	var target := _parse_address()
	status_label.text = "Loading zone, then connecting to %s..." % address_input.text.strip_edges()
	_set_busy(true)
	# The zone loads first and connects from inside itself — see Net.begin_join().
	Net.begin_join_server(target[0], target[1], name_input.text.strip_edges(), password_input.text)


# New characters are designed on the normal creation screen (in server mode), which then hands the
# finished character straight to the server. The password is chosen here and typed twice, since a
# typo would lock the player out of their own new character.
func _on_create_pressed() -> void:
	if _busy or not _inputs_ok(false):
		return
	if password_input.text.length() < Net.MIN_PASSWORD_LENGTH:
		status_label.text = "Choose a password of at least %d characters for the new character." % Net.MIN_PASSWORD_LENGTH
		return
	if password_input.text != confirm_input.text:
		status_label.text = "The two passwords don't match."
		return
	_cancel_probes()
	_remember()
	var target := _parse_address()
	Global.server_creation = {"address": target[0], "port": target[1], "password": password_input.text}
	Global.return_to_join_server_menu = true
	get_tree().change_scene_to_file("res://Scenes/character_creation.tscn")


func _on_delete_pressed() -> void:
	if _busy or not _inputs_ok(true):
		return
	var character := name_input.text.strip_edges()
	_delete_dialog = DeleteCharacterDialog.open(self, character, "the server", true)
	_delete_dialog.confirmed.connect(func(password: String) -> void:
		_cancel_probes()
		var target := _parse_address()
		status_label.text = "Deleting %s..." % character
		Net.request_server_delete(target[0], target[1], character, password)
	)


func _on_server_request_done(ok: bool, kind: String, reason: String, info: Dictionary) -> void:
	if _probe_index >= 0:  # the answer to a status probe, not to a delete
		var probed := _probe_index
		_probe_index = -1
		_apply_probe_result(probed, ok, kind, reason, info)
		_probe_next()
		return
	if ok:
		if is_instance_valid(_delete_dialog):
			_delete_dialog.close()
		status_label.text = reason
		password_input.text = ""
		confirm_input.text = ""
	elif is_instance_valid(_delete_dialog):
		_delete_dialog.set_status(reason)  # stay open so a wrong password can be retyped
		status_label.text = ""
	else:
		status_label.text = reason


func _on_back_pressed() -> void:
	Net.disconnect_game()
	queue_free()
