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

enum FlightModelMode { ASSISTED = 0, NEWTONIAN = 1, ARCADE = 2 }
@export_group("Flight Systems")
## ARCADE = No Man's Sky style (default): point the nose, set throttle, the ship hovers when idle.
## ASSISTED / NEWTONIAN keep the full orbital-mechanics model for sim players.
@export var flight_model: FlightModelMode = FlightModelMode.ARCADE

@export_group("Arcade Flight (NMS style)")
@export var arcade_cruise_atmo: float = 220.0       # m/s
@export var arcade_boost_atmo: float = 700.0        # m/s
@export var arcade_cruise_space: float = 1200.0     # m/s
@export var arcade_boost_space: float = 3500.0      # m/s
@export var arcade_accel_atmo: float = 60.0         # m/s^2
@export var arcade_accel_space: float = 150.0       # m/s^2
@export var arcade_boost_accel_mult: float = 2.5
@export var arcade_vtol_speed: float = 35.0         # m/s vertical (Space / Ctrl)
@export var arcade_takeoff_climb: float = 28.0      # m/s auto-climb when throttle is applied near the ground
@export var arcade_velocity_response_s: float = 0.35
@export var arcade_pitch_rate: float = 1.3          # rad/s
@export var arcade_yaw_rate: float = 0.9
@export var arcade_roll_rate: float = 1.7
@export var arcade_rate_response_s: float = 0.12
@export var arcade_autolevel_gain: float = 1.6
@export var pulse_drive_accel: float = 3500.0       # m/s^2
@export var pulse_drive_decel: float = 2500.0       # m/s^2 (used for the approach-braking curve)
@export var pulse_drive_arrival_alt_m: float = 55000.0
@export var crash_recovery_s: float = 4.0
## Ground starts need the gear down and the player's keys ignored while on foot
@export var input_enabled: bool = true

var current_throttle: float = 0.0
var target_throttle: float = 0.0
var landing_gear_deployed: bool = false
var brakes_engaged: bool = false
var is_landed: bool = false
var is_crashed: bool = false
var rcs_active: bool = false

var flight_regime: int = FlightModel.FlightRegime.LOW_ORBIT
var current_speed_limit: float = FlightModel.SPEED_LIMIT_LOW_ORBIT
var pulse_drive_active: bool = false
var is_boosting: bool = false
var arcade_thrust_fraction: float = 0.0
var arcade_vtol_down: float = 0.0
var _crash_timer: float = 0.0
var _pulse_target_speed: float = 0.0

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
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	continuous_cd = true
	max_contacts_reported = 8
	contact_monitor = true
	_update_engine_plumes(0.0)

func _physics_process(delta: float) -> void:
	if is_crashed:
		_crash_timer += delta
		if _crash_timer >= crash_recovery_s:
			_crash_timer = 0.0
			is_crashed = false
			target_throttle = 0.0
			current_throttle = 0.0
			landing_state_changed.emit(false, "Emergency systems restored.")
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
	
	# Determine Flight Regime (Atmosphere, Low Earth Orbit, Deep Space, Pulse Drive)
	flight_regime = FlightModel.determine_flight_regime(altitude_asl, pulse_drive_active)
	if pulse_drive_active and flight_model == FlightModelMode.ARCADE:
		flight_regime = FlightModel.FlightRegime.PULSE_DRIVE  # arcade pulse drive works anywhere clear of bodies
	
	# Proximity safety check for Pulse Drive (auto-disengage within 50 km or atmosphere)
	if pulse_drive_active and flight_model != FlightModelMode.ARCADE:
		if not FlightModel.can_engage_pulse_drive(altitude_asl, altitude_asl):
			disengage_pulse_drive("Proximity safety: Disengaged pulse drive near planetary body.")
	
	var forward_dir: Vector3 = -global_transform.basis.z.normalized()
	var up_dir: Vector3 = global_transform.basis.y.normalized()
	var velocity: Vector3 = linear_velocity
	var speed: float = velocity.length()
	var non_grav_force: Vector3 = Vector3.ZERO
	var g_local: float = 0.0
	var air_density: float = FlightModel.calculate_air_density(altitude_asl, dom_def, scale_cfg.radius_scale)
	var dynamic_pressure: float = 0.5 * air_density * speed * speed
	var altitude_agl: float = altitude_asl

	if flight_model == FlightModelMode.ARCADE:
		var arc: Dictionary = _process_arcade(delta, ship_pos, sim_time, dom_id, dom_def, planet_up, altitude_asl, planet_radius)
		non_grav_force = arc["force"]
		g_local = arc["g_local"]
		altitude_agl = arc["agl"]
	else:
		# Gravity from dominant body only (B-02 fix)
		var grav_acc = GravityService.gravity_accel(ship_pos, sim_time)
		g_local = grav_acc.length()
		apply_central_force(grav_acc.to_vector3() * mass)
	
		var right_dir: Vector3 = global_transform.basis.x.normalized()
	
		var thrust_amount: float = 0.0 if is_crashed else current_throttle * max_main_thrust
		if pulse_drive_active and not is_crashed:
			thrust_amount = max_main_thrust * 5.0 # Sub-light cruise acceleration
		var thrust_force: Vector3 = forward_dir * thrust_amount
		apply_central_force(thrust_force)
	
		non_grav_force = thrust_force
	
		if control_vtol > 0.01 and not is_crashed:
			rcs_active = true
			var vtol_thrust = up_dir * (control_vtol * max_rcs_thrust)
			apply_central_force(vtol_thrust)
			non_grav_force += vtol_thrust
		else:
			rcs_active = false
		
	
		# Tiered speed regulation per regime (No Man's Sky flight speed limits)
		current_speed_limit = FlightModel.get_regime_speed_limit(flight_regime, is_boosting)
		if flight_model == FlightModelMode.ASSISTED and not is_crashed:
			if speed > current_speed_limit:
				var excess_speed = speed - current_speed_limit
				var damp_force = -velocity.normalized() * (excess_speed * mass * 2.5)
				apply_central_force(damp_force)
				non_grav_force += damp_force
	
		# Scale-height atmospheric aerodynamics (B-05 fix)
		air_density = FlightModel.calculate_air_density(altitude_asl, dom_def, scale_cfg.radius_scale)
		var vel_dir: Vector3 = velocity.normalized() if speed > 0.1 else forward_dir
		var aero_data = FlightModel.calculate_aerodynamics(speed, air_density, wing_area, zero_lift_drag_cd0, landing_gear_deployed, vel_dir)
		dynamic_pressure = aero_data["dynamic_pressure"]
		var drag_force: Vector3 = aero_data["drag_force"]
		apply_central_force(drag_force)
		non_grav_force += drag_force
	

	# Real AGL via radar altimeter and gear rays (B-04 fix)
	var gear_rays: Array = [gear_front_ray, gear_left_ray, gear_right_ray]
	if flight_model != FlightModelMode.ARCADE:
		altitude_agl = FlightModel.calculate_agl(global_position, planet_up, altitude_asl, radar_altimeter_ray, gear_rays)
	
	# Attitude controls with inertia scaling (B-05 fix)
	if flight_model != FlightModelMode.ARCADE:
		_apply_attitude_controls(dynamic_pressure)
	_update_engine_plumes(1.0 if pulse_drive_active else (arcade_thrust_fraction if flight_model == FlightModelMode.ARCADE else current_throttle))
	
	# Collision-based landing evaluation (B-04 fix)
	_evaluate_surface_contact(planet_up, altitude_agl)
	
	var g_force_val = non_grav_force.length() / (mass * 9.81)
	_update_telemetry(altitude_asl, altitude_agl, speed, dynamic_pressure, air_density, g_local, g_force_val)

func _handle_inputs(delta: float) -> void:
	if not input_enabled:
		control_pitch = 0.0
		control_roll = 0.0
		control_yaw = 0.0
		control_vtol = 0.0
		is_boosting = false
		target_throttle = 0.0 if flight_model == FlightModelMode.ARCADE else target_throttle
		return
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
	control_vtol = Input.get_action_strength("vtol_up") - Input.get_action_strength("vtol_down") * 0.0
	arcade_vtol_down = Input.get_action_strength("vtol_down")
	is_boosting = Input.is_action_pressed("boost")
	
	if Input.is_action_just_pressed("pulse_drive"):
		toggle_pulse_drive()

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

# ---------------------------------------------------------------------------------------------
# ARCADE (No Man's Sky style) flight
# ---------------------------------------------------------------------------------------------

func _nearest_body_surface_distance(ship_pos: DVec3, t: float) -> float:
	var best: float = 1e30
	var scale_cfg = GameScale.get_instance()
	for id in BodyRegistry.all_ids():
		var def = BodyRegistry.get_body(id)
		if def == null:
			continue
		var d: float = ship_pos.sub(GravityService.body_position(id, t)).length() - scale_cfg.scaled_radius(def.radius_m)
		best = minf(best, d)
	return best

func _arcade_agl(dom_id: StringName, planet_up: Vector3, altitude_asl: float) -> float:
	var terrain_h: float = BodyFrames.terrain_height_m(dom_id, planet_up)
	return maxf(0.0, altitude_asl - terrain_h)

func _process_arcade(delta: float, ship_pos: DVec3, t: float, dom_id: StringName, dom_def, planet_up: Vector3, altitude_asl: float, _planet_radius: float) -> Dictionary:
	var g_vec: Vector3 = GravityService.gravity_accel(ship_pos, t).to_vector3()
	var basis_now: Basis = global_transform.basis
	var forward: Vector3 = -basis_now.z.normalized()
	var v: Vector3 = linear_velocity
	var agl: float = _arcade_agl(dom_id, planet_up, altitude_asl)
	var landed_like: bool = is_landed or agl < 3.0

	# --- environment-dependent speed envelope (smooth between atmosphere and space)
	var space_blend: float = clampf((altitude_asl - 15000.0) / 35000.0, 0.0, 1.0)
	var cruise: float = lerpf(arcade_cruise_atmo, arcade_cruise_space, space_blend)
	var boost_speed: float = lerpf(arcade_boost_atmo, arcade_boost_space, space_blend)
	var accel: float = lerpf(arcade_accel_atmo, arcade_accel_space, space_blend)
	var boosting: bool = is_boosting and not is_crashed and not pulse_drive_active
	var max_speed: float = boost_speed if boosting else cruise
	var thr: float = maxf(current_throttle, 0.7) if boosting else current_throttle
	var a_max: float = accel * (arcade_boost_accel_mult if boosting else 1.0)

	var v_des: Vector3 = forward * (thr * max_speed)
	current_speed_limit = max_speed
	var extra_lift: Vector3 = Vector3.ZERO
	var g_mag: float = g_vec.length()

	if not is_crashed:
		var takeoff_phase: bool = (landed_like or agl < 14.0) and thr > 0.03 and not pulse_drive_active
		if takeoff_phase:
			# Vertical lift-off first (like NMS), forward speed fades in as the ship clears the ground
			var clear: float = clampf((agl - 2.0) / 12.0, 0.0, 1.0)
			v_des = planet_up * arcade_takeoff_climb + forward * (thr * max_speed) * lerpf(0.05, 1.0, clear)
			if v.dot(planet_up) < arcade_takeoff_climb:
				extra_lift = planet_up * maxf(g_mag * 1.5, 14.0)   # guaranteed lift beyond gravity
		if control_vtol > 0.01:
			v_des += planet_up * (control_vtol * arcade_vtol_speed)
			if landed_like:
				extra_lift = planet_up * maxf(g_mag * 1.5, 14.0)
		if arcade_vtol_down > 0.01:
			v_des -= planet_up * (arcade_vtol_down * arcade_vtol_speed)
		# Landing assist: cap the sink rate as the ground approaches
		var v_up_des: float = v_des.dot(planet_up)
		var max_sink: float = clampf(agl * 0.35, 3.0, 80.0)
		if v_up_des < -max_sink:
			v_des += planet_up * (-max_sink - v_up_des)
	else:
		v_des = Vector3.ZERO

	# --- pulse drive (intra-system cruise) with approach braking
	if pulse_drive_active and not is_crashed:
		# Brake only for bodies AHEAD of us (we are leaving the one behind us); bail out if skimming any body.
		var ahead_room: float = 1e30
		var nearest_any: float = 1e30
		var scale_cfg2 = GameScale.get_instance()
		for id in BodyRegistry.all_ids():
			var bdef = BodyRegistry.get_body(id)
			if bdef == null:
				continue
			var to_body: DVec3 = GravityService.body_position(id, t).sub(ship_pos)
			var dist_c: float = to_body.length()
			var dist_s: float = dist_c - scale_cfg2.scaled_radius(bdef.radius_m)
			nearest_any = minf(nearest_any, dist_s)
			if dist_c > 1.0 and to_body.to_vector3().normalized().dot(forward) > 0.25:
				ahead_room = minf(ahead_room, dist_s - pulse_drive_arrival_alt_m)
				if OS.has_environment("SH_DEBUG") and Engine.get_physics_frames() % 30 == 0 and str(id) == "Earth":
					print("[pulse] ahead body=", id, " dist_surface_km=", snappedf(dist_s / 1000.0, 1.0), " cos=", snappedf(to_body.to_vector3().normalized().dot(forward), 0.01), " fwd.up=", snappedf(forward.dot(planet_up), 0.01), " alt=", snappedf(altitude_asl, 1.0), " vel.up=", snappedf(linear_velocity.normalized().dot(planet_up), 0.01))
		var cap: float = FlightModel.SPEED_LIMIT_PULSE_DRIVE
		if ahead_room < 1e29:
			cap = minf(cap, sqrt(2.0 * pulse_drive_decel * maxf(0.0, ahead_room)))
		_pulse_target_speed = move_toward(_pulse_target_speed, cap, (pulse_drive_accel if cap > _pulse_target_speed else pulse_drive_decel * 1.5) * delta)
		if nearest_any < 20000.0:
			disengage_pulse_drive("Proximity safety: pulse drive disengaged.")
		elif cap < 300.0 and _pulse_target_speed < 400.0:
			disengage_pulse_drive("Arrival: pulse drive disengaged.")
		v_des = forward * _pulse_target_speed
		a_max = pulse_drive_accel
		current_speed_limit = FlightModel.SPEED_LIMIT_PULSE_DRIVE
	else:
		_pulse_target_speed = move_toward(_pulse_target_speed, 0.0, pulse_drive_decel * delta)

	# --- velocity targeting (frame-rate independent)
	var a_cmd: Vector3 = (v_des - v) / maxf(arcade_velocity_response_s, delta)
	if a_cmd.length() > a_max:
		a_cmd = a_cmd.normalized() * a_max
	var thrust_force: Vector3 = a_cmd * mass + extra_lift * mass
	apply_central_force(thrust_force)
	arcade_thrust_fraction = clampf(a_cmd.length() / maxf(a_max, 1.0), 0.0, 1.0) if not is_crashed else 0.0
	if pulse_drive_active:
		arcade_thrust_fraction = 1.0

	# Gravity only matters when resting on / falling onto a surface; otherwise the ship hovers (grav-lift).
	if is_landed or is_crashed or (agl < 1.5 and v_des.length() < 1.0):
		apply_central_force(g_vec * mass)

	# --- direct angular-rate control with auto-level in atmosphere
	var local_target: Vector3 = Vector3(
		control_pitch * arcade_pitch_rate,
		control_yaw * arcade_yaw_rate,
		-control_roll * arcade_roll_rate)
	if is_crashed:
		local_target = Vector3.ZERO
	elif abs(control_roll) < 0.05 and altitude_asl < 40000.0 and not landed_like:
		var bank: float = basis_now.x.normalized().dot(planet_up)  # + when the right wing is high
		local_target.z += -arcade_autolevel_gain * bank
	var w_target: Vector3 = basis_now * local_target
	angular_velocity = angular_velocity.lerp(w_target, 1.0 - exp(-delta / maxf(arcade_rate_response_s, 0.001)))

	return {"force": thrust_force, "g_local": g_vec.length(), "agl": agl}

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
	# Attitude relative to the local horizon (world axes are not "up" once the planet is tilted)
	var pitch_deg: float = 0.0
	var roll_deg: float = 0.0
	var heading_deg: float = 0.0
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
	var fwd: Vector3 = -global_transform.basis.z.normalized()
	var rgt: Vector3 = global_transform.basis.x.normalized()
	var pole: Vector3 = BodyFrames.get_basis(dom_id) * Vector3.UP
	var north_t: Vector3 = pole - planet_up * pole.dot(planet_up)
	north_t = north_t.normalized() if north_t.length() > 1e-4 else Vector3.FORWARD
	var east_t: Vector3 = north_t.cross(planet_up).normalized()
	pitch_deg = rad_to_deg(asin(clampf(fwd.dot(planet_up), -1.0, 1.0)))
	roll_deg = rad_to_deg(asin(clampf(-rgt.dot(planet_up), -1.0, 1.0)))
	heading_deg = fposmod(rad_to_deg(atan2(fwd.dot(east_t), fwd.dot(north_t))), 360.0)
	
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
		"inclination_deg": rad_to_deg(orbit.inclination_rad),
		"flight_regime": FlightModel.get_regime_name(flight_regime),
		"flight_regime_id": flight_regime,
		"speed_limit_ms": current_speed_limit,
		"pulse_drive_active": pulse_drive_active,
		"pulse_drive_available": FlightModel.can_engage_pulse_drive(alt_asl, alt_asl)
	}
	
	flight_data_updated.emit(telemetry_data)

func toggle_pulse_drive() -> bool:
	if pulse_drive_active:
		disengage_pulse_drive("Pulse drive disengaged by pilot.")
		return false
	else:
		return engage_pulse_drive()

func engage_pulse_drive() -> bool:
	var ship_pos: DVec3 = _get_universe_pos()
	var dom_id = GravityService.dominant_body(ship_pos, sim_time)
	var dom_pos = GravityService.body_position(dom_id, sim_time)
	var dom_def = BodyRegistry.get_body(dom_id)
	var planet_radius = GameScale.get_instance().scaled_radius(dom_def.radius_m) if dom_def else 637100.0
	var alt_asl = ship_pos.sub(dom_pos).length() - planet_radius
	
	var nearest_d: float = _nearest_body_surface_distance(ship_pos, sim_time) if flight_model == FlightModelMode.ARCADE else alt_asl
	if not FlightModel.can_engage_pulse_drive(alt_asl, nearest_d):
		var audio_mgr = get_node_or_null("/root/AudioManager")
		if audio_mgr and audio_mgr.has_method("play_alert"):
			audio_mgr.play_alert("terrain_warning")
		return false
		
	pulse_drive_active = true
	_pulse_target_speed = maxf(linear_velocity.length(), 0.0)
	var audio_mgr2 = get_node_or_null("/root/AudioManager")
	if audio_mgr2 and audio_mgr2.has_method("play_alert"):
		audio_mgr2.play_alert("pulse_engage")
	return true

func disengage_pulse_drive(reason: String = "") -> void:
	if OS.has_environment("SH_DEBUG"): print("[pulse] disengage: ", reason, " speed=", linear_velocity.length(), " target=", _pulse_target_speed)
	if pulse_drive_active:
		pulse_drive_active = false
		var audio_mgr = get_node_or_null("/root/AudioManager")
		if audio_mgr and audio_mgr.has_method("play_alert"):
			audio_mgr.play_alert("overspeed")
