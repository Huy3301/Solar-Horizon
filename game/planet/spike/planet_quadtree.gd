class_name SpikePlanetQuadtree extends Node3D

@export var planet_radius_m: float = 637000.0
@export var max_height_m: float = 8000.0
@export var patch_resolution: int = 65
@export var max_depth: int = 16
@export var split_distance_factor: float = 2.0
@export var max_patch_updates_per_frame: int = 8

# INTEGRATE(WP3): Use DVec3 for camera position
var camera_pos: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var planet_center: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])

var grid_mesh: ArrayMesh
var patch_pool: Array[MeshInstance3D] = []
var active_patches: Array = []
var root_nodes: Array = []
var material_pool: Array[ShaderMaterial] = []

var gpu_generator: SpikeGPUHeightGenerator

class PatchNode:
	var face: int
	var offset: Vector2
	var scale: float
	var depth: int
	var children: Array[PatchNode] = []
	var instance: MeshInstance3D = null
	var center_dir: Vector3
	var center_double: PackedFloat64Array
	var bounds_radius: float

func _ready():
	if OS.has_feature("mobile"):
		patch_resolution = 33
		
	gpu_generator = SpikeGPUHeightGenerator.new()
	
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
			st.add_vertex(Vector3(uv.x, uv.y, 0)) # Z is unused, we just use UV
			
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
	# Simplified center
	var uv_center = node.offset + Vector2(0.5, 0.5) * node.scale
	var c_dir = _get_spherified_dir(node.face, uv_center)
	node.center_dir = c_dir
	
	node.center_double = PackedFloat64Array([
		planet_center[0] + c_dir.x * planet_radius_m,
		planet_center[1] + c_dir.y * planet_radius_m,
		planet_center[2] + c_dir.z * planet_radius_m
	])
	# Approximation for bounds: diagonal of the patch
	node.bounds_radius = (node.scale * PI * 0.5 * planet_radius_m) / 2.0

func _get_spherified_dir(face: int, uv: Vector2) -> Vector3:
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
	
	# Evaluate tree
	var visible_nodes = []
	for root in root_nodes:
		_process_node(root, visible_nodes)
		
	# Update active instances
	_update_instances(visible_nodes)

func _process_node(node: PatchNode, visible_nodes: Array):
	var dist_sq = _dist_sq(node.center_double, camera_pos)
	var dist = sqrt(dist_sq)
	var split_dist = node.bounds_radius * split_distance_factor
	
	if dist < split_dist and node.depth < max_depth:
		if node.children.is_empty():
			_split(node)
		for child in node.children:
			_process_node(child, visible_nodes)
	else:
		if not node.children.is_empty():
			node.children.clear() # GC handles them. Real imp might pool nodes too.
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

func _dist_sq(p1: PackedFloat64Array, p2: PackedFloat64Array) -> float:
	var dx = p1[0] - p2[0]
	var dy = p1[1] - p2[1]
	var dz = p1[2] - p2[2]
	return dx*dx + dy*dy + dz*dz

func _update_instances(visible_nodes: Array):
	var current_instances = []
	for node in visible_nodes:
		if not node.instance:
			node.instance = _get_patch_instance()
			_setup_instance(node)
		
		# Update transform relative to camera
		var rel_x = node.center_double[0] - camera_pos[0]
		var rel_y = node.center_double[1] - camera_pos[1]
		var rel_z = node.center_double[2] - camera_pos[2]
		node.instance.position = Vector3(rel_x, rel_y, rel_z)
		current_instances.append(node.instance)
		
	for inst in active_patches:
		if not current_instances.has(inst):
			_recycle_instance(inst)
			
	active_patches = current_instances
	
	_update_collision(visible_nodes)

var current_collider_node: PatchNode = null
var collision_body: StaticBody3D = null

func _update_collision(visible_nodes: Array):
	# Find the deepest node near the camera
	var best_node = null
	var min_dist = 2000.0
	
	for node in visible_nodes:
		var d = sqrt(_dist_sq(node.center_double, camera_pos)) - planet_radius_m
		if d < min_dist:
			min_dist = d
			best_node = node
			
	if best_node != current_collider_node:
		current_collider_node = best_node
		_generate_collision(best_node)

func _generate_collision(node: PatchNode):
	if collision_body:
		collision_body.queue_free()
		collision_body = null
		
	if not node:
		return
		
	collision_body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var mesh_shape = ConcavePolygonShape3D.new()
	
	var res = 16 # smaller res for collision
	var faces = PackedVector3Array()
	var step = 1.0 / (res - 1)
	
	var verts = []
	for y in range(res):
		for x in range(res):
			var uv = node.offset + Vector2(x * step, y * step) * node.scale
			var dir = _get_spherified_dir(node.face, uv)
			var h = SpikeTerrainNoise.sample_height(dir.x, dir.y, dir.z)
			var world_pos_from_center = dir * (planet_radius_m + h * max_height_m)
			verts.append(world_pos_from_center - (node.center_dir * planet_radius_m))
			
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
	shape.shape = mesh_shape
	collision_body.add_child(shape)
	
	var rel_x = node.center_double[0] - camera_pos[0]
	var rel_y = node.center_double[1] - camera_pos[1]
	var rel_z = node.center_double[2] - camera_pos[2]
	collision_body.position = Vector3(rel_x, rel_y, rel_z)
	
	add_child(collision_body)


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
		mat.shader = preload("res://game/planet/spike/terrain_patch.gdshader")
	
	mat.set_shader_parameter("patch_offset", node.offset)
	mat.set_shader_parameter("patch_scale", node.scale)
	mat.set_shader_parameter("face_index", node.face)
	mat.set_shader_parameter("planet_radius", planet_radius_m)
	mat.set_shader_parameter("max_height", max_height_m)
	mat.set_shader_parameter("patch_center_local", node.center_dir * planet_radius_m)
	
	if gpu_generator.is_available:
		mat.set_shader_parameter("use_gpu_height", true)
		# For spike, we aren't fetching the RID texture into the material correctly,
		# Godot 4 texture RIDs can be wrapped in a Texture2DRD.
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

func set_camera_pos_double(x: float, y: float, z: float):
	camera_pos[0] = x
	camera_pos[1] = y
	camera_pos[2] = z
