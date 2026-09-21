# encounter_frame.gd — the ENCOUNTER frame: one row for every enemy that is fighting you (or your group) right now, with its name (coloured by
# how dangerous it is for your level), health bar and distance, nearest first; the one you have targeted is outlined. For fights with several
# enemies at once. Click a row to target it. Draggable (by the title strip) and resizable (lower-right corner), position and size remembered
# per character like every other window; /resetui puts it back. Hidden while nobody is fighting you.
# Who counts: an enemy whose replicated target_key is you or a group member (TargetFrame.target_key_of), plus your current target if it is
# in combat with anyone.
# No class_name on purpose (player3d.gd preloads it: a brand-new class name is not known to Godot until its class cache is rebuilt).
extends CanvasLayer

const KEY := "encounter_frame"
const MIN_SIZE := Vector2(190, 70)
const RESIZE_MARGIN := 14.0
const TITLE_HEIGHT := 18.0
const MAX_ROWS := 16
const REFRESH_SECONDS := 0.2

var _panel: Panel
var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _player: Node = null
var _rows: Dictionary = {}     # monster instance id -> {"panel", "name", "dist", "bar", "hp", "style"}
var _dragging := false
var _resizing := false
var _timer := 0.0


func _ready() -> void:
	add_to_group("encounter_frame")
	visible = false
	_panel = Panel.new()
	_panel.offset_left = 470.0
	_panel.offset_top = 62.0
	_panel.offset_right = 700.0
	_panel.offset_bottom = 210.0
	_panel.add_theme_stylebox_override("panel", Global.window_bg_style())
	WindowPosition.load_full_into(KEY, _panel)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)

	_title = Label.new()
	_title.text = "ENCOUNTER"
	_title.custom_minimum_size = Vector2(0, TITLE_HEIGHT - 6)
	_title.add_theme_font_size_override("font_size", 9)
	_title.add_theme_color_override("font_color", Color(0.9, 0.6, 0.5))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 3)
	_scroll.add_child(_rows_box)

	_panel.gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos: Vector2 = event.position
			if pos.x > _panel.size.x - RESIZE_MARGIN and pos.y > _panel.size.y - RESIZE_MARGIN:
				_resizing = true
			elif pos.y < TITLE_HEIGHT + 4.0:
				_dragging = true
		else:
			if _dragging or _resizing:
				WindowPosition.save(KEY, _panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _resizing:
			_panel.offset_right = maxf(_panel.offset_left + MIN_SIZE.x, _panel.offset_right + event.relative.x)
			_panel.offset_bottom = maxf(_panel.offset_top + MIN_SIZE.y, _panel.offset_bottom + event.relative.y)
		elif _dragging:
			_panel.offset_left += event.relative.x
			_panel.offset_top += event.relative.y
			_panel.offset_right += event.relative.x
			_panel.offset_bottom += event.relative.y


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_SECONDS
	if not is_instance_valid(_player):
		_player = TargetFrame.local_player()
		if not is_instance_valid(_player):
			visible = false
			return
	_refresh()


# The enemies in combat with you or your group right now, nearest first.
func _engaged() -> Array:
	var wanted := {TargetFrame.target_key_of(_player): true}
	var members: Array = _player.get("group_members") if "group_members" in _player else []
	for peer_id in members:
		wanted["p:%d" % int(peer_id)] = true
	var out: Array = []
	for m in get_tree().get_nodes_in_group("monsters"):
		if not is_instance_valid(m) or m.get("current_state") == m.State.DEAD:
			continue
		var fighting: bool = wanted.has(str(m.get("target_key")))
		if not fighting and m == _player.get("current_target") and (m.get("current_state") in [m.State.CHASE, m.State.ATTACK, m.State.FLEEING]):
			fighting = true   # the one you have targeted, when it is in a fight with anyone
		if fighting:
			out.append(m)
	out.sort_custom(func(a, b): return _player.global_position.distance_to(a.global_position) < _player.global_position.distance_to(b.global_position))
	return out.slice(0, MAX_ROWS)


func _refresh() -> void:
	var engaged := _engaged()
	visible = not engaged.is_empty()
	_title.text = "ENCOUNTER  (%d)" % engaged.size()
	var keep := {}
	for m in engaged:
		var id: int = m.get_instance_id()
		keep[id] = true
		if not _rows.has(id):
			_rows[id] = _make_row(m)
		_update_row(_rows[id], m)
	for id in _rows.keys():
		if not keep.has(id):
			_rows[id]["panel"].queue_free()
			_rows.erase(id)
	# nearest first: keep the row order matching the list
	for i in engaged.size():
		var row = _rows[engaged[i].get_instance_id()]
		if row["panel"].get_index() != i:
			_rows_box.move_child(row["panel"], i)


func _make_row(monster: Node) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.07, 0.07, 0.85)
	style.border_color = Color(0.35, 0.2, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", style)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and is_instance_valid(monster) and is_instance_valid(_player):
			_player.current_target = monster
			if _player.has_method("_announce_target"):
				_player._announce_target(monster))
	_rows_box.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_label)
	var dist_label := Label.new()
	dist_label.add_theme_font_size_override("font_size", 10)
	dist_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	dist_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(dist_label)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bottom)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.8, 0.15, 0.15)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.12, 0.05, 0.05)
	back.border_color = Color(0, 0, 0, 0.5)
	back.set_border_width_all(1)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	bottom.add_child(bar)
	var hp_label := Label.new()
	hp_label.custom_minimum_size = Vector2(60, 0)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_label.add_theme_font_size_override("font_size", 9)
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(hp_label)
	return {"panel": panel, "name": name_label, "dist": dist_label, "bar": bar, "hp": hp_label, "style": style}


func _update_row(row: Dictionary, monster: Node) -> void:
	var level := TargetFrame.entity_level(monster)
	var my_level := int(_player.combat_node.level) if "combat_node" in _player and _player.combat_node else 1
	var color := Color(1.0, 0.1, 0.1) if bool(monster.get("is_boss")) else TargetFrame.con_color(level - my_level)
	row["name"].text = TargetFrame.nameplate_name(monster)
	row["name"].add_theme_color_override("font_color", color)
	var metres: float = _player.global_position.distance_to(monster.global_position)
	row["dist"].text = "%.1f m" % metres if metres < 10.0 else "%d m" % int(metres)
	var cn = monster.get("combat_node")
	if cn is CombatNode:
		row["bar"].max_value = maxi(cn.max_hp, 1)
		row["bar"].value = maxi(cn.current_hp, 0)
		row["hp"].text = "%d/%d" % [cn.current_hp, cn.max_hp]
	var is_target: bool = monster == _player.get("current_target")
	row["style"].border_color = Color(1.0, 0.85, 0.35) if is_target else Color(0.35, 0.2, 0.2)
	row["style"].set_border_width_all(2 if is_target else 1)
