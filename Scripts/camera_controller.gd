#camera_controller.gd - controls the player camera
extends Node3D
class_name CameraController

## Camera Controller for Player
## Implements: 3 camera modes, zoom, rotation
## Mouse look is active only while right mouse button is held.

#region Camera Modes
enum CameraMode {
	THIRD_PERSON_BEHIND,  # Default - 6m behind
	THIRD_PERSON_ANGLED,  # Tactical - 8m back, 5m up, 45°
	FIRST_PERSON          # Eye level
}

var current_mode: CameraMode = CameraMode.THIRD_PERSON_BEHIND
#endregion

#region Configuration
const MOUSE_SENSITIVITY: float = 0.002
const ZOOM_SPEED: float = 0.5
const MIN_ZOOM: float = 2.0
const MAX_ZOOM: float = 12.0

const MODE_POSITIONS := {
	CameraMode.THIRD_PERSON_BEHIND: Vector3(0, 2, 6),
	CameraMode.THIRD_PERSON_ANGLED: Vector3(0, 5, 8),
	CameraMode.FIRST_PERSON: Vector3(0, 1.6, 0)
}
#endregion

#region State Variables
var current_zoom: float = 6.0
var rotation_x: float = 0.0
var rotation_y: float = 0.0
var _right_mouse_held: bool = false
#endregion

#region Node References
@onready var camera: Camera3D = $Camera3D
#endregion

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	apply_camera_mode()

func _input(event: InputEvent) -> void:
	# F12 toggles mouse-look on/off
	if event is InputEventKey and event.keycode == KEY_F12 and event.pressed and not event.echo:
		_right_mouse_held = not _right_mouse_held
		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED if _right_mouse_held else Input.MOUSE_MODE_VISIBLE
		)

	# Mouse look — only while toggled on
	if event is InputEventMouseMotion and _right_mouse_held:
		handle_mouse_look(event.relative)

	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_camera(-ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_camera(ZOOM_SPEED)

	# Cycle camera modes (Home key)
	if event.is_action_pressed("cycle_camera_mode"):
		cycle_camera_mode()

func handle_mouse_look(relative: Vector2) -> void:
	rotation_y -= relative.x * MOUSE_SENSITIVITY
	rotation_x -= relative.y * MOUSE_SENSITIVITY
	rotation_x = clamp(rotation_x, -PI/3, PI/3)
	rotation.y = rotation_y
	rotation.x = rotation_x

func zoom_camera(amount: float) -> void:
	current_zoom = clamp(current_zoom + amount, MIN_ZOOM, MAX_ZOOM)
	if current_mode == CameraMode.THIRD_PERSON_BEHIND:
		camera.position.z = current_zoom
	elif current_mode == CameraMode.THIRD_PERSON_ANGLED:
		var zoom_factor: float = current_zoom / 6.0
		camera.position = Vector3(0, 5 * zoom_factor, 8 * zoom_factor)

func cycle_camera_mode() -> void:
	current_mode = (current_mode + 1) % CameraMode.size()
	apply_camera_mode()

func apply_camera_mode() -> void:
	match current_mode:
		CameraMode.THIRD_PERSON_BEHIND:
			camera.position = Vector3(0, 2, current_zoom)
			camera.rotation_degrees = Vector3(0, 0, 0)
		CameraMode.THIRD_PERSON_ANGLED:
			var zoom_factor: float = current_zoom / 6.0
			camera.position = Vector3(0, 5 * zoom_factor, 8 * zoom_factor)
			camera.look_at(Vector3.ZERO, Vector3.UP)
		CameraMode.FIRST_PERSON:
			camera.position = Vector3(0, 1.6, 0)
			camera.rotation_degrees = Vector3(0, 0, 0)

func _process(_delta: float) -> void:
	pass
