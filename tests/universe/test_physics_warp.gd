extends "res://tests/test_case.gd"

const SimulationClockScript = preload("res://game/core/simulation_clock.gd")

func test_physics_warp_x4_advances_sim_time_by_delta() -> void:
	var clock = SimulationClockScript.new()

	# Set to warp index 2 (x4 warp)
	clock.set_warp_index(2)
	assert_eq(clock.get_warp_factor(), 4, "Warp factor is 4")
	assert_false(clock.is_on_rails(), "Warp x4 is physical warp, not on rails")
	assert_almost_eq(Engine.time_scale, 4.0, 1e-5, "Engine.time_scale is 4.0")

	# Physical warp advance: each call to advance(dt) should increment sim_time_s by exactly dt (1.0 ratio),
	# because Godot's Engine.time_scale already scales tick frequency.
	var dt: float = 1.0 / 60.0
	var initial_time: float = clock.sim_time_s
	clock.advance(dt)

	var elapsed: float = clock.sim_time_s - initial_time
	assert_almost_eq(elapsed, dt, 1e-6, "advance(dt) at 4x physical warp must increment sim_time_s by exactly delta (1.0 ratio)")

	# Advance 59 more ticks (total 60 ticks)
	for i in range(59):
		clock.advance(dt)

	var total_elapsed: float = clock.sim_time_s - initial_time
	assert_almost_eq(total_elapsed, 1.0, 1e-5, "60 ticks of 1/60s must advance sim_time_s by exactly 1.0s")

	# Compare with on_rails warp: at 10x (rails warp), advance(dt) multiplies by factor
	clock.set_warp_index(3) # 10x
	assert_true(clock.is_on_rails(), "Warp x10 is on rails")
	var rails_initial: float = clock.sim_time_s
	clock.advance(dt)
	var rails_elapsed: float = clock.sim_time_s - rails_initial
	assert_almost_eq(rails_elapsed, dt * 10.0, 1e-5, "advance(dt) in rails warp must scale by factor")

	# Reset engine time scale and cleanup
	clock.set_warp_index(0)
	Engine.time_scale = 1.0
	clock.free()

func test_get_sun_direction() -> void:
	var clock = SimulationClockScript.new()

	# 1. At origin / near zero, returns sane fallback (Vector3.UP)
	var fallback_dir: Vector3 = clock.get_sun_direction(Vector3.ZERO)
	assert_eq(fallback_dir, Vector3.UP, "Origin query returns Vector3.UP fallback")

	# 2. At positive X offset (+1000 m), vector should point towards Sun (at origin: -X)
	var dir_x: Vector3 = clock.get_sun_direction(Vector3(1000.0, 0.0, 0.0))
	assert_vec_almost_eq(dir_x, Vector3(-1.0, 0.0, 0.0), 1e-5, "Direction towards Sun from +X is (-1, 0, 0)")
	assert_true(dir_x.is_normalized(), "Result direction is normalized")

	# 3. At positive Y offset (+5000 m), vector should point towards Sun (-Y)
	var dir_y: Vector3 = clock.get_sun_direction(Vector3(0.0, 5000.0, 0.0))
	assert_vec_almost_eq(dir_y, Vector3(0.0, -1.0, 0.0), 1e-5, "Direction towards Sun from +Y is (0, -1, 0)")

	# 4. At positive Z offset (+2000 m), vector should point towards Sun (-Z)
	var dir_z: Vector3 = clock.get_sun_direction(Vector3(0.0, 0.0, 2000.0))
	assert_vec_almost_eq(dir_z, Vector3(0.0, 0.0, -1.0), 1e-5, "Direction towards Sun from +Z is (0, 0, -1)")

	# 5. Diagonal position
	var dir_diag: Vector3 = clock.get_sun_direction(Vector3(100.0, 100.0, 0.0))
	var expected_diag: Vector3 = Vector3(-1.0, -1.0, 0.0).normalized()
	assert_vec_almost_eq(dir_diag, expected_diag, 1e-5, "Diagonal query points towards Sun")

	clock.free()
