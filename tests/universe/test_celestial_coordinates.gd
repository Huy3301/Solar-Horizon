extends "res://tests/test_case.gd"

const CelestialCoordinates = preload("res://game/universe/celestial_coordinates.gd")

func test_gmst_advances_tau_in_sidereal_day() -> void:
	var t0: float = 0.0
	var t_quarter: float = CelestialCoordinates.EARTH_SIDEREAL_DAY_SEC * 0.25
	var t_half: float = CelestialCoordinates.EARTH_SIDEREAL_DAY_SEC * 0.5
	var t_three_quarters: float = CelestialCoordinates.EARTH_SIDEREAL_DAY_SEC * 0.75
	var t_full: float = CelestialCoordinates.EARTH_SIDEREAL_DAY_SEC

	var gmst_0: float = CelestialCoordinates.calculate_gmst_rad(t0)
	var gmst_q: float = CelestialCoordinates.calculate_gmst_rad(t_quarter)
	var gmst_h: float = CelestialCoordinates.calculate_gmst_rad(t_half)
	var gmst_tq: float = CelestialCoordinates.calculate_gmst_rad(t_three_quarters)
	var gmst_f: float = CelestialCoordinates.calculate_gmst_rad(t_full)

	assert_almost_eq(gmst_0, 0.0, 1e-6, "GMST at t=0 should be 0")
	assert_almost_eq(gmst_q, TAU * 0.25, 1e-6, "GMST at 0.25 day should be TAU/4")
	assert_almost_eq(gmst_h, TAU * 0.5, 1e-6, "GMST at 0.5 day should be TAU/2")
	assert_almost_eq(gmst_tq, TAU * 0.75, 1e-6, "GMST at 0.75 day should be 3*TAU/4")
	assert_almost_eq(gmst_f, 0.0, 1e-6, "GMST at 1.0 sidereal day completes full revolution and wraps to 0")

	# Progression rate: d(GMST)/dt * sidereal_day = TAU
	var rate: float = (gmst_h - gmst_0) / (t_half - t0)
	assert_almost_eq(rate * CelestialCoordinates.EARTH_SIDEREAL_DAY_SEC, TAU, 1e-6, "GMST advancement rate across one sidereal day is TAU")

	# Local Mean Sidereal Time (LMST) offsets
	var lmst_greenwich: float = CelestialCoordinates.calculate_lmst_rad(t_quarter, 0.0)
	assert_almost_eq(lmst_greenwich, gmst_q, 1e-6, "LMST at Greenwich equals GMST")

	var lmst_east90: float = CelestialCoordinates.calculate_lmst_rad(t0, 90.0)
	assert_almost_eq(lmst_east90, TAU * 0.25, 1e-6, "LMST at 90 deg East starts at TAU/4")

	var lmst_west90: float = CelestialCoordinates.calculate_lmst_rad(t0, -90.0)
	assert_almost_eq(lmst_west90, TAU * 0.75, 1e-6, "LMST at 90 deg West starts at 3*TAU/4")

func test_ecliptic_equatorial_round_trip() -> void:
	var test_vectors: Array[DVec3] = [
		DVec3.new(1.0, 0.0, 0.0),
		DVec3.new(0.0, 1.0, 0.0),
		DVec3.new(0.0, 0.0, 1.0),
		DVec3.new(-1.0, 0.0, 0.0),
		DVec3.new(0.0, -1.0, 0.0),
		DVec3.new(0.0, 0.0, -1.0),
		DVec3.new(1.4959787e11, 0.0, 0.0), # 1 AU
		DVec3.new(0.0, 3.844e8, 0.0),      # Lunar distance
		DVec3.new(-12345.67, 89012.34, -45678.90),
		DVec3.new(0.57735027, 0.57735027, 0.57735027)
	]

	for v in test_vectors:
		var orig_len: float = v.length()
		var r_eq: DVec3 = CelestialCoordinates.ecliptic_to_equatorial(v)
		var eq_len: float = r_eq.length()
		assert_almost_eq(eq_len, orig_len, 1e-6 * maxf(1.0, orig_len), "Length preserved in ecliptic to equatorial")

		var r_ecl: DVec3 = CelestialCoordinates.equatorial_to_ecliptic(r_eq)
		var back_len: float = r_ecl.length()
		assert_almost_eq(back_len, orig_len, 1e-6 * maxf(1.0, orig_len), "Length preserved in round trip")

		var scale: float = maxf(1.0, orig_len)
		assert_almost_eq(r_ecl.x, v.x, 1e-6 * scale, "Round-trip X coordinate matches within 1e-6")
		assert_almost_eq(r_ecl.y, v.y, 1e-6 * scale, "Round-trip Y coordinate matches within 1e-6")
		assert_almost_eq(r_ecl.z, v.z, 1e-6 * scale, "Round-trip Z coordinate matches within 1e-6")

	# Physical sanity check: summer solstice in ecliptic (0, 1, 0) tilts North by obliquity
	var solstice_ecl = DVec3.new(0.0, 1.0, 0.0)
	var solstice_eq = CelestialCoordinates.ecliptic_to_equatorial(solstice_ecl)
	assert_almost_eq(solstice_eq.x, 0.0, 1e-6)
	assert_almost_eq(solstice_eq.y, cos(CelestialCoordinates.EARTH_AXIAL_TILT_RAD), 1e-6)
	assert_almost_eq(solstice_eq.z, sin(CelestialCoordinates.EARTH_AXIAL_TILT_RAD), 1e-6)

func test_adelaide_sun_elevation_at_local_noon_vernal_equinox() -> void:
	# At vernal equinox, Sun ecliptic position is along +X
	var sun_ecliptic: DVec3 = DVec3.new(1.4959787e11, 0.0, 0.0)
	var sun_equatorial: DVec3 = CelestialCoordinates.ecliptic_to_equatorial(sun_ecliptic)

	# Local noon at vernal equinox corresponds to LMST = 0
	var horizontal_noon: Dictionary = CelestialCoordinates.equatorial_to_horizontal(
		sun_equatorial,
		CelestialCoordinates.ADELAIDE_LAT_DEG,
		0.0
	)

	var expected_elevation: float = 90.0 - absf(CelestialCoordinates.ADELAIDE_LAT_DEG)
	var actual_elevation: float = horizontal_noon["elevation_deg"]
	assert_almost_eq(actual_elevation, expected_elevation, 1e-5, "Sun elevation at noon vernal equinox equals 90 - abs(lat)")

	var expected_zenith: float = absf(CelestialCoordinates.ADELAIDE_LAT_DEG)
	assert_almost_eq(horizontal_noon["zenith_angle_deg"], expected_zenith, 1e-5, "Zenith angle equals observer latitude magnitude")

	# In Adelaide (Southern Hemisphere: lat -34.93 deg), Sun is due North at local noon (Azimuth = 0)
	assert_almost_eq(horizontal_noon["azimuth_deg"], 0.0, 1e-5, "Sun azimuth at noon in Southern Hemisphere is due North (0 deg)")

	# Verify through adelaide_sun_direction at sim_time_sec corresponding to Adelaide local noon
	# LMST = GMST + lon = 0  =>  GMST = TAU - deg_to_rad(lon)
	var sim_time_noon: float = (1.0 - CelestialCoordinates.ADELAIDE_LON_DEG / 360.0) * CelestialCoordinates.EARTH_SIDEREAL_DAY_SEC
	var lmst_at_noon: float = CelestialCoordinates.calculate_lmst_rad(sim_time_noon, CelestialCoordinates.ADELAIDE_LON_DEG)
	assert_almost_eq(lmst_at_noon, 0.0, 1e-6, "Calculated sim_time produces local noon (LMST = 0)")

	var adelaide_noon: Dictionary = CelestialCoordinates.adelaide_sun_direction(sun_ecliptic, sim_time_noon)
	assert_almost_eq(adelaide_noon["elevation_deg"], expected_elevation, 1e-5, "adelaide_sun_direction elevation matches 90 - abs(lat)")
	assert_almost_eq(adelaide_noon["azimuth_deg"], 0.0, 1e-5, "adelaide_sun_direction azimuth matches 0 deg (North)")

	var local_dir: Vector3 = adelaide_noon["local_dir"]
	assert_almost_eq(local_dir.length(), 1.0, 1e-5, "Local dir vector is normalized")
	assert_almost_eq(local_dir.x, 0.0, 1e-5, "No East/West component at solar noon")
	assert_almost_eq(local_dir.y, sin(deg_to_rad(expected_elevation)), 1e-5, "Y matches sin(elevation)")
	# North is -Z, so Z should be -cos(elevation)
	assert_almost_eq(local_dir.z, -cos(deg_to_rad(expected_elevation)), 1e-5, "Z matches -cos(elevation) for North direction")

func test_horizontal_coordinates_validity_and_normalization() -> void:
	# Equator observer (lat = 0) at LMST = 0:
	# Up is +X, East is +Y, North is +Z, South is -Z (in equatorial)
	var lat_zero: float = 0.0
	var lmst_zero: float = 0.0

	# Due North horizon test: r_eq = (0, 0, 1) -> North (+Z_eq)
	var r_north: DVec3 = DVec3.new(0.0, 0.0, 1.0)
	var res_north: Dictionary = CelestialCoordinates.equatorial_to_horizontal(r_north, lat_zero, lmst_zero)
	assert_almost_eq(res_north["azimuth_deg"], 0.0, 1e-5, "North azimuth is 0 deg")
	assert_almost_eq(res_north["elevation_deg"], 0.0, 1e-5, "North horizon elevation is 0 deg")
	assert_vec_almost_eq(res_north["local_dir"], Vector3(0.0, 0.0, -1.0), 1e-5, "North local dir points towards -Z")

	# Due South horizon test: r_eq = (0, 0, -1) -> South (-Z_eq)
	var r_south: DVec3 = DVec3.new(0.0, 0.0, -1.0)
	var res_south: Dictionary = CelestialCoordinates.equatorial_to_horizontal(r_south, lat_zero, lmst_zero)
	assert_almost_eq(res_south["azimuth_deg"], 180.0, 1e-5, "South azimuth is 180 deg")
	assert_almost_eq(res_south["elevation_deg"], 0.0, 1e-5, "South horizon elevation is 0 deg")
	assert_vec_almost_eq(res_south["local_dir"], Vector3(0.0, 0.0, 1.0), 1e-5, "South local dir points towards +Z")

	# Due East horizon test: r_eq = (0, 1, 0) -> East (+Y_eq)
	var r_east: DVec3 = DVec3.new(0.0, 1.0, 0.0)
	var res_east: Dictionary = CelestialCoordinates.equatorial_to_horizontal(r_east, lat_zero, lmst_zero)
	assert_almost_eq(res_east["azimuth_deg"], 90.0, 1e-5, "East azimuth is 90 deg")
	assert_almost_eq(res_east["elevation_deg"], 0.0, 1e-5, "East horizon elevation is 0 deg")
	assert_vec_almost_eq(res_east["local_dir"], Vector3(1.0, 0.0, 0.0), 1e-5, "East local dir points towards +X")

	# Due West horizon test: r_eq = (0, -1, 0) -> West (-Y_eq)
	var r_west: DVec3 = DVec3.new(0.0, -1.0, 0.0)
	var res_west: Dictionary = CelestialCoordinates.equatorial_to_horizontal(r_west, lat_zero, lmst_zero)
	assert_almost_eq(res_west["azimuth_deg"], 270.0, 1e-5, "West azimuth is 270 deg")
	assert_almost_eq(res_west["elevation_deg"], 0.0, 1e-5, "West horizon elevation is 0 deg")
	assert_vec_almost_eq(res_west["local_dir"], Vector3(-1.0, 0.0, 0.0), 1e-5, "West local dir points towards -X")

	# Zenith test: r_eq = (1, 0, 0) -> Zenith (+X_eq)
	var r_zenith: DVec3 = DVec3.new(1.0, 0.0, 0.0)
	var res_zenith: Dictionary = CelestialCoordinates.equatorial_to_horizontal(r_zenith, lat_zero, lmst_zero)
	assert_almost_eq(res_zenith["elevation_deg"], 90.0, 1e-5, "Zenith elevation is 90 deg")
	assert_almost_eq(res_zenith["zenith_angle_deg"], 0.0, 1e-5, "Zenith angle is 0 deg")
	assert_vec_almost_eq(res_zenith["local_dir"], Vector3(0.0, 1.0, 0.0), 1e-5, "Zenith local dir points towards +Y")

	# Test sweep across multiple latitudes, hour angles, and celestial coordinates
	var lats: Array[float] = [-80.0, -34.9285, 0.0, 37.7749, 51.5074, 85.0]
	var times: Array[float] = [0.0, 12000.0, 43200.0, 60000.0, 86164.0]
	var targets: Array[DVec3] = [
		DVec3.new(1.0, 2.0, 3.0),
		DVec3.new(-4.0, 1.5, -2.5),
		DVec3.new(10.0, -8.0, 6.0)
	]

	for lat in lats:
		for t in times:
			var lmst = CelestialCoordinates.calculate_lmst_rad(t, 138.6007)
			for tgt in targets:
				var res = CelestialCoordinates.equatorial_to_horizontal(tgt, lat, lmst)
				var az: float = res["azimuth_deg"]
				var el: float = res["elevation_deg"]
				var zen: float = res["zenith_angle_deg"]
				var dir: Vector3 = res["local_dir"]

				assert_true(az >= 0.0 and az < 360.0, "Azimuth in [0, 360)")
				assert_true(el >= -90.0 and el <= 90.0, "Elevation in [-90, +90]")
				assert_almost_eq(az + zen - az, zen, 1e-5) # dummy check
				assert_almost_eq(zen + el, 90.0, 1e-5, "Zenith angle + Elevation = 90 deg")
				assert_almost_eq(dir.length(), 1.0, 1e-5, "Local dir vector is normalized")

				# Reconstructed direction matches local_dir
				var el_r = deg_to_rad(el)
				var az_r = deg_to_rad(az)
				var expected_recon = Vector3(
					cos(el_r) * sin(az_r),
					sin(el_r),
					-cos(el_r) * cos(az_r)
				)
				assert_vec_almost_eq(dir, expected_recon, 1e-4, "Local direction vector components match Az/El spherical coords")

	# Test adelaide_moon_direction convenience function
	var moon_ecl: DVec3 = DVec3.new(0.0, 3.844e8, 0.0)
	var moon_dict: Dictionary = CelestialCoordinates.adelaide_moon_direction(moon_ecl, 25000.0)
	assert_true(moon_dict.has("azimuth_deg"))
	assert_true(moon_dict.has("elevation_deg"))
	assert_true(moon_dict.has("zenith_angle_deg"))
	assert_true(moon_dict.has("local_dir"))
	assert_almost_eq(moon_dict["local_dir"].length(), 1.0, 1e-5, "adelaide_moon_direction local_dir is normalized")

	# Zero length vector edge case returns zero dir
	var zero_dict: Dictionary = CelestialCoordinates.equatorial_to_horizontal(DVec3.zero(), 0.0, 0.0)
	assert_eq(zero_dict["local_dir"], Vector3.ZERO, "Zero equatorial vector yields ZERO local_dir")
