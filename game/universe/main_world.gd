class_name MainWorld extends Node3D

## Main Universe Scene Controller.
## Drives the realistic Earth-Moon system at 1:10 scale (Earth radius ≈ 637 km)
## integrated with OriginService, GravityService, BodyRegistry, and GameScale.

@export var starting_altitude_m: float = 200000.0 # 200 km LEO orbit
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
		# Initial origin centered at ship starting position (Earth + altitude along Y)
		var init_offset = earth_pos.add(DVec3.new(0.0, earth_r + starting_altitude_m, 0.0))
		origin_svc.origin.offset = init_offset
		if ship:
			ship.global_position = Vector3.ZERO
			# Calculate circular orbital speed at initial radius
			var earth_mu = scale_cfg.scaled_mu(earth_def.mu_m3_s2, earth_def.radius_m) if earth_def else 3.986e12
			var r0 = earth_r + starting_altitude_m
			var v_circ = sqrt(earth_mu / r0)
			# Orbiting in X-Z plane along -Z
			ship.linear_velocity = Vector3(0.0, 0.0, -v_circ)
			origin_svc.register(ship)
			origin_svc.set_focus_node(ship)
			
	if ship:
		if earth_planet_runtime:
			earth_planet_runtime.target_node = ship
		if moon_planet_runtime:
			moon_planet_runtime.target_node = ship
			
	_update_celestial_positions(sim_time)
	_update_sun_and_shaders(sim_time, earth_pos)

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
		if earth_def and earth_def.rotation_period_s > 0.0:
			var rot_period = scale_cfg.scaled_rotation_period(earth_def.rotation_period_s)
			earth_globe.rotation.y = fmod(TAU * (sim_time / rot_period), TAU)
			
	if moon_globe:
		var moon_local = origin_svc.universe_to_local(UniversePosition.new(Vector3i.ZERO, moon_pos))
		moon_globe.global_position = moon_local

func _update_sun_and_shaders(sim_time: float, earth_pos: DVec3) -> void:
	var sun_pos = GravityService.body_position("Sun", sim_time)
	# Direction from Earth towards Sun in Godot coordinates
	var sun_dir = sun_pos.sub(earth_pos).normalized().to_vector3()
	if sun_dir.length_squared() < 0.1:
		sun_dir = Vector3(0.707, 0.35, 0.612).normalized()
	else:
		# Add solar declination tilt
		var tilt_rad = deg_to_rad(sun_inclination_deg)
		sun_dir = sun_dir.rotated(Vector3.FORWARD, tilt_rad).normalized()
		
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
