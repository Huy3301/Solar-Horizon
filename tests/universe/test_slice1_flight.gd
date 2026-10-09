class_name TestSlice1Flight
extends TestCase

## "Feel" regression tests for the ground -> sky -> space -> Moon loop.
## They run the REAL main.tscn through Jolt (not pure maths) and assert real outcomes.

func _origin() -> Node:
	return tree.root.get_node("OriginService")

func _clock() -> Node:
	return tree.root.get_node("SimulationClock")

func _make_world() -> Node:
	var w = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(w)
	await tree.process_frame   # _ready() of the whole scene runs on the first frame after add_child
	await tree.physics_frame
	return w

func _step(n: int) -> void:
	for i in range(n):
		await tree.physics_frame

func _cleanup(w: Node) -> void:
	for a in ["throttle_up", "vtol_up", "boost", "pitch_up", "pulse_drive"]:
		Input.action_release(a)
	w.queue_free()

func _tel(ship: RigidBody3D, key: String) -> float:
	return float(ship.telemetry_data.get(key, 0.0))

func test_all_input_actions_exist() -> void:
	for a in ["boost", "pulse_drive", "vtol_up", "vtol_down", "throttle_up", "throttle_down"]:
		assert_true(InputMap.has_action(a), "input action exists: " + a)

func test_cpu_terrain_hash_matches_glsl() -> void:
	# GLSL hash33 from terrain_height.glsl, ported 1:1. If this drifts, collision != what is drawn.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst: float = 0.0
	for i in range(500):
		var p := Vector3(rng.randi_range(-20, 20), rng.randi_range(-20, 20), rng.randi_range(-20, 20))
		var q: Vector3 = p * 0.1031
		q = Vector3(q.x - floor(q.x), q.y - floor(q.y), q.z - floor(q.z))
		var dv: float = q.dot(Vector3(q.z + 39.346, q.y + 39.346, q.x + 39.346))
		q += Vector3(dv, dv, dv)
		var r := Vector3(q.x + q.y, q.x + q.z, q.y + q.z)
		r = Vector3(r.x - floor(r.x), r.y - floor(r.y), r.z - floor(r.z))
		var cpu: Vector3 = TerrainNoise.hash33(p.x, p.y, p.z)
		worst = maxf(worst, maxf(absf(cpu.x - r.x), maxf(absf(cpu.y - r.y), absf(cpu.z - r.z))))
	assert_true(worst < 1e-5, "CPU hash equals GLSL hash (max diff %.6f)" % worst)

func test_game_starts_parked_on_the_ground_and_stays_there() -> void:
	require_completion()
	var w = await _make_world()
	var ship: RigidBody3D = w.get_node("Ship")
	await _step(600)  # 10 s while Earth travels ~30 km/s (scaled) - the frame must follow it
	var alt: float = _tel(ship, "altitude_asl_m")
	var agl: float = _tel(ship, "altitude_agl_m")
	assert_true(alt < 4500.0, "spawns in the lowlands, not on a mountain top (ASL %.0f m)" % alt)
	assert_true(agl < 4.0, "resting on the terrain (AGL %.2f m)" % agl)
	assert_true(ship.linear_velocity.length() < 1.0, "not moving (%.2f m/s)" % ship.linear_velocity.length())
	assert_true(ship.is_landed and not ship.is_crashed, "landed, not crashed")
	_cleanup(w)
	complete()

func test_terrain_patches_are_drawn_where_they_belong() -> void:
	require_completion()
	var w = await _make_world()
	var ship: RigidBody3D = w.get_node("Ship")
	var globe: Node3D = w.get_node("EarthGlobe")
	var q = globe.get_node("PlanetRuntime").quadtree
	await _step(240)
	var worst: float = 0.0
	var n: int = 0
	for node in q.last_leaves:
		if node.instance == null or node.center_double.distance_to(q.camera_pos) > 20000.0:
			continue
		var expected: Vector3 = globe.global_position + globe.global_transform.basis * node.center_double.to_vector3()
		worst = maxf(worst, expected.distance_to(node.instance.global_position))
		n += 1
	assert_true(n > 0, "patches exist near the ship")
	assert_true(worst < 3.0, "patch world position error %.2f m over %d patches (was 642 km)" % [worst, n])
	_cleanup(w)
	complete()

func test_camera_stays_locked_to_the_ship_at_any_speed() -> void:
	require_completion()
	var w = await _make_world()
	var ship: RigidBody3D = w.get_node("Ship")
	var cc = ship.get_node("CameraController")
	var cam: Camera3D = cc.get_node("Camera3D")
	await _step(120)
	ship.set("flight_model", 1)
	for speed in [0.0, 500.0, 2000.0, 35000.0]:
		ship.linear_velocity = Vector3(0, 0, -speed)
		await _step(3)
		cc._follow(0.016)  # same instant, same interpolated ship transform the renderer uses
		var d: float = cam.global_position.distance_to(ship.get_global_transform_interpolated().origin)
		assert_true(d < 60.0, "camera %.1f m from ship at %.0f m/s (was ~290 m at 2 km/s)" % [d, speed])
	_cleanup(w)
	complete()

func test_takeoff_lifts_off_without_crashing() -> void:
	require_completion()
	var w = await _make_world()
	var ship: RigidBody3D = w.get_node("Ship")
	await _step(240)
	Input.action_press("throttle_up")
	var lifted_tick: int = -1
	for i in range(60 * 6):
		await tree.physics_frame
		if lifted_tick < 0 and _tel(ship, "altitude_agl_m") > 15.0:
			lifted_tick = i
	assert_true(lifted_tick >= 0 and lifted_tick < 60 * 4, "clears 15 m within 4 s of throttle (tick %d)" % lifted_tick)
	assert_false(ship.is_crashed, "lifting off is not a crash")
	_cleanup(w)
	complete()

func test_on_foot_keys_do_not_fly_the_ship() -> void:
	require_completion()
	var w = await _make_world()
	var ship: RigidBody3D = w.get_node("Ship")
	var rig = w.get_node("PlayerRig")
	await _step(240)
	rig.exit_ship(true)
	Input.action_press("vtol_up")
	Input.action_press("throttle_up")
	await _step(120)
	assert_true(ship.linear_velocity.length() < 3.0, "parked ship ignores flight keys while on foot (%.1f m/s)" % ship.linear_velocity.length())
	_cleanup(w)
	complete()

func test_full_flight_ground_to_space_to_moon() -> void:
	require_completion()
	var w = await _make_world()
	var ship: RigidBody3D = w.get_node("Ship")
	await _step(240)
	Input.action_press("throttle_up")
	await _step(150)
	Input.action_press("pitch_up")
	for i in range(240):
		await tree.physics_frame
		if _tel(ship, "pitch_deg") > 40.0:
			break
	Input.action_release("pitch_up")
	Input.action_press("boost")
	var t_space: float = -1.0
	for i in range(60 * 100):
		await tree.physics_frame
		if _tel(ship, "altitude_asl_m") > 70000.0:
			t_space = float(i) / 60.0
			break
	Input.action_release("boost")
	assert_true(t_space > 0.0 and t_space < 90.0, "ground to 70 km in %.0f s with boost" % t_space)
	assert_false(ship.is_crashed, "no crash on the way up")

	# Put the Moon above the horizon (Earth moves; let the frame follow), then aim and pulse
	var moon_up: bool = false
	for tries in range(300):
		var su = _origin().local_to_universe(ship.global_position).offset
		var t: float = _clock().sim_time_s
		var to_moon: Vector3 = GravityService.body_position(&"Moon", t).sub(su).normalized().to_vector3()
		var up: Vector3 = su.sub(GravityService.body_position(&"Earth", t)).normalized().to_vector3()
		if to_moon.dot(up) > 0.5:
			moon_up = true
			ship.angular_velocity = Vector3.ZERO
			ship.global_transform = Transform3D(Basis.looking_at(to_moon, Vector3.UP), ship.global_position)
			break
		_clock().sim_time_s += 60.0
		await _step(2)
	assert_true(moon_up, "found a time with the Moon above the horizon")
	await _step(20)
	Input.action_press("pulse_drive")
	await _step(2)
	Input.action_release("pulse_drive")
	assert_true(ship.pulse_drive_active, "pulse drive engaged in space")
	var peak: float = 0.0
	var ticks: int = 0
	while ship.pulse_drive_active and ticks < 60 * 200:
		await tree.physics_frame
		ticks += 1
		peak = maxf(peak, ship.linear_velocity.length())
	var secs: float = float(ticks) / 60.0
	assert_false(ship.pulse_drive_active, "pulse drive disengaged on arrival")
	assert_true(secs > 20.0 and secs < 150.0, "crossed to the Moon in %.0f s" % secs)
	assert_true(peak > 20000.0, "reached pulse speeds (peak %.0f m/s)" % peak)
	var su2 = _origin().local_to_universe(ship.global_position).offset
	var t2: float = _clock().sim_time_s
	var moon_def = BodyRegistry.get_body(&"Moon")
	var moon_alt: float = su2.sub(GravityService.body_position(&"Moon", t2)).length() - GameScale.get_instance().scaled_radius(moon_def.radius_m)
	assert_true(moon_alt > 20000.0 and moon_alt < 120000.0, "arrived above the Moon (%.0f km)" % (moon_alt / 1000.0))
	assert_true(ship.linear_velocity.length() < 3000.0, "braked on arrival (%.0f m/s)" % ship.linear_velocity.length())
	assert_false(ship.is_crashed, "no crash")
	_cleanup(w)
	complete()


func test_crash_respawn_returns_to_the_ground_spawn() -> void:
	require_completion()
	var w = await _make_world()
	var ship: RigidBody3D = w.get_node("Ship")
	await _step(240)
	# Fly off into the sky, then "crash": the respawn must put us back on the ground, not at a fixed local point
	ship.freeze = false
	ship.linear_velocity = Vector3.ZERO
	ship.global_position += ship.global_transform.basis.y * 3000.0
	await _step(30)
	var bootstrap = w.get_node("GameBootstrap")
	bootstrap.respawn_player()
	await _step(240)
	assert_true(_tel(ship, "altitude_agl_m") < 6.0, "back on the ground after respawn (AGL %.1f m)" % _tel(ship, "altitude_agl_m"))
	assert_true(ship.linear_velocity.length() < 2.0, "at rest after respawn (%.1f m/s)" % ship.linear_velocity.length())
	assert_false(ship.is_crashed, "recovered")
	_cleanup(w)
	complete()
