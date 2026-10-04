class_name PlanetRuntime extends Node3D

## Planet Runtime Controller
## Coordinates the cube-sphere CDLOD quadtree, far-LOD sphere cross-fading,
## local collision patches, ocean rendering, and altitude AGL queries.

@export var body_name: String = "Earth"
@export var planet_radius_m: float = 637100.0
@export var max_height_m: float = 8848.0
@export var transition_altitude_max: float = 150000.0 # ~150 km Earth
@export var transition_altitude_min: float = 120000.0
@export var target_node: Node3D = null

var quadtree: PlanetQuadtree
var ocean_renderer: OceanRenderer
var far_lod_surface: MeshInstance3D
var origin_service: OriginService
var planet_universe_pos: UniversePosition

func _ready() -> void:
	# 1. Initialize CDLOD Quadtree
	quadtree = PlanetQuadtree.new()
	quadtree.body_name = body_name
	quadtree.planet_radius_m = planet_radius_m
	quadtree.max_height_m = max_height_m
	quadtree.transition_altitude_max = transition_altitude_max
	quadtree.transition_altitude_min = transition_altitude_min
	add_child(quadtree)
	
	# 2. Locate Far-LOD Surface mesh (e.g. EarthVisual/Surface or MoonVisual/Surface)
	var parent_node = get_parent()
	if parent_node:
		var surf = parent_node.get_node_or_null("Surface")
		if surf is MeshInstance3D:
			far_lod_surface = surf
			
	# 3. For Earth: Initialize spherical ocean renderer at sea level
	if body_name == "Earth":
		ocean_renderer = OceanRenderer.new()
		ocean_renderer.name = "OceanRenderer"
		add_child(ocean_renderer)
		ocean_renderer.setup(planet_radius_m)
	
	# 4. OriginService connection
	origin_service = get_node_or_null("/root/OriginService")
	if origin_service:
		origin_service.origin_shifted.connect(_on_origin_shifted)

	planet_universe_pos = UniversePosition.new()
	quadtree.planet_center = DVec3.zero()

func _process(_delta: float) -> void:
	if not target_node:
		# Auto-discover Ship or active camera
		var ship = get_tree().root.find_child("Ship", true, false)
		if ship is Node3D:
			target_node = ship
		else:
			var cam = get_viewport().get_camera_3d()
			if cam:
				target_node = cam
				
	if target_node and is_instance_valid(target_node):
		var target_world = target_node.global_position
		# Target position relative to planet center in local coordinates
		var target_local = to_local(target_world)
		var cam_dist = target_local.length()
		var alt_asl = cam_dist - planet_radius_m
		
		quadtree.camera_pos = DVec3.new(target_local.x, target_local.y, target_local.z)
		
		# Far-LOD cross-fade logic:
		if far_lod_surface and is_instance_valid(far_lod_surface):
			if alt_asl >= transition_altitude_max:
				far_lod_surface.visible = true
				far_lod_surface.transparency = 0.0
			elif alt_asl <= transition_altitude_min:
				far_lod_surface.visible = false
			else:
				far_lod_surface.visible = true
				var t = (alt_asl - transition_altitude_min) / (transition_altitude_max - transition_altitude_min)
				far_lod_surface.transparency = clampf(1.0 - t, 0.0, 1.0)

## Public API: query terrain elevation ASL at world coordinates
func get_terrain_height_at(world_pos: Vector3) -> float:
	var local_pos = to_local(world_pos) if is_inside_tree() else (world_pos - position)
	if local_pos.length_squared() < 1e-4:
		return planet_radius_m
	var dir = local_pos.normalized()
	var h_norm = TerrainNoise.sample_height(dir.x, dir.y, dir.z, body_name)
	return planet_radius_m + h_norm * max_height_m

## Public API: query Above Ground Level (AGL) altitude at world coordinates
func get_altitude_agl(ship_world_pos: Vector3) -> float:
	var local_pos = to_local(ship_world_pos) if is_inside_tree() else (ship_world_pos - position)
	var ship_r = local_pos.length()
	var terrain_r = get_terrain_height_at(ship_world_pos)
	return maxf(0.0, ship_r - terrain_r)

## Public API: query terrain surface normal at world coordinates
func get_surface_normal_at(world_pos: Vector3) -> Vector3:
	var local_pos = to_local(world_pos) if is_inside_tree() else (world_pos - position)
	if local_pos.length_squared() < 1e-4:
		return Vector3.UP
	var dir = local_pos.normalized()
	# Analytical normal approximation using spherical gradient
	var eps = 0.001
	var h0 = TerrainNoise.sample_height(dir.x, dir.y, dir.z, body_name)
	var hx = TerrainNoise.sample_height(dir.x + eps, dir.y, dir.z, body_name)
	var hy = TerrainNoise.sample_height(dir.x, dir.y + eps, dir.z, body_name)
	var hz = TerrainNoise.sample_height(dir.x, dir.y, dir.z + eps, body_name)
	var grad = Vector3(hx - h0, hy - h0, hz - h0) / eps
	var norm_local = (dir - grad * (max_height_m / planet_radius_m)).normalized()
	var basis_world = global_transform.basis if is_inside_tree() else transform.basis
	return basis_world * norm_local

func update_from_universe(camera_universe_pos: UniversePosition) -> void:
	var cam_local = camera_universe_pos.difference_to(planet_universe_pos)
	quadtree.camera_pos = cam_local
	
	if origin_service:
		quadtree.planet_center = planet_universe_pos.difference_to(origin_service.origin)
	else:
		quadtree.planet_center = DVec3.zero()

func _on_origin_shifted(_delta: DVec3) -> void:
	if origin_service:
		quadtree.planet_center = planet_universe_pos.difference_to(origin_service.origin)

func _exit_tree() -> void:
	if quadtree and quadtree.chunk_streamer:
		quadtree.chunk_streamer.wait_all()
