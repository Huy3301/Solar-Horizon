class_name CelestialCoordinates extends RefCounted

const ADELAIDE_LAT_DEG: float = -34.9285
const ADELAIDE_LON_DEG: float = 138.6007
const ADELAIDE_ALT_M: float = 50.0
const EARTH_AXIAL_TILT_RAD: float = deg_to_rad(23.439281)
const EARTH_SIDEREAL_DAY_SEC: float = 86164.0905

## Calculate Greenwich Mean Sidereal Time in radians [0, TAU) advancing TAU per sidereal day.
static func calculate_gmst_rad(sim_time_sec: float) -> float:
	return fposmod((sim_time_sec / EARTH_SIDEREAL_DAY_SEC) * TAU, TAU)

## Calculate Local Mean Sidereal Time in radians [0, TAU) for a given longitude in degrees.
static func calculate_lmst_rad(sim_time_sec: float, lon_deg: float) -> float:
	var gmst: float = calculate_gmst_rad(sim_time_sec)
	return fposmod(gmst + deg_to_rad(lon_deg), TAU)

## Convert ecliptic position to equatorial position by rotating around the X axis by obliquity.
static func ecliptic_to_equatorial(r_ecliptic: DVec3, obliquity: float = EARTH_AXIAL_TILT_RAD) -> DVec3:
	var cos_obl: float = cos(obliquity)
	var sin_obl: float = sin(obliquity)
	return DVec3.new(
		r_ecliptic.x,
		r_ecliptic.y * cos_obl - r_ecliptic.z * sin_obl,
		r_ecliptic.y * sin_obl + r_ecliptic.z * cos_obl
	)

## Convert equatorial position to ecliptic position via inverse rotation around the X axis.
static func equatorial_to_ecliptic(r_equatorial: DVec3, obliquity: float = EARTH_AXIAL_TILT_RAD) -> DVec3:
	var cos_obl: float = cos(obliquity)
	var sin_obl: float = sin(obliquity)
	return DVec3.new(
		r_equatorial.x,
		r_equatorial.y * cos_obl + r_equatorial.z * sin_obl,
		-r_equatorial.y * sin_obl + r_equatorial.z * cos_obl
	)

## Convert equatorial position vector to topocentric horizontal coordinates (azimuth, elevation, local direction).
## Returns Dictionary with:
## - "azimuth_deg": float (0=North, 90=East)
## - "elevation_deg": float (-90 to +90)
## - "zenith_angle_deg": float
## - "local_dir": Vector3 (X=East, Y=Up, Z=South)
static func equatorial_to_horizontal(r_equatorial: DVec3, lat_deg: float, lmst_rad: float) -> Dictionary:
	var length: float = r_equatorial.length()
	if length == 0.0:
		return {
			"azimuth_deg": 0.0,
			"elevation_deg": 0.0,
			"zenith_angle_deg": 90.0,
			"local_dir": Vector3.ZERO
		}

	var rx: float = r_equatorial.x / length
	var ry: float = r_equatorial.y / length
	var rz: float = r_equatorial.z / length

	var phi: float = deg_to_rad(lat_deg)
	var sin_phi: float = sin(phi)
	var cos_phi: float = cos(phi)
	var sin_lmst: float = sin(lmst_rad)
	var cos_lmst: float = cos(lmst_rad)

	# Orthonormal topocentric horizon frame:
	# East:  (-sin(lmst), cos(lmst), 0)
	# Up:    (cos(phi)*cos(lmst), cos(phi)*sin(lmst), sin(phi))
	# South: (sin(phi)*cos(lmst), sin(phi)*sin(lmst), -cos(phi))
	# (North is -South)
	var x_east: float = -rx * sin_lmst + ry * cos_lmst
	var y_up: float = rx * cos_phi * cos_lmst + ry * cos_phi * sin_lmst + rz * sin_phi
	var z_south: float = rx * sin_phi * cos_lmst + ry * sin_phi * sin_lmst - rz * cos_phi

	var local_dir: Vector3 = Vector3(x_east, y_up, z_south)

	var el_rad: float = asin(clampf(y_up, -1.0, 1.0))
	var elevation_deg: float = rad_to_deg(el_rad)
	var zenith_angle_deg: float = 90.0 - elevation_deg

	var north_comp: float = -z_south
	var east_comp: float = x_east
	var azimuth_deg: float = 0.0
	if not (is_zero_approx(north_comp) and is_zero_approx(east_comp)):
		var az_rad: float = atan2(east_comp, north_comp)
		if az_rad < 0.0:
			az_rad += TAU
		azimuth_deg = rad_to_deg(az_rad)
		if azimuth_deg >= 360.0:
			azimuth_deg = 0.0

	return {
		"azimuth_deg": azimuth_deg,
		"elevation_deg": elevation_deg,
		"zenith_angle_deg": zenith_angle_deg,
		"local_dir": local_dir
	}

## Convenience function computing Sun's topocentric azimuth and elevation over Adelaide.
static func adelaide_sun_direction(sun_ecliptic_pos: DVec3, sim_time_sec: float) -> Dictionary:
	var r_equatorial: DVec3 = ecliptic_to_equatorial(sun_ecliptic_pos)
	var lmst_rad: float = calculate_lmst_rad(sim_time_sec, ADELAIDE_LON_DEG)
	return equatorial_to_horizontal(r_equatorial, ADELAIDE_LAT_DEG, lmst_rad)

## Convenience function computing Moon's topocentric azimuth and elevation over Adelaide.
static func adelaide_moon_direction(moon_ecliptic_pos: DVec3, sim_time_sec: float) -> Dictionary:
	var r_equatorial: DVec3 = ecliptic_to_equatorial(moon_ecliptic_pos)
	var lmst_rad: float = calculate_lmst_rad(sim_time_sec, ADELAIDE_LON_DEG)
	return equatorial_to_horizontal(r_equatorial, ADELAIDE_LAT_DEG, lmst_rad)
