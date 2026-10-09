class_name PlanetQuadtree extends Node3D

@export var body_name: String = "Earth"
@export var planet_radius_m: float = 637100.0
@export var max_height_m: float = 8848.0
@export var patch_resolution: int = 33
@export var max_depth: int = 12
@export var split_distance_factor: float = 2.0
@export var max_patch_updates_per_frame: int = 8
@export var max_active_patches: int = 64
@export var transition_altitude_max: float = 150000.0
@export var transition_altitude_min: float = 120000.0

var camera_pos: DVec3 = DVec3.zero()
## Camera position for LOD / collision decisions: same direction, but at (radius + height ABOVE THE TERRAIN)
## instead of above the sea-level sphere. Patch centres sit on the sphere, so without this a ship standing
## on a 2 km plateau would be "2 km from every patch" and never get fine terrain or a collider.
var lod_camera_pos: DVec3 = DVec3.zero()
var planet_center: DVec3 = DVec3.zero()
var is_terrain_active: bool = true
var has_skirts: bool = true

var grid_mesh: ArrayMesh
var patch_pool: Array[MeshInstance3D] = []
var active_patches: Array = []
var root_nodes: Array = []
var material_pool: Array[ShaderMaterial] = []

var gpu_generator: GPUHeightGenerator
var chunk_streamer: ChunkStreamer
var current_collider_node: PatchNode = null
var collision_body: StaticBody3D = null  # legacy single-patch collider (kept for API compatibility)

## World-space position of the camera/ship and the planet's orientation, set by PlanetRuntime each frame.
## Patch instances are placed relative to the camera (small numbers) in world space, never through
## the planet's own (hundreds-of-km) position, so they stay precise and correctly placed.
var camera_world_pos: Vector3 = Vector3.ZERO
var planet_basis: Basis = Basis.IDENTITY
var last_leaves: Array = []

## Ring of collision patches around the camera (one StaticBody3D per leaf patch)
@export var max_collision_patches: int = 9
@export var collision_radius_factor: float = 2.2
@export var collision_min_radius_m: float = 400.0
@export var collision_max_altitude_m: float = 30000.0
var collision_bodies: Dictionary = {}   # PatchNode -> StaticBody3D
var _collision_pending: Dictionary = {} # PatchNode -> true

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

func _ready() -> void:
	if OS.has_feature("mobile"):
		patch_resolution = 33
		max_depth = 8
		split_distance_factor = 1.8
		max_active_patches = 48
	else:
		patch_resolution = 33
		max_depth = 12
		max_active_patches = 64
		
	gpu_generator = GPUHeightGenerator.new()
	chunk_streamer = ChunkStreamer.new(gpu_generator)
	
	_create_grid_mesh()
	_init_roots()

func _create_grid_mesh() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var res = patch_resolution
	var step = 1.0 / (res - 1)
	
	# 1. Surface grid vertices (Color.r = 0.0 indicates surface vertex)
	for y in range(res):
		for x in range(res):
			var uv = Vector2(x * step, y * step)
			st.set_uv(uv)
			st.set_color(Color(0.0, 0.0, 0.0, 1.0))
			st.add_vertex(Vector3(uv.x, uv.y, 0.0))
			
	# Surface indices
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
			
	# 2. Skirt perimeter vertices (Color.r = 1.0 indicates skirt vertex extruded down in shader)
	var vert_count = res * res
	
	# Helper lambda to add a skirt quad along an edge segment
	var add_skirt_segment = func(u0: float, v0: float, u1: float, v1: float, s_idx0: int, s_idx1: int):
		var skirt_v0 = vert_count
		st.set_uv(Vector2(u0, v0))
		st.set_color(Color(1.0, 0.0, 0.0, 1.0))
		st.add_vertex(Vector3(u0, v0, 0.0))
		vert_count += 1
		
		var skirt_v1 = vert_count
		st.set_uv(Vector2(u1, v1))
		st.set_color(Color(1.0, 0.0, 0.0, 1.0))
		st.add_vertex(Vector3(u1, v1, 0.0))
		vert_count += 1
		
		st.add_index(s_idx0)
		st.add_index(skirt_v0)
		st.add_index(s_idx1)
		st.add_index(s_idx1)
		st.add_index(skirt_v0)
		st.add_index(skirt_v1)
	
	# Bottom edge: y = 0
	for x in range(res - 1):
		var v0 = x
		var v1 = x + 1
		add_skirt_segment.call(x * step, 0.0, (x + 1) * step, 0.0, v0, v1)
		
	# Right edge: x = res - 1
	for y in range(res - 1):
		var v0 = y * res + (res - 1)
		var v1 = (y + 1) * res + (res - 1)
		add_skirt_segment.call(1.0, y * step, 1.0, (y + 1) * step, v0, v1)
		
	# Top edge: y = res - 1
	for x in range(res - 1):
		var v0 = (res - 1) * res + x + 1
		var v1 = (res - 1) * res + x
		add_skirt_segment.call((x + 1) * step, 1.0, x * step, 1.0, v0, v1)
		
	# Left edge: x = 0
	for y in range(res - 1):
		var v0 = (y + 1) * res
		var v1 = y * res
		add_skirt_segment.call(0.0, (y + 1) * step, 0.0, y * step, v0, v1)
		
	grid_mesh = st.commit()
	has_skirts = true

func _init_roots() -> void:
	root_nodes.clear()
	for i in range(6):
		var root = PatchNode.new()
		root.face = i
		root.offset = Vector2(0, 0)
		root.scale = 1.0
		root.depth = 0
		_calc_bounds(root)
		root_nodes.append(root)

func _calc_bounds(node: PatchNode) -> void:
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

static func sample_patch_height(face: int, uv: Vector2, body_type: String = "Earth") -> float:
	var dir = get_spherified_dir(face, uv)
	return TerrainNoise.sample_height(dir.x, dir.y, dir.z, body_type)

func _update_lod_camera() -> void:
	var r: float = camera_pos.length()
	if r < 1.0:
		lod_camera_pos = camera_pos
		return
	var inv: float = 1.0 / r
	var dx: float = camera_pos.x * inv
	var dy: float = camera_pos.y * inv
	var dz: float = camera_pos.z * inv
	var terrain_h: float = TerrainNoise.sample_height(dx, dy, dz, body_name) * max_height_m
	var agl: float = maxf(0.0, r - planet_radius_m - terrain_h)
	var rr: float = planet_radius_m + agl
	lod_camera_pos = DVec3.new(dx * rr, dy * rr, dz * rr)

func _process(_delta: float) -> void:
	_update_lod_camera()
	# Far LOD altitude check: if camera is far above transition altitude, deactivate quadtree to save GPU
	var cam_dist = camera_pos.length()
	var alt_asl = cam_dist - planet_radius_m
	if alt_asl > transition_altitude_max:
		if is_terrain_active:
			_deactivate_terrain()
		return
	else:
		if not is_terrain_active:
			_activate_terrain()

	gpu_generator.begin_frame()
	var visible_nodes = []
	for root in root_nodes:
		_process_node(root, visible_nodes)
	_update_instances(visible_nodes)

func _deactivate_terrain() -> void:
	is_terrain_active = false
	for inst in active_patches:
		_recycle_instance(inst)
	active_patches.clear()
	_clear_collision_ring()

func _activate_terrain() -> void:
	is_terrain_active = true
	if collision_body:
		collision_body.visible = true

func _process_node(node: PatchNode, visible_nodes: Array) -> void:
	var dist = node.center_double.distance_to(lod_camera_pos)
	var split_dist = node.bounds_radius * split_distance_factor
	if dist < split_dist and node.depth < max_depth and visible_nodes.size() < max_active_patches:
		if node.children.is_empty():
			_split(node)
		for child in node.children:
			_process_node(child, visible_nodes)
	else:
		if not node.children.is_empty():
			node.children.clear()
		visible_nodes.append(node)

func _split(node: PatchNode) -> void:
	var s = node.scale * 0.5
	for i in range(4):
		var child = PatchNode.new()
		child.face = node.face
		child.scale = s
		child.offset = node.offset + Vector2(i % 2, i / 2) * s
		child.depth = node.depth + 1
		_calc_bounds(child)
		node.children.append(child)

func _update_instances(visible_nodes: Array) -> void:
	var current_instances = []
	for node in visible_nodes:
		if not node.instance:
			node.instance = _get_patch_instance()
			_setup_instance(node)
		node.instance.global_transform = _patch_world_transform(node)
		current_instances.append(node.instance)
		
	for inst in active_patches:
		if not current_instances.has(inst):
			_recycle_instance(inst)
	active_patches = current_instances
	last_leaves = visible_nodes

## World transform of a patch: planet orientation, positioned relative to the camera in double precision.
func _patch_world_transform(node: PatchNode) -> Transform3D:
	var rel: Vector3 = node.center_double.sub(camera_pos).to_vector3()
	return Transform3D(planet_basis, camera_world_pos + planet_basis * rel)

func _physics_process(_delta: float) -> void:
	_update_collision_ring()

func is_collision_ready() -> bool:
	if collision_bodies.is_empty():
		return false
	# ready when the leaf patch closest to the camera has its collider
	var best: PatchNode = null
	var best_d: float = INF
	for node in last_leaves:
		var d: float = node.center_double.distance_to(lod_camera_pos)
		if d < best_d:
			best_d = d
			best = node
	return best != null and collision_bodies.has(best)

func _update_collision_ring() -> void:
	var alt_asl: float = camera_pos.length() - planet_radius_m
	if alt_asl > collision_max_altitude_m or not is_terrain_active:
		_clear_collision_ring()
		return
	# Nearest leaf patches within reach
	var cands: Array = []
	for node in last_leaves:
		var reach: float = maxf(node.bounds_radius * collision_radius_factor, collision_min_radius_m)
		var d: float = node.center_double.distance_to(lod_camera_pos)
		if d < reach + node.bounds_radius:
			cands.append({"node": node, "d": d})
	cands.sort_custom(func(a, b): return a["d"] < b["d"])
	var desired: Array = []
	for i in range(mini(max_collision_patches, cands.size())):
		desired.append(cands[i]["node"])

	for node in desired:
		if not collision_bodies.has(node) and not _collision_pending.has(node):
			_request_collision(node)

	# Only drop colliders that are no longer desired once the nearest few are covered (no holes)
	var nearest_covered: bool = true
	for i in range(mini(3, desired.size())):
		if not collision_bodies.has(desired[i]):
			nearest_covered = false
	if nearest_covered:
		for node in collision_bodies.keys():
			if not desired.has(node):
				var body: StaticBody3D = collision_bodies[node]
				if is_instance_valid(body):
					body.queue_free()
				collision_bodies.erase(node)

	# Keep every collider glued to its patch in world space (planet-local data, camera-relative placement)
	for node in collision_bodies.keys():
		var body: StaticBody3D = collision_bodies[node]
		if not is_instance_valid(body):
			collision_bodies.erase(node)
			continue
		var t: Transform3D = _patch_world_transform(node)
		if body.global_transform.origin.distance_to(t.origin) > 0.01 or not body.global_transform.basis.is_equal_approx(t.basis):
			body.global_transform = t

func _request_collision(node: PatchNode) -> void:
	_collision_pending[node] = true
	var node_data = {
		'face': node.face,
		'offset': node.offset,
		'scale': node.scale,
		'planet_radius_m': planet_radius_m,
		'max_height_m': max_height_m,
		'center_dir': node.center_dir,
		'body_type': body_name
	}
	chunk_streamer.request_chunk(node_data, Callable(self, "_on_collision_generated").bind(node))

func _on_collision_generated(collision_shape: ConcavePolygonShape3D, node: PatchNode) -> void:
	_collision_pending.erase(node)
	if not is_inside_tree() or collision_bodies.has(node):
		return
	collision_shape.backface_collision = true
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	body.top_level = true
	var shape := CollisionShape3D.new()
	shape.shape = collision_shape
	body.add_child(shape)
	add_child(body)
	body.global_transform = _patch_world_transform(node)
	collision_bodies[node] = body

func _clear_collision_ring() -> void:
	for node in collision_bodies.keys():
		var body: StaticBody3D = collision_bodies[node]
		if is_instance_valid(body):
			body.queue_free()
	collision_bodies.clear()

func _get_patch_instance() -> MeshInstance3D:
	if patch_pool.size() > 0:
		var inst = patch_pool.pop_back()
		inst.visible = true
		return inst
	var inst = MeshInstance3D.new()
	inst.mesh = grid_mesh
	inst.top_level = true
	add_child(inst)
	return inst

func _setup_instance(node: PatchNode) -> void:
	var mat: ShaderMaterial
	if material_pool.size() > 0:
		mat = material_pool.pop_back()
	else:
		mat = ShaderMaterial.new()
		mat.shader = preload("res://shaders/terrain/terrain_splat.gdshader")
	
	mat.set_shader_parameter("body_type", 1 if body_name == "Moon" else 0)
	mat.set_shader_parameter("patch_offset", node.offset)
	mat.set_shader_parameter("patch_scale", node.scale)
	mat.set_shader_parameter("face_index", node.face)
	mat.set_shader_parameter("planet_radius", planet_radius_m)
	mat.set_shader_parameter("max_height", max_height_m)
	mat.set_shader_parameter("patch_center_local", node.center_dir * planet_radius_m)
	mat.set_shader_parameter("patch_resolution", float(patch_resolution))
	
	# Geomorphing calculation: blend odd vertices to coarse level near split threshold
	var dist = node.center_double.distance_to(lod_camera_pos)
	var split_dist = node.bounds_radius * split_distance_factor
	var morph_start = split_dist * 0.65
	var morph = clampf((dist - morph_start) / maxf(1.0, split_dist - morph_start), 0.0, 1.0)
	mat.set_shader_parameter("morph_factor", morph)
	
	if gpu_generator.is_available:
		mat.set_shader_parameter("use_gpu_height", true)
		var body_int = 1 if body_name == "Moon" else 0
		var tex_rid = gpu_generator.generate_height_map(node.face, node.offset, node.scale, patch_resolution, body_int)
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

func _recycle_instance(inst: MeshInstance3D) -> void:
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
