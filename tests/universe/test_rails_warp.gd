extends "res://tests/test_case.gd"

const RailsPropagator = preload("res://game/universe/rails_propagator.gd")

const MU_EARTH: float = 3.986004418e14
const R_EARTH: float = 6371000.0

## Propagate 10 orbits at x100,000, assert semi-major axis drift < 1e-6 and period matches analytic period.
## Also verifies specific orbital energy is conserved to 1e-7.
func test_propagate_10_orbits_at_100k_warp() -> void:
	var r_mag: float = R_EARTH + 300000.0 # 300 km LEO
	var v_circ: float = sqrt(MU_EARTH / r_mag)
	var r0 = DVec3.new(r_mag, 0.0, 0.0)
	var v0 = DVec3.new(0.0, v_circ, 0.0)
	
	var a_analytic: float = r_mag
	var period_analytic: float = 2.0 * PI * sqrt(pow(a_analytic, 3.0) / MU_EARTH)
	var e0: float = 0.5 * v0.length_squared() - MU_EARTH / r0.length()
	
	# Simulate 100,000x warp at 60 Hz physics step
	var warp_factor: float = 100000.0
	var dt_step: float = warp_factor / 60.0
	var total_time: float = period_analytic * 10.0
	var steps: int = int(ceil(total_time / dt_step))
	
	var cur_r = r0
	var cur_v = v0
	for s in range(steps):
		var sub_dt = dt_step
		if s == steps - 1:
			sub_dt = total_time - float(s) * dt_step
		var next_state = RailsPropagator.propagate(cur_r, cur_v, sub_dt, MU_EARTH)
		cur_r = next_state[0]
		cur_v = next_state[1]
		
	var ef: float = 0.5 * cur_v.length_squared() - MU_EARTH / cur_r.length()
	var a_final: float = -MU_EARTH / (2.0 * ef)
	var period_final: float = 2.0 * PI * sqrt(pow(a_final, 3.0) / MU_EARTH)
	
	var a_drift_rel: float = abs(a_final - a_analytic) / a_analytic
	var period_drift_rel: float = abs(period_final - period_analytic) / period_analytic
	var energy_drift_rel: float = abs(ef - e0) / abs(e0)
	
	assert_true(a_drift_rel < 1e-6, "Semi-major axis relative drift %s < 1e-6" % str(a_drift_rel))
	assert_true(period_drift_rel < 1e-6, "Period relative error %s < 1e-6" % str(period_drift_rel))
	assert_true(energy_drift_rel < 1e-7, "Specific orbital energy conserved to 1e-7: drift %s" % str(energy_drift_rel))

## Forward dt then backward -dt returns initial state within 1 mm and 1 mm/s.
func test_forward_and_backward_reversibility() -> void:
	var r_mag: float = R_EARTH + 500000.0
	var v_circ: float = sqrt(MU_EARTH / r_mag)
	# Inclined, eccentric orbit test state
	var r0 = DVec3.new(r_mag * cos(0.3), r_mag * sin(0.3), 100000.0)
	var v0 = DVec3.new(-v_circ * sin(0.3) * 1.1, v_circ * cos(0.3) * 1.1, v_circ * 0.2)
	
	var dt: float = 3456.78
	var fwd = RailsPropagator.propagate(r0, v0, dt, MU_EARTH)
	var bwd = RailsPropagator.propagate(fwd[0], fwd[1], -dt, MU_EARTH)
	
	var dist_r: float = (bwd[0] as DVec3).distance_to(r0)
	var dist_v: float = (bwd[1] as DVec3).distance_to(v0)
	
	# 1 mm = 0.001 m, 1 mm/s = 0.001 m/s
	assert_true(dist_r < 0.001, "Forward/backward reversibility position error %f m < 1 mm" % dist_r)
	assert_true(dist_v < 0.001, "Forward/backward reversibility velocity error %f m/s < 1 mm/s" % dist_v)

## Hyperbolic trajectory propagation preserves energy.
func test_hyperbolic_trajectory_preserves_energy() -> void:
	var r0 = DVec3.new(R_EARTH + 400000.0, 0.0, 0.0)
	var v_esc: float = sqrt(2.0 * MU_EARTH / r0.length())
	var v0 = DVec3.new(0.0, v_esc * 1.25, 0.0) # Well above escape speed
	
	var e0: float = 0.5 * v0.length_squared() - MU_EARTH / r0.length()
	assert_true(e0 > 0.0, "Hyperbolic orbit has positive specific energy")
	
	var dt: float = 7200.0 # 2 hours propagation
	var hyp = RailsPropagator.propagate(r0, v0, dt, MU_EARTH)
	var r_hyp: DVec3 = hyp[0]
	var v_hyp: DVec3 = hyp[1]
	
	var ef: float = 0.5 * v_hyp.length_squared() - MU_EARTH / r_hyp.length()
	var energy_drift_rel: float = abs(ef - e0) / abs(e0)
	assert_true(energy_drift_rel < 1e-7, "Hyperbolic energy conserved: drift %s < 1e-7" % str(energy_drift_rel))
	
	# Also verify round-trip reversibility on hyperbolic arc
	var bwd = RailsPropagator.propagate(r_hyp, v_hyp, -dt, MU_EARTH)
	var dist_r = (bwd[0] as DVec3).distance_to(r0)
	var dist_v = (bwd[1] as DVec3).distance_to(v0)
	assert_true(dist_r < 0.001, "Hyperbolic reversibility position error %f m < 1 mm" % dist_r)
	assert_true(dist_v < 0.001, "Hyperbolic reversibility velocity error %f m/s < 1 mm/s" % dist_v)

## Test can_warp refusal under thrust / atmospheric conditions.
func test_can_warp_refusal_conditions() -> void:
	var clock = preload("res://game/core/simulation_clock.gd").new()
	
	# Thrust checks
	assert_false(clock.can_warp({"thrust": true}), "Refuse warp when thrust is true")
	assert_false(clock.can_warp({"is_thrusting": true}), "Refuse warp when is_thrusting is true")
	assert_false(clock.can_warp({"throttle": 0.5}), "Refuse warp when throttle > 0")
	
	# Atmosphere flag checks
	assert_false(clock.can_warp({"atmosphere": true}), "Refuse warp when atmosphere is true")
	assert_false(clock.can_warp({"in_atmosphere": true}), "Refuse warp when in_atmosphere is true")
	
	# Earth default atmosphere threshold (150,000 m)
	assert_false(clock.can_warp({"altitude": 100000.0}), "Refuse warp when altitude < 150,000 m")
	assert_false(clock.can_warp({"altitude": 149999.0}), "Refuse warp when altitude just below 150,000 m")
	assert_true(clock.can_warp({"altitude": 150001.0}), "Allow warp when altitude > 150,000 m")
	
	# Periapsis within atmosphere
	assert_false(clock.can_warp({"altitude": 250000.0, "periapsis_alt": 100000.0}), "Refuse warp when periapsis < 150,000 m")
	assert_true(clock.can_warp({"altitude": 250000.0, "periapsis_alt": 160000.0}), "Allow warp when both alt and periapsis > 150,000 m")
	
	# Scale height based threshold (12 * scale_height)
	var sh: float = 8500.0 # e.g. Earth scale height ~8.5 km -> 102 km threshold
	assert_false(clock.can_warp({"scale_height": sh, "altitude": 90000.0}), "Refuse warp when altitude < 12 * scale_height")
	assert_true(clock.can_warp({"scale_height": sh, "altitude": 110000.0}), "Allow warp when altitude > 12 * scale_height")
	assert_false(clock.can_warp({"scale_height": sh, "altitude": 150000.0, "periapsis_alt": 95000.0}), "Refuse warp when periapsis < 12 * scale_height")
	
	# Nominal / clean conditions
	assert_true(clock.can_warp({}), "Empty conditions allow warp")
	assert_true(clock.can_warp({"thrust": false, "altitude": 200000.0, "periapsis_alt": 190000.0}), "Safe conditions allow warp")
	
	clock.free()

## Test SimulationClock warp level switching, physical vs rails warp, and rails stepping.
func test_simulation_clock_warp_levels() -> void:
	var clock = preload("res://game/core/simulation_clock.gd").new()
	
	assert_eq(clock.WARP_LEVELS, [1, 2, 4, 10, 50, 100, 1000, 10000, 100000], "WARP_LEVELS array matches spec")
	
	# Warp factor <= 4: physical warp (Engine.time_scale = factor, on_rails = false)
	clock.set_warp_index(0) # 1x
	assert_eq(clock.get_warp_factor(), 1, "Warp index 0 is 1x")
	assert_false(clock.is_on_rails(), "1x is not on rails")
	assert_almost_eq(Engine.time_scale, 1.0, 1e-5, "Engine.time_scale is 1.0 for 1x")
	
	clock.set_warp_index(1) # 2x
	assert_eq(clock.get_warp_factor(), 2, "Warp index 1 is 2x")
	assert_false(clock.is_on_rails(), "2x is physical warp")
	assert_almost_eq(Engine.time_scale, 2.0, 1e-5, "Engine.time_scale is 2.0 for 2x")
	
	clock.set_warp_index(2) # 4x
	assert_eq(clock.get_warp_factor(), 4, "Warp index 2 is 4x")
	assert_false(clock.is_on_rails(), "4x is physical warp")
	assert_almost_eq(Engine.time_scale, 4.0, 1e-5, "Engine.time_scale is 4.0 for 4x")
	
	# Warp factor > 4: rails warp (Engine.time_scale = 1.0, on_rails = true)
	clock.set_warp_index(3) # 10x
	assert_eq(clock.get_warp_factor(), 10, "Warp index 3 is 10x")
	assert_true(clock.is_on_rails(), "10x is rails warp")
	assert_almost_eq(Engine.time_scale, 1.0, 1e-5, "Engine.time_scale is reset to 1.0 for rails warp")
	
	clock.set_warp_index(8) # 100,000x
	assert_eq(clock.get_warp_factor(), 100000, "Warp index 8 is 100000x")
	assert_true(clock.is_on_rails(), "100000x is rails warp")
	assert_almost_eq(Engine.time_scale, 1.0, 1e-5, "Engine.time_scale is 1.0 for 100000x rails warp")
	
	# Test rails state propagation hook
	var r0 = DVec3.new(R_EARTH + 200000.0, 0.0, 0.0)
	var v0 = DVec3.new(0.0, sqrt(MU_EARTH / r0.length()), 0.0)
	var state = RailsPropagator.create_state(r0, v0, MU_EARTH)
	clock.register_state(state)
	
	var initial_time: float = clock.sim_time_s
	# Advance 1 physics tick at 100,000x warp (dt = 0.016667 * 100000 = 1666.7 s)
	clock.advance(0.02)
	assert_almost_eq(clock.sim_time_s, initial_time + 2000.0, 1e-3, "SimulationClock advances by dt * factor in rails warp")
	assert_true(state.r.distance_to(r0) > 1000.0, "State position advanced analytically on rails")
	
	clock.unregister_state(state)
	clock.set_warp_index(0)
	Engine.time_scale = 1.0
	clock.free()
