# tracking_window.gd — Draggable/resizable/persistent window listing monsters
# within TRACK_RANGE, real-time, con-colored by level exactly like targeting
# does (reuses TargetFrame.con_color()/display_name()/is_hidden_from_local_player()
# rather than a second copy of that logic). Opened/closed with T
# (player3d.gd's toggle_tracking_window(), gated on has_tracking_skill() —
# Elf/Half-Elf by race, Woodstalker/Wildspeaker/Troubadour by class).
# Drag/resize/position-persistence follows character_sheet.gd's pattern
# (single gui_input handler, WindowPosition.load_full_into/save), not
# game_log_window.gd's older separate-drag-bar-and-handle-node version.
extends CanvasLayer

const POSITION_KEY := "tracking_window"
const DRAG_BAR_HEIGHT := 24.0
const RESIZE_MARGIN := 16.0
const MIN_WIDTH := 200.0
const MIN_HEIGHT := 160.0
const TRACK_RANGE := 50.0
const REFRESH_INTERVAL := 0.5

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/TitleLabel
@onready var close_btn: Button = $Panel/CloseBtn
@onready var scroll: ScrollContainer = $Panel/Scroll
@onready var list: VBoxContainer = $Panel/Scroll/List

var _player: Node = null
var _dragging := false
var _resizing := false
var _refresh_timer := 0.0


func _ready() -> void:
	layer = 5
	_style_panel()
	close_btn.pressed.connect(queue_free)
	panel.gui_input.connect(_on_panel_gui_input)
	WindowPosition.load_full_into(POSITION_KEY, panel)


func _style_panel() -> void:
	panel.add_theme_stylebox_override("panel", Global.window_bg_style())


func set_player(p: Node) -> void:
	_player = p
	_refresh()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	_refresh()


func _refresh() -> void:
	for c in list.get_children():
		c.queue_free()

	if not is_instance_valid(_player):
		return

	var origin: Vector3 = _player.global_position
	var player_level: int = _player.combat_node.level if "combat_node" in _player else 1

	var nearby: Array = []
	# Monsters, guards, vendors, and other players alike — tracking is about
	# knowing what's nearby, not just threats. Per user request (2026-09-17):
	# guards/vendors included the same way monsters always were; other real
	# players (multiplayer) were missing entirely until now.
	var candidates := get_tree().get_nodes_in_group("monsters") \
		+ get_tree().get_nodes_in_group("npc_guard") \
		+ get_tree().get_nodes_in_group("npc_vendor") \
		+ get_tree().get_nodes_in_group("player")
	for m in candidates:
		if not is_instance_valid(m) or m == _player:
			continue
		if TargetFrame.is_hidden_from_local_player(m):
			continue
		var cn = m.get("combat_node")
		if cn is CombatNode and not cn.is_alive():
			continue
		var dist: float = origin.distance_to(m.global_position)
		if dist > TRACK_RANGE:
			continue
		nearby.append({"node": m, "dist": dist})

	nearby.sort_custom(func(a, b): return a["dist"] < b["dist"])

	if nearby.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Nothing within %dm." % int(TRACK_RANGE)
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		list.add_child(empty_lbl)
		return

	for entry in nearby:
		list.add_child(_make_row(entry["node"], entry["dist"], player_level))


func _make_row(mob: Node, dist: float, player_level: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var mob_level: int = TargetFrame.entity_level(mob)
	var color: Color = TargetFrame.con_color(mob_level - player_level)

	var name_lbl := Label.new()
	name_lbl.text = TargetFrame.display_name(mob)
	name_lbl.add_theme_color_override("font_color", color)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	row.add_child(name_lbl)

	var level_lbl := Label.new()
	level_lbl.text = "Lv %d" % mob_level
	level_lbl.add_theme_color_override("font_color", color)
	row.add_child(level_lbl)

	var dist_lbl := Label.new()
	dist_lbl.text = "%dm" % int(dist)
	dist_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	dist_lbl.custom_minimum_size = Vector2(36, 0)
	dist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(dist_lbl)

	return row


# ===== DRAGGABLE / RESIZABLE PANEL (same pattern as character_sheet.gd) =====

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos = event.position
			if pos.x > panel.size.x - RESIZE_MARGIN and pos.y > panel.size.y - RESIZE_MARGIN:
				_resizing = true
			elif pos.y < DRAG_BAR_HEIGHT:
				_dragging = true
		else:
			if _dragging or _resizing:
				WindowPosition.save(POSITION_KEY, panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _dragging:
			panel.offset_left += event.relative.x
			panel.offset_top += event.relative.y
			panel.offset_right += event.relative.x
			panel.offset_bottom += event.relative.y
		elif _resizing:
			panel.offset_right = max(panel.offset_left + MIN_WIDTH, panel.offset_right + event.relative.x)
			panel.offset_bottom = max(panel.offset_top + MIN_HEIGHT, panel.offset_bottom + event.relative.y)
