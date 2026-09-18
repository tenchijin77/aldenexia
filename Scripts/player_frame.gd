# player_frame.gd — HUD frame showing player HP / Mana / Stamina
extends CanvasLayer
class_name PlayerFrame

const POSITION_KEY := "player_frame"
const RESIZE_MARGIN := 16.0
const MIN_WIDTH := 160.0
const MIN_HEIGHT := 120.0

@onready var panel:      Panel      = $Panel
@onready var name_label: Label      = $Panel/VBox/name_label
@onready var hp_label:   Label      = $Panel/VBox/HPRow/hp_label
@onready var hp_bar:     ProgressBar = $Panel/VBox/HPRow/hp_bar
@onready var mp_label:   Label      = $Panel/VBox/MPRow/mp_label
@onready var mp_bar:     ProgressBar = $Panel/VBox/MPRow/mp_bar
@onready var sta_label:  Label      = $Panel/VBox/STARow/sta_label
@onready var sta_bar:    ProgressBar = $Panel/VBox/STARow/sta_bar
@onready var food_label: Label      = $Panel/VBox/FoodRow/food_label
@onready var food_bar:   ProgressBar = $Panel/VBox/FoodRow/food_bar
@onready var water_label: Label     = $Panel/VBox/WaterRow/water_label
@onready var water_bar:  ProgressBar = $Panel/VBox/WaterRow/water_bar

var _player: Node = null
var _dragging := false
var _resizing := false


func _ready() -> void:
	_style_panel()
	_style_bar(hp_bar,    Color(0.8, 0.15, 0.15), Color(0.12, 0.05, 0.05))
	_style_bar(mp_bar,    Color(0.2, 0.35, 0.9),  Color(0.05, 0.06, 0.12))
	_style_bar(sta_bar,   Color(0.9, 0.8, 0.15),  Color(0.12, 0.10, 0.04))
	_style_bar(food_bar,  Color(0.8, 0.5, 0.2),   Color(0.12, 0.08, 0.04))
	_style_bar(water_bar, Color(0.2, 0.7, 0.8),   Color(0.04, 0.1, 0.12))

	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	panel.gui_input.connect(_on_panel_gui_input)
	WindowPosition.load_full_into(POSITION_KEY, panel)


func _style_panel() -> void:
	panel.add_theme_stylebox_override("panel", Global.window_bg_style())


func _style_bar(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)

	var back := StyleBoxFlat.new()
	back.bg_color = bg_color
	back.border_color = Color(0, 0, 0, 0.5)
	back.set_border_width_all(1)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos: Vector2 = event.position
			if pos.x > panel.size.x - RESIZE_MARGIN and pos.y > panel.size.y - RESIZE_MARGIN:
				_resizing = true
			else:
				_dragging = true
		else:
			if _dragging or _resizing:
				WindowPosition.save(POSITION_KEY, panel)
			_dragging = false
			_resizing = false
	elif event is InputEventMouseMotion:
		if _resizing:
			panel.offset_right  = max(panel.offset_left + MIN_WIDTH, panel.offset_right + event.relative.x)
			panel.offset_bottom = max(panel.offset_top + MIN_HEIGHT, panel.offset_bottom + event.relative.y)
		elif _dragging:
			panel.offset_left   += event.relative.x
			panel.offset_top    += event.relative.y
			panel.offset_right  += event.relative.x
			panel.offset_bottom += event.relative.y


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = TargetFrame.local_player()
		if not is_instance_valid(_player):
			return
		name_label.text = _player.player_name if "player_name" in _player else "Player"

	if not "combat_node" in _player:
		return

	var cn = _player.combat_node

	hp_bar.max_value = cn.max_hp
	hp_bar.value     = cn.current_hp
	hp_label.text    = "HP  %d / %d" % [cn.current_hp, cn.max_hp]

	mp_bar.max_value = cn.max_mana
	mp_bar.value     = cn.current_mana
	mp_label.text    = "MP  %d / %d" % [cn.current_mana, cn.max_mana]

	var sta     = float(_player.get("current_stamina") if "current_stamina" in _player else 0.0)
	var max_sta = float(_player.get("max_stamina")     if "max_stamina"     in _player else 100.0)
	sta_bar.max_value = max_sta
	sta_bar.value     = sta
	sta_label.text    = "STA %d / %d" % [int(sta), int(max_sta)]

	var food = int(_player.get("satiety") if "satiety" in _player else 100)
	food_bar.max_value = 100
	food_bar.value     = food
	food_label.text    = "Food %d / 100" % food

	var water = int(_player.get("thirst") if "thirst" in _player else 100)
	water_bar.max_value = 100
	water_bar.value     = water
	water_label.text    = "Water %d / 100" % water
