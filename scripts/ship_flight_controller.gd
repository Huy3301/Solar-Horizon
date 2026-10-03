extends RigidBody3D
class_name ShipFlightController

## High-Fidelity Aerospace Exploration Orbiter Flight Controller (LEO & Entry Model).
## Supports orbital vacuum mechanics, Newtonian spherical gravity, Reaction Control System (RCS),
## supersonic/hypersonic entry aerodynamics, and main orbital maneuvering engines (OME).

signal flight_data_updated(telemetry: Dictionary)
signal landing_gear_toggled(is_down: bool)
signal landing_state_changed(is_landed: bool, status_message: String)

@export_group("Orbital Propulsion")
@export var max_main_thrust: float = 450000.0  # 450 kN twin rocket engines
@export var max_rcs_thrust: float = 24000.0   # 24 kN vacuum RCS translation
@export var throttle_spool_rate: float = 0.65  # Seconds 0% to 100%
@export var delta_v_total: float = 4250.0      # m/s available delta-V

@export_group("Attitude Control Authority")
@export var pitch_torque_max: float = 65000.0   # Nm pitch authority
@export var roll_torque_max: float = 48000.0    # Nm roll authority
@export var yaw_torque_max: float = 38000.0     # Nm yaw authority
@export var rcs_rotational_torque: float = 42000.0 # Nm pure vacuum RCS

@export_group("Aerodynamics & Reentry")
@export var wing_area: float = 42.0             # m^2 (swept delta lifting body)
@export var lift_coefficient_slope: float = 3.8 # dCl/d(alpha) in rad^-1
@export var zero_lift_drag_cd0: float = 0.018   # Hypersonic parasitic drag
@export var induced_drag_k: float = 0.12        # Induced drag factor
@export var entry_heat_scaling: float = 1.0

@export_group("Planetary Environment")
@export var earth_center_pos: Vector3 = Vector3(0, -50000, 0)
@export var earth_surface_radius: float = 50000.0 # Scaled simulation radius
@export var sea_level_gravity: float = 9.81
@export var atmosphere_thickness: float = 1200.0  # Atmosphere boundary layer

var current_throttle: float = 0.0
var target_throttle: float = 0.0
var landing_gear_deployed: bool = false
var brakes_engaged: bool = false
var is_landed: bool = false
var rcs_active: bool = false

var control_pitch: float = 0.0
var control_roll: float = 0.0
var control_yaw: float = 0.0
var control_vtol: float = 0.0

@onready var left_plume: MeshInstance3D = get_node_or_null("VisualModel/LeftEnginePlume")
@onready var right_plume: MeshInstance3D = get_node_or_null("VisualModel/RightEnginePlume")
@onready var radar_altimeter_ray: RayCast3D = get_node_or_null("RadarAltimeter")
@onready var gear_front_ray: RayCast3D = get_node_or_null("GearFrontRay")
@onready var gear_left_ray: RayCast3D = get_node_or_null("GearLeftRay")
@onready var gear_right_ray: RayCast3D = get_node_or_null("GearRightRay")

var telemetry_data: Dictionary = {}

func _ready() -> void:
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 0.15
	max_contacts_reported = 4
	contact_monitor = true
	_update_engine_plumes(0.0)

func _physics_process(delta: float) -> void:
	_handle_inputs(delta)
	_update_throttle(delta)
	
	var to_ship: Vector3 = global_position - earth_center_pos
	var r_dist: float = to_ship.length()
	var planet_up: Vector3 = to_ship / max(1.0, r_dist)
	var altitude_asl: float = r_dist - earth_surface_radius
	
	var g_local: float = sea_level_gravity * pow(earth_surface_radius / max(1.0, r_dist), 2.0)
	var gravity_force: Vector3 = -planet_up * (mass * g_local)
	apply_central_force(gravity_force)
	
	var forward_dir: Vector3 = -global_transform.basis.z.normalized()
	var right_dir: Vector3 = global_transform.basis.x.normalized()
	var up_dir: Vector3 = global_transform.basis.y.normalized()
	
	var thrust_amount: float = current_throttle * max_main_thrust
	var thrust_force: Vector3 = forward_dir * thrust_amount
	apply_central_force(thrust_force)
	
	if control_vtol > 0.01:
		rcs_active = true
		apply_central_force(up_dir * (control_vtol * max_rcs_thrust))
	else:
		rcs_active = false
		
	var velocity: Vector3 = linear_velocity
	var speed: float = velocity.length()
	var dynamic_pressure: float = 0.0
	var air_density: float = 0.0
	
	if altitude_asl < atmosphere_thickness:
		var entry_h_norm: float = clamp(altitude_asl / atmosphere_thickness, 0.0, 1.0)
		air_density = 1.225 * exp(-entry_h_norm * 7.5)
		dynamic_pressure = 0.5 * air_density * speed * speed
		
		var vel_dir: Vector3 = velocity.normalized()
		var cd: float = zero_lift_drag_cd0 + (0.04 if landing_gear_deployed else 0.0)
		var drag_force: Vector3 = -vel_dir * (cd * dynamic_pressure * wing_area)
		apply_central_force(drag_force)
	
	_apply_attitude_controls(dynamic_pressure)
	_update_engine_plumes(current_throttle)
	_evaluate_surface_contact(altitude_asl, speed)
	_update_telemetry(altitude_asl, speed, dynamic_pressure, air_density, g_local)

func _handle_inputs(delta: float) -> void:
	control_pitch = Input.get_axis("pitch_down", "pitch_up")
	control_roll = Input.get_axis("roll_right", "roll_left")
	control_yaw = Input.get_axis("yaw_right", "yaw_left")
	
	if Input.is_action_pressed("throttle_up"):
		target_throttle = clamp(target_throttle + 0.45 * delta, 0.0, 1.0)
	elif Input.is_action_pressed("throttle_down"):
		target_throttle = clamp(target_throttle - 0.45 * delta, 0.0, 1.0)
		
	if Input.is_action_just_pressed("toggle_gear"):
		toggle_landing_gear()
		
	brakes_engaged = Input.is_action_pressed("brake")
	control_vtol = Input.get_action_strength("vtol_up")

func _update_throttle(delta: float) -> void:
	current_throttle = move_toward(current_throttle, target_throttle, (1.0 / throttle_spool_rate) * delta)

func _apply_attitude_controls(q: float) -> void:
	var aero_blend: float = clamp(q / 8000.0, 0.0, 1.0)
	var p_torque: float = (pitch_torque_max * aero_blend + rcs_rotational_torque) * control_pitch
	var r_torque: float = (roll_torque_max * aero_blend + rcs_rotational_torque) * control_roll
	var y_torque: float = (yaw_torque_max * aero_blend + rcs_rotational_torque) * control_yaw
	
	var total_torque: Vector3 = (
		global_transform.basis.x * p_torque +
		-global_transform.basis.z * r_torque +
		global_transform.basis.y * y_torque
	)
	apply_torque(total_torque)

func _update_engine_plumes(throttle: float) -> void:
	if not left_plume or not right_plume:
		return
		
	if throttle > 0.01:
		left_plume.visible = true
		right_plume.visible = true
		var plume_len: float = clamp(throttle * 1.6, 0.2, 1.8)
		left_plume.scale = Vector3(throttle * 0.9, plume_len, throttle * 0.9)
		right_plume.scale = Vector3(throttle * 0.9, plume_len, throttle * 0.9)
	else:
		left_plume.visible = false
		right_plume.visible = false

func _evaluate_surface_contact(altitude: float, speed: float) -> void:
	var on_surface: bool = false
	if gear_front_ray and gear_front_ray.is_colliding():
		on_surface = true
	elif altitude <= 1.5:
		on_surface = true
		
	if on_surface:
		if not is_landed:
			is_landed = true
			if speed < 40.0:
				landing_state_changed.emit(true, "Touchdown confirmed. Ship anchored at base.")
			else:
				landing_state_changed.emit(false, "Surface touchdown at high speed.")
		if brakes_engaged:
			var brake_force: Vector3 = -linear_velocity.normalized() * 35000.0
			apply_central_force(brake_force)
	else:
		if is_landed:
			is_landed = false
			landing_state_changed.emit(false, "Vessel orbital departure.")

func toggle_landing_gear() -> void:
	landing_gear_deployed = not landing_gear_deployed
	landing_gear_toggled.emit(landing_gear_deployed)

func set_direct_throttle(val: float) -> void:
	target_throttle = clamp(val, 0.0, 1.0)

func set_control_pitch(val: float) -> void:
	control_pitch = clamp(val, -1.0, 1.0)

func set_control_roll(val: float) -> void:
	control_roll = clamp(val, -1.0, 1.0)

func set_control_yaw(val: float) -> void:
	control_yaw = clamp(val, -1.0, 1.0)

func set_vtol_thrust(val: float) -> void:
	control_vtol = clamp(val, 0.0, 1.0)

func _update_telemetry(alt_asl: float, speed: float, q: float, rho: float, g_local: float) -> void:
	var rot: Vector3 = global_transform.basis.get_euler()
	var pitch_deg: float = rad_to_deg(rot.x)
	var roll_deg: float = rad_to_deg(rot.z)
	var heading_deg: float = fmod(rad_to_deg(-rot.y) + 360.0, 360.0)
	var vspeed: float = linear_velocity.dot((global_position - earth_center_pos).normalized())
	var mach: float = speed / 340.29
	
	telemetry_data = {
		"speed_ms": speed,
		"speed_kmh": speed * 3.6,
		"speed_knots": speed * 1.94384,
		"mach": mach,
		"altitude_asl_m": alt_asl,
		"altitude_asl_ft": alt_asl * 3.28084,
		"altitude_agl_m": alt_asl,
		"vspeed_ms": vspeed,
		"pitch_deg": pitch_deg,
		"roll_deg": roll_deg,
		"heading_deg": heading_deg,
		"throttle_pct": current_throttle * 100.0,
		"dynamic_pressure_pa": q,
		"air_density": rho,
		"gear_down": landing_gear_deployed,
		"brakes": brakes_engaged,
		"is_landed": is_landed,
		"vtol_active": control_vtol > 0.05 or rcs_active,
		"g_local": g_local
	}
	
	flight_data_updated.emit(telemetry_data)
