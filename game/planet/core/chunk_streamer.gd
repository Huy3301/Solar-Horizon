class_name ChunkStreamer extends RefCounted

var pending_tasks: Array[int] = []
var active_gpu_generator: GPUHeightGenerator

func _init(gpu_generator: GPUHeightGenerator):
	active_gpu_generator = gpu_generator

func request_chunk(node, callback: Callable):
	var task_id = WorkerThreadPool.add_task(_generate_chunk.bind(node, callback), true, "GenerateChunk")
	pending_tasks.append(task_id)

func _generate_chunk(node_data: Dictionary, callback: Callable):
	var collision_data = _build_collision_mesh(node_data)
	callback.call_deferred(collision_data)

func _build_collision_mesh(node_data: Dictionary) -> ConcavePolygonShape3D:
	var mesh_shape = ConcavePolygonShape3D.new()
	var res = 16 
	var faces = PackedVector3Array()
	var step = 1.0 / (res - 1)
	
	var verts = []
	for y in range(res):
		for x in range(res):
			var uv = node_data.offset + Vector2(x * step, y * step) * node_data.scale
			var dir = PlanetQuadtree.get_spherified_dir(node_data.face, uv)
			var h = TerrainNoise.sample_height(dir.x, dir.y, dir.z)
			var world_pos_from_center = dir * (node_data.planet_radius_m + h * node_data.max_height_m)
			verts.append(world_pos_from_center - (node_data.center_dir * node_data.planet_radius_m))
			
	for y in range(res - 1):
		for x in range(res - 1):
			var i0 = y * res + x
			var i1 = i0 + 1
			var i2 = (y + 1) * res + x
			var i3 = i2 + 1
			faces.append(verts[i0])
			faces.append(verts[i2])
			faces.append(verts[i1])
			faces.append(verts[i1])
			faces.append(verts[i2])
			faces.append(verts[i3])
			
	mesh_shape.set_faces(faces)
	return mesh_shape

func wait_all():
	for task in pending_tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	pending_tasks.clear()
