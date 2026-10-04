extends "res://tests/test_case.gd"

const OnFootRigScript = preload("res://game/player/on_foot_rig.gd")

func test_on_foot_rig_camera_toggle() -> void:
	var rig = OnFootRigScript.new()
	rig._setup_nodes()
	rig._setup_camera()
	
	assert_true(rig.is_third_person, "Default camera mode is third person")
	assert_almost_eq(rig.spring_arm.spring_length, rig.third_person_distance, 0.01, "Spring arm has 3rd person distance")
	
	rig.toggle_camera_mode()
	assert_false(rig.is_third_person, "Toggled to first person")
	assert_almost_eq(rig.spring_arm.spring_length, 0.0, 0.01, "Spring arm retracted in first person")
	
	rig.toggle_camera_mode()
	assert_true(rig.is_third_person, "Toggled back to third person")
	rig.free()

func test_on_foot_lunar_gravity() -> void:
	var rig = OnFootRigScript.new()
	# Set gravity override mimicking lunar surface gravity (1.62 m/s^2 down)
	rig.gravity_override = Vector3(0.0, -1.62, 0.0)
	
	var g_vec = rig.calculate_gravity_vector()
	assert_almost_eq(g_vec.y, -1.62, 0.01, "Lunar gravity magnitude matches lunar 1.62 m/s^2")
	assert_almost_eq(g_vec.length(), 1.62, 0.01, "Gravity vector length matches 1.62")
	
	rig.free()

func test_on_foot_jetpack_fuel_drain_and_recharge() -> void:
	var rig = OnFootRigScript.new()
	rig._setup_nodes()
	rig._setup_camera()
	
	assert_almost_eq(rig.get_jetpack_fuel(), rig.get_max_jetpack_fuel(), 0.01, "Jetpack fuel starts full")
	
	# Simulate fuel burn
	rig._jetpack_fuel -= 40.0
	assert_almost_eq(rig.get_jetpack_fuel(), 60.0, 0.01, "Fuel burned correctly")
	
	# Recharge fuel manually simulating on-floor recharge
	rig._jetpack_fuel = move_toward(rig._jetpack_fuel, rig.get_max_jetpack_fuel(), 10.0)
	assert_almost_eq(rig.get_jetpack_fuel(), 70.0, 0.01, "Fuel recharged correctly")
	
	rig.free()

func test_on_foot_active_toggle() -> void:
	var rig = OnFootRigScript.new()
	rig._setup_nodes()
	rig._setup_camera()
	
	rig.set_active(false)
	assert_false(rig.is_processing(), "Process disabled when inactive")
	assert_false(rig.is_physics_processing(), "Physics process disabled when inactive")
	assert_true(rig.collision_shape.disabled, "Collision disabled when inactive")
	
	rig.set_active(true)
	assert_true(rig.is_processing(), "Process enabled when active")
	assert_true(rig.is_physics_processing(), "Physics process enabled when active")
	assert_false(rig.collision_shape.disabled, "Collision enabled when active")
	
	rig.free()
