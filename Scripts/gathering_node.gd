# gathering_node.gd — one gatherable spot in the world: a thistle patch, an ore vein, a tree. Right-click in range
# (player3d.gd's _try_gather()) to gather from it. The node's numbers all come from Data/gathering_nodes.json
# (generated from the crafting workbook): the item it gives, the gathering skill it trains, min skill, max level,
# success / crit chances, gather time, respawn time, the tool it needs and any bonus drop.
#
# Rules (Crafting.xlsx, Rules tab): gathering is innate, gated only by min skill. Success = base + 1% per skill point
# above min (max 98%). A crit gives the crit yield. A failure finds nothing and leaves the node up; a success uses the
# node until it respawns. Skill-ups stop at the node's max level, and a failure never trains.
#
# Built and gathered locally by each player's own client (crafting_world_spawner.gd places the same nodes in the same
# spots everywhere, moving them to new random spots each in-game day), so every player sees their own copy of each node — no networking needed.
extends Node3D
class_name GatheringNode

const USE_RANGE := 4.0
const MOVE_CANCEL_DISTANCE := 1.0
const MAX_SUCCESS := 0.98

var node_id: String = ""
var def: Dictionary = {}

var _available := true
var _gatherer: Node3D = null
var _gather_left := 0.0
var _gather_total := 0.0
var _gather_start_pos := Vector3.ZERO
var _gather_started_msec := 0
var _visual: Node3D = null
var _respawn_timer: Timer = Timer.new()
var _sound: Node = null   # the gathering sound loop (sfx.gd) while someone gathers here
const GATHER_SOUNDS := {"prospecting": "gather_mining", "woodworking": "gather_wood", "fishing": "gather_fishing"}


var model_config: Dictionary = {}  # Data/crafting_models.json entry ({} = placeholder shape)


# Sets the node type (a key in Data/gathering_nodes.json) and its model (Data/crafting_models.json). Call before adding
# to the tree.
func setup(id: String, definition: Dictionary, model_cfg: Dictionary = {}) -> void:
	node_id = id
	def = definition
	model_config = model_cfg
	name = "Gather_%s" % id


func _ready() -> void:
	add_to_group("gathering_node")
	_visual = _build_visual()
	add_child(_visual)
	_respawn_timer.one_shot = true
	_respawn_timer.timeout.connect(_on_respawn)
	add_child(_respawn_timer)
	set_process(false)


# True while someone is in the middle of gathering it (crafting_world_spawner.gd doesn't move it then).
func is_being_gathered() -> bool:
	return is_instance_valid(_gatherer)


func is_available() -> bool:
	return _available and _gatherer == null


# Starts gathering: checks the tool and skill, then runs the gather timer (_process). Moving away or being attacked
# interrupts it.
func start_gather(player: Node3D) -> void:
	if not is_available():
		return
	var skill_name: String = str(def.get("skill", ""))
	var skill: int = _skill_of(player)
	var min_skill: int = int(def.get("min_skill", 0))
	if skill < min_skill:
		GameLog.log_general("You need %s %d to gather from the %s (you have %d)." % [
			skill_name.capitalize(), min_skill, def.get("name", "node"), skill])
		return
	var tool: Dictionary = {}
	var tool_skill: String = str(def.get("tool", ""))
	if not tool_skill.is_empty():
		tool = ItemHelper.best_gather_tool(tool_skill)
		if tool.is_empty():
			GameLog.log_general("You need %s to gather from the %s." % [
				"a Miner's Pick" if tool_skill == "prospecting" else "a Woodcutter's Axe", def.get("name", "node")])
			return
	_gatherer = player
	_gather_left = float(def.get("gather_seconds", 3.0)) * (1.0 - float(tool.get("gather_speed_bonus", 0.0)))
	_gather_total = _gather_left
	_gather_start_pos = player.global_position
	_gather_started_msec = Time.get_ticks_msec()
	GameLog.log_general("You begin gathering from the %s..." % def.get("name", "node"))
	if GATHER_SOUNDS.has(skill_name):
		_sound = Sfx.start_loop(GATHER_SOUNDS[skill_name], self)
	set_process(true)


func _process(delta: float) -> void:
	if not is_instance_valid(_gatherer):
		_cancel("")
		return
	if _gatherer.global_position.distance_to(_gather_start_pos) > MOVE_CANCEL_DISTANCE:
		_cancel("You stop gathering.")
		return
	if "last_attacked_msec" in _gatherer and _gatherer.last_attacked_msec > _gather_started_msec:
		_cancel("You are attacked and stop gathering.")
		return
	_gather_left -= delta
	if _gatherer.has_method("set_task_progress"):
		_gatherer.set_task_progress("Gathering: %s" % def.get("name", "node"), 1.0 - _gather_left / maxf(_gather_total, 0.01), _gather_left)
	if _gather_left <= 0.0:
		_finish()


func _cancel(message: String) -> void:
	Sfx.stop(_sound)
	_sound = null
	if is_instance_valid(_gatherer) and _gatherer.has_method("clear_task_progress"):
		_gatherer.clear_task_progress()
	_gatherer = null
	set_process(false)
	if not message.is_empty():
		GameLog.log_general("[color=#ffaa66]%s[/color]" % message)


# Rolls the gather: success gives the item (crit: the crit yield) plus any bonus drop and uses the node up.
func _finish() -> void:
	Sfx.stop(_sound)
	_sound = null
	var player := _gatherer
	_gatherer = null
	if player.has_method("clear_task_progress"):
		player.clear_task_progress()
	set_process(false)
	var skill: int = _skill_of(player)
	var tool: Dictionary = ItemHelper.best_gather_tool(str(def.get("tool", ""))) if not str(def.get("tool", "")).is_empty() else {}
	var success := randf() < success_chance(def, skill)
	if not success:
		GameLog.log_general("[color=#ff8866]You search the %s but find nothing useful.[/color]" % def.get("name", "node"))
		return
	var crit := randf() < float(def.get("crit_chance", 0.0)) + float(tool.get("gather_crit_bonus", 0.0))
	var item_id: String = str(def.get("item", ""))
	var qty: int = int(def.get("crit_yield" if crit else "yield", 1))
	_give(item_id, qty, crit)
	var bonus: Variant = def.get("bonus")
	if typeof(bonus) == TYPE_DICTIONARY and randf() < float(bonus.get("chance", 0.0)):
		_give(str(bonus.get("item", "")), 1, false)
	if skill < int(def.get("max_level", 9999)) and player.has_method("_tick_skill"):
		player._tick_skill(str(def.get("skill", "")), 1.0)
	_deplete()


func _give(item_id: String, qty: int, crit: bool) -> void:
	if item_id.is_empty():
		return
	var item_name: String = Inventory.get_item_definition(item_id).get("name", item_id)
	if not Inventory.add_item(item_id, qty):
		GameLog.log_general("[color=#ffaa66]Your bags are full — you leave the %s behind.[/color]" % item_name)
		return
	Sfx.play("pickup")
	if crit:
		GameLog.log_general("[color=#ffdd44]A fine find! You gather [b]%d %s[/b].[/color]" % [qty, item_name])
	else:
		GameLog.log_general("[color=#88ffaa]You gather [b]%d %s[/b].[/color]" % [qty, item_name])


func _deplete() -> void:
	_available = false
	_visual.visible = false
	_respawn_timer.start(maxf(float(def.get("respawn_seconds", 60.0)), 1.0))


func _on_respawn() -> void:
	_available = true
	_visual.visible = true


# Chance to succeed: the node's base chance + 1% per skill point above its min skill, capped at 98%.
static func success_chance(definition: Dictionary, skill: int) -> float:
	var above: int = maxi(skill - int(definition.get("min_skill", 0)), 0)
	return minf(float(definition.get("base_success", 1.0)) + 0.01 * above, MAX_SUCCESS)


func _skill_of(player: Node) -> int:
	if not is_instance_valid(player) or not ("skill_levels" in player):
		return 0
	return int(player.skill_levels.get(str(def.get("skill", "")), 0))


# The node's model from Data/crafting_models.json, or a placeholder (a small plant, a rock, or a tree, tinted per node),
# with a name label above it.
func _build_visual() -> Node3D:
	var root := Node3D.new()
	var skill: String = str(def.get("skill", ""))
	if not model_config.is_empty():
		add_child(root)  # CraftingStation.add_model() measures the model in place
		var height := CraftingStation.add_model(root, model_config)
		remove_child(root)
		if height > 0.0:
			root.add_child(_name_label(height + 0.4))
			return root
	root.add_child(_name_label(6.2 if skill == "woodworking" else 1.6))
	var color: Color = NODE_COLORS.get(node_id, Color(0.5, 0.5, 0.5))
	if skill == "forage":
		root.add_child(_mesh(_sphere(0.45, 0.6), color, Vector3(0, 0.3, 0)))
	elif skill == "prospecting":
		root.add_child(_mesh(_sphere(0.9, 1.1), color, Vector3(0, 0.45, 0)))
	else:
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.25
		trunk.bottom_radius = 0.35
		trunk.height = 4.0
		root.add_child(_mesh(trunk, Color(0.35, 0.24, 0.14), Vector3(0, 2.0, 0)))
		root.add_child(_mesh(_sphere(1.6, 2.2), color, Vector3(0, 4.4, 0)))
	return root


func _name_label(height: float) -> Label3D:
	var label := Label3D.new()
	label.text = str(def.get("name", node_id))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	label.position = Vector3(0, height, 0)
	label.visibility_range_end = 25.0
	label.modulate = Color(0.85, 1.0, 0.8)
	return label


const NODE_COLORS := {
	"thistle_patch": Color(0.55, 0.3, 0.7), "sandroot_mound": Color(0.6, 0.45, 0.25),
	"venom_cactus": Color(0.75, 0.15, 0.15), "moonpetal_sage": Color(0.75, 0.8, 0.9),
	"tin_vein": Color(0.7, 0.72, 0.75), "copper_vein": Color(0.72, 0.42, 0.22), "glittering_vein": Color(0.35, 0.6, 0.85),
	"fir_tree": Color(0.2, 0.42, 0.22), "ironwood_tree": Color(0.18, 0.28, 0.16), "palm_tree": Color(0.45, 0.6, 0.2),
}


func _sphere(radius: float, height: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = height
	return s


func _mesh(mesh: Mesh, color: Color, offset: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = offset
	return mi
