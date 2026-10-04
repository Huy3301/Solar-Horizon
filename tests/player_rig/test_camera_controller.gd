extends "res://tests/test_case.gd"

const CameraControllerScript = preload("res://scripts/camera_controller.gd")

func test_camera_mode_cycle() -> void:
	var controller = CameraControllerScript.new()
	controller.current_mode = CameraControllerScript.CameraMode.COCKPIT
	
	controller._cycle_camera_mode()
	assert_eq(controller.current_mode, CameraControllerScript.CameraMode.CHASE, "Cycling from COCKPIT enters CHASE")
	
	controller._cycle_camera_mode()
	assert_eq(controller.current_mode, CameraControllerScript.CameraMode.FREE, "Cycling from CHASE enters FREE")
	
	controller._cycle_camera_mode()
	assert_eq(controller.current_mode, CameraControllerScript.CameraMode.COCKPIT, "Cycling from FREE enters COCKPIT")
	controller.free()

func test_camera_trauma_and_shake() -> void:
	var controller = CameraControllerScript.new()
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	controller.add_child(cam)
	
	assert_eq(controller.get_trauma(), 0.0, "Initial trauma should be 0")
	
	controller.add_shake(0.5)
	assert_almost_eq(controller.get_trauma(), 0.5, 0.001, "Trauma adds up")
	
	controller.add_trauma(0.8)
	assert_almost_eq(controller.get_trauma(), 1.0, 0.001, "Trauma clamps to 1.0")
	
	# Apply shake decay over delta
	controller._apply_camera_shake(0.5)
	assert_true(controller.get_trauma() < 1.0, "Trauma decays after physics frame")
	
	# Decay to zero
	controller._apply_camera_shake(2.0)
	assert_eq(controller.get_trauma(), 0.0, "Trauma reaches 0.0 after decay")
	assert_eq(cam.position, Vector3.ZERO, "Camera returns to rest position")
	
	controller.free()

func test_dynamic_fov_by_speed() -> void:
	var controller = CameraControllerScript.new()
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	controller.add_child(cam)
	controller.base_fov = 70.0
	controller.max_fov = 90.0
	cam.fov = 70.0
	
	var mock_ship = RigidBody3D.new()
	mock_ship.linear_velocity = Vector3(0, 0, 0)
	controller.set_target(mock_ship)
	
	controller._update_dynamic_fov(1.0)
	assert_almost_eq(cam.fov, 70.0, 0.5, "FOV stays near base FOV at zero speed")
	
	# High speed (8000 m/s)
	mock_ship.linear_velocity = Vector3(8000.0, 0, 0)
	for i in range(10):
		controller._update_dynamic_fov(0.5)
		
	assert_true(cam.fov > 80.0, "FOV increases significantly at high speed")
	assert_true(cam.fov <= 90.01, "FOV does not exceed max_fov")
	
	controller.free()
	mock_ship.free()
