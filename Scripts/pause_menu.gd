# pause_menu.gd — Pause / save menu opened with Escape
extends CanvasLayer

signal closed

func _ready() -> void:
	layer = 20
	_build_ui()


func _build_ui() -> void:
	# Dim overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Centered panel
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(260, 160)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -130.0
	panel.offset_top    = -80.0
	panel.offset_right  =  130.0
	panel.offset_bottom =  80.0

	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.08, 0.07, 0.06, 0.97)
	bg.border_color = Color(0.45, 0.38, 0.25)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  20.0
	vbox.offset_top    =  16.0
	vbox.offset_right  = -20.0
	vbox.offset_bottom = -16.0
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "— Paused —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	vbox.add_child(title)

	var save_btn := _make_button("Save Game")
	save_btn.pressed.connect(_on_save)
	vbox.add_child(save_btn)

	var exit_btn := _make_button("Save and Exit")
	exit_btn.pressed.connect(_on_save_and_exit)
	vbox.add_child(exit_btn)

	var resume_btn := _make_button("Resume")
	resume_btn.pressed.connect(_on_resume)
	vbox.add_child(resume_btn)


func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 34)
	return btn


func _on_save() -> void:
	Global.save_player_data_to_file()
	GameLog.log_general("[color=#88cc88]Game saved.[/color]")
	_on_resume()


func _on_save_and_exit() -> void:
	Global.save_player_data_to_file()
	# Free every CanvasLayer on the root — covers HUD, character sheet, backpack,
	# abilities book, loot window, inspect popup, and this pause menu itself.
	# Autoloads (Global, GameLog, Inventory, GlobalBackgroundMusic) are not
	# CanvasLayers so they are unaffected.
	for node in get_tree().root.get_children():
		if node is CanvasLayer:
			node.queue_free()
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")


func _on_resume() -> void:
	emit_signal("closed")
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_resume()
		get_viewport().set_input_as_handled()
