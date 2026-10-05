class_name TestJoltOrbit
extends TestCase

## Verification test for simulation truth:
## SH-01: Jolt velocity unclamp (speeds > 500 m/s allowed for orbital mechanics)
## SH-02: Earth and Moon lie in horizontal orbital plane (|y|/|r| < sin(inc))
## SH-03: Body position cache invalidates correctly at large sim times
## SH-06: Longitude of ascending node (LAN) and ArgP frame roundtrip
## SH-07: Hyperbolic orbit apoapsis reporting

func test_jolt_velocity_unclamped_in_settings() -> void:
	var max_v = ProjectSettings.get_setting("physics/jolt_physics_3d/limits/max_linear_velocity")
	assert_true(max_v != null, "Jolt max_linear_velocity setting is configured")
	if max_v != null:
		assert_true(float(max_v) >= 10000.0, "Jolt max_linear_velocity is at least 10,000 m/s (found %f)" % float(max_v))

func test_body_positions_in_horizontal_plane() -> void:
	var earth_pos = GravityService.body_position("Earth", 0.0)
	var earth_len = earth_pos.length()
	assert_true(earth_len > 1e6, "Earth distance from Sun is > 1 million km")

	# In ecliptic-aligned Godot frame, inclination of Earth is ~0, so y component must be small
	var earth_y_ratio = abs(earth_pos.y) / earth_len
	assert_true(earth_y_ratio < 0.01, "Earth orbital plane has |y|/|r| = %f < 0.01 (horizontal ecliptic plane)" % earth_y_ratio)

	var moon_pos = GravityService.body_position("Moon", 0.0)
	var to_moon = moon_pos.sub(earth_pos)
	var moon_len = to_moon.length()
	assert_true(moon_len > 1e4, "Moon distance from Earth is > 10,000 km")
	var moon_y_ratio = abs(to_moon.y) / moon_len
	# Moon inclination to ecliptic is ~5.14 degrees -> sin(5.14°) ≈ 0.09
	assert_true(moon_y_ratio < 0.12, "Moon orbital plane has |y|/|r| = %f < 0.12" % moon_y_ratio)

func test_cache_invalidation_at_large_sim_time() -> void:
	# At t = 2,000,000 seconds (~23 days in sim time)
	var t0: float = 2000000.0
	var t1: float = 2000001.0 # 1 second later

	var pos_t0 = GravityService.body_position("Moon", t0)
	var pos_t1 = GravityService.body_position("Moon", t1)

	var delta_pos = pos_t1.sub(pos_t0).length()
	assert_true(delta_pos > 10.0, "Moon moves at large sim times (t=%f): delta=%f m > 10 m" % [t0, delta_pos])

func test_orbital_elements_lan_and_argp_roundtrip() -> void:
	var elements = OrbitalMechanics.OrbitElements.new()
	elements.semi_major_axis = 700000.0
	elements.eccentricity = 0.05
	elements.inclination_rad = deg_to_rad(30.0)
	elements.lan_rad = deg_to_rad(40.0)
	elements.arg_periapsis_rad = deg_to_rad(50.0)
	elements.mean_anomaly_rad = 1.0
	var mu = 3.986e11
	elements.period_seconds = 2.0 * PI * sqrt(pow(elements.semi_major_axis, 3.0) / mu)

	var state = OrbitalMechanics.state_from_elements(elements, mu, 0.0)
	var r = state[0] as DVec3
	var v = state[1] as DVec3

	var extracted = OrbitalMechanics.calculate_orbit(r.to_vector3(), v.to_vector3(), mu, 637100.0)

	var lan_deg = rad_to_deg(extracted.lan_rad)
	var inc_deg = rad_to_deg(extracted.inclination_rad)
	var argp_deg = rad_to_deg(extracted.arg_periapsis_rad)

	assert_almost_eq(lan_deg, 40.0, 0.05, "Extracted LAN matches 40.0° (not 320°)")
	assert_almost_eq(inc_deg, 30.0, 0.05, "Extracted Inclination matches 30.0°")
	assert_almost_eq(argp_deg, 50.0, 0.05, "Extracted Argument of Periapsis matches 50.0°")

func test_hyperbolic_orbit_apoapsis() -> void:
	var r = Vector3(0.0, 700000.0, 0.0)
	# Speed well above escape speed sqrt(2 * mu / r) ≈ sqrt(2 * 3.986e11 / 700000) ≈ 1067 m/s
	var v = Vector3(2500.0, 0.0, 0.0)
	var mu = 3.986e11
	var radius = 637100.0

	var orbit = OrbitalMechanics.calculate_orbit(r, v, mu, radius)
	assert_true(orbit.is_hyperbolic, "High-velocity orbit detected as hyperbolic")
	assert_false(orbit.is_closed_orbit, "Hyperbolic orbit is not closed")
	assert_eq(orbit.apoapsis_alt, -1.0, "Hyperbolic apoapsis altitude is -1.0 (unbound)")
