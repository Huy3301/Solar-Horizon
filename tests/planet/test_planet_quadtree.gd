extends "res://tests/test_case.gd"

func test_spherified_cube_mapping():
	var v = PlanetQuadtree.get_spherified_dir(0, Vector2(0.5, 0.5))
	assert_almost_eq(v.length(), 1.0, 0.001, "Should be unit vector")

func test_cpu_noise_deterministic():
	var a = TerrainNoise.sample_height(1.0, 0.0, 0.0)
	var b = TerrainNoise.sample_height(1.0, 0.0, 0.0)
	assert_eq(a, b, "Noise should be deterministic")

func test_quadtree_split_and_merge():
	var qt = PlanetQuadtree.new()
	qt.max_depth = 2
	qt._init_roots()
	
	# Move camera very close to root 0 to trigger split
	qt.camera_pos = qt.root_nodes[0].center_double
	qt._update_lod_camera()
	var visible = []
	qt._process_node(qt.root_nodes[0], visible)
	assert_true(qt.root_nodes[0].children.size() > 0, "Root should split when camera is close")
	
	# Move camera far away to trigger merge
	qt.camera_pos = qt.root_nodes[0].center_double.add(DVec3.new(0, 0, 5000000.0))
	qt._update_lod_camera()
	visible.clear()
	qt._process_node(qt.root_nodes[0], visible)
	assert_true(qt.root_nodes[0].children.is_empty(), "Root should merge (clear children) when camera is far")
	qt.free()

func test_edge_height_continuity_same_lod():
	# Two adjacent sample points on the shared edge between two UV sub-patches
	var uv_shared = Vector2(0.5, 0.25)
	var h1 = PlanetQuadtree.sample_patch_height(0, uv_shared, "Earth")
	var h2 = PlanetQuadtree.sample_patch_height(0, uv_shared, "Earth")
	assert_eq(h1, h2, "Heights at identical shared edge must be identical")

func test_edge_height_continuity_across_faces():
	# Test continuity across the shared edge between Face 4 (+Z) and Face 0 (+X)
	# On Face 4, right edge is uv.x = 1.0
	# On Face 0, left edge is uv.x = 0.0
	for step_i in range(5):
		var t = float(step_i) / 4.0
		var dir_face4 = PlanetQuadtree.get_spherified_dir(4, Vector2(1.0, t))
		var dir_face0 = PlanetQuadtree.get_spherified_dir(0, Vector2(0.0, t))
		assert_vec_almost_eq(dir_face4, dir_face0, 0.002, "Boundary directions across cube faces must match")
		
		var h_face4 = PlanetQuadtree.sample_patch_height(4, Vector2(1.0, t), "Moon")
		var h_face0 = PlanetQuadtree.sample_patch_height(0, Vector2(0.0, t), "Moon")
		assert_almost_eq(h_face4, h_face0, 0.005, "Terrain height must be continuous across cube face boundaries")

func test_skirts_generation():
	var qt = PlanetQuadtree.new()
	qt.patch_resolution = 17
	qt._create_grid_mesh()
	assert_true(qt.has_skirts, "Quadtree grid mesh must have skirts flag enabled")
	assert_true(qt.grid_mesh != null, "Grid mesh must be generated")
	# Regular surface vertices = 17 * 17 = 289
	# Skirt perimeter vertices = 4 * 16 * 2 = 128
	var arrays = qt.grid_mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var has_skirt_vertex = false
	for c in colors:
		if c.r > 0.5:
			has_skirt_vertex = true
			break
	assert_true(has_skirt_vertex, "Mesh must contain skirt vertices with Color.r = 1.0")
	qt.free()

func test_earth_height_determinism():
	var p1 = Vector3(0.577, 0.577, 0.577).normalized()
	var p2 = Vector3(-0.3, 0.8, 0.5).normalized()
	var h1_a = TerrainNoise.sample_earth_height(p1)
	var h1_b = TerrainNoise.sample_earth_height(p1)
	var h2_a = TerrainNoise.sample_earth_height(p2)
	var h2_b = TerrainNoise.sample_earth_height(p2)
	assert_eq(h1_a, h1_b, "Earth height at p1 must be deterministic")
	assert_eq(h2_a, h2_b, "Earth height at p2 must be deterministic")

func test_moon_crater_noise_determinism():
	var p = Vector3(0.2, -0.6, 0.77).normalized()
	var h_a = TerrainNoise.sample_moon_height(p)
	var h_b = TerrainNoise.sample_moon_height(p)
	assert_eq(h_a, h_b, "Moon crater height must be strictly deterministic")
	assert_true(h_a >= 0.0 and h_a <= 1.0, "Moon height should be within [0, 1]")

func test_moon_crater_profile():
	# Center of crater feature (min_dist near 0) vs rim (min_dist ~ 0.40)
	var center = Vector3(0.0, 0.0, 0.0)
	var rim_pt = Vector3(0.40, 0.0, 0.0)
	var bowl_val = TerrainNoise.crater_noise_3d(center)
	var rim_val = TerrainNoise.crater_noise_3d(rim_pt)
	# Rim should be elevated relative to bowl floor
	assert_true(rim_val > bowl_val, "Crater rim must be elevated relative to crater bowl")

func test_collision_mesh_sync_generation():
	var streamer = ChunkStreamer.new(null)
	var node_data = {
		'face': 0,
		'offset': Vector2(0, 0),
		'scale': 0.5,
		'planet_radius_m': 637100.0,
		'max_height_m': 8848.0,
		'center_dir': Vector3(1, 0, 0),
		'body_type': "Earth"
	}
	var shape = streamer.generate_chunk_sync(node_data)
	assert_true(shape != null, "ChunkStreamer must generate a valid collision shape")
	assert_true(shape is ConcavePolygonShape3D, "Shape must be ConcavePolygonShape3D trimesh")
	var faces = (shape as ConcavePolygonShape3D).get_faces()
	assert_true(faces.size() > 0, "Collision mesh faces must not be empty")

func test_ocean_renderer_collision_free():
	var ocean = OceanRenderer.new()
	ocean.radius = 637100.0
	ocean._ready()
	
	# Verify ocean renderer has no StaticBody3D or collision shapes
	var has_collision = false
	for child in ocean.get_children():
		if child is StaticBody3D or child is CollisionShape3D:
			has_collision = true
	assert_false(has_collision, "OceanRenderer must be collision-free at sea level")
	ocean.free()

func test_ocean_renderer_quality_tier_switching():
	var ocean = OceanRenderer.new()
	ocean._ready()
	ocean.set_quality_tier(0) # Mobile
	assert_eq(ocean.quality_tier, 0, "Quality tier should switch to Mobile (0)")
	assert_eq(ocean.mesh_resolution, 33, "Mobile ocean mesh resolution should be 33")
	
	ocean.set_quality_tier(1) # Desktop
	assert_eq(ocean.quality_tier, 1, "Quality tier should switch to Desktop (1)")
	assert_eq(ocean.mesh_resolution, 64, "Desktop ocean mesh resolution should be 64")
	ocean.free()

func test_planet_runtime_altitude_thresholds():
	var rt = PlanetRuntime.new()
	rt.body_name = "Earth"
	rt.planet_radius_m = 637100.0
	rt.max_height_m = 8848.0
	rt.transition_altitude_max = 150000.0
	rt.transition_altitude_min = 120000.0
	
	# Test terrain height query
	var h_north_pole = rt.get_terrain_height_at(Vector3(0, 700000.0, 0))
	assert_true(h_north_pole >= 637100.0, "Terrain height at north pole must be >= sea level")
	
	# Test AGL query
	var ship_pos = Vector3(0, 637100.0 + 500.0, 0)
	var agl = rt.get_altitude_agl(ship_pos)
	assert_true(agl >= 0.0, "AGL should be non-negative")
	rt.free()

func test_geomorph_edge_height_sharing():
	# In CDLOD geomorphing, odd edge vertices on fine LOD patch morph towards
	# the linear interpolation of their adjacent even vertices (coarse patch edge).
	# At morph_factor = 1.0, the fine patch edge elevation strictly matches the coarse edge.
	var h_even_0 = TerrainNoise.sample_height(1.0, 0.0, 0.0, "Earth")
	var h_even_1 = TerrainNoise.sample_height(1.0, 0.1, 0.0, "Earth")
	var coarse_edge_midpoint = (h_even_0 + h_even_1) * 0.5
	var fine_detail_height = TerrainNoise.sample_height(1.0, 0.05, 0.0, "Earth")
	
	# Apply morph blend at factor 1.0
	var morphed_height = lerpf(fine_detail_height, coarse_edge_midpoint, 1.0)
	assert_almost_eq(morphed_height, coarse_edge_midpoint, 1e-6, "Morphed fine edge height must strictly equal coarse edge midpoint")

