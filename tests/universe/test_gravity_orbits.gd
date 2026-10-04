extends "res://tests/test_case.gd"

func test_leo_circular_orbit_10_orbits() -> void:
	var earth_pos = GravityService.body_position("Earth", 0.0)
	var earth_r = GravityService.get_body_scaled_radius("Earth")
	var earth_mu = GravityService.get_body_scaled_mu("Earth")
	
	assert_true(earth_r > 0.0, "Earth scaled radius > 0")
	assert_true(earth_mu > 0.0, "Earth scaled mu > 0")
	
	# LEO altitude: 200 km
	var alt = 200000.0
	var r0 = earth_r + alt
	var v_circ = sqrt(earth_mu / r0)
	var period = 2.0 * PI * sqrt(pow(r0, 3.0) / earth_mu)
	
	# Initial state: on Godot X axis, velocity along Godot Z axis
	var pos = earth_pos.add(DVec3.new(r0, 0.0, 0.0))
	var vel = DVec3.new(0.0, 0.0, v_circ)
	
	# Integrate 10 full orbits using Velocity Verlet
	var dt = 2.0 # seconds
	var total_time = period * 10.0
	var steps = int(total_time / dt)
	
	var r_min = r0
	var r_max = r0
	
	var acc = GravityService.gravity_accel(pos, 0.0)
	for step in range(steps):
		# Half-step velocity
		vel.add_in_place(acc.mul_scalar(dt * 0.5))
		# Full-step position
		pos.add_in_place(vel.mul_scalar(dt))
		# New acceleration
		acc = GravityService.gravity_accel(pos, 0.0)
		# Half-step velocity
		vel.add_in_place(acc.mul_scalar(dt * 0.5))
		
		var current_r = pos.distance_to(earth_pos)
		if current_r < r_min:
			r_min = current_r
		if current_r > r_max:
			r_max = current_r
			
	var final_r = pos.distance_to(earth_pos)
	var final_drift = abs(final_r - r0) / r0
	var max_drift = max(abs(r_max - r0), abs(r_min - r0)) / r0
	
	# Acceptance criteria: < 0.5% drift over 10 orbits
	assert_true(final_drift < 0.005, "10-orbit final radius drift %.4f%% < 0.5%%" % [final_drift * 100.0])
	assert_true(max_drift < 0.005, "10-orbit max radius drift %.4f%% < 0.5%%" % [max_drift * 100.0])

func test_escape_velocity() -> void:
	var earth_pos = GravityService.body_position("Earth", 0.0)
	var earth_r = GravityService.get_body_scaled_radius("Earth")
	var earth_mu = GravityService.get_body_scaled_mu("Earth")
	
	var r0 = earth_r + 100000.0 # 100 km altitude
	var v_esc = sqrt(2.0 * earth_mu / r0)
	
	# Sub-orbital energy
	var v_sub = v_esc * 0.8
	var eps_sub = 0.5 * v_sub * v_sub - earth_mu / r0
	assert_true(eps_sub < 0.0, "Sub-escape velocity has negative specific orbital energy (bound)")
	
	# Escape energy
	var eps_esc = 0.5 * v_esc * v_esc - earth_mu / r0
	assert_almost_eq(eps_esc, 0.0, 1e-3, "Escape velocity has zero specific orbital energy (parabolic)")
	
	# Hyperbolic energy
	var v_hyp = v_esc * 1.2
	var eps_hyp = 0.5 * v_hyp * v_hyp - earth_mu / r0
	assert_true(eps_hyp > 0.0, "Hyperbolic velocity has positive specific orbital energy (unbound)")
	
	# Radial escape propagation: particle never falls back
	var pos = earth_pos.add(DVec3.new(r0, 0.0, 0.0))
	var vel = DVec3.new(v_esc, 0.0, 0.0)
	var dt = 10.0
	var prev_r = r0
	
	for i in range(100):
		var acc = GravityService.gravity_accel(pos, 0.0)
		vel.add_in_place(acc.mul_scalar(dt * 0.5))
		pos.add_in_place(vel.mul_scalar(dt))
		var new_acc = GravityService.gravity_accel(pos, 0.0)
		vel.add_in_place(new_acc.mul_scalar(dt * 0.5))
		
		var curr_r = pos.distance_to(earth_pos)
		assert_true(curr_r > prev_r, "Escaping particle distance strictly increases (radial outward)")
		prev_r = curr_r

func test_soi_earth_moon_continuity() -> void:
	var earth_pos = GravityService.body_position("Earth", 0.0)
	var moon_pos = GravityService.body_position("Moon", 0.0)
	var moon_soi = GravityService.get_soi_radius("Moon")
	
	assert_true(moon_soi > 0.0 and moon_soi < INF, "Moon SOI radius is valid and finite")
	
	var dir_to_earth = earth_pos.sub(moon_pos).normalized()
	
	# Just inside Moon SOI (100m inside boundary)
	var pos_inside_moon = moon_pos.add(dir_to_earth.mul_scalar(moon_soi - 100.0))
	var dom_inside = GravityService.dominant_body(pos_inside_moon, 0.0)
	assert_eq(dom_inside, &"Moon", "Dominant body inside Moon SOI is Moon")
	
	# Just outside Moon SOI (100m outside boundary)
	var pos_outside_moon = moon_pos.add(dir_to_earth.mul_scalar(moon_soi + 100.0))
	var dom_outside = GravityService.dominant_body(pos_outside_moon, 0.0)
	assert_eq(dom_outside, &"Earth", "Dominant body outside Moon SOI towards Earth is Earth")
	
	# Transition boundary check: boundary is sharp and well-defined
	var mid_step = 10.0 # meters
	for d_offset in [-50.0, -10.0, 10.0, 50.0]:
		var test_p = moon_pos.add(dir_to_earth.mul_scalar(moon_soi + d_offset))
		var dom = GravityService.dominant_body(test_p, 0.0)
		if d_offset < 0.0:
			assert_eq(dom, &"Moon", "Offset %.1f m inside SOI gives Moon" % d_offset)
		else:
			assert_eq(dom, &"Earth", "Offset %.1f m outside SOI gives Earth" % d_offset)
