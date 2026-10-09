class_name TestSurvival extends TestCase

func test_earth_environment_benign() -> void:
	var survival := SurvivalSystem.new()
	survival.set_environment("Earth")
	assert_eq(String(survival.current_body_id), "Earth", "Current body is Earth")
	assert_almost_eq(survival.current_hazard_intensity, 0.0, 0.001, "Earth hazard intensity is 0")
	assert_true(survival.has_breathable_atmosphere, "Earth has breathable atmosphere")

	# Drain process for 10 seconds outside ship
	survival.is_inside_ship = false
	survival._drain(10.0)
	assert_almost_eq(survival.get_life_support(), 100.0, 0.01, "Life support stays full in Earth atmosphere")
	assert_almost_eq(survival.get_hazard_protection(), 100.0, 0.01, "Hazard protection stays full")

	survival.free()

func test_moon_environment_hazards() -> void:
	var survival := SurvivalSystem.new()

	# Moon Daytime
	survival.set_environment("Moon", true, 1.0)
	assert_eq(String(survival.current_body_id), "Moon", "Current body is Moon")
	assert_false(survival.has_breathable_atmosphere, "Moon lacks atmosphere")
	assert_almost_eq(survival.vacuum_hazard, 0.4, 0.01, "Lunar vacuum hazard is 0.4")
	assert_almost_eq(survival.thermal_hazard, 0.3, 0.01, "Lunar day thermal hazard is 0.3")
	assert_almost_eq(survival.radiation_hazard, 0.2, 0.01, "Lunar day radiation is 0.2")
	assert_almost_eq(survival.current_hazard_intensity, 0.9, 0.01, "Total lunar day hazard is 0.9")

	# Moon Nighttime
	survival.set_environment("Moon", false, 1.0)
	assert_almost_eq(survival.thermal_hazard, 0.4, 0.01, "Lunar night thermal hazard is 0.4")
	assert_almost_eq(survival.radiation_hazard, 0.1, 0.01, "Lunar night radiation is 0.1")
	assert_almost_eq(survival.current_hazard_intensity, 0.9, 0.01, "Total lunar night hazard is 0.9")

	survival.free()

func test_moon_hazard_drain_and_breach() -> void:
	var survival := SurvivalSystem.new()
	survival.set_environment("Moon", true)
	survival.is_inside_ship = false

	# Drain hazard protection
	survival._drain(10.0)
	assert_almost_eq(survival.get_hazard_protection(), 55.0, 0.1, "Hazard protection drained by ~45")

	# Drain remaining hazard protection to 0
	survival._drain(15.0)
	assert_almost_eq(survival.get_hazard_protection(), 0.0, 0.01, "Hazard protection breached")

	# Now next drain tick incurs life support drain penalty
	survival._drain(1.0)
	assert_true(survival.get_life_support() < 100.0, "Life support begins draining after breach")

	survival.free()

func test_ship_safe_haven_recharge() -> void:
	var survival := SurvivalSystem.new()
	survival.set_environment("Moon")
	survival._hazard_protection = 50.0
	survival._life_support = 60.0
	survival.is_inside_ship = true

	# Recharge at 20 units/s for 2 seconds -> +40
	survival._recharge(2.0)
	assert_almost_eq(survival.get_hazard_protection(), 90.0, 0.1, "Hazard protection recharged")
	assert_almost_eq(survival.get_life_support(), 100.0, 0.1, "Life support fully recharged")

	survival.free()

func test_death_and_respawn_signal() -> void:
	var survival := SurvivalSystem.new()
	survival.set_environment("Moon")
	survival.is_inside_ship = false
	survival._hazard_protection = 0.0
	survival._life_support = 1.0

	var flags := {
		"died": false,
		"respawned_body": "",
		"respawn_pos": Vector3.ZERO
	}
	survival.player_died.connect(func(): flags["died"] = true)

	survival._drain(2.0)
	assert_true(flags["died"], "Player died signal fired")
	assert_almost_eq(survival.get_life_support(), 0.0, 0.001, "Life support is 0")

	# Respawn
	survival.player_respawned.connect(func(body: StringName, pos: Vector3):
		flags["respawned_body"] = String(body)
		flags["respawn_pos"] = pos
	)

	survival.respawn("Earth", Vector3(10, 20, 30))
	assert_eq(flags["respawned_body"], "Earth", "Respawned on Earth")
	assert_vec_almost_eq(flags["respawn_pos"], Vector3(10, 20, 30), 0.01, "Respawn position preserved")
	assert_almost_eq(survival.get_life_support(), 100.0, 0.01, "Life support restored")
	assert_almost_eq(survival.get_hazard_protection(), 100.0, 0.01, "Hazard protection restored")
	assert_almost_eq(survival.current_hazard_intensity, 0.0, 0.01, "Earth hazard intensity is 0")

	survival.free()

func test_replenish_consumables() -> void:
	var survival := SurvivalSystem.new()
	survival._life_support = 40.0
	survival._hazard_protection = 30.0

	survival.replenish_life_support(25.0)
	assert_almost_eq(survival.get_life_support(), 65.0, 0.01, "Replenished life support")

	survival.replenish_hazard_protection(100.0)
	assert_almost_eq(survival.get_hazard_protection(), 100.0, 0.01, "Capped at max hazard protection")

	survival.free()

func test_serialization_roundtrip() -> void:
	var s1 := SurvivalSystem.new()
	s1.set_environment("Moon")
	s1._life_support = 77.5
	s1._hazard_protection = 33.2
	s1.max_life_support = 150.0

	var data := s1.to_dict()
	var s2 := SurvivalSystem.new()
	s2.from_dict(data)

	assert_almost_eq(s2.get_life_support(), 77.5, 0.01)
	assert_almost_eq(s2.get_hazard_protection(), 33.2, 0.01)
	assert_almost_eq(s2.max_life_support, 150.0, 0.01)
	assert_eq(String(s2.current_body_id), "Moon")

	s1.free()
	s2.free()
