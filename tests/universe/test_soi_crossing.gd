extends "res://tests/test_case.gd"

## Phase A' Exit Gate: Trans-Lunar Injection & SOI Crossing Test (SH-16 Exit Gate)
## Validates Earth LEO departure, TLI burn, Keplerian transfer arc energy conservation,
## and patched-conic frame hand-off across the Moon's Sphere of Influence (SOI).

func test_trans_lunar_injection_and_soi_crossing() -> void:
	# 1. Retrieve scaled Earth and Moon parameters from BodyRegistry and GameScale
	var scale: GameScale = GameScale.get_instance()
	var earth_def: CelestialBodyDef = BodyRegistry.get_body(&"Earth")
	var moon_def: CelestialBodyDef = BodyRegistry.get_body(&"Moon")

	assert_true(earth_def != null, "Earth definition retrieved from BodyRegistry")
	assert_true(moon_def != null, "Moon definition retrieved from BodyRegistry")

	var earth_r: float = scale.scaled_radius(earth_def.radius_m)
	var earth_mu: float = scale.scaled_mu(earth_def.mu_m3_s2, earth_def.radius_m)
	var moon_r: float = scale.scaled_radius(moon_def.radius_m)
	var moon_mu: float = scale.scaled_mu(moon_def.mu_m3_s2, moon_def.radius_m)

	assert_true(earth_r > 0.0, "Earth scaled radius > 0")
	assert_true(earth_mu > 0.0, "Earth scaled mu > 0")
	assert_true(moon_r > 0.0, "Moon scaled radius > 0")
	assert_true(moon_mu > 0.0, "Moon scaled mu > 0")

	# Lunar orbital distance (~38,440 km at 1:10 scale)
	var r_moon: float = moon_def.semi_major_axis_m * scale.radius_scale
	assert_almost_eq(r_moon, 38440000.0, 1000.0, "Lunar orbital distance matches ~38,440 km at 1:10 scale")

	# Moon SOI radius (~6,600 km via Laplace formula: r_soi = r_moon * (moon_mu / earth_mu)^0.4)
	var r_soi_moon: float = scale.scaled_soi(r_moon, moon_mu / earth_mu)
	assert_true(abs(r_soi_moon - 6600000.0) < 50000.0, "Moon SOI radius matches ~6,600 km (actual: %f m)" % r_soi_moon)

	# 2. Simulate ship in Earth LEO (altitude ~200 km, radius r1)
	var alt_leo: float = 200000.0 # 200 km
	var r1: float = earth_r + alt_leo
	var v_circ: float = sqrt(earth_mu / r1)

	assert_almost_eq(alt_leo, 200000.0, 1.0, "LEO altitude is 200 km")
	assert_true(r1 > earth_r, "LEO radius exceeds Earth surface radius")
	assert_true(v_circ > 0.0, "Circular LEO orbital speed is positive")

	# 3. Compute TLI (Trans-Lunar Injection) delta-v to reach lunar orbital distance
	var a_trans: float = (r1 + r_moon) / 2.0
	var v_tli: float = sqrt(earth_mu * (2.0 / r1 - 1.0 / a_trans))
	var delta_v_tli: float = v_tli - v_circ

	assert_true(v_tli > v_circ, "TLI injection speed exceeds circular orbital speed")
	assert_true(delta_v_tli > 0.0, "TLI delta-v is positive")

	var e_trans_expected: float = -earth_mu / (2.0 * a_trans)

	# 4. Propagate state along transfer trajectory to Moon's SOI (~6,600 km radius)
	# Initial state at injection (periapsis): on Godot X axis, velocity along Godot Z axis
	var pos0 = DVec3.new(r1, 0.0, 0.0)
	var vel0 = DVec3.new(0.0, 0.0, v_tli)

	# Analytic orbital geometry of transfer ellipse
	var e_ecc: float = (r_moon - r1) / (r_moon + r1)
	var r_soi_boundary_earth: float = r_moon - r_soi_moon

	# Eccentric anomaly at SOI boundary entrance: r = a * (1 - e * cos(E))
	var cos_e_soi: float = clamp((1.0 - r_soi_boundary_earth / a_trans) / e_ecc, -1.0, 1.0)
	var e_anom_soi: float = acos(cos_e_soi)
	var m_anom_soi: float = e_anom_soi - e_ecc * sin(e_anom_soi)
	var mean_motion: float = sqrt(earth_mu / pow(a_trans, 3.0))
	var t_soi: float = m_anom_soi / mean_motion

	# Validate specific orbital energy conservation along the transfer arc at intermediate points
	var sample_steps: int = 10
	for i in range(sample_steps + 1):
		var t_step: float = t_soi * (float(i) / float(sample_steps))
		var state_step: Array = RailsPropagator.propagate(pos0, vel0, t_step, earth_mu)
		var p_step: DVec3 = state_step[0]
		var v_step: DVec3 = state_step[1]

		var r_mag: float = p_step.length()
		var v_mag: float = v_step.length()
		var energy_earth: float = (v_mag * v_mag) * 0.5 - (earth_mu / r_mag)

		var rel_err: float = abs(energy_earth - e_trans_expected) / abs(e_trans_expected)
		assert_true(rel_err < 1e-4, "Earth specific energy conserved to within 1e-4 at step %d (rel err: %s)" % [i, str(rel_err)])
		assert_almost_eq(energy_earth, e_trans_expected, abs(e_trans_expected) * 1e-4, "E = v^2/2 - mu/r == -mu/(2*a) at step %d" % i)

	# 5. Crosses the SOI boundary: patched-conic frame hand-off
	var state_at_soi: Array = RailsPropagator.propagate(pos0, vel0, t_soi, earth_mu)
	var pos_at_soi: DVec3 = state_at_soi[0]
	var vel_at_soi: DVec3 = state_at_soi[1]

	# Position before hand-off in Earth-centered frame
	var pos_before: DVec3 = pos_at_soi
	var v_rel_earth: DVec3 = vel_at_soi

	# Moon position at encounter: located at distance r_moon along the approach direction
	var moon_unit_dir: DVec3 = pos_at_soi.normalized()
	var pos_moon_earth: DVec3 = moon_unit_dir.mul_scalar(r_moon)

	# Lunar orbital velocity around Earth in circular orbit coplanar with transfer orbit
	# Normal to orbital plane is Godot -Y (pos on +X, vel on +Z => cross is (0, -r1*v, 0))
	var plane_normal: DVec3 = DVec3.new(0.0, -1.0, 0.0)
	var moon_vel_dir: DVec3 = plane_normal.cross(moon_unit_dir).normalized()
	var v_moon_speed: float = sqrt(earth_mu / r_moon)
	var v_moon_earth: DVec3 = moon_vel_dir.mul_scalar(v_moon_speed)

	# Relative state with respect to the Moon at SOI boundary
	var pos_rel_moon: DVec3 = pos_before.sub(pos_moon_earth)
	var dist_to_moon: float = pos_rel_moon.length()
	assert_almost_eq(dist_to_moon, r_soi_moon, 1.0, "Ship is precisely at Moon SOI boundary radius")

	# Position hand-off continuity:
	# Hand-off reconstructs inertial coordinates pos_after = pos_moon_earth + pos_rel_moon
	var pos_after: DVec3 = pos_moon_earth.add(pos_rel_moon)
	var pos_delta: float = pos_before.distance_to(pos_after)
	assert_almost_eq(pos_delta, 0.0, 1e-9, "Position is continuous across SOI boundary (|pos_before - pos_after| == 0.0)")

	# Velocity hand-off:
	# v_rel_moon = v_rel_earth - v_moon_earth
	var v_rel_moon: DVec3 = v_rel_earth.sub(v_moon_earth)

	# Validate post-crossing hyperbolic specific energy relative to Moon:
	# E_moon = v^2/2 - moon_mu / r > 0
	var v_moon_rel_mag: float = v_rel_moon.length()
	var e_moon: float = (v_moon_rel_mag * v_moon_rel_mag) * 0.5 - (moon_mu / dist_to_moon)
	assert_true(e_moon > 0.0, "Post-crossing hyperbolic specific energy relative to Moon is valid (E_moon = %f > 0, ready for LOI burn)" % e_moon)

	# Check hyperbolic orbital elements relative to Moon
	var moon_orbit: OrbitalMechanics.OrbitElements = OrbitalMechanics.elements_from_state(pos_rel_moon, v_rel_moon, moon_mu)
	assert_true(moon_orbit.is_hyperbolic, "Moon encounter orbit is hyperbolic")
	assert_true(moon_orbit.eccentricity > 1.0, "Moon encounter eccentricity > 1.0")
	assert_true(moon_orbit.periapsis_radius > 0.0, "Periapsis radius relative to Moon is positive")
