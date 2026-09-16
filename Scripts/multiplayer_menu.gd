# multiplayer_menu.gd — Host/Join screen for LAN co-op, reached from the
# main menu's Multiplayer button. Manual IP entry (no auto-discovery/relay) —
# good enough for testing across two machines on the same network. Loads an
# existing single-player save by character name (same file format/loader as
# the normal Begin Your Adventure flow) rather than creating a new one.
extends CanvasLayer

var panel: Panel
var status_label: Label
var character_select: OptionButton
var ip_input: LineEdit
var host_btn: Button
var join_btn: Button

var _connecting := false


func _ready() -> void:
	layer = 10
	_build_ui()

	Net.connection_succeeded.connect(_on_connection_succeeded)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_disconnected.connect(_on_server_disconnected)


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.55)
	add_child(overlay)

	panel = Panel.new()
	panel.custom_minimum_size = Vector2(380, 340)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -190.0
	panel.offset_top    = -170.0
	panel.offset_right  =  190.0
	panel.offset_bottom =  170.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  20.0
	vbox.offset_top    =  16.0
	vbox.offset_right  = -20.0
	vbox.offset_bottom = -16.0
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "— Multiplayer (LAN) —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	vbox.add_child(title)

	vbox.add_child(_make_label_row("Character"))
	character_select = OptionButton.new()
	vbox.add_child(character_select)
	_populate_character_dropdown()

	vbox.add_child(HSeparator.new())

	var host_label := Label.new()
	host_label.text = "Host a Game"
	host_label.add_theme_font_size_override("font_size", 12)
	host_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	vbox.add_child(host_label)

	host_btn = _make_button("Host Game")
	host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(host_btn)

	vbox.add_child(HSeparator.new())

	var join_label := Label.new()
	join_label.text = "Join a Game"
	join_label.add_theme_font_size_override("font_size", 12)
	join_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	vbox.add_child(join_label)

	ip_input = LineEdit.new()
	ip_input.placeholder_text = "Host's LAN IP (e.g. 192.168.1.23)"
	vbox.add_child(ip_input)

	join_btn = _make_button("Join Game")
	join_btn.pressed.connect(_on_join_pressed)
	vbox.add_child(join_btn)

	vbox.add_child(HSeparator.new())

	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	vbox.add_child(status_label)

	var back_btn := _make_button("Back")
	back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(back_btn)


# Same save-directory scan as load_game.gd's load_save_files() — a dropdown
# of every existing single-player character instead of typing the name in by
# hand (and risking a typo that silently fails to find the save file).
func _populate_character_dropdown() -> void:
	character_select.clear()
	var save_dir_path := ProjectSettings.globalize_path("user://saves/")
	var dir := DirAccess.open(save_dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var stems: Array = []
	while file_name != "":
		if file_name.ends_with("_character_stats.json"):
			stems.append(file_name.replace("_character_stats.json", ""))
		file_name = dir.get_next()
	dir.list_dir_end()
	stems.sort()
	for stem in stems:
		character_select.add_item(str(stem).capitalize())
		character_select.set_item_metadata(character_select.item_count - 1, stem)
	if character_select.item_count == 0:
		character_select.add_item("No characters found")
		character_select.disabled = true


func _selected_character_name() -> String:
	if character_select.item_count == 0 or character_select.disabled:
		return ""
	var idx := character_select.selected
	if idx < 0:
		idx = 0
	return str(character_select.get_item_metadata(idx))


func _make_label_row(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	return l


func _panel_style() -> StyleBoxFlat:
	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.08, 0.07, 0.06, 0.97)
	bg.border_color = Color(0.45, 0.38, 0.25)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(5)
	return bg


func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 32)
	return btn


func _load_named_character(char_name: String) -> bool:
	if char_name.is_empty():
		status_label.text = "No saved characters found — create one first."
		return false
	var data := Global.load_player_data_from_file(char_name)
	if data.is_empty():
		status_label.text = "No saved character named '%s'." % char_name
		return false
	return true


func _on_host_pressed() -> void:
	if _connecting:
		return
	if not _load_named_character(_selected_character_name()):
		return
	if Net.host_game() != OK:
		status_label.text = "Failed to host — is the port already in use?"
		return
	status_label.text = "Hosting on %s:%d. Loading zone..." % [Net.get_local_ip(), Net.DEFAULT_PORT]
	_connecting = true
	get_tree().change_scene_to_file(Net.pending_zone_path)


func _on_join_pressed() -> void:
	if _connecting:
		return
	var ip := ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Enter the host's LAN IP."
		return
	if not _load_named_character(_selected_character_name()):
		return
	if Net.join_game(ip) != OK:
		status_label.text = "Failed to connect."
		return
	status_label.text = "Connecting to %s..." % ip
	_connecting = true
	host_btn.disabled = true
	join_btn.disabled = true


func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_file(Net.pending_zone_path)


func _on_connection_failed() -> void:
	status_label.text = "Could not connect. Check the IP and make sure the host has started."
	_connecting = false
	host_btn.disabled = false
	join_btn.disabled = false


func _on_server_disconnected() -> void:
	status_label.text = "Disconnected from host."
	_connecting = false
	host_btn.disabled = false
	join_btn.disabled = false


func _on_back_pressed() -> void:
	Net.disconnect_game()
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")
