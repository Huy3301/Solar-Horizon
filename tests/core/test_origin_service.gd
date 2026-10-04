extends "res://tests/test_case.gd"

func test_origin_service_100_shifts_relative_precision() -> void:
	var service = preload("res://game/core/origin_service.gd").new()
	var root = Node3D.new()
	service.world_root = root
	
	var node_a = Node3D.new()
	node_a.position = Vector3(100.0, 200.0, 300.0)
	root.add_child(node_a)
	
	var node_b = Node3D.new()
	node_b.position = Vector3(150.0, 220.0, 310.0)
	root.add_child(node_b)
	
	var initial_diff = node_b.position - node_a.position
	
	# Perform 100 shifts
	for i in range(100):
		var shift_x = sin(i * 0.3) * 5000.0
		var shift_y = cos(i * 0.5) * 5000.0
		var shift_z = sin(i * 0.7) * 5000.0
		service.shift_origin(DVec3.new(shift_x, shift_y, shift_z))
		
		var diff = node_b.position - node_a.position
		var drift = (diff - initial_diff).length()
		assert_true(drift < 1e-3, "Relative position drift after shift %d is %f < 1e-3 m" % [i, drift])
		
	node_a.free()
	node_b.free()
	root.free()
	service.free()

func test_origin_service_600km_precision() -> void:
	var service = preload("res://game/core/origin_service.gd").new()
	
	# Initial universe position 600 km (600,000 m) out
	var up = UniversePosition.new(Vector3i.ZERO, DVec3.new(600000.0, 0.0, 0.0))
	
	# Local position relative to origin (0, 0, 0)
	var local_pos = service.universe_to_local(up)
	assert_almost_eq(local_pos.x, 600000.0, 1e-3, "Initial local coordinate at 600km")
	
	# Shift origin near the object (e.g., 600,000 m)
	service.shift_origin(DVec3.new(600000.0, 0.0, 0.0))
	
	var rebasing_local_pos = service.universe_to_local(up)
	assert_almost_eq(rebasing_local_pos.x, 0.0, 1e-3, "Rebased local coordinate is centered")
	
	# Convert back to universe position
	var roundtrip_up = service.local_to_universe(rebasing_local_pos)
	var diff = roundtrip_up.difference_to(up)
	assert_almost_eq(diff.length(), 0.0, 1e-3, "Round trip universe position precision at 600km")
	
	service.free()

func test_origin_service_focus_tracking_no_pingpong() -> void:
	var service = preload("res://game/core/origin_service.gd").new()
	service.threshold_m = 5000.0
	
	var focus_node = Node3D.new()
	focus_node.position = Vector3(100.0, 0.0, 0.0)
	
	var other_node = Node3D.new()
	other_node.position = Vector3(-10000.0, 0.0, 0.0) # Far away beyond threshold
	
	service.register(focus_node)
	service.register(other_node)
	service.set_focus_node(focus_node)
	
	# other_node is beyond threshold, but focus_node is at 100m (< 5000m)
	var shifted = service.check_and_shift()
	assert_false(shifted, "Should not shift when only non-focus node exceeds threshold")
	
	# Now focus_node moves beyond threshold
	focus_node.position = Vector3(5500.0, 0.0, 0.0)
	shifted = service.check_and_shift()
	assert_true(shifted, "Should shift when focus node exceeds threshold")
	
	focus_node.free()
	other_node.free()
	service.free()
