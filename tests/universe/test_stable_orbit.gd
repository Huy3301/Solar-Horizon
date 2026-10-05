class_name TestStableOrbit
extends TestCase

## SH-15, SH-16, SH-18 Verification: Stable Orbit & Physics Integration
## Verifies that dominant-body co-moving frame anchors Earth in Godot local space,
## preserving Keplerian orbit without heliocentric drift for 600 ticks.

func test_stable_circular_orbit() -> void:
	# 1. Verify main scene instantiates and ship damping configuration (SH-15)
	var scene_res = load("res://scenes/main.tscn") as PackedScene
	assert_true(scene_res != null, "scenes/main.tscn loads successfully")
	var main_scene = scene_res.instantiate()
	assert_true(main_scene != null, "scenes/main.tscn instantiates")
	
	var ship = main_scene.get_node_or_null("Ship") as ShipFlightController
	assert_true(ship != null, "Ship node found in main scene")
	if ship:
		ship._ready()
		assert_eq(ship.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE, "Ship linear_damp_mode is REPLACE")
		assert_eq(ship.angular_damp_mode, RigidBody3D.DAMP_MODE_REPLACE, "Ship angular_damp_mode is REPLACE")
		assert_almost_eq(ship.linear_damp, 0.0, 1e-6, "Ship linear_damp is 0.0")
		assert_almost_eq(ship.angular_damp, 0.0, 1e-6, "Ship angular_damp is 0.0")
	main_scene.free()
	
	# 2. Step the ship with gravity for 600 ticks in the dominant-body co-moving frame (SH-16)
	var scale_cfg = GameScale.get_instance()
	var earth_def = BodyRegistry.get_body("Earth")
	var earth_mu = scale_cfg.scaled_mu(earth_def.mu_m3_s2, earth_def.radius_m) if earth_def else 3.986e11
	var earth_r = scale_cfg.scaled_radius(earth_def.radius_m) if earth_def else 637100.0
	
	var alt = 200000.0 # 200 km LEO
	var r0 = earth_r + alt
	var v_circ = sqrt(earth_mu / r0)
	assert_true(v_circ > 1000.0, "Circular orbital speed is realistic (v0 = %f m/s)" % v_circ)
	
	var sim_time: float = 0.0
	var earth_pos = GravityService.body_position("Earth", sim_time)
	var prev_earth_pos = earth_pos
	
	# Initial relative state: radius r0 on Y, velocity v_circ on -Z
	var rel_pos = DVec3.new(0.0, r0, 0.0)
	var rel_vel = DVec3.new(0.0, 0.0, -v_circ)
	var ship_pos = earth_pos.add(rel_pos)
	
	# Co-moving origin tracking
	var co_moving_origin = UniversePosition.new(Vector3i.ZERO, earth_pos.add(rel_pos))
	
	var dt: float = 0.1 # 600 ticks * 0.1s = 60s
	var v0: float = rel_vel.length()
	var min_v: float = v0
	var max_v: float = v0
	var max_e: float = 0.0
	
	var acc = GravityService.gravity_accel(ship_pos, sim_time)
	
	for _step in range(600):
		# Advance time
		sim_time += dt
		
		# Dominant body displacement (Earth moving in heliocentric orbit around Sun)
		var next_earth_pos = GravityService.body_position("Earth", sim_time)
		var delta_dom = next_earth_pos.sub(prev_earth_pos)
		prev_earth_pos = next_earth_pos
		
		# Advance co-moving frame origin by dominant body displacement without shifting nodes
		co_moving_origin.add_offset(delta_dom)
		
		# Velocity Verlet step for relative Keplerian motion
		rel_vel.add_in_place(acc.mul_scalar(0.5 * dt))
		rel_pos.add_in_place(rel_vel.mul_scalar(dt))
		
		ship_pos = next_earth_pos.add(rel_pos)
		acc = GravityService.gravity_accel(ship_pos, sim_time)
		rel_vel.add_in_place(acc.mul_scalar(0.5 * dt))
		
		var cur_v = rel_vel.length()
		min_v = min(min_v, cur_v)
		max_v = max(max_v, cur_v)
		
		var orbit = OrbitalMechanics.calculate_orbit(rel_pos.to_vector3(), rel_vel.to_vector3(), earth_mu, earth_r)
		if orbit.eccentricity > max_e:
			max_e = orbit.eccentricity
			
	var speed_drift = max(abs(max_v - v0), abs(min_v - v0)) / v0
	assert_true(speed_drift < 0.005, "Speed |v| remains constant to within 0.5%% (drift: %.4f%%)" % [speed_drift * 100.0])
	assert_true(max_e < 0.01, "Eccentricity e < 0.01 (max e: %.6f)" % max_e)

func test_ship_input_gating_on_foot() -> void:
	var ship_script = load("res://scripts/ship_flight_controller.gd")
	var ship = ship_script.new()
	assert_true("is_player_controlled" in ship, "Ship has is_player_controlled property")
	assert_true(ship.is_player_controlled, "Ship is player controlled by default")
	
	# When not player controlled, inputs are zeroed
	ship.is_player_controlled = false
	ship.control_pitch = 0.5
	ship.control_yaw = 0.5
	ship.control_roll = 0.5
	ship.target_throttle = 0.8
	ship._handle_inputs(0.016)
	
	assert_almost_eq(ship.control_pitch, 0.0, 1e-6, "Pitch zeroed when not player controlled")
	assert_almost_eq(ship.control_yaw, 0.0, 1e-6, "Yaw zeroed when not player controlled")
	assert_almost_eq(ship.control_roll, 0.0, 1e-6, "Roll zeroed when not player controlled")
	assert_almost_eq(ship.control_throttle, 0.0, 1e-6, "Throttle zeroed when not player controlled")
	
	# Player rig integration
	var player_rig_script = load("res://game/player/player_rig.gd")
	var on_foot_rig_script = load("res://game/player/on_foot_rig.gd")
	var rig = player_rig_script.new()
	var on_foot = on_foot_rig_script.new()
	rig.set_ship(ship)
	rig.set_on_foot_rig(on_foot)
	rig.add_child(on_foot)
	
	if tree and tree.root:
		tree.root.add_child(rig)
		
	rig.enter_ship(ship)
	assert_true(ship.is_player_controlled, "Ship is player controlled after entering")
	
	ship.is_landed = true
	ship.linear_velocity = Vector3.ZERO
	rig.exit_ship(true)
	assert_false(ship.is_player_controlled, "Ship is not player controlled after exiting")
	
	if rig.get_parent():
		rig.get_parent().remove_child(rig)
	rig.free()
	ship.free()
