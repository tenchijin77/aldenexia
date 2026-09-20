# delete_character_dialog.gd — "Delete <name>?" confirmation shared by the Load Game screen, the LAN
# multiplayer screen and the Join a Server screen. Deleting only unlocks once the player has typed the
# character's name exactly (case-sensitive), so a stray click can't destroy a character. The dialog only
# asks: the caller does the deleting when `confirmed` fires, then calls close() — or set_status() to
# keep the dialog open with a message (a wrong server password, say) so the player can try again.
class_name DeleteCharacterDialog
extends CanvasLayer

## Emitted when the name matches and Delete is pressed. `password` is "" unless needs_password was set.
signal confirmed(password: String)

var _expected_name := ""
var _needs_password := false
var _name_input: LineEdit
var _password_input: LineEdit
var _delete_button: Button
var _cancel_button: Button
var _status: Label


# Opens the dialog on `parent` (the screen that asked). `where` is "this computer" or "the server".
static func open(parent: Node, display_name: String, where: String, needs_password: bool = false) -> DeleteCharacterDialog:
	var dialog := DeleteCharacterDialog.new()
	dialog._expected_name = display_name
	dialog._needs_password = needs_password
	dialog._build(display_name, where)
	parent.add_child(dialog)
	dialog._name_input.grab_focus()
	return dialog


func set_status(text: String) -> void:
	_status.text = text
	set_busy(false)


func set_busy(busy: bool) -> void:
	_name_input.editable = not busy
	if _password_input:
		_password_input.editable = not busy
	_cancel_button.disabled = busy
	_delete_button.disabled = busy or not _can_delete()


func close() -> void:
	queue_free()


func _build(display_name: String, where: String) -> void:
	layer = 20

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.7)
	add_child(overlay)  # also swallows clicks meant for the screen underneath

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 0)
	panel.offset_left = -200.0
	panel.offset_right = 200.0
	panel.offset_top = -150.0 if _needs_password else -125.0
	panel.offset_bottom = 150.0 if _needs_password else 125.0
	panel.add_theme_stylebox_override("panel", Global.opaque_window_bg_style())
	add_child(panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20.0
	box.offset_top = 16.0
	box.offset_right = -20.0
	box.offset_bottom = -16.0
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Delete %s?" % display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.5, 0.4))
	box.add_child(title)

	var warning := Label.new()
	warning.text = "This permanently deletes %s from %s. It cannot be undone." % [display_name, where]
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.add_theme_font_size_override("font_size", 12)
	box.add_child(warning)

	var prompt := Label.new()
	prompt.text = "To confirm, type the character's name exactly:  %s" % display_name
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_theme_font_size_override("font_size", 12)
	prompt.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	box.add_child(prompt)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = display_name
	_name_input.text_changed.connect(func(_t: String) -> void: _refresh())
	_name_input.text_submitted.connect(func(_t: String) -> void: _on_delete_pressed())
	box.add_child(_name_input)

	if _needs_password:
		_password_input = LineEdit.new()
		_password_input.placeholder_text = "%s's password" % display_name
		_password_input.secret = true
		_password_input.text_changed.connect(func(_t: String) -> void: _refresh())
		_password_input.text_submitted.connect(func(_t: String) -> void: _on_delete_pressed())
		box.add_child(_password_input)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.95, 0.6, 0.45))
	box.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.custom_minimum_size = Vector2(0, 32)
	_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_button.pressed.connect(close)
	row.add_child(_cancel_button)

	_delete_button = Button.new()
	_delete_button.text = "Delete"
	_delete_button.custom_minimum_size = Vector2(0, 32)
	_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_button.disabled = true
	_delete_button.add_theme_color_override("font_color", Color(0.95, 0.5, 0.4))
	_delete_button.pressed.connect(_on_delete_pressed)
	row.add_child(_delete_button)


func _can_delete() -> bool:
	if _name_input.text != _expected_name:
		return false
	return not _needs_password or not _password_input.text.is_empty()


func _refresh() -> void:
	_delete_button.disabled = not _can_delete()


func _on_delete_pressed() -> void:
	if not _can_delete() or _delete_button.disabled:
		return
	_status.text = ""
	set_busy(true)
	confirmed.emit(_password_input.text if _needs_password else "")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not _cancel_button.disabled:
		get_viewport().set_input_as_handled()
		close()
