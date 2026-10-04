extends "res://tests/test_case.gd"

func test_main_scene_loads() -> void:
	var main_scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_true(main_scene_path != "", "Main scene path is defined in ProjectSettings")
	
	var scene_resource = load(main_scene_path) as PackedScene
	assert_true(scene_resource != null, "Main scene resource loads successfully: %s" % main_scene_path)
	
	if scene_resource:
		var scene_instance = scene_resource.instantiate()
		assert_true(scene_instance != null, "Main scene instantiates successfully")
		
		if scene_instance:
			var ship = scene_instance.get_node_or_null("Ship")
			assert_true(ship != null, "Ship node exists in main scene")
			
			var earth = scene_instance.get_node_or_null("EarthGlobe")
			assert_true(earth != null, "EarthGlobe node exists in main scene")
			
			var sun = scene_instance.get_node_or_null("SunLight")
			assert_true(sun != null, "SunLight node exists in main scene")
			
			scene_instance.free()

func test_input_map_actions() -> void:
	# Ensure essential input map actions exist
	assert_true(InputMap.has_action("interact"), "InputMap contains 'interact'")
	assert_true(InputMap.has_action("scan"), "InputMap contains 'scan'")
	assert_true(InputMap.has_action("visor"), "InputMap contains 'visor'")
	assert_true(InputMap.has_action("jetpack"), "InputMap contains 'jetpack'")
	
	# Verify distinct actions
	assert_true(InputMap.action_get_events("interact").size() > 0, "interact has bound events")
	assert_true(InputMap.action_get_events("scan").size() > 0, "scan has bound events")
	assert_true(InputMap.action_get_events("visor").size() > 0, "visor has bound events")
	assert_true(InputMap.action_get_events("jetpack").size() > 0, "jetpack has bound events")
