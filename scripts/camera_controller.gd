extends Node3D
class_name CameraController

## Dual-mode Chase and Cockpit camera controller for the exploration vessel.
## Supports dynamic speed FOV expansion, vibration dampening, and mouse/touch orbit.

enum CameraMode {
	CHASE_THIRD_PERSON,
	COCKPIT_FIRST_PERSON,
	ORBIT_INSPECTION
}

@export var current_mode: CameraMode = CameraMode.CHASE_THIRD_PERSON
@export var target_node_path: NodePath
@export var chase_distance: float = 28.0
@export var chase_height: float = 7.0
@export var chase_smooth_speed: float = 8.0
@export var base_fov: float = 72.0
@export var max_fov: float = 90.0

@onready var camera: Camera3D = $Camera3D

var target_ship: RigidBody3D
var orbit_yaw: float = 0.0
var orbit_pitch: float = -12.0
var is_touch_dragging: bool = false
var touch_start_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	set_as_top_level(true)
	if not target_node_path.is_empty():
		target_ship = get_node(target_node_path)
	elif get_parent() is RigidBody3D:
		target_ship = get_parent()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		_cycle_camera_mode()
		
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		orbit_yaw -= event.relative.x * 0.2
		orbit_pitch = clamp(orbit_pitch - event.relative.y * 0.2, -60.0, 70.0)
	elif event is InputEventScreenDrag:
		orbit_yaw -= event.relative.x * 0.3
		orbit_pitch = clamp(orbit_pitch - event.relative.y * 0.3, -60.0, 70.0)

func _physics_process(delta: float) -> void:
	if not target_ship or not camera:
		return
		
	match current_mode:
		CameraMode.CHASE_THIRD_PERSON:
			_process_chase_camera(delta)
		CameraMode.COCKPIT_FIRST_PERSON:
			_process_cockpit_camera(delta)
		CameraMode.ORBIT_INSPECTION:
			_process_orbit_camera(delta)
			
	_update_dynamic_fov(delta)

func _process_chase_camera(delta: float) -> void:
	var ship_transform: Transform3D = target_ship.global_transform
	var forward: Vector3 = -ship_transform.basis.z.normalized()
	var up: Vector3 = ship_transform.basis.y.normalized()
	
	var desired_pos: Vector3 = target_ship.global_position - forward * chase_distance + up * chase_height
	global_position = global_position.lerp(desired_pos, chase_smooth_speed * delta)
	
	var look_target: Vector3 = target_ship.global_position + target_ship.linear_velocity * 0.02
	camera.look_at(look_target, up)

func _process_cockpit_camera(_delta: float) -> void:
	var ship_transform: Transform3D = target_ship.global_transform
	var cockpit_offset: Vector3 = ship_transform.basis * Vector3(0.0, 1.2, -2.6)
	global_position = target_ship.global_position + cockpit_offset
	global_transform.basis = ship_transform.basis

func _process_orbit_camera(delta: float) -> void:
	var yaw_rad: float = deg_to_rad(orbit_yaw)
	var pitch_rad: float = deg_to_rad(orbit_pitch)
	
	var offset: Vector3 = Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		-sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	) * chase_distance
	
	var desired_pos: Vector3 = target_ship.global_position + offset
	global_position = global_position.lerp(desired_pos, chase_smooth_speed * delta)
	camera.look_at(target_ship.global_position, target_ship.global_transform.basis.y.normalized())

func _update_dynamic_fov(delta: float) -> void:
	if not target_ship:
		return
	var speed: float = target_ship.linear_velocity.length()
	var fov_factor: float = clamp(speed / 8000.0, 0.0, 1.0)
	var target_fov: float = lerp(base_fov, max_fov, fov_factor)
	camera.fov = lerp(camera.fov, target_fov, 4.0 * delta)

func _cycle_camera_mode() -> void:
	match current_mode:
		CameraMode.CHASE_THIRD_PERSON:
			current_mode = CameraMode.COCKPIT_FIRST_PERSON
		CameraMode.COCKPIT_FIRST_PERSON:
			current_mode = CameraMode.ORBIT_INSPECTION
		CameraMode.ORBIT_INSPECTION:
			current_mode = CameraMode.CHASE_THIRD_PERSON
