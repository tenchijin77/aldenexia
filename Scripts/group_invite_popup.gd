# group_invite_popup.gd — "So-and-so invites you to their group." Accept/
# Decline popup shown to the invited player. Spawned by net.gd's
# _rpc_receive_group_invite() the moment an invite RPC arrives; the response
# goes back to the inviter over the network via Net.send_group_invite_response().
# Also used for trade invites (trade_relay.gd) through ask(): any "Accept / Decline" question in the same look.
# Opens in the middle of the screen; drag it anywhere by its panel.
extends CanvasLayer

var _inviter_peer_id: int = -1
var _answer: Callable = Callable()   # ask(): called with true / false instead of the group-invite reply
var _panel: Panel
var _dragging := false


func setup(inviter_peer_id: int, inviter_name: String) -> void:
	_inviter_peer_id = inviter_peer_id
	layer = 15
	_build_ui("%s invites you to their group." % inviter_name, "Accept", "Decline")


# A general question in this popup's look: `on_answer` gets true (accept) or false (decline).
func ask(text: String, accept_text: String, decline_text: String, on_answer: Callable) -> void:
	_answer = on_answer
	layer = 15
	_build_ui(text, accept_text, decline_text)


# Answers "no" on its own (an invite that times out).
func expire() -> void:
	_on_decline_pressed()


func _build_ui(text: String, accept_text: String, decline_text: String) -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.35)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(320, 130)
	# Centred on the screen.
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -160.0
	panel.offset_top    = -65.0
	panel.offset_right  =  160.0
	panel.offset_bottom =  65.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_panel_gui_input)
	_panel = panel

	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.08, 0.07, 0.06, 0.97)
	bg.border_color = Color(0.45, 0.38, 0.25)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  16.0
	vbox.offset_top    =  14.0
	vbox.offset_right  = -16.0
	vbox.offset_bottom = -14.0
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	vbox.add_child(label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var accept_btn := Button.new()
	accept_btn.text = accept_text
	accept_btn.custom_minimum_size = Vector2(100, 30)
	accept_btn.pressed.connect(_on_accept_pressed)
	btn_row.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = decline_text
	decline_btn.custom_minimum_size = Vector2(100, 30)
	decline_btn.pressed.connect(_on_decline_pressed)
	btn_row.add_child(decline_btn)


func _on_accept_pressed() -> void:
	_reply(true)


func _on_decline_pressed() -> void:
	_reply(false)


func _reply(yes: bool) -> void:
	if is_queued_for_deletion():
		return
	if _answer.is_valid():
		_answer.call(yes)
	else:
		Net.send_group_invite_response(_inviter_peer_id, yes)
	queue_free()


# Drag the popup by its panel.
func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_panel.position += event.relative
