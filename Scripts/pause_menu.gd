# pause_menu.gd — Pause / save menu opened with Escape. Also hosts the
# Options panel (audio volume, invert look Y, loot preference management).
extends CanvasLayer

signal closed

var main_panel: Panel
var options_panel: Panel


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

	_build_main_panel()
	_build_options_panel()
	options_panel.visible = false


# ===== Main panel (Save / Save & Exit / Options / Resume) =====

func _build_main_panel() -> void:
	var panel := Panel.new()
	main_panel = panel
	panel.custom_minimum_size = Vector2(260, 190)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -130.0
	panel.offset_top    = -95.0
	panel.offset_right  =  130.0
	panel.offset_bottom =  95.0
	panel.add_theme_stylebox_override("panel", _panel_style())
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

	var options_btn := _make_button("Options")
	options_btn.pressed.connect(_show_options)
	vbox.add_child(options_btn)

	var exit_btn := _make_button("Save and Exit")
	exit_btn.pressed.connect(_on_save_and_exit)
	vbox.add_child(exit_btn)

	var resume_btn := _make_button("Resume")
	resume_btn.pressed.connect(_on_resume)
	vbox.add_child(resume_btn)


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
	btn.custom_minimum_size = Vector2(0, 34)
	return btn


# ===== Options panel =====

func _build_options_panel() -> void:
	var panel := Panel.new()
	options_panel = panel
	panel.custom_minimum_size = Vector2(420, 460)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -210.0
	panel.offset_top    = -230.0
	panel.offset_right  =  210.0
	panel.offset_bottom =  230.0
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
	title.text = "— Options —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	vbox.add_child(title)

	vbox.add_child(_make_slider_row("Music Volume", "music_volume"))
	vbox.add_child(_make_slider_row("Sound Volume", "sfx_volume"))
	vbox.add_child(_make_invert_y_row())
	vbox.add_child(_make_toggle_row("Show Name Tags", "show_name_tags"))

	vbox.add_child(HSeparator.new())

	var loot_label := Label.new()
	loot_label.text = "Loot Preferences"
	loot_label.add_theme_font_size_override("font_size", 12)
	loot_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	vbox.add_child(loot_label)

	var hint := Label.new()
	hint.text = "Items you've marked Loot/Ignore/Sell in the loot window — reset one if you marked it by accident."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_loot_prefs_list = VBoxContainer.new()
	_loot_prefs_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loot_prefs_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_loot_prefs_list)

	var back_btn := _make_button("Back")
	back_btn.pressed.connect(_hide_options)
	vbox.add_child(back_btn)


func _make_slider_row(label_text: String, settings_key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = Global.settings.get(settings_key, 1.0) * 100.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = "%d%%" % int(slider.value)
	value_label.custom_minimum_size = Vector2(40, 0)
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%d%%" % int(v)
		Global.settings[settings_key] = v / 100.0
		Global.apply_audio_settings()
	)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		Global.save_settings()
	)

	return row


func _make_invert_y_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = "Invert Look Y"
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)

	# Plain toggle Button with explicit stylebox overrides, not CheckBox — see
	# corpse_loot_window.gd's _make_preference_checkboxes() for why: CheckBox's
	# built-in check glyph doesn't render in this project for reasons that
	# weren't worth chasing further, so every toggle in the game now draws its
	# own on/off indicator via background color instead.
	var off_style := StyleBoxFlat.new()
	off_style.bg_color = Color(0.16, 0.16, 0.18)
	off_style.border_color = Color(0.4, 0.4, 0.45)
	off_style.set_border_width_all(1)
	off_style.set_corner_radius_all(3)
	off_style.content_margin_left = 10
	off_style.content_margin_right = 10
	off_style.content_margin_top = 3
	off_style.content_margin_bottom = 3

	var on_style := StyleBoxFlat.new()
	on_style.bg_color = Color(0.25, 0.5, 0.28)
	on_style.border_color = Color(0.5, 0.95, 0.55)
	on_style.set_border_width_all(1)
	on_style.set_corner_radius_all(3)
	on_style.content_margin_left = 10
	on_style.content_margin_right = 10
	on_style.content_margin_top = 3
	on_style.content_margin_bottom = 3

	var btn := Button.new()
	btn.text = "On" if Global.settings.get("invert_look_y", false) else "Off"
	btn.toggle_mode = true
	btn.button_pressed = Global.settings.get("invert_look_y", false)
	btn.add_theme_stylebox_override("normal", off_style)
	btn.add_theme_stylebox_override("hover", off_style)
	btn.add_theme_stylebox_override("pressed", on_style)
	btn.add_theme_stylebox_override("hover_pressed", on_style)
	btn.toggled.connect(func(pressed: bool) -> void:
		btn.text = "On" if pressed else "Off"
		Global.settings["invert_look_y"] = pressed
		Global.save_settings()
	)
	row.add_child(btn)

	return row


# Generic version of _make_invert_y_row()'s on/off toggle button, for any
# boolean Global.settings key — defaults to true unless default_value says
# otherwise (Show Name Tags defaults on, unlike Invert Look Y).
func _make_toggle_row(label_text: String, settings_key: String, default_value: bool = true) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)

	var off_style := StyleBoxFlat.new()
	off_style.bg_color = Color(0.16, 0.16, 0.18)
	off_style.border_color = Color(0.4, 0.4, 0.45)
	off_style.set_border_width_all(1)
	off_style.set_corner_radius_all(3)
	off_style.content_margin_left = 10
	off_style.content_margin_right = 10
	off_style.content_margin_top = 3
	off_style.content_margin_bottom = 3

	var on_style := StyleBoxFlat.new()
	on_style.bg_color = Color(0.25, 0.5, 0.28)
	on_style.border_color = Color(0.5, 0.95, 0.55)
	on_style.set_border_width_all(1)
	on_style.set_corner_radius_all(3)
	on_style.content_margin_left = 10
	on_style.content_margin_right = 10
	on_style.content_margin_top = 3
	on_style.content_margin_bottom = 3

	var btn := Button.new()
	var current: bool = Global.settings.get(settings_key, default_value)
	btn.text = "On" if current else "Off"
	btn.toggle_mode = true
	btn.button_pressed = current
	btn.add_theme_stylebox_override("normal", off_style)
	btn.add_theme_stylebox_override("hover", off_style)
	btn.add_theme_stylebox_override("pressed", on_style)
	btn.add_theme_stylebox_override("hover_pressed", on_style)
	btn.toggled.connect(func(pressed: bool) -> void:
		btn.text = "On" if pressed else "Off"
		Global.settings[settings_key] = pressed
		Global.save_settings()
	)
	row.add_child(btn)

	return row


var _loot_prefs_list: VBoxContainer


func _rebuild_loot_prefs_list() -> void:
	for child in _loot_prefs_list.get_children():
		_loot_prefs_list.remove_child(child)
		child.queue_free()

	var prefs: Dictionary = Global.player_data.get("loot_preferences", {})
	if prefs.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No saved preferences yet."
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		empty_lbl.add_theme_font_size_override("font_size", 10)
		_loot_prefs_list.add_child(empty_lbl)
		return

	for item_id in prefs:
		_loot_prefs_list.add_child(_make_loot_pref_row(item_id, prefs[item_id]))


func _make_loot_pref_row(item_id: String, preference: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = item_id.replace("_", " ").capitalize()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 10)
	row.add_child(name_label)

	var pref_label := Label.new()
	pref_label.text = preference.capitalize()
	pref_label.custom_minimum_size = Vector2(50, 0)
	pref_label.add_theme_font_size_override("font_size", 10)
	pref_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	row.add_child(pref_label)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.add_theme_font_size_override("font_size", 9)
	reset_btn.custom_minimum_size = Vector2(50, 20)
	reset_btn.pressed.connect(func() -> void:
		var prefs: Dictionary = Global.player_data.get("loot_preferences", {})
		prefs.erase(item_id)
		Global.player_data["loot_preferences"] = prefs
		Global.save_player_data_to_file()
		_rebuild_loot_prefs_list()
	)
	row.add_child(reset_btn)

	return row


func _show_options() -> void:
	main_panel.visible = false
	options_panel.visible = true
	_rebuild_loot_prefs_list()


func _hide_options() -> void:
	options_panel.visible = false
	main_panel.visible = true


# ===== Main panel actions =====

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
		if options_panel.visible:
			_hide_options()
		else:
			_on_resume()
		get_viewport().set_input_as_handled()
