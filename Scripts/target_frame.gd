# target_frame.gd — HUD frame showing current target with EQ-style con system
extends CanvasLayer
class_name TargetFrame

@onready var name_label:  Label       = $Panel/VBox/NameRow/name_label
@onready var level_label: Label       = $Panel/VBox/NameRow/level_label
@onready var hp_label:    Label       = $Panel/VBox/HPRow/hp_label
@onready var hp_bar:      ProgressBar = $Panel/VBox/HPRow/hp_bar

var _player: Node = null
var _target: Node = null


func _ready() -> void:
	add_to_group("target_frame")
	visible = false

	var hp_fill = StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.75, 0.1, 0.1)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)


func set_target(target: Node) -> void:
	_target = target
	visible  = target != null and is_instance_valid(target)
	if visible:
		_refresh_name_and_con()


func _refresh_name_and_con() -> void:
	if not is_instance_valid(_target):
		return

	var target_level := int(_target.get("level") if "level" in _target else 1)
	var player_level := 1
	if is_instance_valid(_player) and "combat_node" in _player:
		player_level = _player.combat_node.level

	var diff := target_level - player_level
	name_label.add_theme_color_override("font_color", _con_color(diff))
	level_label.text = "Lv %d" % target_level

	if _target.has_method("get_monster_name"):
		name_label.text = _target.get_monster_name().capitalize()
	elif "monster_name" in _target:
		name_label.text = str(_target.monster_name).capitalize()


func _con_color(diff: int) -> Color:
	if   diff >= 5:  return Color(1.00, 0.10, 0.10)  # Red    — very dangerous
	elif diff >= 4:  return Color(1.00, 0.50, 0.00)  # Orange — dangerous
	elif diff >= 2:  return Color(1.00, 1.00, 0.00)  # Yellow — challenging
	elif diff >= -1: return Color(1.00, 1.00, 1.00)  # White  — even
	elif diff >= -3: return Color(0.40, 0.60, 1.00)  # Blue   — easy
	elif diff >= -5: return Color(0.00, 0.80, 0.00)  # Green  — very easy
	else:            return Color(0.55, 0.55, 0.55)  # Grey   — trivial (no XP)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		var players = get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			_player = players[0]

	if not is_instance_valid(_target):
		visible = false
		_target = null
		return

	visible = true

	if "combat_node" in _target:
		var cn = _target.combat_node
		hp_bar.max_value = cn.max_hp
		hp_bar.value     = cn.current_hp
		hp_label.text    = "%d / %d" % [cn.current_hp, cn.max_hp]
	elif "current_health" in _target:
		hp_bar.max_value = _target.max_health
		hp_bar.value     = _target.current_health
		hp_label.text    = "%d / %d" % [_target.current_health, _target.max_health]
