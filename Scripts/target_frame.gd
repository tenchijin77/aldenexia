# target_frame.gd — HUD frame showing current target with EQ-style con system
extends CanvasLayer
class_name TargetFrame

const POSITION_KEY := "target_frame"

@onready var panel:         Panel       = $Panel
@onready var name_label:    Label       = $Panel/VBox/NameRow/name_label
@onready var level_label:   Label       = $Panel/VBox/NameRow/level_label
@onready var faction_label: Label       = $Panel/VBox/NameRow/faction_label
@onready var hp_label:      Label       = $Panel/VBox/HPRow/hp_label
@onready var hp_bar:        ProgressBar = $Panel/VBox/HPRow/hp_bar

var _player: Node = null
var _target: Node = null
var _dragging := false

# Appraisal "wrong color" cosmetic effect (failed/critically-failed Insight
# Check) — overrides the real con-color for a short time, then self-corrects.
var _wrong_color: Color = Color.WHITE
var _wrong_color_until: float = 0.0


func _ready() -> void:
	add_to_group("target_frame")
	visible = false

	_style_panel(panel)
	_style_bar(hp_bar, Color(0.8, 0.15, 0.15), Color(0.12, 0.05, 0.05))

	# Long monster names (or the appraisal color effect landing on a long one)
	# used to overflow the label's own box and visually overlap level_label/
	# faction_label next to it — clip with an ellipsis instead.
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	panel.gui_input.connect(_on_panel_gui_input)
	WindowPosition.load_position_into(POSITION_KEY, panel)


# Shared with player_frame.gd/pet_frame.gd's look (dark parchment-bordered
# panel, same palette pause_menu.gd/corpse_loot_window.gd already use) —
# duplicated per-file rather than factored into a shared util, matching how
# each HUD frame already builds its own styleboxes independently.
func _style_panel(target_panel: Panel) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.06, 0.92)
	bg.border_color = Color(0.45, 0.38, 0.25)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(5)
	target_panel.add_theme_stylebox_override("panel", bg)


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
		_dragging = event.pressed
		if not _dragging:
			WindowPosition.save(POSITION_KEY, panel)
	elif event is InputEventMouseMotion and _dragging:
		panel.offset_left   += event.relative.x
		panel.offset_top    += event.relative.y
		panel.offset_right  += event.relative.x
		panel.offset_bottom += event.relative.y


func set_target(target: Node) -> void:
	_target = target
	visible = target != null and is_instance_valid(target)
	_wrong_color_until = 0.0


func show_wrong_color(duration: float) -> void:
	# Called by player3d.gd on a failed/critical-failed Insight Check.
	var tiers := [
		Color(1.00, 0.10, 0.10), Color(1.00, 0.50, 0.00), Color(1.00, 1.00, 0.00),
		Color(1.00, 1.00, 1.00), Color(0.40, 0.60, 1.00), Color(0.00, 0.80, 0.00),
		Color(0.55, 0.55, 0.55),
	]
	_wrong_color = tiers[randi() % tiers.size()]
	_wrong_color_until = Time.get_ticks_msec() / 1000.0 + duration


static func display_name(target: Node) -> String:
	# The player (targetable via group-targeting or the group frame's own row)
	# and pets each expose their name under a different field than any of the
	# monster_description/monster_name/npc_name ones below.
	if "player_name" in target:
		var plname: String = str(target.get("player_name"))
		if not plname.is_empty():
			return plname
	if "pet_name" in target:
		var pname: String = str(target.get("pet_name"))
		if not pname.is_empty():
			return pname
	# Prefer monster_description (e.g. "a crumbling skeleton") stripped of leading article
	var desc: String = ""
	if "monster_description" in target:
		desc = str(target.get("monster_description"))
	if not desc.is_empty():
		for article in ["an ", "a ", "the "]:
			if desc.begins_with(article):
				desc = desc.substr(article.length())
				break
		return desc.capitalize()
	# Fall back to exported monster_name var
	if "monster_name" in target:
		var mname: String = str(target.get("monster_name"))
		if not mname.is_empty() and mname != "monster":
			return mname.capitalize()
	# NPCs (e.g. guards) expose npc_name instead of monster_name/monster_description
	if "npc_name" in target:
		var nname: String = str(target.get("npc_name"))
		if not nname.is_empty():
			return nname
	# Last resort: virtual method
	if target.has_method("get_monster_name"):
		return target.get_monster_name().capitalize()
	return "Unknown"


func _refresh_name_and_con() -> void:
	if not is_instance_valid(_target):
		return

	var target_level := int(_target.get("level") if "level" in _target else 1)
	var player_level := 1
	if is_instance_valid(_player) and "combat_node" in _player:
		player_level = _player.combat_node.level

	var diff := target_level - player_level
	# Boss mobs always show as the most dangerous tier, regardless of level.
	var is_boss: bool = _target.get("is_boss") if "is_boss" in _target else false
	var color := Color(1.00, 0.10, 0.10) if is_boss else _con_color(diff)
	if _wrong_color_until > Time.get_ticks_msec() / 1000.0:
		color = _wrong_color

	name_label.add_theme_color_override("font_color", color)
	level_label.add_theme_color_override("font_color", color)
	name_label.text  = display_name(_target)
	level_label.text = "Lv %d" % target_level

	var faction := faction_status(_target)
	faction_label.text = "(%s)" % faction
	faction_label.add_theme_color_override("font_color", _faction_color(faction))


func _con_color(diff: int) -> Color:
	if   diff >= 6:  return Color(1.00, 0.10, 0.10)  # Red    — 6+ levels above
	elif diff >= 4:  return Color(1.00, 0.50, 0.00)  # Orange — 4-5 levels above
	elif diff >= 2:  return Color(1.00, 1.00, 0.00)  # Yellow — 2-3 levels above
	elif diff >= -1: return Color(1.00, 1.00, 1.00)  # White  — same level / ±1
	elif diff >= -3: return Color(0.40, 0.60, 1.00)  # Blue   — 2-3 levels below
	elif diff >= -5: return Color(0.00, 0.80, 0.00)  # Green  — 4-5 levels below
	else:            return Color(0.55, 0.55, 0.55)  # Grey   — 6+ levels below (no XP)


static func faction_status(target: Node) -> String:
	# Ally/Neutral/Enemy — derived from what already exists (group membership,
	# behavior_type), not a separate faction-standing system. See game_flow.txt.
	if target.is_in_group("player") or target.is_in_group("npc_guard") or target.is_in_group("npc_vendor") or target.is_in_group("pets"):
		return "Ally"
	if target.get("behavior_type") == "passive":
		return "Neutral"
	return "Enemy"


func _faction_color(status: String) -> Color:
	match status:
		"Ally":  return Color(0.4, 0.6, 1.0)
		"Enemy": return Color(1.0, 0.2, 0.2)
		_:       return Color(1.0, 1.0, 1.0)


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
	_refresh_name_and_con()

	if "combat_node" in _target:
		var cn = _target.combat_node
		hp_bar.max_value = cn.max_hp
		hp_bar.value     = cn.current_hp
		hp_label.text    = "%d / %d" % [cn.current_hp, cn.max_hp]
	elif "current_health" in _target:
		hp_bar.max_value = _target.max_health
		hp_bar.value     = _target.current_health
		hp_label.text    = "%d / %d" % [_target.current_health, _target.max_health]
