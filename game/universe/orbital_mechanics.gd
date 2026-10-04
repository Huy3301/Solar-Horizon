class_name OrbitalMechanics extends RefCounted

const DEFAULT_MU: float = 3.986004418e14
const EARTH_RADIUS: float = 6371000.0

# Frame convention: Godot is Y-up.
# Ecliptic has Z pointing North.
# To map Ecliptic (X, Y, Z_north) to Godot:
# Godot X = Ecliptic X
# Godot Y = Ecliptic Z_north
# Godot Z = -Ecliptic Y
static func ecliptic_to_godot(v_ecliptic: DVec3) -> DVec3:
	return DVec3.new(v_ecliptic.x, v_ecliptic.z, -v_ecliptic.y)

static func godot_to_ecliptic(v_godot: DVec3) -> DVec3:
	return DVec3.new(v_godot.x, -v_godot.z, v_godot.y)

class OrbitElements:
	var semi_major_axis: float = 0.0
	var eccentricity: float = 0.0
	var inclination_rad: float = 0.0
	var lan_rad: float = 0.0
	var arg_periapsis_rad: float = 0.0
	var true_anomaly_rad: float = 0.0
	var mean_anomaly_rad: float = 0.0
	var epoch: float = 0.0
	
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
	var dr = DVec3.from_vector3(r)
	var dv = DVec3.from_vector3(v)
	var elements = elements_from_state(dr, dv, mu)
	elements.periapsis_alt = elements.periapsis_radius - body_radius
	elements.apoapsis_alt = elements.apoapsis_radius - body_radius
	return elements

static func elements_from_state(r: DVec3, v: DVec3, mu: float) -> OrbitElements:
	var orbit = OrbitElements.new()
	var r_mag = r.length()
	var v_mag = v.length()
	
	if r_mag < 100.0 or v_mag < 0.1:
		return orbit
		
	var h = r.cross(v)
	var h_mag = h.length()
	orbit.h_vector = h.to_vector3()
	
	if h_mag < 0.001:
		return orbit
		
	var k_unit = DVec3.new(0, 1, 0)
	var n = k_unit.cross(h)
	var n_mag = n.length()
	
	var r_dot_v = r.dot(v)
	var e_vec = r.mul_scalar(v_mag * v_mag - mu / r_mag).sub(v.mul_scalar(r_dot_v)).div_scalar(mu)
	var e = e_vec.length()
	orbit.e_vector = e_vec.to_vector3()
	orbit.eccentricity = e
	
	var epsilon = (v_mag * v_mag) * 0.5 - (mu / r_mag)
	orbit.specific_energy = epsilon
	
	if abs(epsilon) > 1e-7:
		orbit.semi_major_axis = -mu / (2.0 * epsilon)
	else:
		orbit.semi_major_axis = 1e12
		
	var a = orbit.semi_major_axis
	
	orbit.periapsis_radius = a * (1.0 - e)
	
	if e < 1.0:
		orbit.is_closed_orbit = true
		orbit.is_hyperbolic = false
		orbit.apoapsis_radius = a * (1.0 + e)
		if a > 0:
			orbit.period_seconds = 2.0 * PI * sqrt(pow(a, 3.0) / mu)
	else:
		orbit.is_closed_orbit = false
		orbit.is_hyperbolic = true
		orbit.apoapsis_radius = -1.0
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
		if r_dot_v < 0:
			orbit.true_anomaly_rad = 2.0 * PI - orbit.true_anomaly_rad
	else:
		orbit.true_anomaly_rad = 0.0
	
	var nu = orbit.true_anomaly_rad
	if e < 1.0:
		var EA = 2.0 * atan(sqrt((1.0 - e)/(1.0 + e)) * tan(nu / 2.0))
		orbit.mean_anomaly_rad = EA - e * sin(EA)
	else:
		var F = 2.0 * atanh(sqrt((e - 1.0)/(e + 1.0)) * tan(nu / 2.0))
		orbit.mean_anomaly_rad = e * sinh(F) - F
		
	return orbit

static func solve_kepler(M: float, e: float) -> float:
	M = fmod(M, 2.0 * PI)
	if M < 0:
		M += 2.0 * PI
	var E = M
	if e > 0.8:
		E = PI
	var max_iter = 100
	var tol = 1e-12
	for i in range(max_iter):
		var dE = (E - e * sin(E) - M) / (1.0 - e * cos(E))
		E -= dE
		if abs(dE) < tol:
			break
	return E

static func solve_kepler_hyperbolic(M: float, e: float) -> float:
	var F = M
	var max_iter = 100
	var tol = 1e-12
	for i in range(max_iter):
		var dF = (e * sinh(F) - F - M) / (e * cosh(F) - 1.0)
		F -= dF
		if abs(dF) < tol:
			break
	return F

static func state_from_elements(elements: OrbitElements, mu: float, t_seconds_since_epoch: float) -> Array:
	var a = elements.semi_major_axis
	var e = elements.eccentricity
	var M = elements.mean_anomaly_rad
	
	if elements.period_seconds > 0:
		var n = sqrt(mu / pow(a, 3.0))
		M += n * t_seconds_since_epoch
	elif e > 1.0:
		var n = sqrt(mu / pow(-a, 3.0))
		M += n * t_seconds_since_epoch
		
	var nu = 0.0
	var r_mag = 0.0
	
	if e < 1.0:
		var E = solve_kepler(M, e)
		nu = 2.0 * atan(sqrt((1.0 + e)/(1.0 - e)) * tan(E / 2.0))
		r_mag = a * (1.0 - e * cos(E))
	else:
		var F = solve_kepler_hyperbolic(M, e)
		nu = 2.0 * atan(sqrt((e + 1.0)/(e - 1.0)) * tanh(F / 2.0))
		r_mag = a * (1.0 - e * cosh(F))
		if r_mag < 0: r_mag = -r_mag
		
	var p = a * (1.0 - e * e)
	var h_mag = sqrt(mu * p)
	
	var r_orb = DVec3.new(r_mag * cos(nu), r_mag * sin(nu), 0.0)
	var v_orb = DVec3.new(-mu / h_mag * sin(nu), mu / h_mag * (e + cos(nu)), 0.0)
	
	var inc = elements.inclination_rad
	var lan = elements.lan_rad
	var arg_p = elements.arg_periapsis_rad
	
	# Rotations
	var r_ecliptic = _rotate_orb_to_ecliptic(r_orb, lan, inc, arg_p)
	var v_ecliptic = _rotate_orb_to_ecliptic(v_orb, lan, inc, arg_p)
	
	return [ecliptic_to_godot(r_ecliptic), ecliptic_to_godot(v_ecliptic)]

static func _rotate_orb_to_ecliptic(v: DVec3, lan: float, inc: float, arg_p: float) -> DVec3:
	# arg_p around Z
	var x1 = v.x * cos(arg_p) - v.y * sin(arg_p)
	var y1 = v.x * sin(arg_p) + v.y * cos(arg_p)
	var z1 = v.z
	
	# inc around X
	var y2 = y1 * cos(inc) - z1 * sin(inc)
	var z2 = y1 * sin(inc) + z1 * cos(inc)
	var x2 = x1
	
	# lan around Z
	var x3 = x2 * cos(lan) - y2 * sin(lan)
	var y3 = x2 * sin(lan) + y2 * cos(lan)
	var z3 = z2
	
	return DVec3.new(x3, y3, z3)

static func propagate(elements: OrbitElements, mu: float, dt: float) -> Array:
	return state_from_elements(elements, mu, dt)

static func sample_orbit_points(elements: OrbitElements, n: int) -> Array[DVec3]:
	var points: Array[DVec3] = []
	var a = elements.semi_major_axis
	var e = elements.eccentricity
	var p = a * (1.0 - e * e)
	
	var start_nu = 0.0
	var end_nu = 2.0 * PI
	
	if e > 1.0:
		var max_nu = acos(-1.0 / e) * 0.85
		start_nu = -max_nu
		end_nu = max_nu
		
	var step = (end_nu - start_nu) / float(n)
	var inc = elements.inclination_rad
	var lan = elements.lan_rad
	var arg_p = elements.arg_periapsis_rad
	
	for i in range(n + 1):
		var nu = start_nu + float(i) * step
		var r_mag = p / (1.0 + e * cos(nu))
		if r_mag > 0:
			var r_orb = DVec3.new(r_mag * cos(nu), r_mag * sin(nu), 0.0)
			var r_ecliptic = _rotate_orb_to_ecliptic(r_orb, lan, inc, arg_p)
			points.append(ecliptic_to_godot(r_ecliptic))
			
	return points

static func generate_trajectory_path(orbit: OrbitElements, num_segments: int = 128) -> PackedVector3Array:
	var points = PackedVector3Array()
	var samples = sample_orbit_points(orbit, num_segments)
	for s in samples:
		points.append(s.to_vector3())
	return points
