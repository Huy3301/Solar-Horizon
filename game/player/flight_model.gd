class_name FlightModel extends RefCounted

## Dual-tier flight mechanics and atmospheric aerodynamics model.
## Supports Assisted (fly-by-wire auto-damping) and Newtonian (pure vacuum/inertial) modes.
## Provides scale-height barometric atmosphere, inertia-scaled torques, collision landing evaluation, and AGL calculation.

enum Mode {
	ASSISTED = 0,
	NEWTONIAN = 1
}

enum LandingState {
	AIRBORNE = 0,
	TOUCHDOWN = 1,
	CRASH = 2
}

const TOUCHDOWN_MAX_VSPEED: float = 10.0 # m/s vertical descent limit
const TOUCHDOWN_MAX_HSPEED: float = 15.0 # m/s horizontal touchdown limit
const TOUCHDOWN_MAX_TILT_DEG: float = 25.0 # degrees max tilt from planet normal
const SEA_LEVEL_DENSITY: float = 1.225 # kg/m^3
const DEFAULT_SCALE_HEIGHT_M: float = 850.0 # 1:10 scaled Earth scale height (8500m * 0.1)

## Computes barometric scale-height air density: rho = rho0 * exp(-h / H)
static func calculate_air_density(altitude_asl: float, body_def: CelestialBodyDef, radius_scale: float = 0.1) -> float:
	if body_def == null or not body_def.has_atmosphere:
		return 0.0
		
	var scale_height: float = DEFAULT_SCALE_HEIGHT_M
	if body_def.scale_height_m > 0.0:
		scale_height = body_def.scale_height_m * radius_scale
		
	if scale_height <= 0.0:
		return 0.0
		
	var rho0 = SEA_LEVEL_DENSITY
	if body_def.surface_pressure_pa > 0.0:
		rho0 = body_def.surface_pressure_pa * 1.225 / 101325.0
		
	if altitude_asl < 0.0:
		return rho0
		
	# Cutoff at 15 scale heights (virtually zero density)
	if altitude_asl > scale_height * 15.0:
		return 0.0
		
	return rho0 * exp(-altitude_asl / scale_height)

## Computes aerodynamic drag and dynamic pressure
static func calculate_aerodynamics(speed: float, air_density: float, wing_area: float, cd0: float, gear_down: bool, vel_dir: Vector3) -> Dictionary:
	var q: float = 0.5 * air_density * speed * speed
	var cd: float = cd0 + (0.04 if gear_down else 0.0)
	var drag_mag: float = cd * q * wing_area
	var drag_force: Vector3 = -vel_dir * drag_mag
	return {
		"dynamic_pressure": q,
		"drag_force": drag_force,
		"drag_magnitude": drag_mag
	}

## Computes attitude torque scaled by moments of inertia
## inputs: Vector3(pitch, yaw, roll) normalized [-1, 1]
## moments_of_inertia: Vector3(Ix, Iy, Iz)
## max_angular_accel: Vector3(alpha_pitch, alpha_yaw, alpha_roll) rad/s^2
static func calculate_attitude_torque(
	inputs: Vector3,
	moments_of_inertia: Vector3,
	max_angular_accel: Vector3,
	dynamic_pressure: float,
	mode: int,
	current_angular_vel_world: Vector3,
	ship_basis: Basis
) -> Vector3:
	var aero_blend: float = clamp(dynamic_pressure / 8000.0, 0.0, 1.0)
	
	# Command angular accelerations
	var p_accel = inputs.x * max_angular_accel.x * (1.0 + aero_blend * 0.5)
	var y_accel = inputs.y * max_angular_accel.y * (1.0 + aero_blend * 0.5)
	var r_accel = inputs.z * max_angular_accel.z * (1.0 + aero_blend * 0.5)
	
	# Torque = I * alpha (in local coordinates)
	var tau_local = Vector3(
		moments_of_inertia.x * p_accel,
		moments_of_inertia.y * y_accel,
		-moments_of_inertia.z * r_accel # roll around -Z
	)
	
	# Assisted fly-by-wire damping when inputs are near neutral
	if mode == Mode.ASSISTED:
		var local_ang_vel = ship_basis.inverse() * current_angular_vel_world
		var damp_gain = 2.5
		if abs(inputs.x) < 0.05:
			tau_local.x -= moments_of_inertia.x * local_ang_vel.x * damp_gain
		if abs(inputs.y) < 0.05:
			tau_local.y -= moments_of_inertia.y * local_ang_vel.y * damp_gain
		if abs(inputs.z) < 0.05:
			tau_local.z -= moments_of_inertia.z * local_ang_vel.z * damp_gain
			
	return ship_basis * tau_local

## Evaluates contact / touchdown status against structural speed and attitude limits
static func evaluate_landing(
	contact_count: int,
	gear_rays_colliding: bool,
	linear_velocity: Vector3,
	planet_up: Vector3,
	ship_up: Vector3,
	gear_deployed: bool,
	max_vspeed: float = TOUCHDOWN_MAX_VSPEED,
	max_hspeed: float = TOUCHDOWN_MAX_HSPEED,
	max_tilt_deg: float = TOUCHDOWN_MAX_TILT_DEG
) -> Dictionary:
	var on_surface = (contact_count > 0 or gear_rays_colliding)
	if not on_surface:
		return {
			"state": LandingState.AIRBORNE,
			"is_landed": false,
			"is_crashed": false,
			"message": "In flight"
		}
		
	var vspeed: float = linear_velocity.dot(planet_up)
	var descent_speed: float = abs(vspeed)
	var hspeed_vec: Vector3 = linear_velocity - planet_up * vspeed
	var hspeed: float = hspeed_vec.length()
	
	var tilt_dot = clamp(ship_up.dot(planet_up), -1.0, 1.0)
	var tilt_deg = rad_to_deg(acos(tilt_dot))
	
	if not gear_deployed:
		return {
			"state": LandingState.CRASH,
			"is_landed": false,
			"is_crashed": true,
			"message": "Crash: Landing gear not deployed"
		}
		
	if descent_speed > max_vspeed:
		return {
			"state": LandingState.CRASH,
			"is_landed": false,
			"is_crashed": true,
			"message": "Crash: Vertical touchdown speed %.1f m/s exceeded limit (%.1f m/s)" % [descent_speed, max_vspeed]
		}
		
	if hspeed > max_hspeed:
		return {
			"state": LandingState.CRASH,
			"is_landed": false,
			"is_crashed": true,
			"message": "Crash: Horizontal speed %.1f m/s exceeded limit (%.1f m/s)" % [hspeed, max_hspeed]
		}
		
	if tilt_deg > max_tilt_deg:
		return {
			"state": LandingState.CRASH,
			"is_landed": false,
			"is_crashed": true,
			"message": "Crash: Attitude tilt %.1f deg exceeded limit (%.1f deg)" % [tilt_deg, max_tilt_deg]
		}
		
	return {
		"state": LandingState.TOUCHDOWN,
		"is_landed": true,
		"is_crashed": false,
		"message": "Touchdown confirmed. Ship landed safely."
	}

## Calculates true Above Ground Level (AGL) via radar altimeter and gear rays, falling back to ASL
static func calculate_agl(
	global_pos: Vector3,
	planet_up: Vector3,
	altitude_asl: float,
	radar_ray: RayCast3D,
	gear_rays: Array = []
) -> float:
	var agl = altitude_asl
	
	if radar_ray and is_instance_valid(radar_ray):
		# Point radar ray toward planet surface
		var ray_target_world = global_pos - planet_up * 50000.0
		radar_ray.target_position = radar_ray.to_local(ray_target_world)
		radar_ray.force_raycast_update()
		if radar_ray.is_colliding():
			var hit_dist = global_pos.distance_to(radar_ray.get_collision_point())
			agl = min(agl, hit_dist)
			
	for ray in gear_rays:
		if ray and is_instance_valid(ray) and ray.is_colliding():
			var gear_dist = global_pos.distance_to(ray.get_collision_point())
			agl = min(agl, gear_dist)
			
	return max(0.0, agl)
