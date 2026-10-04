class_name TestShipVFX
extends TestCase

## Smoke test for Ship VFX (WP 3.6):
## Verifies engine plume shader (shock diamonds, heat gradient, expansion),
## RCS puff shader and socket wiring, and re-entry plasma heating response.

const ShipVFXScript = preload("res://game/fx/ship_vfx.gd")

func test_engine_plume_shader() -> void:
	var plume_shader = load("res://shaders/engine_plume.gdshader") as Shader
	assert_true(plume_shader != null, "engine_plume.gdshader loads as Shader")
	
	if plume_shader:
		var code: String = plume_shader.code
		assert_true(code.contains("shock_diamond_frequency"), "Plume shader contains shock_diamond_frequency uniform")
		assert_true(code.contains("shock_speed"), "Plume shader contains animated shock_speed uniform")
		assert_true(code.contains("atmosphere_density"), "Plume shader contains atmosphere_density uniform")
		assert_true(code.contains("expansion_factor"), "Plume shader contains expansion_factor uniform")
		assert_true(code.contains("plume_color_core"), "Plume shader contains plume_color_core uniform")
		assert_true(code.contains("plume_color_mid"), "Plume shader contains plume_color_mid uniform")
		assert_true(code.contains("plume_color_outer"), "Plume shader contains plume_color_outer uniform")
		assert_true(code.contains("plume_color_edge"), "Plume shader contains plume_color_edge uniform")
		assert_true(code.contains("sin("), "Plume shader contains sin waves for shock diamonds")
		assert_true(code.contains("cos("), "Plume shader contains cos rings for shock diamonds")
		
		# Test instantiation on a material
		var mat = ShaderMaterial.new()
		mat.shader = plume_shader
		mat.set_shader_parameter("atmosphere_density", 0.0)  # Vacuum
		mat.set_shader_parameter("expansion_factor", 1.5)
		mat.set_shader_parameter("thrust_intensity", 1.0)
		mat.set_shader_parameter("shock_diamond_frequency", 8.0)
		assert_almost_eq(mat.get_shader_parameter("atmosphere_density"), 0.0, 1e-4, "Vacuum atmosphere density set correctly")
		assert_almost_eq(mat.get_shader_parameter("expansion_factor"), 1.5, 1e-4, "Expansion factor set correctly")

func test_rcs_puff_shader() -> void:
	var rcs_shader = load("res://shaders/fx/rcs_puff.gdshader") as Shader
	assert_true(rcs_shader != null, "shaders/fx/rcs_puff.gdshader loads as Shader")
	
	var rcs_game_shader = load("res://game/fx/rcs_puff.gdshader") as Shader
	assert_true(rcs_game_shader != null, "game/fx/rcs_puff.gdshader loads as Shader")
	
	if rcs_shader:
		var code: String = rcs_shader.code
		assert_true(code.contains("puff_intensity"), "RCS shader contains puff_intensity uniform")
		assert_true(code.contains("burst_progress"), "RCS shader contains burst_progress uniform")
		assert_true(code.contains("cone_expansion"), "RCS shader contains cone_expansion uniform")
		
		var mat = ShaderMaterial.new()
		mat.shader = rcs_shader
		mat.set_shader_parameter("burst_progress", 0.5)
		assert_almost_eq(mat.get_shader_parameter("burst_progress"), 0.5, 1e-4, "RCS burst progress set correctly")

func test_reentry_plasma_shader() -> void:
	var reentry_shader = load("res://shaders/fx/reentry_plasma.gdshader") as Shader
	assert_true(reentry_shader != null, "shaders/fx/reentry_plasma.gdshader loads as Shader")
	
	if reentry_shader:
		var code: String = reentry_shader.code
		assert_true(code.contains("heat_intensity"), "Reentry shader contains heat_intensity uniform")
		assert_true(code.contains("stream_speed"), "Reentry shader contains stream_speed uniform")
		assert_true(code.contains("plasma_color_core"), "Reentry shader contains plasma_color_core uniform")
		assert_true(code.contains("plasma_color_outer"), "Reentry shader contains plasma_color_outer uniform")
		
		var mat = ShaderMaterial.new()
		mat.shader = reentry_shader
		mat.set_shader_parameter("heat_intensity", 0.75)
		assert_almost_eq(mat.get_shader_parameter("heat_intensity"), 0.75, 1e-4, "Reentry heat intensity set correctly")

func test_ship_scene_vfx_structure() -> void:
	var ship_scene = load("res://scenes/ship.tscn") as PackedScene
	assert_true(ship_scene != null, "scenes/ship.tscn loads successfully")
	
	var ship = ship_scene.instantiate() as ShipFlightController
	assert_true(ship != null, "scenes/ship.tscn instantiates as ShipFlightController")
	
	if ship:
		var ship_vfx = ship.get_node_or_null("ShipVFX")
		assert_true(ship_vfx != null, "ShipVFX node exists on Ship")
		assert_true(ship_vfx is ShipVFXScript, "ShipVFX node is instance of ShipVFXScript")
		if ship_vfx:
			ship_vfx.ensure_initialized()
		
		var sheath = ship.get_node_or_null("VisualModel/ReentrySheath") as MeshInstance3D
		assert_true(sheath != null, "ReentrySheath mesh exists under VisualModel")
		if sheath:
			assert_false(sheath.visible, "ReentrySheath initially hidden when not in reentry")
			
		# Check all 7 RCS socket nodes and their attached puff meshes
		var sockets: Array[String] = [
			"SOCKET_rcs_nose_pitch_up",
			"SOCKET_rcs_nose_pitch_down",
			"SOCKET_rcs_nose_yaw_port",
			"SOCKET_rcs_nose_yaw_stbd",
			"SOCKET_rcs_tail_port",
			"SOCKET_rcs_tail_stbd",
			"SOCKET_rcs_tail_up"
		]
		
		for s_name in sockets:
			var sock_path = "VisualModel/OrbiterModel/" + s_name
			var socket = ship.get_node_or_null(sock_path)
			assert_true(socket != null, "Orbiter socket exists: " + s_name)
			if socket:
				var puff = socket.get_node_or_null("RCSPuff") as MeshInstance3D
				assert_true(puff != null, "RCSPuff mesh exists on socket: " + s_name)
				if puff:
					assert_false(puff.visible, "RCSPuff initially hidden on socket: " + s_name)
					
		# Check engine plumes
		var left_plume = ship.get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_L/LeftEnginePlume")
		var right_plume = ship.get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_R/RightEnginePlume")
		assert_true(left_plume != null, "LeftEnginePlume exists on SOCKET_engine_L")
		assert_true(right_plume != null, "RightEnginePlume exists on SOCKET_engine_R")
		
		ship.free()

func test_ship_vfx_reentry_dynamics() -> void:
	var ship_scene = load("res://scenes/ship.tscn") as PackedScene
	var ship = ship_scene.instantiate() as ShipFlightController
	
	if ship:
		var vfx = ship.get_node_or_null("ShipVFX")
		assert_true(vfx != null, "ShipVFX node found")
		
		if vfx:
			vfx.ensure_initialized()
			
			# Initially at zero heating
			assert_almost_eq(vfx.get_reentry_heat(), 0.0, 1e-4, "Initial reentry heat is 0.0")
			
			# Simulate entry conditions: q = 800 Pa, Mach = 20 -> q * mach = 16000
			vfx.set_reentry_parameters(800.0, 20.0)
			assert_almost_eq(vfx.target_reentry_heat, 1.0, 1e-4, "Target reentry heat reaches 1.0 at threshold")
			
			# Process 0.25 s -> thermal rise begins smoothly
			vfx._process(0.25)
			assert_true(vfx.get_reentry_heat() > 0.1, "Reentry heat rises smoothly after process tick")
			assert_true(vfx.get_reentry_heat() < 1.0, "Reentry heat does not instantaneously jump to max")
			
			# Process full rise to max
			vfx._process(1.0)
			assert_almost_eq(vfx.get_reentry_heat(), 1.0, 0.05, "Reentry heat reaches peak")
			assert_true(vfx.reentry_sheath != null and vfx.reentry_sheath.visible, "ReentrySheath mesh is visible under active heating")
			
			# Simulate cooling (exited atmosphere or decelerated)
			vfx.set_reentry_parameters(0.0, 0.0)
			assert_almost_eq(vfx.target_reentry_heat, 0.0, 1e-4, "Target reentry heat drops to 0.0")
			
			# Thermal dissipation / cooling inertia
			vfx._process(0.5)
			assert_true(vfx.get_reentry_heat() > 0.0, "Reentry heat fades smoothly, retaining residual heat")
			assert_true(vfx.get_reentry_heat() < 1.0, "Reentry heat cools down over time")
			
			# Full cool down
			vfx._process(3.0)
			assert_almost_eq(vfx.get_reentry_heat(), 0.0, 1e-3, "Reentry heat fully dissipated")
			assert_false(vfx.reentry_sheath != null and vfx.reentry_sheath.visible, "ReentrySheath mesh hidden after cooling")
			
		ship.free()

func test_ship_vfx_rcs_controls() -> void:
	var ship_scene = load("res://scenes/ship.tscn") as PackedScene
	var ship = ship_scene.instantiate() as ShipFlightController
	
	if ship:
		var vfx = ship.get_node_or_null("ShipVFX")
		assert_true(vfx != null, "ShipVFX node found")
		
		if vfx:
			vfx.ensure_initialized()
			
			# Verify initially inactive
			assert_false(vfx.get_rcs_active("SOCKET_rcs_nose_pitch_up"), "Nose pitch up RCS initially inactive")
			assert_false(vfx.get_rcs_active("SOCKET_rcs_nose_yaw_port"), "Nose yaw port RCS initially inactive")
			
			# Test Pitch Up
			ship.control_pitch = 1.0
			vfx._process(0.016)
			assert_true(vfx.get_rcs_active("SOCKET_rcs_nose_pitch_up"), "Pitch up fires SOCKET_rcs_nose_pitch_up")
			assert_false(vfx.get_rcs_active("SOCKET_rcs_nose_pitch_down"), "Pitch up does not fire pitch down")
			
			# Test Pitch Down
			ship.control_pitch = -1.0
			vfx._process(0.016)
			assert_true(vfx.get_rcs_active("SOCKET_rcs_nose_pitch_down"), "Pitch down fires SOCKET_rcs_nose_pitch_down")
			
			# Test Yaw Left (Port)
			ship.control_pitch = 0.0
			ship.control_yaw = 1.0
			vfx._process(0.016)
			assert_true(vfx.get_rcs_active("SOCKET_rcs_nose_yaw_port"), "Yaw port fires SOCKET_rcs_nose_yaw_port")
			assert_true(vfx.get_rcs_active("SOCKET_rcs_tail_stbd"), "Yaw port fires SOCKET_rcs_tail_stbd")
			
			# Test VTOL Up
			ship.control_yaw = 0.0
			ship.control_vtol = 1.0
			vfx._process(0.016)
			assert_true(vfx.get_rcs_active("SOCKET_rcs_tail_up"), "VTOL fires SOCKET_rcs_tail_up")
			
			# Test manual puff trigger
			vfx.trigger_rcs_puff("SOCKET_rcs_tail_port", 0.8)
			assert_true(vfx.get_rcs_active("SOCKET_rcs_tail_port"), "Manual trigger fires SOCKET_rcs_tail_port")
			
			# Test puff expiration
			vfx._process(vfx.rcs_puff_duration + 0.1)
			assert_false(vfx.get_rcs_active("SOCKET_rcs_tail_port"), "RCS puff expires after duration")
			
		ship.free()

func test_ship_vfx_atmosphere_expansion() -> void:
	var ship_scene = load("res://scenes/ship.tscn") as PackedScene
	var ship = ship_scene.instantiate() as ShipFlightController
	
	if ship:
		var vfx = ship.get_node_or_null("ShipVFX")
		if vfx:
			vfx.ensure_initialized()
			
			# Test vacuum setting
			vfx.set_atmosphere_density(0.0)
			assert_almost_eq(vfx.get_atmosphere_density(), 0.0, 1e-4, "Vacuum atmosphere density is 0.0")
			
			# Test sea-level dense air setting
			vfx.set_atmosphere_density(1.0)
			assert_almost_eq(vfx.get_atmosphere_density(), 1.0, 1e-4, "Dense air atmosphere density is 1.0")
			
			# Test throttle update
			vfx.set_throttle(0.85)
			assert_almost_eq(vfx.current_throttle, 0.85, 1e-4, "Throttle updated to 0.85")
			
			# Verify plume material uniforms updated
			vfx._process(0.016)
			var plume = ship.get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_L/LeftEnginePlume") as MeshInstance3D
			assert_true(plume != null, "Left engine plume exists")
			if plume:
				var mat = plume.material_override as ShaderMaterial
				if mat == null and plume.mesh:
					mat = plume.mesh.material as ShaderMaterial
				assert_true(mat != null, "Plume has ShaderMaterial")
				if mat:
					var atm = mat.get_shader_parameter("atmosphere_density")
					assert_true(atm != null, "atmosphere_density parameter is not null")
					if atm != null:
						assert_almost_eq(float(atm), 1.0, 1e-4, "Plume material atmosphere_density matches")
					var thr = mat.get_shader_parameter("thrust_intensity")
					assert_true(thr != null, "thrust_intensity parameter is not null")
					if thr != null:
						assert_almost_eq(float(thr), 0.85, 1e-4, "Plume material thrust_intensity matches")
					
		ship.free()
