# zone_line.gd — an EverQuest-style zone line: walk into it and you go to another zone (Data/zones.json), arriving at a
# Marker3D in that zone's "Markers" folder. Put one in the zone scene's ZoneLines folder, set Target Zone and Target Marker
# in the Inspector and stretch Size over the gap in the mountains. In the editor it shows as a see-through orange wall with
# its destination written on it; in the game it is invisible.
# Only your own character triggers it (Net.zone_travel()). The server keeps the zone lines too: it only accepts a save that
# changes zone when that player is standing at a zone line to that zone (net.gd _check_zone_change()).
@tool
extends Area3D
class_name ZoneLine

## The zone it takes you to (a key of Data/zones.json: "dustwind_plateaus", "lumora_outskirts" ...).
@export var target_zone := "":
	set(value):
		target_zone = value
		_refresh_editor()
## The Marker3D (under that zone's Markers) you arrive at — keep it a little way in from that zone's own zone line.
@export var target_marker := "":
	set(value):
		target_marker = value
		_refresh_editor()
## The wall's size in metres (width, height, depth): wide enough to cover the gap.
@export var size := Vector3(40, 20, 4):
	set(value):
		size = value
		_refresh_editor()

const SERVER_TOLERANCE := 12.0   # metres of lag slack when the server checks a player really was at the line

var _shape: CollisionShape3D
var _preview: MeshInstance3D
var _label: Label3D
var _fired := false


func _ready() -> void:
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	_refresh_editor()
	if Engine.is_editor_hint():
		return
	add_to_group("zone_line")
	monitoring = true
	monitorable = false
	collision_mask = 1          # characters are on layer 1
	body_entered.connect(_on_body_entered)


func _refresh_editor() -> void:
	if _shape == null:
		return
	(_shape.shape as BoxShape3D).size = size
	_shape.position = Vector3(0, size.y / 2.0, 0)
	if not Engine.is_editor_hint():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.55, 0.1, 0.25)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_preview.material_override = mat
		add_child(_preview)
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.pixel_size = 0.02
		_label.modulate = Color(1.0, 0.75, 0.4)
		add_child(_label)
	var box := BoxMesh.new()
	box.size = size
	_preview.mesh = box
	_preview.position = Vector3(0, size.y / 2.0, 0)
	_label.text = "Zone line to %s\n(arrive at %s)" % [target_zone if not target_zone.is_empty() else "?", target_marker if not target_marker.is_empty() else "?"]
	_label.position = Vector3(0, size.y + 2.0, 0)


func _on_body_entered(body: Node) -> void:
	if _fired or not body.is_in_group("player") or body != TargetFrame.local_player():
		return
	if body.get("dying"):
		return
	_fired = true
	get_tree().create_timer(3.0).timeout.connect(func(): _fired = false)   # if the trip didn't start, you can try again
	Net.zone_travel(target_zone, target_marker)


# Is this point at the line (within its box, plus SERVER_TOLERANCE)? For the server's check.
func covers(point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * point
	var half := size / 2.0 + Vector3.ONE * SERVER_TOLERANCE
	return absf(local.x) <= half.x and local.y >= -SERVER_TOLERANCE and local.y <= size.y + SERVER_TOLERANCE and absf(local.z) <= half.z
