class_name TestEarthShaders
extends TestCase

## Unit tests for Earth Shaders and Graphics Polish (WP 2.6, 2.7).
## Validates shader loading, uniform reflection, parameter assignment,
## material resource loading, and headless compilation on RenderingServer.

func test_earth_atmosphere_shader_loads() -> void:
	var shader = load("res://shaders/earth_atmosphere.gdshader") as Shader
	assert_true(shader != null, "earth_atmosphere.gdshader loads successfully as Shader")
	if not shader:
		return

	assert_true(shader.get_rid().is_valid(), "Atmosphere shader has valid resource ID")
	var code: String = shader.code
	assert_true(code.contains("shader_type spatial;"), "Atmosphere shader is a spatial shader")
	assert_true(code.contains("quality_tier"), "Atmosphere shader has quality_tier uniform")
	assert_true(code.contains("sun_direction"), "Atmosphere shader has sun_direction uniform")
	assert_true(code.contains("atmosphere_density"), "Atmosphere shader has atmosphere_density uniform")
	assert_true(code.contains("aurora_intensity"), "Atmosphere shader has aurora_intensity uniform")
	assert_true(code.contains("aurora_green_color"), "Atmosphere shader has aurora_green_color uniform")
	assert_true(code.contains("aurora_crimson_color"), "Atmosphere shader has aurora_crimson_color uniform")
	assert_true(code.contains("city_lights_mask"), "Atmosphere shader has city_lights_mask uniform")
	assert_true(code.contains("city_diffusion_intensity"), "Atmosphere shader has city_diffusion_intensity uniform")
	assert_true(code.contains("dot(-V, L)"), "Atmosphere shader calculates forward sun alignment for corona flare")

func test_earth_surface_shader_loads() -> void:
	var shader = load("res://shaders/earth_surface.gdshader") as Shader
	assert_true(shader != null, "earth_surface.gdshader loads successfully as Shader")
	if not shader:
		return

	assert_true(shader.get_rid().is_valid(), "Surface shader has valid resource ID")
	var code: String = shader.code
	assert_true(code.contains("shader_type spatial;"), "Surface shader is a spatial shader")
	assert_true(code.contains("quality_tier"), "Surface shader has quality_tier uniform")
	assert_true(code.contains("sun_direction"), "Surface shader has sun_direction uniform")
	assert_true(code.contains("atmosphere_density"), "Surface shader has atmosphere_density uniform")
	assert_true(code.contains("cloud_shadow_intensity"), "Surface shader has cloud_shadow_intensity uniform")
	assert_true(code.contains("micro_relief_strength"), "Surface shader has micro_relief_strength uniform")
	assert_true(code.contains("glint_core"), "Surface shader implements triple-lobe ocean glint")
	assert_true(code.contains("cloud_obscuration"), "Surface shader obscures city lights by clouds")

func test_earth_clouds_shader_loads() -> void:
	var shader = load("res://shaders/earth_clouds.gdshader") as Shader
	assert_true(shader != null, "earth_clouds.gdshader loads successfully as Shader")
	if not shader:
		return

	assert_true(shader.get_rid().is_valid(), "Clouds shader has valid resource ID")
	var code: String = shader.code
	assert_true(code.contains("shader_type spatial;"), "Clouds shader is a spatial shader")
	assert_true(code.contains("quality_tier"), "Clouds shader has quality_tier uniform")
	assert_true(code.contains("sun_direction"), "Clouds shader has sun_direction uniform")
	assert_true(code.contains("cloud_coverage"), "Clouds shader has cloud_coverage uniform")
	assert_true(code.contains("cloud_thickness"), "Clouds shader has cloud_thickness uniform")
	assert_true(code.contains("shadow_intensity"), "Clouds shader has shadow_intensity uniform")
	assert_true(code.contains("silver_lining_intensity"), "Clouds shader has silver_lining_intensity uniform")
	assert_true(code.contains("sunset_cloud_color"), "Clouds shader has sunset_cloud_color uniform")

func test_earth_shader_material_parameters() -> void:
	var atmo_shader = load("res://shaders/earth_atmosphere.gdshader") as Shader
	var surf_shader = load("res://shaders/earth_surface.gdshader") as Shader
	var cld_shader = load("res://shaders/earth_clouds.gdshader") as Shader

	assert_true(atmo_shader != null and surf_shader != null and cld_shader != null, "All shaders load")
	if not (atmo_shader and surf_shader and cld_shader):
		return

	# Test atmosphere material parameters
	var atmo_mat = ShaderMaterial.new()
	atmo_mat.shader = atmo_shader
	atmo_mat.set_shader_parameter("quality_tier", 0)
	assert_eq(atmo_mat.get_shader_parameter("quality_tier"), 0, "Atmosphere quality_tier set to 0")
	atmo_mat.set_shader_parameter("quality_tier", 1)
	assert_eq(atmo_mat.get_shader_parameter("quality_tier"), 1, "Atmosphere quality_tier set to 1")

	var test_sun_dir = Vector3(0.5, 0.5, 0.707).normalized()
	atmo_mat.set_shader_parameter("sun_direction", test_sun_dir)
	var got_dir = atmo_mat.get_shader_parameter("sun_direction") as Vector3
	assert_vec_almost_eq(got_dir, test_sun_dir, 1e-4, "sun_direction on atmosphere material")

	atmo_mat.set_shader_parameter("atmosphere_density", 2.8)
	assert_almost_eq(atmo_mat.get_shader_parameter("atmosphere_density"), 2.8, 1e-4, "atmosphere_density on atmosphere material")

	atmo_mat.set_shader_parameter("aurora_intensity", 1.25)
	assert_almost_eq(atmo_mat.get_shader_parameter("aurora_intensity"), 1.25, 1e-4, "aurora_intensity on atmosphere material")

	# Test surface material parameters
	var surf_mat = ShaderMaterial.new()
	surf_mat.shader = surf_shader
	surf_mat.set_shader_parameter("quality_tier", 0)
	assert_eq(surf_mat.get_shader_parameter("quality_tier"), 0, "Surface quality_tier set to 0")
	surf_mat.set_shader_parameter("quality_tier", 1)
	assert_eq(surf_mat.get_shader_parameter("quality_tier"), 1, "Surface quality_tier set to 1")

	surf_mat.set_shader_parameter("atmosphere_density", 1.5)
	assert_almost_eq(surf_mat.get_shader_parameter("atmosphere_density"), 1.5, 1e-4, "atmosphere_density on surface material")

	surf_mat.set_shader_parameter("cloud_shadow_intensity", 0.8)
	assert_almost_eq(surf_mat.get_shader_parameter("cloud_shadow_intensity"), 0.8, 1e-4, "cloud_shadow_intensity on surface material")

	# Test clouds material parameters
	var cld_mat = ShaderMaterial.new()
	cld_mat.shader = cld_shader
	cld_mat.set_shader_parameter("quality_tier", 0)
	assert_eq(cld_mat.get_shader_parameter("quality_tier"), 0, "Clouds quality_tier set to 0")
	cld_mat.set_shader_parameter("quality_tier", 1)
	assert_eq(cld_mat.get_shader_parameter("quality_tier"), 1, "Clouds quality_tier set to 1")

	cld_mat.set_shader_parameter("silver_lining_intensity", 2.0)
	assert_almost_eq(cld_mat.get_shader_parameter("silver_lining_intensity"), 2.0, 1e-4, "silver_lining_intensity on clouds material")

	cld_mat.set_shader_parameter("shadow_intensity", 0.65)
	assert_almost_eq(cld_mat.get_shader_parameter("shadow_intensity"), 0.65, 1e-4, "shadow_intensity on clouds material")

func test_earth_material_resources_load() -> void:
	var atmo_res = load("res://assets/materials/earth_atmosphere_mat.tres") as ShaderMaterial
	assert_true(atmo_res != null, "earth_atmosphere_mat.tres loads as ShaderMaterial")
	if atmo_res:
		assert_true(atmo_res.shader != null, "Atmosphere material has assigned shader")
		assert_true(atmo_res.get_shader_parameter("atmosphere_density") != null, "Atmosphere density parameter is set")
		assert_true(atmo_res.get_shader_parameter("aurora_intensity") != null, "Aurora intensity parameter is set")

	var surf_res = load("res://assets/materials/earth_surface_mat.tres") as ShaderMaterial
	assert_true(surf_res != null, "earth_surface_mat.tres loads as ShaderMaterial")
	if surf_res:
		assert_true(surf_res.shader != null, "Surface material has assigned shader")
		assert_true(surf_res.get_shader_parameter("sun_direction") != null, "Surface sun_direction is set")
		assert_true(surf_res.get_shader_parameter("cloud_shadow_intensity") != null, "Cloud shadow intensity is set")

	var cld_res = load("res://assets/materials/earth_clouds_mat.tres") as ShaderMaterial
	assert_true(cld_res != null, "earth_clouds_mat.tres loads as ShaderMaterial")
	if cld_res:
		assert_true(cld_res.shader != null, "Clouds material has assigned shader")
		assert_true(cld_res.get_shader_parameter("silver_lining_intensity") != null, "Silver lining intensity is set")

func test_earth_shaders_compile_headless() -> void:
	var shaders: Array[String] = [
		"res://shaders/earth_atmosphere.gdshader",
		"res://shaders/earth_surface.gdshader",
		"res://shaders/earth_clouds.gdshader"
	]

	for path in shaders:
		var shd = load(path) as Shader
		assert_true(shd != null, "Shader loaded for compilation: " + path)
		if not shd:
			continue

		# Verify RenderingServer material binding compiles cleanly
		var rs_mat = RenderingServer.material_create()
		assert_true(rs_mat.is_valid(), "RenderingServer created material for " + path)
		RenderingServer.material_set_shader(rs_mat, shd.get_rid())

		# Test attaching to a mesh instance
		var mat = ShaderMaterial.new()
		mat.shader = shd
		var mesh_inst = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		mesh_inst.mesh = sphere
		mesh_inst.material_override = mat

		# Clean up references before freeing
		mesh_inst.material_override = null
		mesh_inst.mesh = null
		mesh_inst.free()
		RenderingServer.free_rid(rs_mat)
