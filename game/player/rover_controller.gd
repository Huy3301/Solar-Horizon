class_name RoverController extends VehicleBody3D

## Lunar Rover Controller designed for low-gravity planetary surface exploration.
## Features 4WD electric torque distribution, adaptive low-gravity steering,
## active roll/pitch stabilization, brake damping, and driver mount/dismount interaction API.

signal mounted(driver: Node)
signal dismounted(driver: Node, exit_position: Vector3)
signal headlights_changed(is_on: bool)

# Lunar surface physics defaults (Moon gravity ~1.62 m/s²)
const LUNAR_GRAVITY_DEFAULT: float = 1.62
const EARTH_GRAVITY_DEFAULT: float = 9.80665

@export_group("Lunar Dynamics")
@export var lunar_gravity: float = LUNAR_GRAVITY_DEFAULT
@export var apply_lunar_gravity_scale: bool = true
@export var gravity_override: Vector3 = Vector3.ZERO
@export var downforce_enabled: bool = true
@export var downforce_strength: float = 1.5
@export var roll_stabilization_enabled: bool = true
@export var roll_stabilization_strength: float = 6.0
@export var pitch_stabilization_strength: float = 3.0
@export var angular_damping_strength: float = 2.5

@export_group("Powertrain & 4WD")
@export var four_wheel_drive: bool = true
@export var max_engine_force: float = 600.0
@export var max_brake_force: float = 40.0
@export_range(0.0, 1.0) var torque_balance_front_rear: float = 0.5
@export var brake_damping: float = 4.0
@export var coasting_damping: float = 1.5

@export_group("Steering")
@export var max_steer_angle: float = deg_to_rad(28.0) # ~0.4886 rad
@export var steer_speed: float = 5.0
@export var rear_wheel_counter_steer: bool = false
@export var rear_steer_ratio: float = 0.0

@export_group("Mount & Driver")
@export var exit_offset: Vector3 = Vector3(-1.8, 0.2, 0.0)
@export var seat_offset: Vector3 = Vector3(-0.4, 0.6, 0.0)
@export var accept_player_input: bool = true

@export_group("References")
@export var wheel_fl: VehicleWheel3D
@export var wheel_fr: VehicleWheel3D
@export var wheel_rl: VehicleWheel3D
@export var wheel_rr: VehicleWheel3D
@export var camera: Camera3D
@export var driver_seat: Node3D
@export var exit_point: Node3D

var driver: Node = null
var headlights_on: bool = false

var throttle_input: float = 0.0:
	set(val):
		throttle_input = clampf(val, -1.0, 1.0)
		_current_throttle = throttle_input
		_apply_control_values()

var steer_input: float = 0.0:
	set(val):
		steer_input = clampf(val, -1.0, 1.0)
		_current_steer_angle = steer_input * max_steer_angle
		_apply_control_values()

var brake_input: float = 0.0:
	set(val):
		brake_input = clampf(val, 0.0, 1.0)
		_current_brake = brake_input
		_apply_control_values()

var _wheels: Array[VehicleWheel3D] = []
var _headlights: Array[SpotLight3D] = []

var _current_throttle: float = 0.0
var _current_steer_angle: float = 0.0
var _current_brake: float = 0.0
var _base_linear_damp: float = 0.0
var _base_angular_damp: float = 0.0

func _ready() -> void:
	_base_linear_damp = linear_damp
	_base_angular_damp = angular_damp

	_resolve_wheels()
	_resolve_headlights()
	_resolve_references()

	if apply_lunar_gravity_scale:
		_setup_lunar_gravity()

	set_headlights(headlights_on)
	_apply_control_values()

func _setup_lunar_gravity() -> void:
	var def_g: float = ProjectSettings.get_setting("physics/3d/default_gravity", EARTH_GRAVITY_DEFAULT)
	if def_g > 0.01:
		gravity_scale = lunar_gravity / def_g
	else:
		gravity_scale = lunar_gravity / EARTH_GRAVITY_DEFAULT

func _resolve_wheels() -> void:
	_wheels.clear()
	if wheel_fl and is_instance_valid(wheel_fl):
		_wheels.append(wheel_fl)
	if wheel_fr and is_instance_valid(wheel_fr):
		_wheels.append(wheel_fr)
	if wheel_rl and is_instance_valid(wheel_rl):
		_wheels.append(wheel_rl)
	if wheel_rr and is_instance_valid(wheel_rr):
		_wheels.append(wheel_rr)

	if _wheels.size() == 4:
		return

	# Auto-discover child VehicleWheel3D nodes
	_wheels.clear()
	var candidates: Array[VehicleWheel3D] = []
	for child in find_children("*", "VehicleWheel3D", true, false):
		if child is VehicleWheel3D:
			candidates.append(child)

	for w in candidates:
		var n = w.name.to_upper()
		if "FL" in n or ("FRONT" in n and "LEFT" in n):
			wheel_fl = w
		elif "FR" in n or ("FRONT" in n and "RIGHT" in n):
			wheel_fr = w
		elif "RL" in n or ("REAR" in n and "LEFT" in n) or ("BACK" in n and "LEFT" in n):
			wheel_rl = w
		elif "RR" in n or ("REAR" in n and "RIGHT" in n) or ("BACK" in n and "RIGHT" in n):
			wheel_rr = w

	# If positions distinguish them when naming doesn't match
	if (wheel_fl == null or wheel_fr == null or wheel_rl == null or wheel_rr == null) and candidates.size() >= 4:
		# Sort by Z (front has smaller Z / negative Z in Godot)
		candidates.sort_custom(func(a: VehicleWheel3D, b: VehicleWheel3D) -> bool:
			return a.position.z < b.position.z
		)
		var front_pair = [candidates[0], candidates[1]]
		var rear_pair = [candidates[2], candidates[3]]
		
		front_pair.sort_custom(func(a: VehicleWheel3D, b: VehicleWheel3D) -> bool:
			return a.position.x < b.position.x
		)
		rear_pair.sort_custom(func(a: VehicleWheel3D, b: VehicleWheel3D) -> bool:
			return a.position.x < b.position.x
		)
		
		if wheel_fl == null: wheel_fl = front_pair[0]
		if wheel_fr == null: wheel_fr = front_pair[1]
		if wheel_rl == null: wheel_rl = rear_pair[0]
		if wheel_rr == null: wheel_rr = rear_pair[1]

	_wheels.clear()
	if wheel_fl: _wheels.append(wheel_fl)
	if wheel_fr: _wheels.append(wheel_fr)
	if wheel_rl: _wheels.append(wheel_rl)
	if wheel_rr: _wheels.append(wheel_rr)

func _resolve_headlights() -> void:
	_headlights.clear()
	for child in find_children("*", "SpotLight3D", true, false):
		if child is SpotLight3D:
			_headlights.append(child)

func _resolve_references() -> void:
	if not driver_seat:
		driver_seat = get_node_or_null("DriverSeat") as Node3D
	if not exit_point:
		exit_point = get_node_or_null("ExitPoint") as Node3D
	if not camera:
		camera = get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
		if not camera:
			for child in find_children("*", "Camera3D", true, false):
				if child is Camera3D:
					camera = child
					break

func get_wheels() -> Array[VehicleWheel3D]:
	if _wheels.is_empty():
		_resolve_wheels()
	return _wheels

func get_headlights() -> Array[SpotLight3D]:
	if _headlights.is_empty():
		_resolve_headlights()
	return _headlights

# =========================================================================
# Interaction API (Task 1 Requirements)
# =========================================================================

func can_mount() -> bool:
	return not is_occupied()

func mount(driver_node: Node) -> void:
	if driver_node == null:
		return
	if is_occupied():
		push_warning("RoverController: Cannot mount, vehicle is already occupied.")
		return

	driver = driver_node

	if driver.has_method("set_active"):
		driver.set_active(false)
	if driver is Node3D:
		var seat_pos = get_driver_seat_position()
		if (driver as Node3D).is_inside_tree():
			(driver as Node3D).global_position = seat_pos
		else:
			(driver as Node3D).position = seat_pos
		(driver as Node3D).visible = false

	if camera and is_instance_valid(camera):
		camera.current = true

	# Release parking brake on mount
	brake_input = 0.0
	mounted.emit(driver_node)

func dismount() -> Vector3:
	var exit_pos = get_exit_position()
	var prev_driver = driver

	if is_instance_valid(driver):
		if driver.has_method("set_active"):
			driver.set_active(true)
		if driver is Node3D:
			if (driver as Node3D).is_inside_tree():
				(driver as Node3D).global_position = exit_pos
			else:
				(driver as Node3D).position = exit_pos
			(driver as Node3D).visible = true

	driver = null

	if camera and is_instance_valid(camera):
		camera.current = false

	# Reset controls and engage parking brake
	throttle_input = 0.0
	steer_input = 0.0
	brake_input = 1.0
	_apply_control_values()

	dismounted.emit(prev_driver, exit_pos)
	return exit_pos

func is_occupied() -> bool:
	return driver != null and is_instance_valid(driver)

func get_driver() -> Node:
	return driver

func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6

func toggle_headlights() -> bool:
	return set_headlights(not headlights_on)

func set_headlights(enabled: bool) -> bool:
	headlights_on = enabled
	for light in get_headlights():
		if is_instance_valid(light):
			light.visible = headlights_on
	headlights_changed.emit(headlights_on)
	return headlights_on

func get_exit_position() -> Vector3:
	if not exit_point:
		_resolve_references()
	if exit_point and is_instance_valid(exit_point):
		return exit_point.global_position if is_inside_tree() else exit_point.position
	if is_inside_tree():
		return global_transform * exit_offset
	return position + transform.basis * exit_offset

func get_driver_seat_position() -> Vector3:
	if not driver_seat:
		_resolve_references()
	if driver_seat and is_instance_valid(driver_seat):
		return driver_seat.global_position if is_inside_tree() else driver_seat.position
	if is_inside_tree():
		return global_transform * seat_offset
	return position + transform.basis * seat_offset

# =========================================================================
# Control Inputs & 4WD Torque Distribution
# =========================================================================

func set_throttle_input(val: float) -> void:
	self.throttle_input = val

func set_steering_input(val: float) -> void:
	self.steer_input = val

func set_brake_input(val: float) -> void:
	self.brake_input = val

func apply_inputs(throttle: float, steer: float, brake_val: float) -> void:
	self.throttle_input = throttle
	self.steer_input = steer
	self.brake_input = brake_val

func _apply_control_values() -> void:
	if _wheels.is_empty():
		_resolve_wheels()

	var total_torque = _current_throttle * max_engine_force
	self.engine_force = total_torque

	# 4WD torque distribution between front and rear axles
	if four_wheel_drive:
		var front_total = total_torque * torque_balance_front_rear
		var rear_total = total_torque * (1.0 - torque_balance_front_rear)
		var fl_torque = front_total * 0.5
		var fr_torque = front_total * 0.5
		var rl_torque = rear_total * 0.5
		var rr_torque = rear_total * 0.5

		if is_instance_valid(wheel_fl): wheel_fl.engine_force = fl_torque
		if is_instance_valid(wheel_fr): wheel_fr.engine_force = fr_torque
		if is_instance_valid(wheel_rl): wheel_rl.engine_force = rl_torque
		if is_instance_valid(wheel_rr): wheel_rr.engine_force = rr_torque
	else:
		# Rear-wheel drive fallback
		var r_torque = total_torque * 0.5
		if is_instance_valid(wheel_fl): wheel_fl.engine_force = 0.0
		if is_instance_valid(wheel_fr): wheel_fr.engine_force = 0.0
		if is_instance_valid(wheel_rl): wheel_rl.engine_force = r_torque
		if is_instance_valid(wheel_rr): wheel_rr.engine_force = r_torque

	# Steering distribution
	self.steering = _current_steer_angle
	if is_instance_valid(wheel_fl) and wheel_fl.use_as_steering:
		wheel_fl.steering = _current_steer_angle
	if is_instance_valid(wheel_fr) and wheel_fr.use_as_steering:
		wheel_fr.steering = _current_steer_angle

	var rear_steer: float = 0.0
	if rear_wheel_counter_steer:
		rear_steer = -_current_steer_angle
	elif abs(rear_steer_ratio) > 0.001:
		rear_steer = _current_steer_angle * rear_steer_ratio

	if is_instance_valid(wheel_rl) and wheel_rl.use_as_steering:
		wheel_rl.steering = rear_steer
	if is_instance_valid(wheel_rr) and wheel_rr.use_as_steering:
		wheel_rr.steering = rear_steer

	# Braking distribution
	var total_brake = _current_brake * max_brake_force
	self.brake = total_brake
	for w in _wheels:
		if is_instance_valid(w):
			w.brake = total_brake

	# Dynamic linear & angular damping for brake stability
	if _current_brake > 0.01:
		linear_damp = _base_linear_damp + _current_brake * brake_damping
		angular_damp = _base_angular_damp + _current_brake * brake_damping
	elif abs(_current_throttle) < 0.01 and abs(linear_velocity.length()) > 0.1:
		linear_damp = _base_linear_damp + coasting_damping
		angular_damp = _base_angular_damp
	else:
		linear_damp = _base_linear_damp
		angular_damp = _base_angular_damp

func _unhandled_input(event: InputEvent) -> void:
	if not is_occupied() or not accept_player_input:
		return
	if event.is_action_pressed("interact"):
		dismount()
	elif event.is_action_pressed("toggle_gear"):
		toggle_headlights()

func _physics_process(delta: float) -> void:
	if is_occupied() and accept_player_input:
		_process_player_inputs(delta)

func _process_player_inputs(_delta: float) -> void:
	var forward = Input.get_axis("move_back", "move_forward")
	# move_left -> positive steering angle, move_right -> negative
	var steer = -Input.get_axis("move_left", "move_right")
	var brk = 1.0 if Input.is_action_pressed("brake") else 0.0

	self.throttle_input = forward
	self.steer_input = steer
	self.brake_input = brk

# =========================================================================
# Surface Physics, Planetary Gravity, & Roll Stabilization
# =========================================================================

func get_gravity_vector() -> Vector3:
	if gravity_override != Vector3.ZERO:
		return gravity_override
	var tree = get_tree() if is_inside_tree() else null
	if tree and tree.root:
		var sim_clock = tree.root.get_node_or_null("SimulationClock")
		var sim_time: float = sim_clock.sim_time_s if sim_clock and "sim_time_s" in sim_clock else 0.0
		var origin_svc = tree.root.get_node_or_null("OriginService")
		if origin_svc == null:
			origin_svc = tree.get_first_node_in_group("origin_service")
		var universe_pos: DVec3
		var pos = global_position if is_inside_tree() else position
		if origin_svc and origin_svc.has_method("local_to_universe"):
			var up = origin_svc.local_to_universe(pos)
			universe_pos = up.offset
		else:
			universe_pos = DVec3.from_vector3(pos)

		var grav_acc = GravityService.gravity_accel(universe_pos, sim_time)
		var grav_vec = grav_acc.to_vector3()
		if grav_vec.length() > 0.05:
			return grav_vec

	var def_g: float = ProjectSettings.get_setting("physics/3d/default_gravity", EARTH_GRAVITY_DEFAULT)
	return Vector3(0.0, -def_g, 0.0)

func calculate_stabilization_torque(current_up: Vector3, target_up: Vector3, ang_vel: Vector3) -> Vector3:
	var torque = Vector3.ZERO
	if roll_stabilization_enabled:
		var tilt_axis = current_up.cross(target_up)
		var tilt_angle = current_up.angle_to(target_up)
		if tilt_angle > 0.02 and tilt_axis.length_squared() > 1e-6:
			torque += tilt_axis.normalized() * (tilt_angle * roll_stabilization_strength * mass)
		torque -= ang_vel * (angular_damping_strength * mass)
	return torque

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_inside_tree():
		return

	# Roll & pitch stabilization
	if roll_stabilization_enabled:
		var current_up = global_transform.basis.y
		var grav_vec = get_gravity_vector()
		var target_up = -grav_vec.normalized() if grav_vec.length_squared() > 0.01 else Vector3.UP
		var stab_torque = calculate_stabilization_torque(current_up, target_up, state.angular_velocity)
		if stab_torque.length_squared() > 0.001:
			state.apply_torque(stab_torque)

	# Downforce for low-gravity surface tire adhesion
	if downforce_enabled:
		var speed = state.linear_velocity.length()
		if speed > 0.5:
			var down_dir = -global_transform.basis.y
			var df = down_dir * (speed * downforce_strength * mass * 0.1)
			state.apply_central_force(df)
