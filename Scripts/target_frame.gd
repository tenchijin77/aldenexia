# target_frame.gd — HUD frame showing current target with EQ-style con system
extends CanvasLayer
class_name TargetFrame

const POSITION_KEY := "target_frame"
const RESIZE_MARGIN := 16.0
const MIN_WIDTH := 160.0
const MIN_HEIGHT := 90.0

@onready var panel:         Panel       = $Panel
@onready var name_label:    Label       = $Panel/VBox/NameRow/name_label
@onready var level_label:   Label       = $Panel/VBox/NameRow/level_label
@onready var faction_label: Label       = $Panel/VBox/NameRow/faction_label
@onready var hp_label:      Label       = $Panel/VBox/HPRow/hp_label
@onready var hp_bar:        ProgressBar = $Panel/VBox/HPRow/hp_bar

var _player: Node = null
var _target: Node = null
var _dragging := false
var _resizing := false

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
	WindowPosition.load_full_into(POSITION_KEY, panel)


func _style_panel(target_panel: Panel) -> void:
	target_panel.add_theme_stylebox_override("panel", Global.window_bg_style())


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


# ── Invisibility / stealth / GM nameplate flags ─────────────────────────────
# Invisibility hiding/perception is evaluated per-viewer, not networked — each
# client independently checks its OWN local player's see-invisible against
# whatever combat_node state it has for `entity` (player3d.gd's replicated
# puppets, or a locally-simulated monster). This finds "my own local player"
# among every Player3D in the "player" group.
static func local_player() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	for p in tree.get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			return p
	return null


# Resolves a multiplayer peer id to whatever local Node currently represents
# that peer — the pre-placed host node, a RemotePlayers-spawned puppet, or
# this node itself. Same idea as player3d.gd's own instance-method
# `_peer_id_to_player_node()`, exposed statically so non-player scripts
# (monster3d.gd's kill-credit routing) don't need a Player3D instance just to
# call it.
static func peer_id_to_player_node(peer_id: int) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p) and p.get_multiplayer_authority() == peer_id:
			return p
	return null


# True when `entity` is magically invisible and the local viewer can't see
# invisible — used to hide both the 3D model and any nameplate/targeting for
# it. You can always see/target yourself. Once an invisible entity attacks,
# CombatNode.break_invisibility() clears its own "invisibility" effect, so
# this naturally starts returning false for everyone at that point.
static func is_hidden_from_local_player(entity: Node) -> bool:
	if not is_instance_valid(entity):
		return false
	var cn = entity.get("combat_node") if "combat_node" in entity else null
	if not (cn is CombatNode) or not cn.is_currently_invisible():
		return false
	var viewer := local_player()
	if viewer == null or viewer == entity:
		return false
	var viewer_cn = viewer.get("combat_node") if "combat_node" in viewer else null
	return not (viewer_cn is CombatNode and viewer_cn.has_see_invisible())


# Nameplate text for `entity` as seen by the local viewer. While invisible-
# but-perceived (the viewer has see-invisible, so is_hidden_from_local_player()
# is false, but true identity is still concealed until the entity attacks and
# actually breaks its own invisibility), this replaces the name entirely with
# a vague parenthesized descriptor — "(a ghost)" for a monster using its own
# flavor description, or a generic placeholder for a player, since players
# don't have an equivalent flavor-text field. Otherwise appends the
# game-master/stealth tags to the normal name.
static func nameplate_name(entity: Node) -> String:
	var cn = entity.get("combat_node") if "combat_node" in entity else null
	if cn is CombatNode and cn.is_currently_invisible():
		var desc: String = ""
		if "monster_description" in entity:
			desc = str(entity.get("monster_description"))
		if desc.is_empty():
			desc = "a shadowy figure"
		return "(%s)" % desc

	var text := display_name(entity)
	if "is_game_master" in entity and entity.is_game_master:
		text += " <game master>"
	if cn is CombatNode and cn.is_stealthed():
		text += " [stealth]"
	return text


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
	var color := Color(1.00, 0.10, 0.10) if is_boss else con_color(diff)
	if _wrong_color_until > Time.get_ticks_msec() / 1000.0:
		color = _wrong_color

	name_label.add_theme_color_override("font_color", color)
	level_label.add_theme_color_override("font_color", color)
	name_label.text  = nameplate_name(_target)
	level_label.text = "Lv %d" % target_level

	var faction := faction_status(_target)
	faction_label.text = "(%s)" % faction
	faction_label.add_theme_color_override("font_color", _faction_color(faction))


static func con_color(diff: int) -> Color:
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
		_player = local_player()

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
