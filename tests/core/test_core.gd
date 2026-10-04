extends "res://tests/test_case.gd"

func test_dvec3_precision() -> void:
	var v = DVec3.new(1.0e12, 0.0, 0.0)
	v.add_in_place(DVec3.new(0.001, 0.0, 0.0))
	assert_almost_eq(v.x, 1000000000000.001, 1e-5, "DVec3 precision at 1e12 m (adding 0.001 m)")

func test_universe_position_carry() -> void:
	var up = UniversePosition.new(Vector3i.ZERO, DVec3.new(0, 0, 0))
	up.add_offset(DVec3.new(6.0e11, 0, 0))
	assert_eq(up.sector.x, 1, "Sector carry x")
	assert_almost_eq(up.offset.x, -4.0e11, 1e-5, "Offset carry x")

func test_universe_position_difference() -> void:
	var up1 = UniversePosition.new(Vector3i(1, 0, 0), DVec3.new(1.0e11, 0, 0))
	var up2 = UniversePosition.new(Vector3i(-1, 0, 0), DVec3.new(-1.0e11, 0, 0))
	var diff = up1.difference_to(up2)
	assert_almost_eq(diff.x, -2.2e12, 1e-5, "Difference across sectors")

func test_gamescale_period() -> void:
	var scale = GameScale.get_instance()
	var real_a = 384400000.0 # Moon
	var real_mu = 3.986e14
	var real_r = 6371000.0
	
	var scaled_a = scale.scaled_semi_major_axis(real_a)
	var scaled_mu = scale.scaled_mu(real_mu, real_r)
	
	var real_period = 2.0 * PI * sqrt(pow(real_a, 3.0) / real_mu)
	var scaled_period = 2.0 * PI * sqrt(pow(scaled_a, 3.0) / scaled_mu)
	
	assert_almost_eq(scaled_period, real_period * 0.01, real_period * 0.001, "Moon period scaled ≈ real × 0.01")

func test_simulation_clock() -> void:
	var clock = preload("res://game/core/simulation_clock.gd").new()
	clock.set_warp_index(0) # 1x
	assert_true(clock.physics_warp_allowed, "Warp 1 allows physics")
	clock.set_warp_index(5) # 100x
	assert_false(clock.physics_warp_allowed, "Warp 100 on-rails")
	
	clock.set_warp_index(1) # 2x
	clock.advance(1.0)
	assert_almost_eq(clock.sim_time_s, 2.0, 1e-5, "Clock advance")
