# ley_line_node.gd — a travel site in the world (Data/ley_lines.json, placed by crafting_world_spawner.gd). Each class that
# travels the ley-lines has its OWN sites, in different zones (the map: ~/NCT/Aldenexia-Lightfall/Aldenexia Map.png):
#   Arcanist    — Spires: raised by the scholars of the Lycaeum before the Lightfall, precise as coordinates.
#   Wildspeaker — Ruins: older than any city, places where the Green still remembers the world before the Lightfall.
#   Chaosborn   — Rifts: wounds the Lightfall tore in the world, which never closed.
# Right-click one within USE_RANGE (player3d.gd _try_ley_line_node()): its own class anchors it in memory with their ritual,
# and their travel spell (Spectral Bridge, Root-Tunnel, Chaos Rift) can take them there afterwards. The other two travel
# classes recognise it but can't use it; everyone else sees an old tower / overgrown ruins / scarred ground. A site with no
# "class" in the data is open to all three (tests). Attunements are the character's own (Global.player_data
# ["attuned_ley_lines"]) and never fade. Stand-in look per kind until real models exist.
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

# Each class's kind of site: what it's called, what an outsider sees, what a different travel class is told, stand-in colour.
const KINDS := {
	"Arcanist": {"kind": "Spire", "plural": "Spires", "outsider": "Old Tower", "colour": Color(0.45, 0.6, 1.0),
		"other": "An Arcanist Spire, raised by the Lycaeum. Its runes are exact, cold and not written for you."},
	"Wildspeaker": {"kind": "Ruins", "plural": "Ruins", "outsider": "Overgrown Ruins", "colour": Color(0.4, 0.95, 0.5),
		"other": "Wildspeaker Ruins. The Green remembers this place, but not for you."},
	"Chaosborn": {"kind": "Rift", "plural": "Rifts", "outsider": "Scarred Ground", "colour": Color(0.8, 0.3, 1.0),
		"other": "A Chaosborn Rift, a wound the Lightfall left behind. It wants blood, and not yours."},
}

var node_id := ""
var site_class := ""                    # "Arcanist" / "Wildspeaker" / "Chaosborn"; "" = any of them
var display_name := "Ley-Stone"
var flavour := ""
var _label: Label3D
var _light: OmniLight3D
var _time := 0.0


func setup(entry: Dictionary) -> void:
	node_id = str(entry.get("id", ""))
	display_name = str(entry.get("name", "Ley-Stone"))
	flavour = str(entry.get("flavour", ""))
	site_class = str(entry.get("class", ""))


# The kind of site a class travels to ("Spire"), and its full name ("Arcanist Spire").
static func kind_for(player_class: String) -> String:
	return str(KINDS.get(player_class, {}).get("kind", "ley-line site"))


static func site_phrase(player_class: String) -> String:
	if not KINDS.has(player_class):
		return "a ley-line site"
	return "%s %s" % [player_class, kind_for(player_class)]


# Can this class attune here / travel here?
static func usable_by(entry_class: String, player_class: String) -> bool:
	return RITUALS.has(player_class) and (entry_class.is_empty() or entry_class == player_class)

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
	var colour: Color = KINDS.get(site_class, {}).get("colour", Color(0.2, 0.9, 0.8))
	mat.emission = colour
	match site_class:
		"Arcanist":   # a tall, slim spire
			mesh.top_radius = 0.08
			mesh.bottom_radius = 0.6
			mesh.height = 5.0
			mesh.radial_segments = 4
		"Chaosborn":  # a jagged, leaning shard
			mesh.top_radius = 0.02
			mesh.bottom_radius = 0.7
			mesh.height = 3.0
			mesh.radial_segments = 3
			stone.rotation_degrees = Vector3(12, 0, 8)
	mat.emission_energy_multiplier = 0.25
	stone.material_override = mat
	stone.position.y = mesh.height / 2.0
	add_child(stone)
	if site_class == "Wildspeaker":   # a broken ring of low stones around the centre one
		for i in 6:
			var piece := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.6, 0.6 + 0.5 * (i % 3), 0.5)
			piece.mesh = box
			piece.material_override = mat
			var a := TAU * i / 6.0
			piece.position = Vector3(cos(a) * 2.2, box.size.y / 2.0, sin(a) * 2.2)
			piece.rotation.y = -a
			add_child(piece)
	_light = OmniLight3D.new()
	_light.light_color = KINDS.get(site_class, {}).get("colour", Color(0.35, 0.95, 0.85))
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
	_label.position.y = 5.8 if site_class == "Arcanist" else 3.4
	_label.visible = false
	add_child(_label)


func _process(delta: float) -> void:
	_time += delta
	_light.light_energy = 0.8 + 0.4 * sin(_time * 1.3)
	var player := TargetFrame.local_player()
	_label.visible = is_instance_valid(player) and global_position.distance_to(player.global_position) <= LABEL_RANGE
	if _label.visible:
		# A travel class sees what the site is (its own, by name; another's, by kind); everyone else sees something old.
		var pc := str(player.get("player_class"))
		if usable_by(site_class, pc):
			_label.text = display_name
		elif RITUALS.has(pc):
			_label.text = site_phrase(site_class)
		else:
			_label.text = str(KINDS.get(site_class, {}).get("outsider", "Old Standing Stone"))


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
		GameLog.log_general("[color=#99ddcc]%s You feel like a person with magical knowledge could make use of this.[/color]" % flavour)
		return
	if not usable_by(site_class, player_class):
		GameLog.log_general("[color=#99ddcc]%s[/color]" % str(KINDS.get(site_class, {}).get("other", flavour)))
		return
	if is_attuned(node_id):
		GameLog.log_general("[color=#99ddcc]You are already attuned to the %s.[/color]" % display_name)
		return
	if player.combat_node and player.combat_node.in_combat:
		GameLog.log_general("[color=#ff8866]You can't attune to the %s in the middle of a fight.[/color]" % display_name)
		return
	attuned()[node_id] = true
	Global.save_player_data_to_file()
	Sfx.play("quest_received")
	GameLog.log_general("[color=#99ddcc]%s[/color]" % RITUALS[player_class])
	GameLog.log_general("[color=#ffdd44]You are attuned to the [b]%s[/b].[/color]" % display_name)
