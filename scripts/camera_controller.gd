extends Node3D
class_name CameraController

## Multi-mode Camera Controller: Cockpit (1st-person), Chase (3rd-person), and Free (orbit/free-look).
## Supports dynamic speed FOV expansion, trauma-based camera shake, and mouse/touch/gamepad controls.

enum CameraMode {
	COCKPIT = 0,
	CHASE = 1,
	FREE = 2,
	# Backward-compatible aliases
	COCKPIT_FIRST_PERSON = 0,
	CHASE_THIRD_PERSON = 1,
	ORBIT_INSPECTION = 2
}

@export var current_mode: CameraMode = CameraMode.CHASE
@export var target_node_path: NodePath
@export var chase_distance: float = 28.0
@export var chase_height: float = 7.0
@export var chase_smooth_speed: float = 8.0
## How fast the camera's *orientation* follows the ship (1/s). Position is rigidly tied to the ship
## so the camera never trails behind at speed (a position lerp lags v*dt*(1-a)/a metres: ~240 m at 2 km/s).
@export var chase_rotation_speed: float = 5.0
## Extra pull-back (fraction of chase_distance/height) at the speed reference (boost / limit).
@export var chase_speed_pullback: float = 0.35
@export var chase_look_ahead: float = 45.0
@export var base_fov: float = 72.0
@export var max_fov: float = 90.0
@export var fov_speed_threshold: float = 8000.0
@export var cockpit_offset: Vector3 = Vector3(0.0, 1.2, -2.6)
@export var trauma_decay: float = 1.2
@export var max_shake_offset: Vector3 = Vector3(0.25, 0.25, 0.1)
@export var max_shake_roll_deg: float = 2.0

@onready var camera: Camera3D = get_node_or_null("Camera3D")

var target_ship: RigidBody3D
var target_node: Node3D
var orbit_yaw: float = 0.0
var orbit_pitch: float = -12.0
var is_touch_dragging: bool = false
var touch_start_pos: Vector2 = Vector2.ZERO

var trauma: float = 0.0
var _shake_time: float = 0.0
var _chase_basis: Basis = Basis.IDENTITY
var _chase_ready: bool = false

func _ready() -> void:
	set_as_top_level(true)
	_ready_interp_off()
	_ensure_camera()
	_resolve_target()

func _ensure_camera() -> void:
	if not camera:
		camera = get_node_or_null("Camera3D")
	if not camera:
		for child in get_children():
			if child is Camera3D:
				camera = child
				break
	if not camera:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)

func _resolve_target() -> void:
	if not target_node_path.is_empty():
		var node = get_node_or_null(target_node_path)
		if node is Node3D:
			set_target(node)
	elif get_parent() is Node3D and get_parent() != get_tree().root:
		set_target(get_parent() as Node3D)

func set_target(new_target: Node3D) -> void:
	target_node = new_target
	if new_target is RigidBody3D:
		target_ship = new_target as RigidBody3D
	else:
		target_ship = null

func get_target_velocity() -> Vector3:
	if target_ship:
		return target_ship.linear_velocity
	elif target_node and "velocity" in target_node:
		return target_node.velocity
	elif target_node and "linear_velocity" in target_node:
		return target_node.linear_velocity
	return Vector3.ZERO

func add_trauma(amount: float) -> void:
	trauma = clamp(trauma + amount, 0.0, 1.0)

func add_shake(amount: float) -> void:
	add_trauma(amount)

func get_trauma() -> float:
	return trauma

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		_cycle_camera_mode()
		
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		orbit_yaw -= event.relative.x * 0.2
		orbit_pitch = clamp(orbit_pitch - event.relative.y * 0.2, -80.0, 80.0)
	elif event is InputEventScreenDrag:
		orbit_yaw -= event.relative.x * 0.3
		orbit_pitch = clamp(orbit_pitch - event.relative.y * 0.3, -80.0, 80.0)

func _ready_interp_off() -> void:
	# The camera follows the *rendered* (interpolated) ship every frame, so it must not be interpolated itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _process(delta: float) -> void:
	_follow(delta)

func _physics_process(_delta: float) -> void:
	pass

func _follow(delta: float) -> void:
	_ensure_camera()
	if not target_node and target_ship:
		target_node = target_ship
	if not target_node or not camera:
		return
		
	_handle_orbit_input(delta)
	
	match current_mode:
		CameraMode.COCKPIT:
			_process_cockpit_camera(delta)
		CameraMode.CHASE:
			_process_chase_camera(delta)
		CameraMode.FREE:
			_process_free_camera(delta)
			
	_update_dynamic_fov(delta)
	_apply_camera_shake(delta)

func _handle_orbit_input(delta: float) -> void:
	if current_mode == CameraMode.FREE:
		var look_x = Input.get_axis("look_left", "look_right")
		var look_y = Input.get_axis("look_up", "look_down")
		if abs(look_x) > 0.05 or abs(look_y) > 0.05:
			orbit_yaw -= look_x * 90.0 * delta
			orbit_pitch = clamp(orbit_pitch - look_y * 90.0 * delta, -80.0, 80.0)

func _target_transform() -> Transform3D:
	if target_node and target_node.is_inside_tree():
		return target_node.get_global_transform_interpolated()
	return Transform3D.IDENTITY

func _speed_reference() -> float:
	if target_node and "current_speed_limit" in target_node:
		return maxf(float(target_node.current_speed_limit), 50.0)
	return fov_speed_threshold

func _process_chase_camera(delta: float) -> void:
	var tt: Transform3D = _target_transform()
	var ship_basis: Basis = tt.basis.orthonormalized()
	if not _chase_ready:
		_chase_basis = ship_basis
		_chase_ready = true
	# Smooth orientation only (frame-rate independent); position stays rigidly attached to the ship.
	var w: float = 1.0 - exp(-chase_rotation_speed * delta)
	_chase_basis = _chase_basis.slerp(ship_basis, w).orthonormalized()

	var speed: float = get_target_velocity().length()
	var pull: float = 1.0 + chase_speed_pullback * clampf(speed / _speed_reference(), 0.0, 1.0)
	var forward: Vector3 = -_chase_basis.z
	var up: Vector3 = _chase_basis.y
	global_position = tt.origin - forward * (chase_distance * pull) + up * (chase_height * pull)

	var look_target: Vector3 = tt.origin + forward * chase_look_ahead
	if global_position.distance_to(look_target) > 0.01:
		camera.look_at(look_target, up)

func _process_cockpit_camera(_delta: float) -> void:
	var target_transform: Transform3D = target_node.global_transform
	var offset: Vector3 = target_transform.basis * cockpit_offset
	global_position = target_node.global_position + offset
	global_transform.basis = target_transform.basis
	camera.transform = Transform3D.IDENTITY

func _process_free_camera(delta: float) -> void:
	var yaw_rad: float = deg_to_rad(orbit_yaw)
	var pitch_rad: float = deg_to_rad(orbit_pitch)
	
	var offset: Vector3 = Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		-sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	) * chase_distance
	
	var desired_pos: Vector3 = target_node.global_position + offset
	global_position = global_position.lerp(desired_pos, chase_smooth_speed * delta)
	var up_vec: Vector3 = target_node.global_transform.basis.y.normalized()
	if abs(up_vec.dot(Vector3.UP)) < 0.99:
		camera.look_at(target_node.global_position, up_vec)
	else:
		camera.look_at(target_node.global_position, Vector3.UP)

func _update_dynamic_fov(delta: float) -> void:
	_ensure_camera()
	if not camera:
		return
	var speed: float = get_target_velocity().length()
	var fov_factor: float = clamp(speed / _speed_reference(), 0.0, 1.0)
	var target_fov: float = lerp(base_fov, max_fov, fov_factor)
	var weight: float = clamp(4.0 * delta, 0.0, 1.0)
	camera.fov = lerp(camera.fov, target_fov, weight)

func _apply_camera_shake(delta: float) -> void:
	_ensure_camera()
	if not camera:
		return
	if trauma <= 0.0:
		return
		
	_shake_time += delta * 25.0
	var shake_val = trauma * trauma
	var offset_x = sin(_shake_time * 1.1) * max_shake_offset.x * shake_val
	var offset_y = cos(_shake_time * 1.3) * max_shake_offset.y * shake_val
	var offset_z = sin(_shake_time * 0.9) * max_shake_offset.z * shake_val
	var roll = sin(_shake_time * 1.5) * deg_to_rad(max_shake_roll_deg) * shake_val
	
	if current_mode == CameraMode.COCKPIT:
		camera.position = Vector3(offset_x, offset_y, offset_z)
		camera.rotation.z = roll
	else:
		camera.position = Vector3(offset_x, offset_y, offset_z)
	
	trauma = max(0.0, trauma - trauma_decay * delta)
	if trauma == 0.0:
		camera.position = Vector3.ZERO
		camera.rotation.z = 0.0

func _cycle_camera_mode() -> void:
	_chase_ready = false
	match current_mode:
		CameraMode.COCKPIT:
			set_camera_mode(CameraMode.CHASE)
		CameraMode.CHASE:
			set_camera_mode(CameraMode.FREE)
		CameraMode.FREE:
			set_camera_mode(CameraMode.COCKPIT)

func set_camera_mode(new_mode: CameraMode) -> void:
	_chase_ready = false
	current_mode = new_mode
	if camera:
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
