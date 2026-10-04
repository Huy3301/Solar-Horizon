extends "res://tests/test_case.gd"

func test_ship_sim_time_advances() -> void:
	var clock = preload("res://game/core/simulation_clock.gd").new()
	var ship = ShipFlightController.new()
	ship.simulation_clock = clock
	
	clock.sim_time_s = 100.0
	ship._physics_process(0.1)
	assert_almost_eq(ship.sim_time, 100.0, 1e-5, "Ship sim_time matches SimulationClock time")
	
	clock.advance(5.0)
	ship._physics_process(0.1)
	assert_almost_eq(ship.sim_time, 105.0, 1e-5, "Ship sim_time advances when SimulationClock advances")
	assert_almost_eq(ship.telemetry_data.get("sim_time", 0.0), 105.0, 1e-5, "Telemetry dictionary contains sim_time")
	
	clock.free()
	ship.free()

func test_game_manager_transition_and_orbit() -> void:
	var gm = GameManagerAutoload.new()
	assert_true(gm.is_in_orbit(), "Initial GameManager state should be in orbit")
	
	var test_pos = UniversePosition.new(Vector3i(2, 0, 1), DVec3.new(500.0, 1000.0, 1500.0))
	gm.transition_to_surface(test_pos)
	assert_false(gm.is_in_orbit(), "GameManager should not be in orbit after surface transition")
	
	gm.transition_to_orbit()
	assert_true(gm.is_in_orbit(), "GameManager should be in orbit after transition_to_orbit")
	gm.free()
