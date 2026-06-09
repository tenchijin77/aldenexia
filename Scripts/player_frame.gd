# player_frame.gd — HUD frame showing player HP / Mana / Stamina
extends CanvasLayer
class_name PlayerFrame

@onready var name_label: Label      = $Panel/VBox/name_label
@onready var hp_label:   Label      = $Panel/VBox/HPRow/hp_label
@onready var hp_bar:     ProgressBar = $Panel/VBox/HPRow/hp_bar
@onready var mp_label:   Label      = $Panel/VBox/MPRow/mp_label
@onready var mp_bar:     ProgressBar = $Panel/VBox/MPRow/mp_bar
@onready var sta_label:  Label      = $Panel/VBox/STARow/sta_label
@onready var sta_bar:    ProgressBar = $Panel/VBox/STARow/sta_bar

var _player: Node = null


func _ready() -> void:
	var hp_fill = StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.75, 0.1, 0.1)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)

	var mp_fill = StyleBoxFlat.new()
	mp_fill.bg_color = Color(0.1, 0.25, 0.85)
	mp_bar.add_theme_stylebox_override("fill", mp_fill)

	var sta_fill = StyleBoxFlat.new()
	sta_fill.bg_color = Color(0.85, 0.75, 0.1)
	sta_bar.add_theme_stylebox_override("fill", sta_fill)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		var players = get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		_player = players[0]
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
