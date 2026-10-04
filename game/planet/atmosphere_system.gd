class_name AtmosphereSystem
extends Node3D
## System for managing Earth and planetary atmosphere rendering (Rayleigh+Mie scattering).
## Supports high/low quality tiers, analytic shader driving, and optional compute LUT generation.

enum QualityTier {
	LOW = 0,
	HIGH = 1
}

const TRANSMITTANCE_SIZE = Vector2i(256, 64)
const MULTISCATTERING_SIZE = Vector2i(32, 32)
const SKYVIEW_SIZE = Vector2i(200, 100)

@export var quality_tier: QualityTier = QualityTier.HIGH:
	set(val):
		quality_tier = val
		_apply_parameters_to_materials()

@export var atmosphere_material: ShaderMaterial:
	set(val):
		atmosphere_material = val
		_apply_parameters_to_materials()

@export var sky_material: ShaderMaterial:
	set(val):
		sky_material = val
		_apply_parameters_to_materials()

@export var surface_material: ShaderMaterial:
	set(val):
		surface_material = val
		_apply_parameters_to_materials()

@export var body_def: Resource: # CelestialBodyDef
	set(val):
		body_def = val
		_extract_body_def_params()
		_apply_parameters_to_materials()

@export var sun_direction: Vector3 = Vector3(0.707, 0.35, 0.612):
	set(val):
		sun_direction = val.normalized() if val.length_squared() > 0.0001 else Vector3.UP
		_apply_parameters_to_materials()

@export var sun_intensity: float = 1.0:
	set(val):
		sun_intensity = val
		_apply_parameters_to_materials()

@export var atmosphere_density: float = 2.4:
	set(val):
		atmosphere_density = val
		_apply_parameters_to_materials()

@export var rayleigh_day_color: Color = Color(0.18, 0.58, 1.0, 1.0):
	set(val):
		rayleigh_day_color = val
		_apply_parameters_to_materials()

@export var rayleigh_sunset_color: Color = Color(1.0, 0.38, 0.08, 1.0):
	set(val):
		rayleigh_sunset_color = val
		_apply_parameters_to_materials()

@export var planet_radius: float = 637100.0:
	set(val):
		planet_radius = val
		_apply_parameters_to_materials()

@export var atmosphere_radius: float = 646100.0:
	set(val):
		atmosphere_radius = val
		_apply_parameters_to_materials()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var transmittance_lut: RID
var multiscattering_lut: RID
var skyview_lut: RID
var transmittance_tex: Texture2DRD
var multiscattering_tex: Texture2DRD
var skyview_tex: Texture2DRD

var needs_update: bool = false
var _use_compute: bool = false

func _ready() -> void:
	if body_def:
		_extract_body_def_params()
	
	rd = RenderingServer.get_rendering_device()
	if rd:
		_initialize_compute()
		if pipeline.is_valid():
			_create_textures()
			_use_compute = true
	
	_apply_parameters_to_materials()

func set_body_def(def: Resource) -> void:
	body_def = def

func set_sun_direction(dir: Vector3) -> void:
	sun_direction = dir

func set_quality_tier(tier: int) -> void:
	quality_tier = tier as QualityTier

func _extract_body_def_params() -> void:
	if not body_def:
		return
	
	if "radius_m" in body_def:
		# At 1:10 scale default
		planet_radius = body_def.radius_m * 0.1
	elif "radius" in body_def:
		planet_radius = body_def.radius * 0.1
		
	if "scale_height_m" in body_def:
		var scaled_scale_height: float = body_def.scale_height_m * 0.1
		atmosphere_radius = planet_radius + scaled_scale_height * 10.0
	else:
		atmosphere_radius = planet_radius + 9000.0
		
	if "atmosphere_color" in body_def and body_def.atmosphere_color.a > 0.0:
		rayleigh_day_color = body_def.atmosphere_color

func _apply_parameters_to_materials() -> void:
	if atmosphere_material:
		atmosphere_material.set_shader_parameter("quality_tier", int(quality_tier))
		atmosphere_material.set_shader_parameter("sun_direction", sun_direction)
		atmosphere_material.set_shader_parameter("sun_intensity", sun_intensity)
		atmosphere_material.set_shader_parameter("planet_radius", planet_radius)
		atmosphere_material.set_shader_parameter("atmosphere_radius", atmosphere_radius)
		atmosphere_material.set_shader_parameter("atmosphere_density", atmosphere_density)
		atmosphere_material.set_shader_parameter("rayleigh_day_color", rayleigh_day_color)
		atmosphere_material.set_shader_parameter("rayleigh_sunset_color", rayleigh_sunset_color)
		
	if sky_material:
		sky_material.set_shader_parameter("sun_direction", sun_direction)
		sky_material.set_shader_parameter("sun_intensity", sun_intensity)
		sky_material.set_shader_parameter("rayleigh_day_color", rayleigh_day_color)
		sky_material.set_shader_parameter("rayleigh_sunset_color", rayleigh_sunset_color)
		
	if surface_material:
		surface_material.set_shader_parameter("sun_direction", sun_direction)
		surface_material.set_shader_parameter("atmosphere_density", atmosphere_density * 0.6)

func _process(_delta: float) -> void:
	var clock = get_node_or_null("/root/SimulationClock")
	if clock and clock.has_method("get_sun_direction"):
		var new_sun_dir: Vector3 = clock.get_sun_direction(global_position)
		if new_sun_dir.distance_squared_to(sun_direction) > 0.0001:
			sun_direction = new_sun_dir
			needs_update = true
			
	if needs_update:
		_apply_parameters_to_materials()
		if _use_compute and pipeline.is_valid():
			_update_luts()
		needs_update = false

func _initialize_compute() -> void:
	var shader_file = load("res://shaders/atmosphere/atmosphere_luts.glsl")
	if shader_file:
		var spirv: RDShaderSPIRV = shader_file.get_spirv()
		shader = rd.shader_create_from_spirv(spirv)
		if shader.is_valid():
			pipeline = rd.compute_pipeline_create(shader)

func _create_textures() -> void:
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	
	fmt.width = TRANSMITTANCE_SIZE.x
	fmt.height = TRANSMITTANCE_SIZE.y
	transmittance_lut = rd.texture_create(fmt, RDTextureView.new())
	
	fmt.width = MULTISCATTERING_SIZE.x
	fmt.height = MULTISCATTERING_SIZE.y
	multiscattering_lut = rd.texture_create(fmt, RDTextureView.new())
	
	fmt.width = SKYVIEW_SIZE.x
	fmt.height = SKYVIEW_SIZE.y
	skyview_lut = rd.texture_create(fmt, RDTextureView.new())
	
	transmittance_tex = Texture2DRD.new()
	transmittance_tex.texture_rd_rid = transmittance_lut
	
	multiscattering_tex = Texture2DRD.new()
	multiscattering_tex.texture_rd_rid = multiscattering_lut
	
	skyview_tex = Texture2DRD.new()
	skyview_tex.texture_rd_rid = skyview_lut

func _update_luts() -> void:
	if not rd or not pipeline.is_valid():
		return
		
	var rayleigh = Vector3(5.8e-3, 1.35e-2, 3.31e-2)
	var mie = Vector3(3.996e-3, 3.996e-3, 3.996e-3)
	var p_radius_km = planet_radius / 1000.0
	var atmo_radius_km = atmosphere_radius / 1000.0
	
	var push_constant = PackedFloat32Array([
		rayleigh.x, rayleigh.y, rayleigh.z, p_radius_km,
		mie.x, mie.y, mie.z, atmo_radius_km,
		sun_direction.x, sun_direction.y, sun_direction.z, sun_intensity
	])
	
	var u1 = RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 0
	u1.add_id(transmittance_lut)
	
	var u2 = RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u2.binding = 1
	u2.add_id(multiscattering_lut)
	
	var u3 = RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u3.binding = 2
	u3.add_id(skyview_lut)
	
	var uniform_set = rd.uniform_set_create([u1, u2, u3], shader, 0)
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	
	var x_groups = ceili(256.0 / 8.0)
	var y_groups = ceili(100.0 / 8.0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()

func _exit_tree() -> void:
	if rd:
		if transmittance_lut.is_valid(): rd.free_rid(transmittance_lut)
		if multiscattering_lut.is_valid(): rd.free_rid(multiscattering_lut)
		if skyview_lut.is_valid(): rd.free_rid(skyview_lut)
		if pipeline.is_valid(): rd.free_rid(pipeline)
		if shader.is_valid(): rd.free_rid(shader)
