class_name MainWorld extends Node3D

## Main Universe Scene Controller.
## Drives the realistic Earth-Moon system at 1:10 scale (Earth radius ≈ 637 km)
## integrated with OriginService, GravityService, BodyRegistry, and GameScale.

enum StartMode { SURFACE = 0, ORBIT = 1 }
## SURFACE: begin parked on the ground near Adelaide (default). ORBIT: legacy 200 km LEO start.
@export var start_mode: StartMode = StartMode.SURFACE
@export var spawn_lat_deg: float = -34.9285
@export var spawn_lon_deg: float = 138.6007
@export var spawn_search_radius_km: float = 120.0   # (scaled km) search for flat ground near the target
@export var spawn_clearance_m: float = 1.4
@export var sun_elevation_at_spawn_deg: float = 42.0
## Planets do not spin under the player (a spinning surface would slide under a parked ship at ~760 m/s).
## Day/night is a slow consequence of the orbital year; set true only for visual experiments.
@export var spin_planets: bool = false
@export var starting_altitude_m: float = 200000.0 # ORBIT start: 200 km LEO
@export var cloud_drift_speed: float = 0.003
@export var sun_inclination_deg: float = 23.44

@onready var sky_env: SkyEnvironmentVisual = get_node_or_null("SkyEnvironment")
@onready var sun_light: Node = get_node_or_null("SunLight")
@onready var world_env: WorldEnvironment = get_node_or_null("WorldEnvironment")
@onready var earth_globe: Node3D = get_node_or_null("EarthGlobe")
@onready var moon_globe: Node3D = get_node_or_null("MoonGlobe")
@onready var ship: RigidBody3D = get_node_or_null("Ship")
@onready var earth_planet_runtime: PlanetRuntime = get_node_or_null("EarthGlobe/PlanetRuntime")
@onready var moon_planet_runtime: PlanetRuntime = get_node_or_null("MoonGlobe/PlanetRuntime")

@onready var earth_surface_mesh: MeshInstance3D = get_node_or_null("EarthGlobe/Surface")
@onready var earth_clouds_mesh: MeshInstance3D = get_node_or_null("EarthGlobe/Clouds")
@onready var earth_atmo_mesh: MeshInstance3D = get_node_or_null("EarthGlobe/Atmosphere")

var mat_surface: ShaderMaterial
var mat_clouds: ShaderMaterial
var mat_atmosphere: ShaderMaterial
var mat_sky: ShaderMaterial

var current_cloud_rot: float = 0.0
var _earth_theta: float = 0.0
var _spawn_dir_local: Vector3 = Vector3.UP
var _frame_body: StringName = &"Earth"
var _frame_prev_pos: DVec3 = null
var _frame_candidate: StringName = &""
var _frame_candidate_ticks: int = 0
var _waiting_for_collision: bool = false
var _wait_ticks: int = 0

func _ready() -> void:
	_init_materials()
	
	var scale_cfg = GameScale.get_instance()
	var earth_def = BodyRegistry.get_body("Earth")
	var earth_r = scale_cfg.scaled_radius(earth_def.radius_m) if earth_def else 637100.0
	var moon_def = BodyRegistry.get_body("Moon")
	var moon_r = scale_cfg.scaled_radius(moon_def.radius_m) if moon_def else 173740.0
	
	var sun_ctrl: SunController = sky_env.sun_node if (sky_env and sky_env.sun_node) else (sky_env.get_node_or_null("Sun") as SunController if sky_env else null)
	if sun_ctrl:
		sun_ctrl.add_occluder(earth_globe, earth_r)
		sun_ctrl.add_occluder(moon_globe, moon_r)
	
	var sim_clock = get_node_or_null("/root/SimulationClock")
	var sim_time = sim_clock.sim_time_s if sim_clock else 0.0
	var earth_pos = GravityService.body_position("Earth", sim_time)
	
	var origin_svc = get_node_or_null("/root/OriginService")
	if origin_svc:
		origin_svc.world_root = self
		if ship:
			if start_mode == StartMode.SURFACE:
				_place_ship_on_surface(origin_svc, earth_r, earth_pos, sim_time)
			else:
				_apply_earth_orientation(sim_time)
				_place_ship_in_orbit(origin_svc, scale_cfg, earth_def, earth_r, earth_pos)
			origin_svc.register(ship)
			origin_svc.set_focus_node(ship)
		_frame_body = &"Earth"
		_frame_prev_pos = earth_pos

	if ship:
		if earth_planet_runtime:
			earth_planet_runtime.target_node = ship
		if moon_planet_runtime:
			moon_planet_runtime.target_node = ship
			
	_update_celestial_positions(sim_time)
	_update_sun_and_shaders(sim_time, earth_pos)

# ---------------------------------------------------------------------------------------------
# Start placement, planet orientation and the co-moving physics frame
# ---------------------------------------------------------------------------------------------

func _polar_axis_world() -> Vector3:
	# Earth's spin axis in the ecliptic Godot frame (ecliptic z -> +Y): tilted by the obliquity about +X.
	var eps: float = CelestialCoordinates.EARTH_AXIAL_TILT_RAD
	return Vector3(0.0, cos(eps), -sin(eps)).normalized()

func _earth_basis_for_theta(theta: float) -> Basis:
	var polar: Vector3 = _polar_axis_world()
	var b0 := Basis(Quaternion(Vector3.UP, polar))
	return Basis(polar, theta) * b0

func _apply_earth_orientation(sim_time: float) -> void:
	var theta: float = _earth_theta
	if spin_planets:
		var earth_def = BodyRegistry.get_body("Earth")
		if earth_def and earth_def.rotation_period_s > 0.0:
			theta += TAU * (sim_time / GameScale.get_instance().scaled_rotation_period(earth_def.rotation_period_s))
	var b: Basis = _earth_basis_for_theta(theta)
	BodyFrames.set_basis(&"Earth", b)
	if earth_globe:
		earth_globe.basis = b

func _slope_ok_score(dir: Vector3, radius: float) -> float:
	# Max height difference (m) within ~40 m of a candidate point: a measure of local flatness.
	var east: Vector3 = Vector3.UP.cross(dir)
	if east.length() < 1e-4:
		east = Vector3.RIGHT
	east = east.normalized()
	var north: Vector3 = dir.cross(east).normalized()
	var ang: float = 40.0 / radius
	var h0: float = TerrainNoise.sample_height(dir.x, dir.y, dir.z, "Earth") * 8848.0
	var worst: float = 0.0
	for t in [east, -east, north, -north]:
		var d2: Vector3 = (dir * cos(ang) + t * sin(ang)).normalized()
		var h: float = TerrainNoise.sample_height(d2.x, d2.y, d2.z, "Earth") * 8848.0
		worst = maxf(worst, absf(h - h0))
	return worst

func _find_spawn_dir(earth_r: float) -> Vector3:
	var base: Vector3 = BodyFrames.geo_dir(spawn_lat_deg, spawn_lon_deg)
	var east: Vector3 = Vector3.UP.cross(base).normalized()
	var north: Vector3 = base.cross(east).normalized()
	var best: Vector3 = base
	var best_score: float = INF
	var rings: int = int(spawn_search_radius_km / 8.0)
	for ri in range(0, rings + 1):
		var arc_m: float = float(ri) * 8000.0
		var bearings: int = 1 if ri == 0 else 12
		for bi in range(bearings):
			var b: float = TAU * float(bi) / float(bearings)
			var tangent: Vector3 = north * cos(b) + east * sin(b)
			var a: float = arc_m / earth_r
			var cand: Vector3 = (base * cos(a) + tangent * sin(a)).normalized()
			var h_c: float = TerrainNoise.sample_height(cand.x, cand.y, cand.z, "Earth") * 8848.0
			# flat first, lowlands strongly preferred (a spaceport is not on a mountain top), close to the target
			var score: float = _slope_ok_score(cand, earth_r) + h_c * 0.012 + arc_m * 0.0004
			if score < best_score:
				best_score = score
				best = cand
		if best_score < 3.0 and ri >= 1:
			break
	return best

func _solve_spin_for_sun(sim_time: float, earth_pos: DVec3) -> float:
	var sun_pos = GravityService.body_position("Sun", sim_time)
	var sun_dir: Vector3 = sun_pos.sub(earth_pos).normalized().to_vector3()
	var polar: Vector3 = _polar_axis_world()
	var target_el: float = deg_to_rad(sun_elevation_at_spawn_deg)
	var best_theta: float = 0.0
	var best_err: float = INF
	for deg in range(0, 360):
		var th: float = deg_to_rad(float(deg))
		var up: Vector3 = (_earth_basis_for_theta(th) * _spawn_dir_local).normalized()
		var east: Vector3 = polar.cross(up).normalized()
		if sun_dir.dot(east) <= 0.0:
			continue  # prefer a morning sun (rising in the east)
		var el: float = asin(clampf(sun_dir.dot(up), -1.0, 1.0))
		var err: float = absf(el - target_el)
		if err < best_err:
			best_err = err
			best_theta = th
	return best_theta

func _place_ship_on_surface(origin_svc: Node, earth_r: float, earth_pos: DVec3, sim_time: float) -> void:
	_spawn_dir_local = _find_spawn_dir(earth_r)
	_earth_theta = _solve_spin_for_sun(sim_time, earth_pos)
	_apply_earth_orientation(sim_time)
	_orient_and_place_ship(origin_svc, earth_r, earth_pos)
	_waiting_for_collision = true
	_wait_ticks = 0

func _orient_and_place_ship(origin_svc: Node, earth_r: float, earth_pos: DVec3) -> void:
	var up_w: Vector3 = (BodyFrames.get_basis(&"Earth") * _spawn_dir_local).normalized()
	var h: float = TerrainNoise.sample_height(_spawn_dir_local.x, _spawn_dir_local.y, _spawn_dir_local.z, "Earth") * 8848.0
	var r_here: float = earth_r + h + spawn_clearance_m
	origin_svc.origin.offset = earth_pos.add(DVec3.new(up_w.x * r_here, up_w.y * r_here, up_w.z * r_here))
	ship.global_position = Vector3.ZERO
	var polar: Vector3 = _polar_axis_world()
	var north: Vector3 = (polar - up_w * polar.dot(up_w)).normalized()
	var z_axis: Vector3 = -north
	var x_axis: Vector3 = up_w.cross(z_axis).normalized()
	ship.global_transform = Transform3D(Basis(x_axis, up_w, z_axis), Vector3.ZERO)
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	if "landing_gear_deployed" in ship:
		ship.landing_gear_deployed = true
	if "is_landed" in ship:
		ship.is_landed = true
	if "is_crashed" in ship:
		ship.is_crashed = false
	if "current_throttle" in ship:
		ship.current_throttle = 0.0
		ship.target_throttle = 0.0
	# Hold the ship until the ground collider under it exists (it is built on a worker thread)
	ship.freeze = true

## Put the ship back on the ground at the spawn point (used after a crash / by respawn).
func respawn_ship_at_spawn() -> void:
	if not ship:
		return
	var origin_svc = get_node_or_null("/root/OriginService")
	var sim_clock = get_node_or_null("/root/SimulationClock")
	if not origin_svc or not sim_clock:
		return
	var t: float = sim_clock.sim_time_s
	var earth_def = BodyRegistry.get_body("Earth")
	var earth_r: float = GameScale.get_instance().scaled_radius(earth_def.radius_m)
	var earth_pos: DVec3 = GravityService.body_position("Earth", t)
	_frame_body = &"Earth"
	_frame_prev_pos = earth_pos
	_apply_earth_orientation(t)
	_orient_and_place_ship(origin_svc, earth_r, earth_pos)
	_waiting_for_collision = true
	_wait_ticks = 0

func _place_ship_in_orbit(origin_svc: Node, scale_cfg, earth_def, earth_r: float, earth_pos: DVec3) -> void:
	var init_offset = earth_pos.add(DVec3.new(0.0, earth_r + starting_altitude_m, 0.0))
	origin_svc.origin.offset = init_offset
	ship.global_position = Vector3.ZERO
	var earth_mu = scale_cfg.scaled_mu(earth_def.mu_m3_s2, earth_def.radius_m) if earth_def else 3.986e12
	var r0 = earth_r + starting_altitude_m
	var v_circ = sqrt(earth_mu / r0)
	ship.linear_velocity = Vector3(0.0, 0.0, -v_circ)

func _physics_process(_delta: float) -> void:
	if not ship:
		return
	var origin_svc = get_node_or_null("/root/OriginService")
	var sim_clock = get_node_or_null("/root/SimulationClock")
	if not origin_svc or not sim_clock:
		return
	_track_frame(origin_svc, sim_clock.sim_time_s)
	if _waiting_for_collision:
		_wait_ticks += 1
		var ready: bool = earth_planet_runtime != null and earth_planet_runtime.quadtree != null and earth_planet_runtime.quadtree.is_collision_ready()
		if ready or _wait_ticks > 600:
			ship.freeze = false
			_waiting_for_collision = false

## Keep the local physics frame co-moving with the dominant body, so a ship at rest relative to Earth
## stays at rest relative to Earth while Earth travels 30 km/s around the Sun (and hand over on SOI change).
func _track_frame(origin_svc: Node, t: float) -> void:
	var ship_u: DVec3 = origin_svc.local_to_universe(ship.global_position).offset
	var dom: StringName = GravityService.dominant_body(ship_u, t)
	if dom != _frame_body:
		if dom == _frame_candidate:
			_frame_candidate_ticks += 1
		else:
			_frame_candidate = dom
			_frame_candidate_ticks = 1
		if _frame_candidate_ticks >= 10:
			# Patched-conic hand-over: ship velocity is stored relative to the old body.
			var v_old: DVec3 = GravityService.body_velocity(_frame_body, t)
			var v_new: DVec3 = GravityService.body_velocity(dom, t)
			ship.linear_velocity += v_old.sub(v_new).to_vector3()
			_frame_body = dom
			_frame_prev_pos = GravityService.body_position(dom, t)
			_frame_candidate = &""
			_frame_candidate_ticks = 0
	else:
		_frame_candidate = &""
		_frame_candidate_ticks = 0
	var pos_now: DVec3 = GravityService.body_position(_frame_body, t)
	if _frame_prev_pos != null:
		origin_svc.origin.add_offset(pos_now.sub(_frame_prev_pos))
	_frame_prev_pos = pos_now

func _init_materials() -> void:
	if earth_surface_mesh and earth_surface_mesh.get_active_material(0) is ShaderMaterial:
		mat_surface = earth_surface_mesh.get_active_material(0) as ShaderMaterial
	if earth_clouds_mesh and earth_clouds_mesh.get_active_material(0) is ShaderMaterial:
		mat_clouds = earth_clouds_mesh.get_active_material(0) as ShaderMaterial
	if earth_atmo_mesh and earth_atmo_mesh.get_active_material(0) is ShaderMaterial:
		mat_atmosphere = earth_atmo_mesh.get_active_material(0) as ShaderMaterial
	if world_env and world_env.environment and world_env.environment.sky:
		if world_env.environment.sky.sky_material is ShaderMaterial:
			mat_sky = world_env.environment.sky.sky_material as ShaderMaterial

func _process(delta: float) -> void:
	var sim_clock = get_node_or_null("/root/SimulationClock")
	var sim_time = sim_clock.sim_time_s if sim_clock else 0.0
	
	var earth_pos = GravityService.body_position("Earth", sim_time)
	_update_celestial_positions(sim_time)
	_update_sun_and_shaders(sim_time, earth_pos)
	
	current_cloud_rot = fmod(current_cloud_rot + cloud_drift_speed * delta, TAU)
	if mat_clouds:
		mat_clouds.set_shader_parameter("cloud_rotation", current_cloud_rot)

func _update_celestial_positions(sim_time: float) -> void:
	var origin_svc = get_node_or_null("/root/OriginService")
	if not origin_svc:
		return
		
	var scale_cfg = GameScale.get_instance()
	var earth_def = BodyRegistry.get_body("Earth")
	var earth_pos = GravityService.body_position("Earth", sim_time)
	var moon_pos = GravityService.body_position("Moon", sim_time)
	
	if earth_globe:
		var earth_local = origin_svc.universe_to_local(UniversePosition.new(Vector3i.ZERO, earth_pos))
		earth_globe.global_position = earth_local
		_apply_earth_orientation(sim_time)
			
	if moon_globe:
		var moon_local = origin_svc.universe_to_local(UniversePosition.new(Vector3i.ZERO, moon_pos))
		moon_globe.global_position = moon_local

func _update_sun_and_shaders(sim_time: float, earth_pos: DVec3) -> void:
	var sun_pos = GravityService.body_position("Sun", sim_time)
	# Direction from Earth towards Sun in Godot coordinates
	var sun_dir = sun_pos.sub(earth_pos).normalized().to_vector3()
	if sun_dir.length_squared() < 0.1:
		sun_dir = Vector3(0.707, 0.35, 0.612).normalized()
	# (Earth itself is now tilted by its obliquity via the globe basis, so no declination hack is needed.)
		
	if sun_light and sun_light is DirectionalLight3D:
		(sun_light as DirectionalLight3D).look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
		
	if sky_env:
		sky_env.set_sun_direction(sun_dir)
	if earth_globe and earth_globe.has_method("set_sun_direction"):
		earth_globe.set_sun_direction(sun_dir)
	if moon_globe and moon_globe.has_method("set_sun_direction"):
		moon_globe.set_sun_direction(sun_dir)
		
	if mat_surface:
		mat_surface.set_shader_parameter("sun_direction", sun_dir)
	if mat_clouds:
		mat_clouds.set_shader_parameter("sun_direction", sun_dir)
	if mat_atmosphere:
		mat_atmosphere.set_shader_parameter("sun_direction", sun_dir)
	if mat_sky:
		mat_sky.set_shader_parameter("sun_direction", sun_dir)
