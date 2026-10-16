class_name TestS2cToS5Roadmap extends TestCase
## Verifies Sprint S2c, S2d, S2e, S3, S4, and S5 deliverables under `tests/run_tests.gd`.


func test_s2c_terrain_shader_has_debug_views_and_view_space_normal() -> void:
	var shader_code: String = FileAccess.get_file_as_string("res://game/planet/core/terrain_patch.gdshader")
	assert_true(shader_code.contains("uniform int debug_view_mode"), "S2c shader must expose debug_view_mode")
	assert_true(shader_code.contains("VIEW_MATRIX * vec4(world_normal"), "S2c shader must transform world_normal to view space")


func test_s2d_speed_sensation_and_side_plume() -> void:
	var idle_metrics: Dictionary = ShipVFX.compute_speed_sensation_metrics(0.0, false, false)
	assert_almost_eq(float(idle_metrics["target_fov_deg"]), 75.0, 1e-4, "Idle FOV should be 75 deg")
	assert_almost_eq(float(idle_metrics["streak_alpha"]), 0.0, 1e-4, "Idle streak alpha should be 0")

	var boost_metrics: Dictionary = ShipVFX.compute_speed_sensation_metrics(280.0, true, false)
	assert_true(float(boost_metrics["target_fov_deg"]) >= 89.0, "Boost must apply FOV kick")
	assert_true(float(boost_metrics["streak_alpha"]) > 0.5, "High speed must enable speed streaks")


func test_s2e_touch_steering_and_thermal_governor() -> void:
	var dead_vec: Vector2 = TouchControls.compute_touch_steering_vector(Vector2(4.0, 0.0), 100.0)
	assert_almost_eq(dead_vec.length(), 0.0, 1e-5, "Deflection inside deadzone must return zero")

	var active_vec: Vector2 = TouchControls.compute_touch_steering_vector(Vector2(100.0, 0.0), 100.0)
	assert_almost_eq(active_vec.x, 1.0, 1e-4, "Full deflection must return 1.0")

	var lod_mobile: int = QualityGovernor.get_terrain_max_lod_depth(true, 0.5)
	assert_eq(lod_mobile, 8, "S26+ mobile terrain LOD depth must be capped at 8")

	var throttled_scale: float = QualityGovernor.compute_thermal_render_scale(0.67, 0.96, 15.0)
	assert_almost_eq(throttled_scale, 0.60, 1e-4, "Critical thermal headroom must step down render scale")


func test_s3_moon_landing_assist_eva_10_min_and_atomic_crafting() -> void:
	var rem_o2: float = SurvivalSystem.compute_eva_oxygen_remaining(600.0, 120.0, 0)
	assert_almost_eq(rem_o2, 480.0, 1e-3, "2 minutes of EVA should leave 480s of 600s capacity")

	var stock: Dictionary = {"iron_ore": 2, "silicate": 1}
	var recipe: Dictionary = {"iron_ore": 2, "silicate": 3}
	var failed: bool = CraftingSystem.execute_atomic_craft(stock, recipe, "circuit", 1)
	assert_false(failed, "Craft must fail when silicate is insufficient")
	assert_eq(int(stock["iron_ore"]), 2, "Atomic craft must not deduct iron_ore on failure")

	stock["silicate"] = 3
	var passed: bool = CraftingSystem.execute_atomic_craft(stock, recipe, "circuit", 1)
	assert_true(passed, "Craft must succeed when all inputs are present")
	assert_eq(int(stock["circuit"]), 1, "Crafted item must be added to stock")

	var assist_accel: Vector3 = FlightModel.compute_low_gravity_landing_assist(
		Vector3(6.0, -15.0, 0.0),
		Vector3.UP,
		40.0,
		1.62
	)
	assert_true(assist_accel.y > 0.0, "Landing assist must provide upward braking when sinking fast")
	assert_true(assist_accel.x < 0.0, "Landing assist must oppose positive X lateral drift")


func test_s4_star_class_diversity_and_seeded_system_determinism() -> void:
	var seen_classes: Dictionary = {}
	for i: int in range(80):
		var code: String = StarSystemGenerator.select_spectral_class_code(1000 + i * 9973)
		seen_classes[code] = true
	assert_true(seen_classes.size() >= 4, "StarSystemGenerator must generate multiple spectral classes, not only M")

	var sys_a: Dictionary = SystemLoader.build_seeded_system_state(424242)
	var sys_b: Dictionary = SystemLoader.build_seeded_system_state(424242)
	assert_eq(str(sys_a["star_class"]), str(sys_b["star_class"]), "Same seed must produce identical star class")
	assert_eq(int(sys_a["planet_count"]), int(sys_b["planet_count"]), "Same seed must produce identical planet count")


func test_s5_discovery_upload_and_speed_upgrades() -> void:
	var credits: int = DiscoverySystem.compute_upload_payout(4, 1.5)
	assert_eq(credits, 1500, "4 discoveries at 1.5x rarity should award 1500 Survey Credits")

	var upgraded: Dictionary = DiscoverySystem.compute_upgraded_speed_limits(200.0, 100000.0, 2)
	assert_almost_eq(float(upgraded["max_speed_mps"]), 320.0, 1e-3, "Tier 2 upgrade should raise speed by 60%")
	assert_almost_eq(float(upgraded["pulse_range_m"]), 200000.0, 1e-1, "Tier 2 upgrade should double pulse range")
