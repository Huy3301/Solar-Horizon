extends "res://tests/test_case.gd"

const FlightModel = preload("res://game/player/flight_model.gd")

func test_scale_height_atmosphere_earth_and_moon() -> void:
	var earth_def = BodyRegistry.get_body("Earth")
	var moon_def = BodyRegistry.get_body("Moon")
	
	# Earth sea level
	var rho_earth_0 = FlightModel.calculate_air_density(0.0, earth_def, 0.1)
	assert_almost_eq(rho_earth_0, 1.225, 0.01, "Earth sea level air density = 1.225")
	
	# Earth at 1 scale height (850 m at 1:10 scale)
	var scale_h = 850.0
	var rho_earth_1h = FlightModel.calculate_air_density(scale_h, earth_def, 0.1)
	var expected_1h = 1.225 * exp(-1.0)
	assert_almost_eq(rho_earth_1h, expected_1h, 0.01, "Earth density at 1 scale height is rho0/e")
	
	# Earth at 5 scale heights
	var rho_earth_5h = FlightModel.calculate_air_density(scale_h * 5.0, earth_def, 0.1)
	var expected_5h = 1.225 * exp(-5.0)
	assert_almost_eq(rho_earth_5h, expected_5h, 0.005, "Earth density at 5 scale heights")
	
	# Earth vacuum cutoff (above 15 scale heights)
	var rho_earth_high = FlightModel.calculate_air_density(20000.0, earth_def, 0.1)
	assert_almost_eq(rho_earth_high, 0.0, 1e-6, "Earth density at orbital altitude (vacuum)")
	
	# Moon surface and altitude: has_atmosphere is false
	var rho_moon_0 = FlightModel.calculate_air_density(0.0, moon_def, 0.1)
	var rho_moon_high = FlightModel.calculate_air_density(5000.0, moon_def, 0.1)
	assert_almost_eq(rho_moon_0, 0.0, 1e-6, "Moon has zero air density on surface")
	assert_almost_eq(rho_moon_high, 0.0, 1e-6, "Moon has zero air density at altitude")

func test_inertia_scaled_torque() -> void:
	var basis = Basis.IDENTITY
	var inputs = Vector3(1.0, 0.0, 0.0) # Full pitch
	var max_accel = Vector3(2.0, 1.5, 3.0)
	var I_light = Vector3(1000.0, 1000.0, 500.0)
	var I_heavy = Vector3(10000.0, 10000.0, 5000.0)
	
	var torque_light = FlightModel.calculate_attitude_torque(inputs, I_light, max_accel, 0.0, FlightModel.Mode.NEWTONIAN, Vector3.ZERO, basis)
	var torque_heavy = FlightModel.calculate_attitude_torque(inputs, I_heavy, max_accel, 0.0, FlightModel.Mode.NEWTONIAN, Vector3.ZERO, basis)
	
	# Resulting angular acceleration = torque / I must be identical!
	var alpha_light = torque_light.x / I_light.x
	var alpha_heavy = torque_heavy.x / I_heavy.x
	assert_almost_eq(alpha_light, alpha_heavy, 1e-4, "Angular acceleration is invariant with inertia scaling")
	assert_almost_eq(alpha_light, max_accel.x, 1e-4, "Pitch acceleration matches command authority")

func test_assisted_flight_mode_damping() -> void:
	var basis = Basis.IDENTITY
	var inputs = Vector3.ZERO # Neutral stick
	var max_accel = Vector3(2.0, 1.5, 3.0)
	var I = Vector3(5000.0, 5000.0, 2000.0)
	var current_ang_vel = Vector3(1.0, 0.0, 0.0) # Pitching rate
	
	# Assisted mode must generate opposing restoring torque
	var torque_assisted = FlightModel.calculate_attitude_torque(inputs, I, max_accel, 0.0, FlightModel.Mode.ASSISTED, current_ang_vel, basis)
	assert_true(torque_assisted.x < 0.0, "Assisted mode generates negative damping torque opposing pitch rate")
	
	# Newtonian mode with neutral stick produces zero torque
	var torque_newtonian = FlightModel.calculate_attitude_torque(inputs, I, max_accel, 0.0, FlightModel.Mode.NEWTONIAN, current_ang_vel, basis)
	assert_almost_eq(torque_newtonian.x, 0.0, 1e-5, "Newtonian mode produces zero damping torque")

func test_landing_evaluation_limits() -> void:
	var planet_up = Vector3.UP
	var ship_up = Vector3.UP # Level attitude
	
	# 1. Gentle touchdown with gear deployed
	var gentle_vel = Vector3(2.0, -3.0, 0.0) # vspeed = -3 m/s, hspeed = 2 m/s
	var eval_safe = FlightModel.evaluate_landing(1, true, gentle_vel, planet_up, ship_up, true)
	assert_eq(eval_safe["state"], FlightModel.LandingState.TOUCHDOWN, "Gentle landing is TOUCHDOWN")
	assert_true(eval_safe["is_landed"], "is_landed is true")
	assert_false(eval_safe["is_crashed"], "is_crashed is false")
	
	# 2. Hard landing exceeding vertical speed limit (vspeed = -15 m/s)
	var hard_v_vel = Vector3(0.0, -15.0, 0.0)
	var eval_hard_v = FlightModel.evaluate_landing(1, true, hard_v_vel, planet_up, ship_up, true)
	assert_eq(eval_hard_v["state"], FlightModel.LandingState.CRASH, "Excessive vspeed causes CRASH")
	assert_true(eval_hard_v["is_crashed"], "is_crashed is true on excessive vspeed")
	
	# 3. Excessive horizontal speed (hspeed = 25 m/s)
	var hard_h_vel = Vector3(25.0, -2.0, 0.0)
	var eval_hard_h = FlightModel.evaluate_landing(1, true, hard_h_vel, planet_up, ship_up, true)
	assert_eq(eval_hard_h["state"], FlightModel.LandingState.CRASH, "Excessive hspeed causes CRASH")
	assert_true(eval_hard_h["is_crashed"], "is_crashed is true on excessive hspeed")
	
	# 4. Excessive attitude tilt (45 degrees)
	var tilted_ship_up = Vector3(1.0, 1.0, 0.0).normalized()
	var eval_tilted = FlightModel.evaluate_landing(1, true, gentle_vel, planet_up, tilted_ship_up, true)
	assert_eq(eval_tilted["state"], FlightModel.LandingState.CRASH, "Excessive tilt causes CRASH")
	
	# 5. Gear not deployed on touchdown
	var eval_gear_up = FlightModel.evaluate_landing(1, true, gentle_vel, planet_up, ship_up, false)
	assert_eq(eval_gear_up["state"], FlightModel.LandingState.CRASH, "Gear up causes CRASH")

func test_agl_radar_calculation() -> void:
	var global_pos = Vector3(0.0, 500.0, 0.0)
	var planet_up = Vector3.UP
	var alt_asl = 500.0
	
	# When no radar ray is colliding, falls back to ASL
	var agl_no_ray = FlightModel.calculate_agl(global_pos, planet_up, alt_asl, null)
	assert_almost_eq(agl_no_ray, 500.0, 1e-4, "AGL falls back to ASL when radar ray is null")
