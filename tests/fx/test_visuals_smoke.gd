class_name TestVisualsSmoke
extends TestCase

func test_earth_visual_scene_and_material() -> void:
	var earth_scene = load("res://game/fx/earth_visual.tscn")
	assert_true(earth_scene != null, "Earth visual scene should load")
	assert_true(earth_scene is PackedScene, "Earth visual should be PackedScene")

	var instance = earth_scene.instantiate()
	assert_true(instance != null, "Earth visual should instantiate")
	assert_true(instance is EarthVisual, "Instance should be EarthVisual")

	var earth: EarthVisual = instance as EarthVisual
	assert_almost_eq(earth.radius, 637100.0, 1.0, "Earth radius should be 637,100 m (1:10 scale)")
	assert_almost_eq(earth.cloud_altitude, 1500.0, 0.1, "Cloud altitude should be 1,500 m")
	assert_almost_eq(earth.atmosphere_thickness, 9000.0, 0.1, "Atmosphere thickness should be 9,000 m")

	# Test sun direction propagation
	var test_sun_dir = Vector3(1.0, 0.0, 0.0)
	earth.set_sun_direction(test_sun_dir)
	assert_vec_almost_eq(earth.sun_direction, test_sun_dir, 1e-4, "Sun direction should update")

	# Test quality tier propagation
	earth.set_quality_tier(0)
	assert_eq(earth.quality_tier, 0, "Quality tier should switch to Low (0)")
	earth.set_quality_tier(1)
	assert_eq(earth.quality_tier, 1, "Quality tier should switch to High (1)")

	# Verify sub-nodes
	var surf_node = earth.get_node_or_null("Surface")
	assert_true(surf_node != null and surf_node is MeshInstance3D, "Surface node should exist")
	var atmo_node = earth.get_node_or_null("Atmosphere")
	assert_true(atmo_node != null and atmo_node is MeshInstance3D, "Atmosphere node should exist")
	var clouds_node = earth.get_node_or_null("Clouds")
	assert_true(clouds_node != null and clouds_node is MeshInstance3D, "Clouds node should exist")

	earth.free()

func test_moon_visual_scene_and_material() -> void:
	var moon_scene = load("res://game/fx/moon_visual.tscn")
	assert_true(moon_scene != null, "Moon visual scene should load")
	assert_true(moon_scene is PackedScene, "Moon visual should be PackedScene")

	var instance = moon_scene.instantiate()
	assert_true(instance != null, "Moon visual should instantiate")
	assert_true(instance is MoonVisual, "Instance should be MoonVisual")

	var moon: MoonVisual = instance as MoonVisual
	assert_almost_eq(moon.radius, 173740.0, 1.0, "Moon radius should be 173,740 m (1:10 scale)")

	# Test sun direction propagation
	var test_sun_dir = Vector3(0.0, 1.0, 0.0)
	moon.set_sun_direction(test_sun_dir)
	assert_vec_almost_eq(moon.sun_direction, test_sun_dir, 1e-4, "Moon sun direction should update")

	moon.set_quality_tier(0)
	assert_eq(moon.quality_tier, 0, "Moon quality tier should switch to Low")
	moon.set_quality_tier(1)
	assert_eq(moon.quality_tier, 1, "Moon quality tier should switch to High")

	var surf_node = moon.get_node_or_null("Surface")
	assert_true(surf_node != null and surf_node is MeshInstance3D, "Moon surface node should exist")

	moon.free()

func test_sky_environment_scene_and_material() -> void:
	var sky_scene = load("res://game/fx/sky_environment.tscn")
	assert_true(sky_scene != null, "Sky environment scene should load")
	assert_true(sky_scene is PackedScene, "Sky environment should be PackedScene")

	var instance = sky_scene.instantiate()
	assert_true(instance != null, "Sky environment should instantiate")
	assert_true(instance is SkyEnvironmentVisual, "Instance should be SkyEnvironmentVisual")

	var sky_env: SkyEnvironmentVisual = instance as SkyEnvironmentVisual
	var test_sun_dir = Vector3(0.5, 0.5, 0.707).normalized()
	sky_env.set_sun_direction(test_sun_dir)
	assert_vec_almost_eq(sky_env.sun_direction, test_sun_dir, 1e-4, "Sky sun direction should update")

	var sun_node = sky_env.get_node_or_null("Sun")
	assert_true(sun_node != null and sun_node is SunController, "SunController node should exist")
	var sun_ctrl: SunController = sun_node as SunController

	# Test eclipse-less state
	sun_ctrl._calculate_eclipse()
	assert_almost_eq(sun_ctrl.current_eclipse_factor, 1.0, 1e-4, "Eclipse factor should be 1.0 with no occluders")

	sky_env.free()

func test_all_materials_load_and_compile() -> void:
	var materials = [
		"res://assets/materials/earth_atmosphere_mat.tres",
		"res://assets/materials/earth_clouds_mat.tres",
		"res://assets/materials/earth_surface_mat.tres",
		"res://assets/materials/lunar_surface_mat.tres",
		"res://assets/materials/space_sky_mat.tres",
		"res://assets/materials/sun_glare_mat.tres",
	]

	for mat_path in materials:
		var mat = load(mat_path)
		assert_true(mat != null, "Material %s should load" % mat_path)
		assert_true(mat is ShaderMaterial, "Material %s should be ShaderMaterial" % mat_path)
		var smat = mat as ShaderMaterial
		assert_true(smat.shader != null, "Shader for %s should not be null" % mat_path)
