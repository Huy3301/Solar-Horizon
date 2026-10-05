class_name TestQuadtreePlacement extends TestCase

func test_leaf_patch_placement_in_planet_local_space() -> void:
	var qt := PlanetQuadtree.new()
	qt._ready()
	# Set camera at an offset
	qt.camera_pos = DVec3.new(250000.0, 300000.0, 350000.0)

	var visible_nodes: Array = []
	for root in qt.root_nodes:
		qt._process_node(root, visible_nodes)

	assert_true(visible_nodes.size() > 0, "Quadtree should produce visible leaf nodes")
	qt._update_instances(visible_nodes)

	for node in visible_nodes:
		assert_true(node.instance != null, "Visible node must have an instantiated mesh")
		var expected_pos: Vector3 = node.center_double.to_vector3()
		assert_vec_almost_eq(node.instance.position, expected_pos, 0.001, "Patch instance must be at node.center_double.to_vector3() in planet-local space")
		var cam_local_pos: Vector3 = node.center_double.to_local_vector3(qt.camera_pos)
		assert_false(node.instance.position.is_equal_approx(cam_local_pos), "Patch instance must not be placed in camera-relative coordinates")

	# Move camera significantly and re-update instances: planet-local position must remain invariant
	var original_positions: Array[Vector3] = []
	for node in visible_nodes:
		original_positions.append(node.instance.position)

	qt.camera_pos = DVec3.new(777000.0, -888000.0, 999000.0)
	qt._update_instances(visible_nodes)

	for i in range(visible_nodes.size()):
		var node = visible_nodes[i]
		assert_vec_almost_eq(node.instance.position, original_positions[i], 0.001, "Planet-local patch position must remain invariant under camera shifts")

	if qt.chunk_streamer:
		qt.chunk_streamer.wait_all()
	qt.free()

func test_collision_placement_in_planet_local_space() -> void:
	var qt := PlanetQuadtree.new()
	qt._ready()
	qt.camera_pos = DVec3.new(123456.0, 654321.0, 500000.0)

	var target_node = qt.root_nodes[0]
	var dummy_shape := ConcavePolygonShape3D.new()
	dummy_shape.set_faces(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)
	]))

	qt._on_collision_generated(dummy_shape, target_node)

	assert_true(qt.collision_body != null, "Collision body must be created")
	var expected_pos: Vector3 = target_node.center_double.to_vector3()
	assert_vec_almost_eq(qt.collision_body.position, expected_pos, 0.001, "Collision body must be at target_node.center_double.to_vector3() in planet-local space")
	var cam_local_pos: Vector3 = target_node.center_double.to_local_vector3(qt.camera_pos)
	assert_false(qt.collision_body.position.is_equal_approx(cam_local_pos), "Collision body must not be in camera-relative coordinates")

	# Regenerate with same collider node: position must remain planet-local
	qt._on_collision_generated(dummy_shape, target_node)
	assert_vec_almost_eq(qt.collision_body.position, expected_pos, 0.001, "Subsequent collision update maintains planet-local placement")

	if qt.chunk_streamer:
		qt.chunk_streamer.wait_all()
	qt.free()
