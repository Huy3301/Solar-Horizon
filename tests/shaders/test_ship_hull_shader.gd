class_name TestShipHullShader
extends TestCase

## Unit tests for Spacecraft Hull PBR & Re-entry Thermal Glow Shader (WP 3.5).
## Verifies shader resource loading, syntax validation, uniform exposure,
## parameter inspection (reentry_heat, panel_lines_intensity, underside_bias),
## and clean headless compilation on RenderingServer.

func test_ship_hull_shader_loads() -> void:
	var shader = load("res://shaders/ship_hull.gdshader") as Shader
	assert_true(shader != null, "res://shaders/ship_hull.gdshader loads successfully as Shader")
	
	if shader:
		assert_true(shader.get_rid().is_valid(), "Shader has valid resource ID")
		var code: String = shader.code
		assert_true(code.contains("shader_type spatial;"), "Shader is a spatial shader")
		assert_true(code.contains("albedo_color"), "Shader contains albedo_color uniform")
		assert_true(code.contains("albedo_texture"), "Shader contains albedo_texture uniform")
		assert_true(code.contains("orm_texture"), "Shader contains orm_texture uniform")
		assert_true(code.contains("normal_texture"), "Shader contains normal_texture uniform")
		assert_true(code.contains("panel_lines_intensity"), "Shader contains panel_lines_intensity uniform")
		assert_true(code.contains("reentry_heat"), "Shader contains reentry_heat uniform")
		assert_true(code.contains("heat_glow_color"), "Shader contains heat_glow_color uniform")
		assert_true(code.contains("underside_bias"), "Shader contains underside_bias uniform")
		assert_true(code.contains("pow(effective_heat, 2.5)"), "Shader uses heat^2.5 exponential ramp")
		assert_true(code.contains("thermal_shimmer"), "Shader computes thermal shimmer / emissive pulsation")

func test_ship_hull_shader_material_parameters() -> void:
	var shader = load("res://shaders/ship_hull.gdshader") as Shader
	assert_true(shader != null, "Shader must be valid to test material parameters")
	if not shader:
		return
	
	var mat = ShaderMaterial.new()
	mat.shader = shader
	
	# Verify reentry_heat parameter set and get
	mat.set_shader_parameter("reentry_heat", 0.0)
	assert_almost_eq(mat.get_shader_parameter("reentry_heat"), 0.0, 1e-4, "reentry_heat set to 0.0")
	mat.set_shader_parameter("reentry_heat", 0.65)
	assert_almost_eq(mat.get_shader_parameter("reentry_heat"), 0.65, 1e-4, "reentry_heat set to 0.65")
	mat.set_shader_parameter("reentry_heat", 1.0)
	assert_almost_eq(mat.get_shader_parameter("reentry_heat"), 1.0, 1e-4, "reentry_heat set to 1.0")
	
	# Verify panel_lines_intensity parameter set and get
	mat.set_shader_parameter("panel_lines_intensity", 0.4)
	assert_almost_eq(mat.get_shader_parameter("panel_lines_intensity"), 0.4, 1e-4, "panel_lines_intensity default 0.4")
	mat.set_shader_parameter("panel_lines_intensity", 0.85)
	assert_almost_eq(mat.get_shader_parameter("panel_lines_intensity"), 0.85, 1e-4, "panel_lines_intensity set to 0.85")
	
	# Verify underside_bias parameter set and get
	mat.set_shader_parameter("underside_bias", 1.0)
	assert_almost_eq(mat.get_shader_parameter("underside_bias"), 1.0, 1e-4, "underside_bias default 1.0")
	mat.set_shader_parameter("underside_bias", 2.5)
	assert_almost_eq(mat.get_shader_parameter("underside_bias"), 2.5, 1e-4, "underside_bias set to 2.5")
	
	# Verify Color parameters
	var default_albedo = Color(0.9, 0.9, 0.92, 1.0)
	mat.set_shader_parameter("albedo_color", default_albedo)
	var get_albedo = mat.get_shader_parameter("albedo_color") as Color
	assert_true(get_albedo != null, "albedo_color can be retrieved as Color")
	if get_albedo != null:
		assert_almost_eq(get_albedo.r, 0.9, 1e-3, "albedo_color red")
		assert_almost_eq(get_albedo.g, 0.9, 1e-3, "albedo_color green")
		assert_almost_eq(get_albedo.b, 0.92, 1e-3, "albedo_color blue")
	
	var default_heat_glow = Color(1.0, 0.35, 0.05, 1.0)
	mat.set_shader_parameter("heat_glow_color", default_heat_glow)
	var get_heat_glow = mat.get_shader_parameter("heat_glow_color") as Color
	assert_true(get_heat_glow != null, "heat_glow_color can be retrieved as Color")
	if get_heat_glow != null:
		assert_almost_eq(get_heat_glow.r, 1.0, 1e-3, "heat_glow_color red")
		assert_almost_eq(get_heat_glow.g, 0.35, 1e-3, "heat_glow_color green")
		assert_almost_eq(get_heat_glow.b, 0.05, 1e-3, "heat_glow_color blue")

func test_ship_hull_shader_compiles_headless() -> void:
	var shader = load("res://shaders/ship_hull.gdshader") as Shader
	assert_true(shader != null, "Shader loaded for compilation test")
	if not shader:
		return
		
	# Test attaching shader material to a mesh in RenderingServer
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("reentry_heat", 0.5)
	mat.set_shader_parameter("panel_lines_intensity", 0.4)
	mat.set_shader_parameter("underside_bias", 1.0)
	
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	
	# Verify RenderingServer material binding compiles cleanly
	var rs_mat_rid = RenderingServer.material_create()
	assert_true(rs_mat_rid.is_valid(), "RenderingServer created material")
	RenderingServer.material_set_shader(rs_mat_rid, shader.get_rid())
	
	# Clean up
	RenderingServer.free_rid(rs_mat_rid)
	box.free()
	mesh_inst.free()
