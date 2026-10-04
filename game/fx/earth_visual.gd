class_name EarthVisual
extends Node3D
## Self-contained, reusable Earth planetary visual presentation.
## Combines PBR surface, dynamic clouds with shadows, and Rayleigh/Mie atmosphere scattering shell.
## Calibrated for 1:10 scale (radius = 637,100 m).

@export var radius: float = 637100.0:
	set(val):
		radius = val
		_update_mesh_sizes()

@export var cloud_altitude: float = 1500.0:
	set(val):
		cloud_altitude = val
		_update_mesh_sizes()

@export var atmosphere_thickness: float = 9000.0:
	set(val):
		atmosphere_thickness = val
		_update_mesh_sizes()

@export var rotation_speed_deg_per_sec: float = 0.00417
@export var sun_direction: Vector3 = Vector3(0.707, 0.35, 0.612):
	set(val):
		sun_direction = val.normalized() if val.length_squared() > 0.0001 else Vector3.UP
		_update_sun_direction()

@export var quality_tier: int = 1:
	set(val):
		quality_tier = clampi(val, 0, 1)
		_update_quality_tier()

@export var surface_material: ShaderMaterial
@export var clouds_material: ShaderMaterial
@export var atmosphere_material: ShaderMaterial

@onready var surface_mesh_node: MeshInstance3D = get_node_or_null("Surface")
@onready var clouds_mesh_node: MeshInstance3D = get_node_or_null("Clouds")
@onready var atmosphere_mesh_node: MeshInstance3D = get_node_or_null("Atmosphere")
@onready var atmosphere_system: AtmosphereSystem = get_node_or_null("AtmosphereSystem")
@onready var weather_system: WeatherSystem = get_node_or_null("WeatherSystem")

var _current_rotation_rad: float = 0.0

func _ready() -> void:
	if not surface_mesh_node:
		surface_mesh_node = get_node_or_null("Surface")
	if not clouds_mesh_node:
		clouds_mesh_node = get_node_or_null("Clouds")
	if not atmosphere_mesh_node:
		atmosphere_mesh_node = get_node_or_null("Atmosphere")
	if not atmosphere_system:
		atmosphere_system = get_node_or_null("AtmosphereSystem")
	if not weather_system:
		weather_system = get_node_or_null("WeatherSystem")

	if not surface_material and surface_mesh_node and surface_mesh_node.material_override is ShaderMaterial:
		surface_material = surface_mesh_node.material_override
	if not clouds_material and clouds_mesh_node and clouds_mesh_node.material_override is ShaderMaterial:
		clouds_material = clouds_mesh_node.material_override
	if not atmosphere_material and atmosphere_mesh_node and atmosphere_mesh_node.material_override is ShaderMaterial:
		atmosphere_material = atmosphere_mesh_node.material_override

	_update_mesh_sizes()
	_update_sun_direction()
	_update_quality_tier()

func _process(delta: float) -> void:
	# Continental rotation around polar Y axis
	if rotation_speed_deg_per_sec != 0.0:
		_current_rotation_rad += deg_to_rad(rotation_speed_deg_per_sec) * delta
		if _current_rotation_rad > TAU:
			_current_rotation_rad -= TAU
		elif _current_rotation_rad < -TAU:
			_current_rotation_rad += TAU
			
		if surface_material:
			surface_material.set_shader_parameter("planet_rotation", _current_rotation_rad)

func set_sun_direction(dir: Vector3) -> void:
	sun_direction = dir

func set_quality_tier(tier: int) -> void:
	quality_tier = tier

func _update_sun_direction() -> void:
	if surface_material:
		surface_material.set_shader_parameter("sun_direction", sun_direction)
	if clouds_material:
		clouds_material.set_shader_parameter("sun_direction", sun_direction)
	if atmosphere_material:
		atmosphere_material.set_shader_parameter("sun_direction", sun_direction)
	if atmosphere_system:
		atmosphere_system.sun_direction = sun_direction

func _update_quality_tier() -> void:
	if surface_material:
		surface_material.set_shader_parameter("quality_tier", quality_tier)
	if clouds_material:
		clouds_material.set_shader_parameter("quality_tier", quality_tier)
	if atmosphere_material:
		atmosphere_material.set_shader_parameter("quality_tier", quality_tier)
	if atmosphere_system:
		atmosphere_system.set_quality_tier(quality_tier)

func _update_mesh_sizes() -> void:
	if surface_mesh_node and surface_mesh_node.mesh is SphereMesh:
		var sm = surface_mesh_node.mesh as SphereMesh
		sm.radius = radius
		sm.height = radius * 2.0
		
	if clouds_mesh_node and clouds_mesh_node.mesh is SphereMesh:
		var cm = clouds_mesh_node.mesh as SphereMesh
		var c_rad = radius + cloud_altitude
		cm.radius = c_rad
		cm.height = c_rad * 2.0
		
	if atmosphere_mesh_node and atmosphere_mesh_node.mesh is SphereMesh:
		var am = atmosphere_mesh_node.mesh as SphereMesh
		var a_rad = radius + atmosphere_thickness
		am.radius = a_rad
		am.height = a_rad * 2.0
		
	if atmosphere_material:
		atmosphere_material.set_shader_parameter("planet_radius", radius)
		atmosphere_material.set_shader_parameter("atmosphere_radius", radius + atmosphere_thickness)
