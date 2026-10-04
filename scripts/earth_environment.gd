extends Node3D
class_name EarthEnvironment

## Earth Low Orbit (LEO) Environmental & Lighting Controller.
## Coordinates planetary axial rotation, differential cloud drift,
## atmospheric limb scattering parameters, and directional solar illumination.

@export_group("Earth Orbital Parameters")
@export var orbit_altitude_km: float = 408.0
@export var earth_radius_km: float = 6371.0
@export var earth_rotation_speed: float = 0.005
@export var cloud_drift_speed: float = 0.007

@export_group("Solar Lighting")
@export var sun_inclination_deg: float = 23.44
@export var day_cycle_speed: float = 0.02
@export var sun_energy: float = 2.4

@onready var sun_light: DirectionalLight3D = get_node_or_null("SunLight")
@onready var world_env: WorldEnvironment = get_node_or_null("WorldEnvironment")
@onready var earth_surface_mesh: MeshInstance3D = get_node_or_null("EarthGlobe/Surface")
@onready var earth_clouds_mesh: MeshInstance3D = get_node_or_null("EarthGlobe/Clouds")
@onready var earth_atmo_mesh: MeshInstance3D = get_node_or_null("EarthGlobe/Atmosphere")

var current_sun_angle: float = 0.85
var current_planet_rot: float = 0.0
var current_cloud_rot: float = 0.0

var mat_surface: ShaderMaterial
var mat_clouds: ShaderMaterial
var mat_atmosphere: ShaderMaterial
var mat_sky: ShaderMaterial

func _ready() -> void:
	_init_materials()
	_update_sun_and_shaders()
	
	# Integrate with Phase 1 Double-Precision core (WP3)
	if get_tree().get_nodes_in_group("origin_service").is_empty():
		var origin_svc = OriginService.new()
		origin_svc.add_to_group("origin_service")
		add_child(origin_svc)
		# Set the origin to exactly Earth's position + Earth radius (637100) + 50000m (EarthGlobe legacy offset)
		var sim_time = 0.0
		if Engine.has_singleton("SimulationClock"):
			sim_time = SimulationClock.sim_time_s
		var earth_pos = GravityService.body_position("Earth", sim_time)
		# We want global_position = 0 to map to altitude 50000 above the scaled Earth radius.
		var offset = earth_pos.add(DVec3.new(0.0, 637100.0 + 50000.0, 0.0))
		origin_svc.origin.offset = offset

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
	current_planet_rot = fmod(current_planet_rot + earth_rotation_speed * delta, TAU)
	current_cloud_rot = fmod(current_cloud_rot + cloud_drift_speed * delta, TAU)
	
	if mat_surface:
		mat_surface.set_shader_parameter("planet_rotation", current_planet_rot)
	if mat_clouds:
		mat_clouds.set_shader_parameter("cloud_rotation", current_cloud_rot)
		
	if day_cycle_speed > 0.0:
		current_sun_angle = fmod(current_sun_angle + day_cycle_speed * delta, TAU)
		_update_sun_and_shaders()

func _update_sun_and_shaders() -> void:
	var tilt_rad: float = deg_to_rad(sun_inclination_deg)
	var sun_dir: Vector3 = Vector3(
		cos(current_sun_angle),
		sin(current_sun_angle) * sin(tilt_rad) + 0.3,
		sin(current_sun_angle) * cos(tilt_rad)
	).normalized()
	
	if sun_light:
		sun_light.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
		sun_light.light_energy = sun_energy
		sun_light.light_color = Color(1.0, 0.98, 0.94)

	if mat_surface:
		mat_surface.set_shader_parameter("sun_direction", sun_dir)
	if mat_clouds:
		mat_clouds.set_shader_parameter("sun_direction", sun_dir)
	if mat_atmosphere:
		mat_atmosphere.set_shader_parameter("sun_direction", sun_dir)
	if mat_sky:
		mat_sky.set_shader_parameter("sun_direction", sun_dir)
