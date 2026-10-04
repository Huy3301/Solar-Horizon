extends RigidBody3D
class_name ShipFlightController

const FlightModel = preload("res://game/player/flight_model.gd")

## High-Fidelity Aerospace Exploration Orbiter Flight Controller (LEO & Entry Model).
## Supports orbital vacuum mechanics, Newtonian spherical gravity, Reaction Control System (RCS),
## supersonic/hypersonic entry aerodynamics, and main orbital maneuvering engines (OME).

signal flight_data_updated(telemetry: Dictionary)
signal landing_gear_toggled(is_down: bool)
signal landing_state_changed(is_landed: bool, status_message: String)
signal ship_crashed(reason: String)

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
@export var atmosphere_thickness: float = 12000.0  # Scaled 120km to 12km (at 1/10)

enum FlightModelMode { ASSISTED = 0, NEWTONIAN = 1 }
@export_group("Flight Systems")
@export var flight_model: FlightModelMode = FlightModelMode.ASSISTED

var current_throttle: float = 0.0
var target_throttle: float = 0.0
var landing_gear_deployed: bool = false
var brakes_engaged: bool = false
var is_landed: bool = false
var is_crashed: bool = false
var rcs_active: bool = false

var control_pitch: float = 0.0
var control_roll: float = 0.0
var control_yaw: float = 0.0
var control_vtol: float = 0.0

@onready var left_plume: MeshInstance3D = get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_L/LeftEnginePlume") if get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_L/LeftEnginePlume") else get_node_or_null("VisualModel/LeftEnginePlume")
@onready var right_plume: MeshInstance3D = get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_R/RightEnginePlume") if get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_R/RightEnginePlume") else get_node_or_null("VisualModel/RightEnginePlume")
@onready var gear_anim: AnimationPlayer = get_node_or_null("VisualModel/OrbiterModel/AnimationPlayer") if get_node_or_null("VisualModel/OrbiterModel/AnimationPlayer") else get_node_or_null("OrbiterModel/AnimationPlayer")
@onready var radar_altimeter_ray: RayCast3D = get_node_or_null("RadarAltimeter")
@onready var gear_front_ray: RayCast3D = get_node_or_null("GearFrontRay")
@onready var gear_left_ray: RayCast3D = get_node_or_null("GearLeftRay")
@onready var gear_right_ray: RayCast3D = get_node_or_null("GearRightRay")

var telemetry_data: Dictionary = {}
var sim_time: float = 0.0
var simulation_clock: Node = null

func _get_sim_clock() -> Node:
	if simulation_clock:
		return simulation_clock
	if is_inside_tree():
		return get_node_or_null("/root/SimulationClock")
	if Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).root:
		return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("SimulationClock")
	return null

func _get_universe_pos() -> DVec3:
	var tree = get_tree()
	if tree:
		var origin_svc = tree.root.get_node_or_null("OriginService") if tree.root else null
		if origin_svc == null:
			origin_svc = tree.get_first_node_in_group("origin_service")
		if origin_svc and origin_svc.has_method("local_to_universe"):
			var up = origin_svc.local_to_universe(global_position)
			return up.offset
	return DVec3.from_vector3(global_position)

func _ready() -> void:
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 0.0
	max_contacts_reported = 8
	contact_monitor = true
	_update_engine_plumes(0.0)

func _physics_process(delta: float) -> void:
	_handle_inputs(delta)
	_update_throttle(delta)
	
	var sim_clock = _get_sim_clock()
	sim_time = sim_clock.sim_time_s if sim_clock else 0.0
	
	if not is_inside_tree():
		telemetry_data["sim_time"] = sim_time
		return
	
	var ship_pos: DVec3 = _get_universe_pos()
	
	var dom_id = GravityService.dominant_body(ship_pos, sim_time)
	var dom_pos = GravityService.body_position(dom_id, sim_time)
	var dom_def = BodyRegistry.get_body(dom_id)
	
	var scale_cfg = GameScale.get_instance()
	var planet_radius = scale_cfg.scaled_radius(dom_def.radius_m) if dom_def else 637100.0
	
	var to_ship_d = ship_pos.sub(dom_pos)
	var r_dist = to_ship_d.length()
	var to_ship = to_ship_d.to_vector3()
	var planet_up = to_ship.normalized() if r_dist > 1.0 else Vector3.UP
	var altitude_asl = r_dist - planet_radius
	
	# Gravity from dominant body only (B-02 fix)
	var grav_acc = GravityService.gravity_accel(ship_pos, sim_time)
	var g_local = grav_acc.length()
	apply_central_force(grav_acc.to_vector3() * mass)
	
	var forward_dir: Vector3 = -global_transform.basis.z.normalized()
	var right_dir: Vector3 = global_transform.basis.x.normalized()
	var up_dir: Vector3 = global_transform.basis.y.normalized()
	
	var thrust_amount: float = 0.0 if is_crashed else current_throttle * max_main_thrust
	var thrust_force: Vector3 = forward_dir * thrust_amount
	apply_central_force(thrust_force)
	
	var non_grav_force = thrust_force
	
	if control_vtol > 0.01 and not is_crashed:
		rcs_active = true
		var vtol_thrust = up_dir * (control_vtol * max_rcs_thrust)
		apply_central_force(vtol_thrust)
		non_grav_force += vtol_thrust
	else:
		rcs_active = false
		
	var velocity: Vector3 = linear_velocity
	var speed: float = velocity.length()
	
	# Scale-height atmospheric aerodynamics (B-05 fix)
	var air_density: float = FlightModel.calculate_air_density(altitude_asl, dom_def, scale_cfg.radius_scale)
	var vel_dir: Vector3 = velocity.normalized() if speed > 0.1 else forward_dir
	var aero_data = FlightModel.calculate_aerodynamics(speed, air_density, wing_area, zero_lift_drag_cd0, landing_gear_deployed, vel_dir)
	var dynamic_pressure: float = aero_data["dynamic_pressure"]
	var drag_force: Vector3 = aero_data["drag_force"]
	apply_central_force(drag_force)
	non_grav_force += drag_force
	
	# Real AGL via radar altimeter and gear rays (B-04 fix)
	var gear_rays: Array = [gear_front_ray, gear_left_ray, gear_right_ray]
	var altitude_agl: float = FlightModel.calculate_agl(global_position, planet_up, altitude_asl, radar_altimeter_ray, gear_rays)
	
	# Attitude controls with inertia scaling (B-05 fix)
	_apply_attitude_controls(dynamic_pressure)
	_update_engine_plumes(current_throttle)
	
	# Collision-based landing evaluation (B-04 fix)
	_evaluate_surface_contact(planet_up, altitude_agl)
	
	var g_force_val = non_grav_force.length() / (mass * 9.81)
	_update_telemetry(altitude_asl, altitude_agl, speed, dynamic_pressure, air_density, g_local, g_force_val)

func _handle_inputs(delta: float) -> void:
	if is_crashed:
		control_pitch = 0.0
		control_roll = 0.0
		control_yaw = 0.0
		target_throttle = 0.0
		return
		
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

func _get_moments_of_inertia() -> Vector3:
	var I = inertia
	if I.x <= 0.0 or I.y <= 0.0 or I.z <= 0.0:
		# Box moment of inertia: Ix = m/12*(y^2+z^2), Iy = m/12*(x^2+z^2), Iz = m/12*(x^2+y^2)
		# Dimensions approx 3.6m x 2.2m x 14.2m
		I = Vector3(mass * 17.2, mass * 17.8, mass * 1.5)
	return I

func _apply_attitude_controls(q: float) -> void:
	if is_crashed:
		return
		
	var I = _get_moments_of_inertia()
	
	# Maximum angular acceleration authorities (rad/s^2)
	var max_accel = Vector3(
		(pitch_torque_max + rcs_rotational_torque) / I.x,
		(yaw_torque_max + rcs_rotational_torque) / I.y,
		(roll_torque_max + rcs_rotational_torque) / I.z
	)
	
	var inputs = Vector3(control_pitch, control_yaw, control_roll)
	var mode = FlightModel.Mode.ASSISTED if flight_model == FlightModelMode.ASSISTED else FlightModel.Mode.NEWTONIAN
	
	var total_torque = FlightModel.calculate_attitude_torque(
		inputs,
		I,
		max_accel,
		q,
		mode,
		angular_velocity,
		global_transform.basis
	)
	
	apply_torque(total_torque)

func _update_engine_plumes(throttle: float) -> void:
	if not left_plume or not right_plume:
		left_plume = get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_L/LeftEnginePlume") if get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_L/LeftEnginePlume") else get_node_or_null("VisualModel/LeftEnginePlume")
		right_plume = get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_R/RightEnginePlume") if get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_R/RightEnginePlume") else get_node_or_null("VisualModel/RightEnginePlume")
	if not left_plume or not right_plume:
		return
		
	if throttle > 0.01 and not is_crashed:
		left_plume.visible = true
		right_plume.visible = true
		var plume_len: float = clamp(throttle * 1.6, 0.2, 1.8)
		left_plume.scale = Vector3(throttle * 0.9, plume_len, throttle * 0.9)
		right_plume.scale = Vector3(throttle * 0.9, plume_len, throttle * 0.9)
	else:
		left_plume.visible = false
		right_plume.visible = false

func _evaluate_surface_contact(planet_up: Vector3, agl: float) -> void:
	var contact_count: int = get_contact_count()
	var gear_colliding: bool = (
		(gear_front_ray and gear_front_ray.is_colliding()) or
		(gear_left_ray and gear_left_ray.is_colliding()) or
		(gear_right_ray and gear_right_ray.is_colliding())
	)
	
	var ship_up: Vector3 = global_transform.basis.y.normalized()
	var landing_eval = FlightModel.evaluate_landing(
		contact_count,
		gear_colliding,
		linear_velocity,
		planet_up,
		ship_up,
		landing_gear_deployed
	)
	
	var state = landing_eval["state"]
	if state == FlightModel.LandingState.CRASH:
		if not is_crashed:
			is_crashed = true
			is_landed = false
			landing_state_changed.emit(false, landing_eval["message"])
			ship_crashed.emit(landing_eval["message"])
	elif state == FlightModel.LandingState.TOUCHDOWN:
		if not is_landed:
			is_landed = true
			landing_state_changed.emit(true, landing_eval["message"])
		if brakes_engaged:
			var brake_force: Vector3 = -linear_velocity.normalized() * min(linear_velocity.length() * mass * 5.0, 45000.0)
			apply_central_force(brake_force)
	elif state == FlightModel.LandingState.AIRBORNE:
		if is_landed and agl > 2.0:
			is_landed = false
			landing_state_changed.emit(false, "Vessel airborne.")

func toggle_landing_gear() -> void:
	landing_gear_deployed = not landing_gear_deployed
	if not gear_anim:
		gear_anim = get_node_or_null("VisualModel/OrbiterModel/AnimationPlayer") if get_node_or_null("VisualModel/OrbiterModel/AnimationPlayer") else get_node_or_null("OrbiterModel/AnimationPlayer")
	if gear_anim and gear_anim.has_animation("gear_deploy"):
		if landing_gear_deployed:
			gear_anim.play("gear_deploy")
		else:
			gear_anim.play_backwards("gear_deploy")
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

func _update_telemetry(alt_asl: float, alt_agl: float, speed: float, q: float, rho: float, g_local: float, g_force_val: float) -> void:
	var rot: Vector3 = global_transform.basis.get_euler()
	var pitch_deg: float = rad_to_deg(rot.x)
	var roll_deg: float = rad_to_deg(rot.z)
	var heading_deg: float = fmod(rad_to_deg(-rot.y) + 360.0, 360.0)
	var mach: float = speed / 340.29
	
	var sim_clock = _get_sim_clock()
	sim_time = sim_clock.sim_time_s if sim_clock else 0.0
	var ship_pos: DVec3 = _get_universe_pos()
	var dom_id = GravityService.dominant_body(ship_pos, sim_time)
	var dom_pos = GravityService.body_position(dom_id, sim_time)
	var to_ship_d = ship_pos.sub(dom_pos)
	var r_vec = to_ship_d.to_vector3()
	var planet_up = r_vec.normalized() if r_vec.length() > 1.0 else Vector3.UP
	
	var vspeed: float = linear_velocity.dot(planet_up)
	
	# Orbit elements
	var dom_def = BodyRegistry.get_body(dom_id)
	var mu = GameScale.get_instance().scaled_mu(dom_def.mu_m3_s2, dom_def.radius_m) if dom_def else OrbitalMechanics.DEFAULT_MU
	var radius = GameScale.get_instance().scaled_radius(dom_def.radius_m) if dom_def else OrbitalMechanics.EARTH_RADIUS
	var orbit = OrbitalMechanics.calculate_orbit(r_vec, linear_velocity, mu, radius)
	
	telemetry_data = {
		"sim_time": sim_time,
		"speed_ms": speed,
		"speed_kmh": speed * 3.6,
		"speed_knots": speed * 1.94384,
		"mach": mach,
		"altitude_asl_m": alt_asl,
		"altitude_asl_ft": alt_asl * 3.28084,
		"altitude_agl_m": alt_agl,
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
		"is_crashed": is_crashed,
		"vtol_active": control_vtol > 0.05 or rcs_active,
		"g_local": g_local,
		"g_force_val": g_force_val,
		"ap_km": orbit.apoapsis_alt / 1000.0,
		"pe_km": orbit.periapsis_alt / 1000.0,
		"eccentricity": orbit.eccentricity,
		"period_min": orbit.period_seconds / 60.0,
		"inclination_deg": rad_to_deg(orbit.inclination_rad)
	}
	
	flight_data_updated.emit(telemetry_data)
