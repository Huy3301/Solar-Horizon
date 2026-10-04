class_name ScatterSystem
extends Node3D
## GPU-driven flora and rock scatter system.
## Reads terrain height and biome rules to populate a MultiMesh.

const MULTIMESH_MAX_INSTANCES = 10000

@export var multimesh_instance: MultiMeshInstance3D
@export var scatter_shader: RDShaderFile
@export var grid_size: int = 65
@export var cell_size: float = 1.0
@export var height_threshold: float = 10.0
@export var density: float = 0.5
@export var scale_min: float = 0.8
@export var scale_max: float = 1.5

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID

func _ready() -> void:
	if multimesh_instance and not multimesh_instance.multimesh:
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = MULTIMESH_MAX_INSTANCES
		mm.visible_instance_count = 0
		multimesh_instance.multimesh = mm
	
	if scatter_shader:
		_rd = RenderingServer.create_local_rendering_device()
		if _rd:
			var spirv: RDShaderSPIRV = scatter_shader.get_spirv()
			_shader = _rd.shader_create_from_spirv(spirv)
			_pipeline = _rd.compute_pipeline_create(_shader)

func update_scatter(heightmap: PackedFloat32Array) -> void:
	if not _rd or not _pipeline:
		return
		
	var heightmap_bytes := heightmap.to_byte_array()
	var heightmap_buffer = _rd.storage_buffer_create(heightmap_bytes.size(), heightmap_bytes)
	
	# InstanceData is 3 vec4s (12 floats, 48 bytes) per instance, but std140/std430 rules 
	# mean an array of structs with vec4s packs tightly. 
	var instance_buffer_size = MULTIMESH_MAX_INSTANCES * 48
	var instance_buffer = _rd.storage_buffer_create(instance_buffer_size)
	
	var counter_bytes = PackedInt32Array([0]).to_byte_array()
	var counter_buffer = _rd.storage_buffer_create(counter_bytes.size(), counter_bytes)
	
	var uniform1 = RDUniform.new()
	uniform1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform1.binding = 0
	uniform1.add_id(heightmap_buffer)
	
	var uniform2 = RDUniform.new()
	uniform2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform2.binding = 1
	uniform2.add_id(instance_buffer)
	
	var uniform3 = RDUniform.new()
	uniform3.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform3.binding = 2
	uniform3.add_id(counter_buffer)
	
	var uniform_set = _rd.uniform_set_create([uniform1, uniform2, uniform3], _shader, 0)
	
	# Push constants: max_instances, grid_size, scale_min, scale_max, height_threshold, density, cell_size
	var push_constant = PackedInt32Array([MULTIMESH_MAX_INSTANCES, grid_size]).to_byte_array()
	push_constant.append_array(PackedFloat32Array([scale_min, scale_max, height_threshold, density, cell_size]).to_byte_array())
	
	var compute_list = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
	_rd.compute_list_dispatch(compute_list, ceil(MULTIMESH_MAX_INSTANCES / 256.0), 1, 1)
	_rd.compute_list_end()
	
	_rd.submit()
	_rd.sync()
	
	var count_bytes = _rd.buffer_get_data(counter_buffer)
	var count_array = count_bytes.to_int32_array()
	var instance_count = count_array[0]
	
	if instance_count > 0:
		var result_bytes = _rd.buffer_get_data(instance_buffer, 0, instance_count * 48)
		var result_floats = result_bytes.to_float32_array()
		
		multimesh_instance.multimesh.buffer = result_floats
		multimesh_instance.multimesh.visible_instance_count = instance_count
	else:
		multimesh_instance.multimesh.visible_instance_count = 0
	
	_rd.free_rid(heightmap_buffer)
	_rd.free_rid(instance_buffer)
	_rd.free_rid(counter_buffer)
	_rd.free_rid(uniform_set)

func _exit_tree() -> void:
	if _rd:
		if _shader.is_valid():
			_rd.free_rid(_shader)
		_rd.free()
