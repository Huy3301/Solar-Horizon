class_name GPUHeightGenerator extends RefCounted

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var max_dispatches_per_frame: int = 8
var current_dispatches: int = 0
var is_available: bool = false

func _init():
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_warning("GPU heights unavailable (no RenderingDevice). Falling back to CPU/analytic.")
		return
		
	var shader_file = load("res://game/planet/core/terrain_height.glsl")
	if not shader_file:
		push_warning("Failed to load compute shader.")
		return
		
	var spirv = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		push_warning("Failed to compile compute shader.")
		return
		
	pipeline = rd.compute_pipeline_create(shader)
	is_available = true

func begin_frame():
	current_dispatches = 0

func can_dispatch() -> bool:
	return is_available and current_dispatches < max_dispatches_per_frame

func generate_height_map(face_index: int, patch_offset: Vector2, patch_scale: float, res: int, body_type: int = 0) -> RID:
	if not can_dispatch():
		return RID()
		
	current_dispatches += 1
	
	var fmt := RDTextureFormat.new()
	fmt.width = res
	fmt.height = res
	fmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var tex = rd.texture_create(fmt, RDTextureView.new(), [])
	
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(tex)
	var uniform_set = rd.uniform_set_create([uniform], shader, 0)
	
	# push constants: vec2 offset (8b), float scale (4b), int face_index (4b), int res (4b), int body_type (4b) -> 24 bytes
	var pc = PackedByteArray()
	pc.resize(24)
	pc.encode_float(0, patch_offset.x)
	pc.encode_float(4, patch_offset.y)
	pc.encode_float(8, patch_scale)
	pc.encode_s32(12, face_index)
	pc.encode_s32(16, res)
	pc.encode_s32(20, body_type)

	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, pc, pc.size())
	
	var groups = ceili(float(res) / 8.0)
	rd.compute_list_dispatch(compute_list, groups, groups, 1)
	rd.compute_list_end()
	
	return tex

func free_texture(tex: RID):
	if rd and tex.is_valid():
		rd.free_rid(tex)
