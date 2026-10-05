extends TestCase

class MockThermalSource extends RefCounted:
	var headroom: float = 0.0
	func get_thermal_headroom() -> float:
		return headroom

class AnchoredNode extends Node3D:
	var universe_pos: UniversePosition

func test_origin_service_shifts_at_threshold_plus_hysteresis_margin() -> void:
	var service = preload("res://game/core/origin_service.gd").new()
	service.threshold_m = 5000.0
	service.hysteresis_margin_m = 500.0
	
	var focus_node = Node3D.new()
	service.register(focus_node)
	service.set_focus_node(focus_node)
	
	# Below threshold
	focus_node.position = Vector3(4000.0, 0.0, 0.0)
	var shifted = service.check_and_shift()
	assert_false(shifted, "Should not shift at 4000m (< threshold 5000m)")
	
	# At threshold (within hysteresis band)
	focus_node.position = Vector3(5000.0, 0.0, 0.0)
	shifted = service.check_and_shift()
	assert_false(shifted, "Should not shift at 5000m (at threshold alone, within hysteresis margin)")
	
	# Slightly below threshold + hysteresis margin
	focus_node.position = Vector3(5490.0, 0.0, 0.0)
	shifted = service.check_and_shift()
	assert_false(shifted, "Should not shift at 5490m (< 5500m)")
	
	# At threshold + hysteresis margin
	focus_node.position = Vector3(5500.0, 0.0, 0.0)
	shifted = service.check_and_shift()
	assert_true(shifted, "Should shift at 5500m (threshold + hysteresis_margin)")
	
	focus_node.free()
	service.free()

func test_origin_service_universe_position_reanchor_cleanly() -> void:
	var service = preload("res://game/core/origin_service.gd").new()
	var root = Node3D.new()
	service.world_root = root
	
	var anchored_node = AnchoredNode.new()
	anchored_node.universe_pos = UniversePosition.new(Vector3i.ZERO, DVec3.new(20000.0, 1000.0, -5000.0))
	root.add_child(anchored_node)
	anchored_node.position = service.universe_to_local(anchored_node.universe_pos)
	service.register(anchored_node)
	
	# Shift origin
	service.shift_origin(DVec3.new(10000.0, 0.0, 0.0))
	var expected_local = service.universe_to_local(anchored_node.universe_pos)
	assert_almost_eq(anchored_node.position.x, expected_local.x, 1e-4, "Re-anchored node x matches universe_to_local")
	assert_almost_eq(anchored_node.position.y, expected_local.y, 1e-4, "Re-anchored node y matches universe_to_local")
	assert_almost_eq(anchored_node.position.z, expected_local.z, 1e-4, "Re-anchored node z matches universe_to_local")
	
	anchored_node.free()
	root.free()
	service.free()

func test_star_catalog_density_and_performance() -> void:
	var catalog = preload("res://game/universe/star_catalog.gd").new()
	catalog.galaxy_generator = GalaxyGenerator.new(42)
	
	var t0 = Time.get_ticks_usec()
	catalog._update_catalog()
	var elapsed_ms = (Time.get_ticks_usec() - t0) / 1000.0
	assert_true(elapsed_ms < 15.0, "Star catalog generation is fast (< 15 ms, measured %f ms)" % elapsed_ms)
	
	var stars = catalog.get_stars_for_skybox()
	assert_true(stars.size() > 40 and stars.size() < 120, "Star count matches density ~0.008 (expected ~74, got %d)" % stars.size())
	assert_eq(GalaxyGenerator.STAR_DENSITY_PER_MILLE, 8, "STAR_DENSITY_PER_MILLE equals 8")
	
	# Verify analytical derivation matches
	assert_true(stars.size() > 0, "Stars catalog contains generated stars")
	var sample = stars[0]
	var seed_val = sample["seed"]
	var star_class = catalog.get_star_class(seed_val)
	var lum = catalog.get_star_luminosity(seed_val)
	assert_eq(sample["class"], star_class, "Cached star class matches analytical derivation")
	assert_almost_eq(sample["luminosity"], lum, 1e-5, "Cached luminosity matches analytical derivation")
	
	# Verify lazy instantiation
	assert_eq(catalog._cached_systems.size(), 0, "No StarSystemGenerator eagerly instantiated at startup")
	var queried = catalog.query_system(sample["sector"])
	assert_true(queried != null, "query_system lazily instantiates StarSystemGenerator on demand")
	assert_eq(catalog._cached_systems.size(), 1, "Cached systems count is now 1")
	
	catalog.free()

func test_quality_governor_handles_missing_plugin_gracefully() -> void:
	var governor = preload("res://game/autoload/quality_governor.gd").new()
	governor.is_mobile = true
	governor.thermal_plugin = null
	
	# Verify 0 delta does not cause division by zero
	governor.record_frame_time(0.0)
	assert_true(governor.smoothed_frametime_ms > 0.0, "Smoothed frametime remains positive")
	
	governor.record_frame_time(0.0166)
	governor.evaluate_performance()
	assert_true(governor.fsr_scale >= governor.MIN_FSR_SCALE and governor.fsr_scale <= governor.MAX_FSR_SCALE, "FSR scale in valid bounds")
	
	# Verify frametime variance spike detection triggers downscale when no plugin is present
	governor.frametime_variance_ms = 8.0
	var initial_scale = governor.fsr_scale
	governor.evaluate_performance()
	assert_true(governor.fsr_scale < initial_scale, "Downscales when frametime variance indicates hitching")
	
	governor.free()

func test_quality_governor_predictive_thermal_scaling_and_hysteresis() -> void:
	var governor = preload("res://game/autoload/quality_governor.gd").new()
	governor.is_mobile = true
	var mock = MockThermalSource.new()
	governor.thermal_plugin = mock
	
	# Predictive downscaling when thermal headroom >= 0.7
	mock.headroom = 0.72
	governor.smoothed_frametime_ms = 16.67
	governor.frametime_variance_ms = 1.0
	var scale_before = governor.fsr_scale
	governor.evaluate_performance()
	assert_true(governor.fsr_scale < scale_before, "Predictively downscales when thermal headroom >= 0.7")
	
	# Hysteresis deadband: headroom in [0.5, 0.7) should not oscillate or change scale
	mock.headroom = 0.60
	governor.smoothed_frametime_ms = 16.67
	governor.frametime_variance_ms = 1.0
	var scale_deadband = governor.fsr_scale
	governor.evaluate_performance()
	assert_almost_eq(governor.fsr_scale, scale_deadband, 1e-5, "Maintains scale in hysteresis deadband")
	
	governor.free()
