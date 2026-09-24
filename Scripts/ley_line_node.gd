# ley_line_node.gd — a Ley-Line Node in the world (Data/ley_lines.json, placed by crafting_world_spawner.gd). Right-click it
# within USE_RANGE (player3d.gd _try_ley_line_node()): an Arcanist, Wildspeaker or Chaosborn anchors it in memory with their
# own ritual, and their travel spell (Spectral Bridge, Root-Tunnel, Chaos Rift) can take them there afterwards. Everyone
# else just feels it hum. Attunements are the character's own (Global.player_data["attuned_ley_lines"]) and never fade.
# Stand-in look: a dark standing stone with a slowly pulsing blue-green light and a name that shows when you are close.
extends Node3D
class_name LeyLineNode

const USE_RANGE := 5.0
const LABEL_RANGE := 20.0
const SAVE_KEY := "attuned_ley_lines"
# Classes that travel the ley-lines, and how each attunes (Class teleportation Spell Notes.txt).
const RITUALS := {
	"Arcanist": "You trace eldritch runes around the stone and fix its position in your memory, precisely, like a coordinate.",
	"Wildspeaker": "You press a Spectral Seed into the earth at the stone's foot. It takes root at once. The Green will remember this place.",
	"Chaosborn": "You cut your palm and press it to the stone. The resonance here drinks your blood and hums your name back at you.",
}

var node_id := ""
var display_name := "Ley-Stone"
var flavour := ""
var _label: Label3D
var _light: OmniLight3D
var _time := 0.0


func setup(entry: Dictionary) -> void:
	node_id = str(entry.get("id", ""))
	display_name = str(entry.get("name", "Ley-Stone"))
	flavour = str(entry.get("flavour", ""))


func _ready() -> void:
	add_to_group("ley_line_node")
	var stone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.55
	mesh.height = 2.6
	mesh.radial_segments = 6
	stone.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.26)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 0.8)
	mat.emission_energy_multiplier = 0.25
	stone.material_override = mat
	stone.position.y = 1.3
	add_child(stone)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.35, 0.95, 0.85)
	_light.omni_range = 6.0
	_light.position.y = 2.0
	add_child(_light)
	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.modulate = Color(0.7, 1.0, 0.95)
	_label.position.y = 3.2
	_label.visible = false
	add_child(_label)


func _process(delta: float) -> void:
	_time += delta
	_light.light_energy = 0.8 + 0.4 * sin(_time * 1.3)
	var player := TargetFrame.local_player()
	_label.visible = is_instance_valid(player) and global_position.distance_to(player.global_position) <= LABEL_RANGE


static func attuned() -> Dictionary:
	if typeof(Global.player_data.get(SAVE_KEY)) != TYPE_DICTIONARY:
		Global.player_data[SAVE_KEY] = {}
	return Global.player_data[SAVE_KEY]


static func is_attuned(id: String) -> bool:
	return attuned().has(id)


# Right-clicked by the local player.
func interact(player: Node) -> void:
	var player_class := str(player.get("player_class"))
	if not RITUALS.has(player_class):
		GameLog.log_general("[color=#99ddcc]%s %s An Arcanist, a Wildspeaker or a Chaosborn could anchor this place in memory.[/color]" % [display_name + ".", flavour])
		return
	if is_attuned(node_id):
		GameLog.log_general("[color=#99ddcc]You are already attuned to the %s.[/color]" % display_name)
		return
	if player.combat_node and player.combat_node.in_combat:
		GameLog.log_general("[color=#ff8866]You can't attune to a ley-line in the middle of a fight.[/color]")
		return
	attuned()[node_id] = true
	Global.save_player_data_to_file()
	Sfx.play("quest_received")
	GameLog.log_general("[color=#99ddcc]%s[/color]" % RITUALS[player_class])
	GameLog.log_general("[color=#ffdd44]You are attuned to the [b]%s[/b].[/color]" % display_name)
