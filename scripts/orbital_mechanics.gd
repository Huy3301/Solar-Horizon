extends RefCounted
class_name OrbitalMechanics

const DEFAULT_MU: float = 3.986004418e14
const EARTH_RADIUS: float = 6371000.0

class OrbitElements:
	var semi_major_axis: float = 0.0
	var eccentricity: float = 0.0
	var inclination_rad: float = 0.0
	var lan_rad: float = 0.0
	var arg_periapsis_rad: float = 0.0
	var true_anomaly_rad: float = 0.0
	var periapsis_radius: float = 0.0
	var apoapsis_radius: float = 0.0
	var periapsis_alt: float = 0.0
	var apoapsis_alt: float = 0.0
	var period_seconds: float = 0.0
	var specific_energy: float = 0.0
	var is_closed_orbit: bool = true
	var is_hyperbolic: bool = false
	var h_vector: Vector3 = Vector3.ZERO
	var e_vector: Vector3 = Vector3.ZERO

static func calculate_orbit(r: Vector3, v: Vector3, mu: float = DEFAULT_MU, body_radius: float = EARTH_RADIUS) -> OrbitElements:
	var orbit: OrbitElements = OrbitElements.new()
	var r_mag: float = r.length()
	var v_mag: float = v.length()
	
	if r_mag < 100.0 or v_mag < 0.1:
		return orbit
		
	var h: Vector3 = r.cross(v)
	var h_mag: float = h.length()
	orbit.h_vector = h
	
	if h_mag < 0.001:
		return orbit
		
	var k_unit: Vector3 = Vector3.UP
	var n: Vector3 = k_unit.cross(h)
	var n_mag: float = n.length()
	
	var e_vec: Vector3 = ((v_mag * v_mag - mu / r_mag) * r - (r.dot(v)) * v) / mu
	var e: float = e_vec.length()
	orbit.e_vector = e_vec
	orbit.eccentricity = e
	
	var epsilon: float = (v_mag * v_mag) * 0.5 - (mu / r_mag)
	orbit.specific_energy = epsilon
	
	if abs(epsilon) > 1e-7:
		orbit.semi_major_axis = -mu / (2.0 * epsilon)
	else:
		orbit.semi_major_axis = 1e12
		
	orbit.periapsis_radius = orbit.semi_major_axis * (1.0 - e)
	orbit.periapsis_alt = orbit.periapsis_radius - body_radius
	
	if e < 1.0:
		orbit.is_closed_orbit = true
		orbit.is_hyperbolic = false
		orbit.apoapsis_radius = orbit.semi_major_axis * (1.0 + e)
		orbit.apoapsis_alt = orbit.apoapsis_radius - body_radius
		if orbit.semi_major_axis > 0:
			orbit.period_seconds = 2.0 * PI * sqrt(pow(orbit.semi_major_axis, 3.0) / mu)
	else:
		orbit.is_closed_orbit = false
		orbit.is_hyperbolic = true
		orbit.apoapsis_radius = -1.0
		orbit.apoapsis_alt = -1.0
		orbit.period_seconds = -1.0
		
	orbit.inclination_rad = acos(clamp(h.y / h_mag, -1.0, 1.0))
	
	if n_mag > 1e-5:
		orbit.lan_rad = acos(clamp(n.x / n_mag, -1.0, 1.0))
		if n.z < 0:
			orbit.lan_rad = 2.0 * PI - orbit.lan_rad
	else:
		orbit.lan_rad = 0.0
		
	if n_mag > 1e-5 and e > 1e-5:
		orbit.arg_periapsis_rad = acos(clamp(n.dot(e_vec) / (n_mag * e), -1.0, 1.0))
		if e_vec.y < 0:
			orbit.arg_periapsis_rad = 2.0 * PI - orbit.arg_periapsis_rad
	else:
		orbit.arg_periapsis_rad = 0.0
		
	if e > 1e-5:
		orbit.true_anomaly_rad = acos(clamp(e_vec.dot(r) / (e * r_mag), -1.0, 1.0))
		if r.dot(v) < 0:
			orbit.true_anomaly_rad = 2.0 * PI - orbit.true_anomaly_rad
	else:
		orbit.true_anomaly_rad = 0.0
		
	return orbit

static func generate_trajectory_path(orbit: OrbitElements, num_segments: int = 128) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	if orbit.semi_major_axis <= 0 or orbit.h_vector.length() < 0.01:
		return points
		
	var a: float = orbit.semi_major_axis
	var e: float = orbit.eccentricity
	var p: float = a * (1.0 - e * e)
	
	var start_nu: float = 0.0
	var end_nu: float = 2.0 * PI
	
	if orbit.is_hyperbolic:
		var max_nu: float = acos(-1.0 / e) * 0.85
		start_nu = -max_nu
		end_nu = max_nu
		
	var step: float = (end_nu - start_nu) / float(num_segments)
	
	var p_unit: Vector3
	if e > 1e-4:
		p_unit = orbit.e_vector.normalized()
	else:
		p_unit = Vector3.RIGHT
		
	var w_unit: Vector3 = orbit.h_vector.normalized()
	var q_unit: Vector3 = w_unit.cross(p_unit).normalized()
	
	for i in range(num_segments + 1):
		var nu: float = start_nu + float(i) * step
		var r: float = p / (1.0 + e * cos(nu))
		if r > 0 and r < 1e12:
			var point: Vector3 = (p_unit * cos(nu) + q_unit * sin(nu)) * r
			points.append(point)
			
	return points
