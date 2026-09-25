# appearance_editor.gd — the window where a character's look is chosen (Scripts/appearance.gd, 2026-09-25): a turning
# preview of the model on the left, sliders and colour swatches on the right. Two uses:
#   "full"   character creation, and Lumora's mirror for a character made before sliders existed (once: saving locks it)
#   "locked" the mirror afterwards: only the hair colour can change (hair and beard styles and accessories will join it
#            when their models exist)
# Built in code. open() returns the window; on_done gets the chosen look, or {} if cancelled.
class_name AppearanceEditor
extends CanvasLayer

const SLIDER_LABELS := {"height": "Height", "weight": "Weight", "muscle": "Muscle", "bust": "Bust", "waist": "Waist", "hips": "Hips"}
const COLOUR_ROWS := [["skin_color", "Skin"], ["hair_color", "Hair"], ["eye_color", "Eyes"]]

var race := "human"
var sex := "male"
var model_info: Dictionary = {}
var mode := "full"
var confirm_final := false        # the mirror's first use: saving asks once more, since it can't be undone
var look: Dictionary = {}
var on_done: Callable

var _model: Node3D
var _pivot: Node3D
var _base_scale := Vector3.ONE
var _save_button: Button
var _armed := false
var _sliders := {}
var _swatch_rows := {}
var _dragging := false


static func open(parent: Node, p_race: String, p_sex: String, p_model_info: Dictionary, current: Dictionary, p_mode: String,
		done: Callable, p_confirm_final := false) -> AppearanceEditor:
	var w := AppearanceEditor.new()
	w.race = p_race.to_lower()
	w.sex = p_sex.to_lower()
	w.model_info = p_model_info
	w.mode = p_mode
	w.confirm_final = p_confirm_final
	w.look = Appearance.validate(current, w.sex, w.race)
	w.on_done = done
	w.layer = 50
	parent.add_child(w)
	return w


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(860, 560)
	panel.position = -panel.custom_minimum_size / 2.0
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	var title := Label.new()
	title.text = "Your Appearance" if mode == "full" and not confirm_final else "The Silvered Mirror"
	title.add_theme_font_size_override("font_size", 22)
	outer.add_child(title)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
	if mode == "locked":
		note.text = "Your look is set. Only your hair can change here. Hair and beard styles and jewellery will come with new models."
	elif confirm_final:
		note.text = "Choose your look once. After you save, only your hair (and, later, beard style and jewellery) can change."
	else:
		note.text = "Your look is chosen now and kept: afterwards only your hair (and, later, beard style and jewellery) can change."
	outer.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(row)
	row.add_child(_build_preview())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("separation", 8)
	scroll.add_child(options)
	if mode == "full":
		options.add_child(_heading("Body"))
		for s in Appearance.SLIDERS:
			if Appearance.FEMALE_ONLY.has(s) and sex != "female":
				continue
			options.add_child(_slider_row(s))
	options.add_child(_heading("Colours"))
	for pair in COLOUR_ROWS:
		if mode == "locked" and pair[0] != "hair_color":
			continue
		if pair[0] == "eye_color" and not Appearance.EYE_COLOUR_ENABLED:
			continue
		options.add_child(_swatch_row(pair[0], pair[1]))
	var styles := Label.new()
	styles.text = "Hair style, beard and jewellery: coming with the new character models."
	styles.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	styles.modulate = Color(1, 1, 1, 0.55)
	options.add_child(styles)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	outer.add_child(buttons)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(_on_reset)
	buttons.add_child(reset)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): _finish({}))
	buttons.add_child(cancel)
	_save_button = Button.new()
	_save_button.text = "Save look"
	_save_button.pressed.connect(_on_save)
	buttons.add_child(_save_button)
	_refresh_preview()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	return l


func _slider_row(key: String) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = SLIDER_LABELS.get(key, key.capitalize())
	l.custom_minimum_size.x = 80
	h.add_child(l)
	var s := HSlider.new()
	var r: Array = Appearance.SLIDERS[key]
	s.min_value = r[0]
	s.max_value = r[1]
	s.step = 0.05
	s.value = float(look.get(key, 0.0))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v): look[key] = v; _disarm(); _refresh_preview())
	h.add_child(s)
	_sliders[key] = s
	return h


func _swatch_row(key: String, label: String) -> Control:
	var v := VBoxContainer.new()
	var l := Label.new()
	l.text = label
	v.add_child(l)
	var flow := HFlowContainer.new()
	v.add_child(flow)
	var palette: Array = Appearance.skin_palette(race) if key == "skin_color" else (Appearance.HAIR_PALETTE if key == "hair_color" else Appearance.EYE_PALETTE)
	var buttons := []
	for hex in [""] + palette:
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30) if not hex.is_empty() else Vector2(74, 30)
		b.toggle_mode = true
		b.tooltip_text = "As painted" if hex.is_empty() else hex
		if hex.is_empty():
			b.text = "Natural"
		else:
			for st in ["normal", "hover", "pressed", "focus"]:
				var box := StyleBoxFlat.new()
				box.bg_color = Color.html(hex)
				box.set_corner_radius_all(4)
				box.set_border_width_all(3 if st == "pressed" else 1)
				box.border_color = Color(1, 0.9, 0.5) if st == "pressed" else Color(0, 0, 0, 0.6)
				b.add_theme_stylebox_override(st, box)
		b.button_pressed = str(look.get(key, "")) == hex
		b.pressed.connect(func():
			look[key] = hex
			for other in buttons:
				other.button_pressed = other == b
			_disarm()
			_refresh_preview())
		buttons.append(b)
		flow.add_child(b)
	_swatch_rows[key] = buttons
	return v


# The preview: the model in its own little world, turning with a drag (or the slider under it).
func _build_preview() -> Control:
	var box := VBoxContainer.new()
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(320, 420)
	holder.stretch = true
	box.add_child(holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	holder.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.12, 0.15)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	_pivot = Node3D.new()
	vp.add_child(_pivot)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(0, 1.0, -2.9)
	cam.look_at_from_position(cam.position, Vector3(0, 0.9, 0))
	cam.fov = 40
	_build_model()
	holder.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = e.pressed
		elif e is InputEventMouseMotion and _dragging:
			_pivot.rotation.y += e.relative.x * 0.01)
	var hint := Label.new()
	hint.text = "Drag to turn"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.5)
	box.add_child(hint)
	return box


func _build_model() -> void:
	var scene := load(str(model_info.get("scene", ""))) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate()
	MeshSmoothing.use_rebuilt_mesh(_model)
	_model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)   # as Player3D.CHARACTER_MODEL_TRANSFORM: turned to face forward
	if float(model_info.get("scale", 1.0)) != 1.0:
		_model.transform = _model.transform.scaled(Vector3.ONE * float(model_info["scale"]))
	_base_scale = _model.scale
	_pivot.add_child(_model)
	var ap := _model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var lib := load(str(model_info.get("library", ""))) as AnimationLibrary if model_info.has("library") else null
	if ap and lib:
		if ap.has_animation_library(""):
			ap.remove_animation_library("")
		ap.add_animation_library("", lib)
		if ap.has_animation("idle"):
			ap.play("idle")


func _refresh_preview() -> void:
	if _model:
		Appearance.apply(_model, str(model_info.get("scene", "")), str(model_info.get("texture_override", "")), look, race, _base_scale)


func _on_reset() -> void:
	# "full": everything back to the model as it is; "locked": just the hair
	if mode == "full":
		look = Appearance.validate({}, sex, race)
	else:
		look["hair_color"] = ""
	for k in _sliders:
		_sliders[k].set_value_no_signal(float(look.get(k, 0.0)))
	for k in _swatch_rows:
		for b in _swatch_rows[k]:
			b.button_pressed = b.tooltip_text == "As painted"
	_disarm()
	_refresh_preview()


func _disarm() -> void:
	_armed = false
	if _save_button:
		_save_button.text = "Save look"


func _on_save() -> void:
	if confirm_final and not _armed:
		_armed = true
		_save_button.text = "This is final: save?"
		return
	_finish(Appearance.validate(look, sex, race))


func _finish(result: Dictionary) -> void:
	if on_done.is_valid():
		on_done.call(result)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish({})
