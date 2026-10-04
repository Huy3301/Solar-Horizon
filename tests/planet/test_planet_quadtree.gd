extends "res://tests/test_case.gd"

func test_spherified_cube_mapping():
	var v = PlanetQuadtree.get_spherified_dir(0, Vector2(0.5, 0.5))
	assert_almost_eq(v.length(), 1.0, 0.001, "Should be unit vector")

func test_cpu_noise_deterministic():
	var a = TerrainNoise.sample_height(1.0, 0.0, 0.0)
	var b = TerrainNoise.sample_height(1.0, 0.0, 0.0)
	assert_eq(a, b, "Noise should be deterministic")

func test_quadtree_split():
	var qt = PlanetQuadtree.new()
	# Set max depth so we can split
	qt.max_depth = 2
	qt._init_roots()
	
	# Move camera very close to root 0
	qt.camera_pos = qt.root_nodes[0].center_double
	
	var visible = []
	qt._process_node(qt.root_nodes[0], visible)
	assert_true(qt.root_nodes[0].children.size() > 0, "Root should split when camera is close")
	qt.free()
