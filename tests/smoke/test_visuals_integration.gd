class_name TestVisualsIntegration
extends TestCase

func test_main_scene_visuals_integration() -> void:
	var main_scene = load("res://scenes/main.tscn") as PackedScene
	assert_true(main_scene != null, "main.tscn loads")
	
	var world = main_scene.instantiate() as MainWorld
	assert_true(world != null, "main.tscn instantiates as MainWorld")
	
	# Verify EarthVisual
	var earth = world.get_node_or_null("EarthGlobe") as EarthVisual
	assert_true(earth != null, "EarthGlobe is EarthVisual")
	if earth:
		assert_almost_eq(earth.radius, 637100.0, 1.0, "Earth radius is 637.1 km")
		assert_true(earth.get_node_or_null("Surface") != null, "Earth has Surface mesh")
		assert_true(earth.get_node_or_null("Clouds") != null, "Earth has Clouds mesh")
		assert_true(earth.get_node_or_null("Atmosphere") != null, "Earth has Atmosphere mesh")
		assert_true(earth.get_node_or_null("SurfaceBody") != null, "Earth has SurfaceBody collider")
	
	# Verify MoonVisual
	var moon = world.get_node_or_null("MoonGlobe") as MoonVisual
	assert_true(moon != null, "MoonGlobe is MoonVisual")
	if moon:
		assert_almost_eq(moon.radius, 173740.0, 1.0, "Moon radius is 173.74 km")
		assert_true(moon.get_node_or_null("Surface") != null, "Moon has Surface mesh")
		assert_true(moon.get_node_or_null("SurfaceBody") != null, "Moon has SurfaceBody collider")
		
	# Verify SkyEnvironment
	var sky_env = world.get_node_or_null("SkyEnvironment") as SkyEnvironmentVisual
	assert_true(sky_env != null, "SkyEnvironment node exists")
	if sky_env:
		var sun_ctrl = sky_env.get_node_or_null("Sun") as SunController
		assert_true(sun_ctrl != null, "SunController exists in SkyEnvironment")
		if sun_ctrl:
			var dir_light = sun_ctrl.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
			assert_true(dir_light != null, "DirectionalLight3D exists")
			if dir_light:
				assert_true(dir_light.shadow_enabled, "Directional shadow enabled for ship")
				assert_almost_eq(dir_light.directional_shadow_max_distance, 350.0, 1.0, "Sane shadow max distance for ship")
		
		var world_env = sky_env.get_node_or_null("WorldEnvironment") as WorldEnvironment
		assert_true(world_env != null, "WorldEnvironment exists")
		if world_env and world_env.environment:
			assert_eq(world_env.environment.tonemap_mode, Environment.TONE_MAPPER_ACES, "ACES tonemapping")
			assert_true(world_env.environment.glow_enabled, "Glow enabled")
			
	# Compatibility node
	assert_true(world.get_node_or_null("SunLight") != null, "SunLight compatibility node exists")
	
	world.free()

func test_ship_visuals_and_sockets_integration() -> void:
	var ship_scene = load("res://scenes/ship.tscn") as PackedScene
	assert_true(ship_scene != null, "ship.tscn loads")
	
	var ship = ship_scene.instantiate() as ShipFlightController
	assert_true(ship != null, "ship.tscn instantiates as ShipFlightController")
	
	# Verify Orbiter glb model instance
	var orbiter = ship.get_node_or_null("VisualModel/OrbiterModel")
	assert_true(orbiter != null, "OrbiterModel exists in VisualModel")
	
	# Verify LODs and visibility ranges
	var lod0 = ship.get_node_or_null("VisualModel/OrbiterModel/Orbiter_LOD0") as MeshInstance3D
	var lod1 = ship.get_node_or_null("VisualModel/OrbiterModel/Orbiter_LOD1") as MeshInstance3D
	assert_true(lod0 != null, "Orbiter_LOD0 exists")
	assert_true(lod1 != null, "Orbiter_LOD1 exists")
	if lod0:
		assert_almost_eq(lod0.visibility_range_end, 120.0, 0.1, "LOD0 visibility range end is 120m")
	if lod1:
		assert_almost_eq(lod1.visibility_range_begin, 120.0, 0.1, "LOD1 visibility range begin is 120m")
		
	# Verify COL_hull is hidden visually
	var col_hull = ship.get_node_or_null("VisualModel/OrbiterModel/COL_hull") as MeshInstance3D
	assert_true(col_hull != null, "COL_hull node exists")
	if col_hull:
		assert_false(col_hull.visible, "COL_hull mesh is not visible")
		
	# Verify Plume sockets
	var left_plume = ship.get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_L/LeftEnginePlume")
	var right_plume = ship.get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_R/RightEnginePlume")
	assert_true(left_plume != null, "Left engine plume attached to SOCKET_engine_L")
	assert_true(right_plume != null, "Right engine plume attached to SOCKET_engine_R")
	
	# Verify Nav light sockets
	var port_light = ship.get_node_or_null("VisualModel/OrbiterModel/SOCKET_nav_port/PortNavLight")
	var stbd_light = ship.get_node_or_null("VisualModel/OrbiterModel/SOCKET_nav_stbd/StarboardNavLight")
	assert_true(port_light != null, "Port nav light attached to SOCKET_nav_port")
	assert_true(stbd_light != null, "Starboard nav light attached to SOCKET_nav_stbd")
	
	# Verify AnimationPlayer gear toggle hook
	var anim_player = ship.get_node_or_null("VisualModel/OrbiterModel/AnimationPlayer") as AnimationPlayer
	assert_true(anim_player != null, "AnimationPlayer exists on OrbiterModel")
	if anim_player:
		assert_true(anim_player.has_animation("gear_deploy"), "gear_deploy animation exists")
		assert_false(ship.landing_gear_deployed, "Landing gear initially retracted")
		ship.toggle_landing_gear()
		assert_true(ship.landing_gear_deployed, "Landing gear deployed after toggle")
		assert_eq(anim_player.current_animation, "gear_deploy", "gear_deploy plays on deploy")
		ship.toggle_landing_gear()
		assert_false(ship.landing_gear_deployed, "Landing gear retracted after second toggle")
		
	# Verify physics colliders preserved
	assert_true(ship.get_node_or_null("FuselageCollision") != null, "FuselageCollision preserved")
	assert_true(ship.get_node_or_null("WingCollision") != null, "WingCollision preserved")
	
	ship.free()
