#camera_controller.gd - controls the player camera
extends Node3D
class_name CameraController

## Camera Controller for Player
## Implements: 3 camera modes, zoom, rotation

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

# Camera mode positions (relative to player)
const MODE_POSITIONS := {
	CameraMode.THIRD_PERSON_BEHIND: Vector3(0, 2, 6),
	CameraMode.THIRD_PERSON_ANGLED: Vector3(0, 5, 8),
	CameraMode.FIRST_PERSON: Vector3(0, 1.6, 0)
}
#endregion

#region State Variables
var current_zoom: float = 6.0
var rotation_x: float = 0.0  # Vertical rotation
var rotation_y: float = 0.0  # Horizontal rotation
#endregion

#region Node References
@onready var camera: Camera3D = $Camera3D
#endregion

func _ready() -> void:
	# Capture mouse initially
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	apply_camera_mode()
	print("[CameraController] Camera initialized")

func _input(event: InputEvent) -> void:
	# Mouse look (right-click hold would go here, but for now always active)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		handle_mouse_look(event.relative)
	
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_camera(-ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_camera(ZOOM_SPEED)
	
	# Toggle mouse capture (ESC for now)
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Cycle camera modes (Home key)
	if event.is_action_pressed("cycle_camera_mode"):
		cycle_camera_mode()

func handle_mouse_look(relative: Vector2) -> void:
	# Horizontal rotation (Y axis)
	rotation_y -= relative.x * MOUSE_SENSITIVITY
	
	# Vertical rotation (X axis) with limits
	rotation_x -= relative.y * MOUSE_SENSITIVITY
	rotation_x = clamp(rotation_x, -PI/3, PI/3)  # -60° to +60°
	
	# Apply rotations
	rotation.y = rotation_y
	rotation.x = rotation_x

func zoom_camera(amount: float) -> void:
	current_zoom = clamp(current_zoom + amount, MIN_ZOOM, MAX_ZOOM)
	
	# Adjust camera position based on zoom
	if current_mode == CameraMode.THIRD_PERSON_BEHIND:
		camera.position.z = current_zoom
	elif current_mode == CameraMode.THIRD_PERSON_ANGLED:
		# Scale proportionally
		var zoom_factor: float = current_zoom / 6.0
		camera.position = Vector3(0, 5 * zoom_factor, 8 * zoom_factor)
	
	print("[CameraController] Zoom: ", current_zoom)

func cycle_camera_mode() -> void:
	current_mode = (current_mode + 1) % CameraMode.size()
	apply_camera_mode()
	print("[CameraController] Camera mode: ", CameraMode.keys()[current_mode])

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
	# Camera follows player smoothly (handled by being child of player)
	pass
