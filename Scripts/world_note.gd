# world_note.gd — A readable object lying in the world: right-click it within USE_RANGE (player3d.gd's _try_read_world_note(),
# range-based like the campfire). Reading logs its text and, the first time, can start a quest ("start_quest"). Readable again
# any time. Built entirely in code (a flat paper with the note icon, a faint warm light that breathes, a name that only shows
# when you are close), so a note is one node with three settings in the scene. Per-viewer: the quest state is the local character's.
extends Node3D
class_name WorldNote

const USE_RANGE := 4.0
const LABEL_RANGE := 14.0
const NOTE_ICON := "res://Assets/icons/items/note.png"
const TEXT_COLOR := "#e8dcc0"

@export var title: String = "Torn Note"
@export_multiline var note_text: String = ""
## Quest id (Data/quests.json) started the first time this is read; empty = none.
@export var start_quest: String = ""

var _label: Label3D
var _light: OmniLight3D
var _time := 0.0
var _label_timer := 0.0


func _ready() -> void:
	add_to_group("world_note")
	var paper := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.7)
	paper.mesh = quad
	var mat := StandardMaterial3D.new()
	var icon := load(NOTE_ICON) as Texture2D
	if icon:
		mat.albedo_texture = icon
	mat.albedo_color = Color(1.0, 0.95, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.75, 0.4)
	mat.emission_energy_multiplier = 0.35
	paper.material_override = mat
	paper.rotation_degrees = Vector3(-84.0, randf() * 360.0, 0.0)   # lying nearly flat, at a random angle
	paper.position = Vector3(0, 0.05, 0)
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paper)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.5)
	_light.omni_range = 3.0
	_light.light_energy = 0.5
	_light.position = Vector3(0, 0.5, 0)
	_light.shadow_enabled = false
	add_child(_light)

	_label = Label3D.new()
	_label.text = title
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.modulate = Color(1.0, 0.92, 0.65)
	_label.outline_size = 8
	_label.position = Vector3(0, 0.55, 0)
	_label.visible = false
	add_child(_label)


func _process(delta: float) -> void:
	_time += delta
	if _light:
		_light.light_energy = 0.45 + 0.15 * sin(_time * 2.2)   # a slow breathing glow so the eye finds it
	_label_timer -= delta
	if _label_timer <= 0.0:
		_label_timer = 0.25
		var player: Node3D = TargetFrame.local_player()
		_label.visible = is_instance_valid(player) and player.global_position.distance_to(global_position) <= LABEL_RANGE


# Right-click within range.
func read(_player: Node) -> void:
	GameLog.log_general("[color=%s]You read the %s:[/color]" % [TEXT_COLOR, title.to_lower()])
	for paragraph in note_text.split("\n", false):
		GameLog.log_general("[color=%s][i]%s[/i][/color]" % [TEXT_COLOR, paragraph])
	if not start_quest.is_empty() and not Quests.is_started(start_quest):
		Quests.start(start_quest)
