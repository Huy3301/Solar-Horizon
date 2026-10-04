class_name PlanetQuadtree extends Node3D

@export var planet_radius_m: float = 637000.0
@export var max_height_m: float = 8000.0
@export var patch_resolution: int = 65
@export var max_depth: int = 16
@export var split_distance_factor: float = 2.0
@export var max_patch_updates_per_frame: int = 8

var camera_pos: DVec3 = DVec3.zero()
var planet_center: DVec3 = DVec3.zero()

var grid_mesh: ArrayMesh
var patch_pool: Array[MeshInstance3D] = []
var active_patches: Array = []
var root_nodes: Array = []
var material_pool: Array[ShaderMaterial] = []

var gpu_generator: GPUHeightGenerator
var chunk_streamer: ChunkStreamer

class PatchNode:
	var face: int
	var offset: Vector2
	var scale: float
	var depth: int
	var children: Array[PatchNode] = []
	var instance: MeshInstance3D = null
	var center_dir: Vector3
	var center_double: DVec3
	var bounds_radius: float
	var generating_collision: bool = false

func _ready():
	if OS.has_feature("mobile"):
		patch_resolution = 33
		
	gpu_generator = GPUHeightGenerator.new()
	chunk_streamer = ChunkStreamer.new(gpu_generator)
	
	_create_grid_mesh()
	_init_roots()

func _create_grid_mesh():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var res = patch_resolution
	var step = 1.0 / (res - 1)
	for y in range(res):
		for x in range(res):
			var uv = Vector2(x * step, y * step)
			st.set_uv(uv)
			st.add_vertex(Vector3(uv.x, uv.y, 0))
	for y in range(res - 1):
		for x in range(res - 1):
			var i0 = y * res + x
			var i1 = i0 + 1
			var i2 = (y + 1) * res + x
			var i3 = i2 + 1
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)
	grid_mesh = st.commit()

func _init_roots():
	for i in range(6):
		var root = PatchNode.new()
		root.face = i
		root.offset = Vector2(0, 0)
		root.scale = 1.0
		root.depth = 0
		_calc_bounds(root)
		root_nodes.append(root)

func _calc_bounds(node: PatchNode):
	var uv_center = node.offset + Vector2(0.5, 0.5) * node.scale
	var c_dir = get_spherified_dir(node.face, uv_center)
	node.center_dir = c_dir
	node.center_double = planet_center.add(DVec3.new(c_dir.x * planet_radius_m, c_dir.y * planet_radius_m, c_dir.z * planet_radius_m))
	node.bounds_radius = (node.scale * PI * 0.5 * planet_radius_m) / 2.0

static func get_spherified_dir(face: int, uv: Vector2) -> Vector3:
	var p = uv * 2.0 - Vector2(1.0, 1.0)
	var v = Vector3()
	if face == 0: v = Vector3(1.0, -p.y, -p.x)
	elif face == 1: v = Vector3(-1.0, -p.y, p.x)
	elif face == 2: v = Vector3(p.x, 1.0, p.y)
	elif face == 3: v = Vector3(p.x, -1.0, -p.y)
	elif face == 4: v = Vector3(p.x, -p.y, 1.0)
	elif face == 5: v = Vector3(-p.x, -p.y, -1.0)
	var x2 = v.x * v.x
	var y2 = v.y * v.y
	var z2 = v.z * v.z
	return Vector3(
		v.x * sqrt(max(0.0, 1.0 - y2/2.0 - z2/2.0 + y2*z2/3.0)),
		v.y * sqrt(max(0.0, 1.0 - x2/2.0 - z2/2.0 + x2*z2/3.0)),
		v.z * sqrt(max(0.0, 1.0 - x2/2.0 - y2/2.0 + x2*y2/3.0))
	).normalized()

func _process(_delta):
	gpu_generator.begin_frame()
	var visible_nodes = []
	for root in root_nodes:
		_process_node(root, visible_nodes)
	_update_instances(visible_nodes)

func _process_node(node: PatchNode, visible_nodes: Array):
	var dist = node.center_double.distance_to(camera_pos)
	var split_dist = node.bounds_radius * split_distance_factor
	if dist < split_dist and node.depth < max_depth:
		if node.children.is_empty():
			_split(node)
		for child in node.children:
			_process_node(child, visible_nodes)
	else:
		if not node.children.is_empty():
			node.children.clear()
		visible_nodes.append(node)

func _split(node: PatchNode):
	var s = node.scale * 0.5
	for i in range(4):
		var child = PatchNode.new()
		child.face = node.face
		child.scale = s
		child.offset = node.offset + Vector2(i % 2, i / 2) * s
		child.depth = node.depth + 1
		_calc_bounds(child)
		node.children.append(child)

func _update_instances(visible_nodes: Array):
	var current_instances = []
	for node in visible_nodes:
		if not node.instance:
			node.instance = _get_patch_instance()
			_setup_instance(node)
		node.instance.position = node.center_double.to_local_vector3(camera_pos)
		current_instances.append(node.instance)
		
	for inst in active_patches:
		if not current_instances.has(inst):
			_recycle_instance(inst)
	active_patches = current_instances
	_update_collision_async(visible_nodes)

var current_collider_node: PatchNode = null
var collision_body: StaticBody3D = null

func _update_collision_async(visible_nodes: Array):
	var best_node = null
	var min_dist = 2000.0
	for node in visible_nodes:
		var d = node.center_double.distance_to(camera_pos) - planet_radius_m
		if d < min_dist:
			min_dist = d
			best_node = node
			
	if best_node != current_collider_node and best_node != null and not best_node.generating_collision:
		best_node.generating_collision = true
		
		var node_data = {
			'face': best_node.face,
			'offset': best_node.offset,
			'scale': best_node.scale,
			'planet_radius_m': planet_radius_m,
			'max_height_m': max_height_m,
			'center_dir': best_node.center_dir
		}
		
		chunk_streamer.request_chunk(node_data, Callable(self, "_on_collision_generated").bind(best_node))

func _on_collision_generated(collision_shape: ConcavePolygonShape3D, node: PatchNode):
	node.generating_collision = false
	if current_collider_node != node:
		current_collider_node = node
		if collision_body:
			collision_body.queue_free()
		collision_body = StaticBody3D.new()
		var shape = CollisionShape3D.new()
		shape.shape = collision_shape
		collision_body.add_child(shape)
		collision_body.position = node.center_double.to_local_vector3(camera_pos)
		add_child(collision_body)
	else:
		if collision_body:
			collision_body.position = node.center_double.to_local_vector3(camera_pos)

func _get_patch_instance() -> MeshInstance3D:
	if patch_pool.size() > 0:
		var inst = patch_pool.pop_back()
		inst.visible = true
		return inst
	var inst = MeshInstance3D.new()
	inst.mesh = grid_mesh
	add_child(inst)
	return inst

func _setup_instance(node: PatchNode):
	var mat: ShaderMaterial
	if material_pool.size() > 0:
		mat = material_pool.pop_back()
	else:
		mat = ShaderMaterial.new()
		mat.shader = preload("res://game/planet/core/terrain_patch.gdshader")
	
	mat.set_shader_parameter("patch_offset", node.offset)
	mat.set_shader_parameter("patch_scale", node.scale)
	mat.set_shader_parameter("face_index", node.face)
	mat.set_shader_parameter("planet_radius", planet_radius_m)
	mat.set_shader_parameter("max_height", max_height_m)
	mat.set_shader_parameter("patch_center_local", node.center_dir * planet_radius_m)
	
	if gpu_generator.is_available:
		mat.set_shader_parameter("use_gpu_height", true)
		var tex_rid = gpu_generator.generate_height_map(node.face, node.offset, node.scale, patch_resolution)
		if tex_rid.is_valid():
			var tex = Texture2DRD.new()
			tex.texture_rd_rid = tex_rid
			mat.set_shader_parameter("height_map", tex)
			node.instance.set_meta("gpu_tex", tex)
		else:
			mat.set_shader_parameter("use_gpu_height", false)
	else:
		mat.set_shader_parameter("use_gpu_height", false)
		
	node.instance.material_override = mat

func _recycle_instance(inst: MeshInstance3D):
	inst.visible = false
	if inst.has_meta("gpu_tex"):
		var tex = inst.get_meta("gpu_tex")
		if tex and tex.texture_rd_rid.is_valid():
			gpu_generator.free_texture(tex.texture_rd_rid)
		inst.remove_meta("gpu_tex")
		
	var mat = inst.material_override
	if mat:
		material_pool.append(mat)
		inst.material_override = null
		
	patch_pool.append(inst)
