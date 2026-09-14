#camera_controller.gd - controls the player camera
extends Node3D
class_name CameraController

## Camera Controller for Player
## Implements: 3 camera modes, zoom, rotation
## Two distinct look modes, both driven by mouse motion:
##  - F12 toggles free-look mouselook: uncapped yaw (full spin), pitch capped
##    only to avoid flipping past vertical. Feels like moving the camera.
##  - Holding the right mouse button (independent of F12) is a "head turn":
##    capped to a realistic head-turn range (MAX_YAW/MAX_PITCH), snaps back to
##    nothing special on release — it just stops moving. Feels like turning
##    your head without touching the camera itself.

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
const MAX_YAW: float = deg_to_rad(90.0)    # head-turn cap: 180° total left/right
const MAX_PITCH: float = deg_to_rad(45.0)  # head-turn cap: 90° total up/down
const FREE_LOOK_MAX_PITCH: float = deg_to_rad(89.0)  # mouselook: capped only to avoid flipping past vertical

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
var _head_turn_held: bool = false
#endregion

#region Node References
@onready var camera: Camera3D = $Camera3D
#endregion

func _ready() -> void:
	Global.restore_mouse_mode()
	apply_camera_mode()

func _input(event: InputEvent) -> void:
	# F12 toggles free-look mouselook on/off
	if event is InputEventKey and event.keycode == KEY_F12 and event.pressed and not event.echo:
		Global.mouselook_enabled = not Global.mouselook_enabled
		Global.restore_mouse_mode()

	# Right mouse button held = capped "head turn", independent of mouselook.
	# Mouselook (if already on) takes priority and owns the mouse mode, so
	# right-click here only matters when mouselook is off.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_head_turn_held = event.pressed
		if not Global.mouselook_enabled:
			if _head_turn_held:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Global.restore_mouse_mode()

	if event is InputEventMouseMotion:
		if Global.mouselook_enabled:
			_handle_free_look(event.relative)
		elif _head_turn_held:
			_handle_head_turn(event.relative)

	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_camera(-ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_camera(ZOOM_SPEED)

	# Cycle camera modes (Home key)
	if event.is_action_pressed("cycle_camera_mode"):
		cycle_camera_mode()


# Uncapped yaw (wraps instead of growing unbounded), pitch capped only to
# avoid flipping past straight up/down.
func _handle_free_look(relative: Vector2) -> void:
	var y_sign: float = -1.0 if Global.settings.get("invert_look_y", false) else 1.0
	rotation_y = wrapf(rotation_y - relative.x * MOUSE_SENSITIVITY, -PI, PI)
	rotation_x = clamp(rotation_x - relative.y * y_sign * MOUSE_SENSITIVITY, -FREE_LOOK_MAX_PITCH, FREE_LOOK_MAX_PITCH)
	rotation.y = rotation_y
	rotation.x = rotation_x


# Capped to a realistic head-turn range — stops moving at the cap instead of
# wrapping or flipping, and just holds there until the button is released.
func _handle_head_turn(relative: Vector2) -> void:
	var y_sign: float = -1.0 if Global.settings.get("invert_look_y", false) else 1.0
	rotation_y = clamp(rotation_y - relative.x * MOUSE_SENSITIVITY, -MAX_YAW, MAX_YAW)
	rotation_x = clamp(rotation_x - relative.y * y_sign * MOUSE_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
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
