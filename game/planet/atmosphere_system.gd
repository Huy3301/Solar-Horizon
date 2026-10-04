class_name AtmosphereSystem
extends Node3D
## System for generating and managing Hillaire 2020 atmosphere LUTs and applying them to materials.

const TRANSMITTANCE_SIZE = Vector2i(256, 64)
const MULTISCATTERING_SIZE = Vector2i(32, 32)
const SKYVIEW_SIZE = Vector2i(200, 100)

var rd: RenderingDevice
var shader: RID
var pipeline: RID

var transmittance_lut: RID
var multiscattering_lut: RID
var skyview_lut: RID

var transmittance_tex: Texture2DRD
var multiscattering_tex: Texture2DRD
var skyview_tex: Texture2DRD

var body_def: Resource # CelestialBodyDef
var needs_update: bool = false

# Sun direction from SimulationClock/StarSystemRuntime
var _sun_direction: Vector3 = Vector3(0, 1, 0)
var _sun_intensity: float = 1.0

func _ready() -> void:
	# Use RenderingServer's singleton RenderingDevice (local)
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("AtmosphereSystem: RenderingDevice not available")
		return
		
	_initialize_compute()
	_create_textures()
	needs_update = true

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

func _process(_delta: float) -> void:
	# Ideally fetch this from a central SimulationClock or StarSystemRuntime
	var clock = get_node_or_null("/root/SimulationClock")
	if clock and clock.has_method("get_sun_direction"):
		var new_sun_dir = clock.get_sun_direction(global_position)
		if new_sun_dir.distance_squared_to(_sun_direction) > 0.001:
			_sun_direction = new_sun_dir
			needs_update = true
			
	if needs_update and pipeline.is_valid():
		_update_luts()
		needs_update = false

func set_body_def(def: Resource) -> void:
	body_def = def
	needs_update = true

func _update_luts() -> void:
	if not rd or not pipeline.is_valid():
		return
		
	# Prepare push constants
	var rayleigh = Vector3(5.8e-3, 1.35e-2, 3.31e-2)
	var mie = Vector3(3.996e-3, 3.996e-3, 3.996e-3)
	var planet_radius = 6360.0
	var atmosphere_radius = 6420.0
	
	if body_def:
		if "rayleigh_scattering" in body_def: rayleigh = body_def.rayleigh_scattering
		if "mie_scattering" in body_def: mie = body_def.mie_scattering
		if "radius" in body_def: planet_radius = body_def.radius / 1000.0
		if "atmosphere_height" in body_def: atmosphere_radius = planet_radius + (body_def.atmosphere_height / 1000.0)

	var push_constant = PackedFloat32Array([
		rayleigh.x, rayleigh.y, rayleigh.z, planet_radius,
		mie.x, mie.y, mie.z, atmosphere_radius,
		_sun_direction.x, _sun_direction.y, _sun_direction.z, _sun_intensity
	])
	
	# Create uniform set
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
	
	# Dispatch sizes based on LUT max dimensions (256x100) / 8
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
