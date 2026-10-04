extends "res://tests/test_case.gd"

func test_kepler_solver() -> void:
	for e in [0.0, 0.2, 0.9, 0.99]:
		var M = 1.0
		var E = OrbitalMechanics.solve_kepler(M, e)
		var residual = E - e * sin(E) - M
		assert_almost_eq(residual, 0.0, 1e-11, "Kepler solver residual e=" + str(e))
		
	var M_hyp = 1.0
	var e_hyp = 1.5
	var F = OrbitalMechanics.solve_kepler_hyperbolic(M_hyp, e_hyp)
	var residual_hyp = e_hyp * sinh(F) - F - M_hyp
	assert_almost_eq(residual_hyp, 0.0, 1e-11, "Kepler hyperbolic solver residual e=1.5")

func test_round_trip() -> void:
	var elements = OrbitalMechanics.OrbitElements.new()
	elements.semi_major_axis = 10000.0
	elements.eccentricity = 0.5
	elements.inclination_rad = 0.1
	elements.lan_rad = 0.2
	elements.arg_periapsis_rad = 0.3
	elements.mean_anomaly_rad = 0.4
	elements.period_seconds = 1000.0
	
	var mu = 3.986e14
	var state = OrbitalMechanics.state_from_elements(elements, mu, 0.0)
	var r = state[0]
	var v = state[1]
	
	var new_elements = OrbitalMechanics.elements_from_state(r, v, mu)
	
	assert_almost_eq(new_elements.semi_major_axis, 10000.0, 1e-3, "Round trip a")
	assert_almost_eq(new_elements.eccentricity, 0.5, 1e-5, "Round trip e")

func test_circular_orbit_period() -> void:
	var elements = OrbitalMechanics.OrbitElements.new()
	elements.semi_major_axis = 7000000.0
	elements.eccentricity = 0.0
	elements.period_seconds = 2.0 * PI * sqrt(pow(7000000.0, 3.0) / 3.986e14)
	var state1 = OrbitalMechanics.propagate(elements, 3.986e14, 0.0)
	var state2 = OrbitalMechanics.propagate(elements, 3.986e14, elements.period_seconds)
	
	var r1 = state1[0] as DVec3
	var r2 = state2[0] as DVec3
	assert_vec_almost_eq(r1, r2, 100.0, "Circular orbit period")

func test_energy_conservation() -> void:
	var elements = OrbitalMechanics.OrbitElements.new()
	elements.semi_major_axis = 10000000.0
	elements.eccentricity = 0.5
	elements.period_seconds = 1.0
	var mu = 3.986e14
	var state1 = OrbitalMechanics.propagate(elements, mu, 0.0)
	var state2 = OrbitalMechanics.propagate(elements, mu, 1000.0)
	
	var r1 = state1[0] as DVec3
	var v1 = state1[1] as DVec3
	var r2 = state2[0] as DVec3
	var v2 = state2[1] as DVec3
	
	var e1 = v1.length_squared() * 0.5 - mu / r1.length()
	var e2 = v2.length_squared() * 0.5 - mu / r2.length()
	assert_almost_eq(e1, e2, 1e-5, "Energy conservation")

func test_earth_heliocentric() -> void:
	# At J2000 (t=0)
	var earth_def = BodyRegistry.get_body("Earth")
	var elements = OrbitalMechanics.OrbitElements.new()
	elements.semi_major_axis = earth_def.semi_major_axis_m
	elements.eccentricity = earth_def.eccentricity
	elements.inclination_rad = deg_to_rad(earth_def.inclination_deg)
	elements.lan_rad = deg_to_rad(earth_def.longitude_ascending_node_deg)
	elements.arg_periapsis_rad = deg_to_rad(earth_def.argument_periapsis_deg)
	elements.mean_anomaly_rad = deg_to_rad(earth_def.mean_anomaly_at_epoch_deg)
	elements.period_seconds = 3.154e7
	
	var sun_def = BodyRegistry.get_body("Sun")
	var mu = sun_def.mu_m3_s2
	
	var state = OrbitalMechanics.state_from_elements(elements, mu, 0.0)
	var pos_ecliptic = OrbitalMechanics.godot_to_ecliptic(state[0])
	
	var au = 149597870700.0
	var x_au = pos_ecliptic.x / au
	var y_au = pos_ecliptic.y / au
	
	assert_almost_eq(x_au, -0.1771, 0.1, "Earth J2000 X")
	assert_almost_eq(y_au, 0.9672, 0.1, "Earth J2000 Y")

func test_dominant_body() -> void:
	# Near Earth
	var earth_def = BodyRegistry.get_body("Earth")
	var pos_near_earth = GravityService.body_position("Earth", 0.0)
	var dom = GravityService.dominant_body(pos_near_earth, 0.0)
	assert_eq(dom, &"Earth", "Dominant body near Earth")
	
	# Near Moon
	var pos_near_moon = GravityService.body_position("Moon", 0.0)
	var dom_moon = GravityService.dominant_body(pos_near_moon, 0.0)
	assert_eq(dom_moon, &"Moon", "Dominant body near Moon")

func test_shim_solar_system_data() -> void:
	var data = SolarSystemData.get_body_data("Earth")
	assert_true(data.has("radius"), "Shim has radius")
	assert_true(data.has("mu"), "Shim has mu")

func test_old_calculate_orbit() -> void:
	var r = Vector3(7000000.0, 0, 0)
	var v = Vector3(0, 0, 7546.0)
	var orb = OrbitalMechanics.calculate_orbit(r, v)
	assert_almost_eq(orb.semi_major_axis, 7000000.0, 100000.0, "Old calculate_orbit a")
