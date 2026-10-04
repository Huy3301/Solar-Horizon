extends "res://tests/test_case.gd"

func test_main_scene_loads() -> void:
	var main_scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_true(main_scene_path != "", "Main scene path is defined in ProjectSettings")
	assert_eq(main_scene_path, "res://scenes/main.tscn", "Main scene is set to scenes/main.tscn")
	
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
			
			var moon = scene_instance.get_node_or_null("MoonGlobe")
			assert_true(moon != null, "MoonGlobe node exists in main scene")
			
			var sun = scene_instance.get_node_or_null("SunLight")
			assert_true(sun != null, "SunLight node exists in main scene")
			
			# Verify real-compressed Earth scale (Earth radius ≈ 637 km)
			var surface_mesh = scene_instance.get_node_or_null("EarthGlobe/Surface") as MeshInstance3D
			assert_true(surface_mesh != null, "Earth surface mesh exists")
			if surface_mesh and surface_mesh.mesh is SphereMesh:
				var sphere = surface_mesh.mesh as SphereMesh
				assert_almost_eq(sphere.radius, 637100.0, 1.0, "Earth sphere radius ≈ 637.1 km (1:10 scale)")
				
			scene_instance.free()

func test_legacy_scene_preserved() -> void:
	var legacy_exists = ResourceLoader.exists("res://scenes/legacy/world.tscn")
	assert_true(legacy_exists, "Legacy world scene preserved under scenes/legacy/ until parity")

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
