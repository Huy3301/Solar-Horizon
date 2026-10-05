extends "res://tests/test_case.gd"

const RoverScene = preload("res://game/player/rover.tscn")
const RoverControllerScript = preload("res://game/player/rover_controller.gd")

func test_rover_initialization_and_defaults() -> void:
	var rover = RoverScene.instantiate()
	tree.root.add_child(rover)
	rover._ready()
	
	assert_true(rover is RoverControllerScript, "Instantiated scene is a RoverController")
	assert_true(rover.four_wheel_drive, "4WD enabled by default")
	assert_almost_eq(rover.lunar_gravity, 1.62, 0.01, "Default lunar gravity is 1.62 m/s²")
	assert_eq(rover.get_wheels().size(), 4, "Rover resolves 4 VehicleWheel3D nodes")
	assert_eq(rover.get_headlights().size(), 2, "Rover resolves 2 SpotLight3D headlights")
	assert_true(rover.can_mount(), "Rover can be mounted when vacant")
	assert_false(rover.is_occupied(), "Rover starts unoccupied")
	assert_almost_eq(rover.get_speed_kmh(), 0.0, 0.1, "Initial speed is zero")
	
	tree.root.remove_child(rover)
	rover.free()

func test_rover_mount_and_dismount() -> void:
	var rover = RoverScene.instantiate()
	tree.root.add_child(rover)
	rover._ready()
	
	var mock_driver = Node.new()
	mock_driver.name = "AstronautDriver"
	tree.root.add_child(mock_driver)
	
	var mounted_signal_fired: Array = []
	var dismounted_signal_fired: Array = []
	rover.mounted.connect(func(d): mounted_signal_fired.append(d))
	rover.dismounted.connect(func(d, pos): dismounted_signal_fired.append([d, pos]))
	
	# 1. Mount
	rover.mount(mock_driver)
	assert_true(rover.is_occupied(), "Rover is occupied after mount")
	assert_eq(rover.get_driver(), mock_driver, "Driver matches mounted node")
	assert_false(rover.can_mount(), "Cannot mount already occupied rover")
	assert_eq(mounted_signal_fired.size(), 1, "Mounted signal fired once")
	assert_eq(mounted_signal_fired[0], mock_driver, "Mounted signal passes driver")
	
	# 2. Dismount
	var exit_pos: Vector3 = rover.dismount()
	assert_false(rover.is_occupied(), "Rover is not occupied after dismount")
	assert_eq(rover.get_driver(), null, "Driver is null after dismount")
	assert_true(rover.can_mount(), "Can mount again after dismount")
	assert_eq(dismounted_signal_fired.size(), 1, "Dismounted signal fired once")
	assert_eq(dismounted_signal_fired[0][0], mock_driver, "Dismounted signal passes driver")
	assert_true(exit_pos != Vector3.ZERO, "Exit position is non-zero")
	
	tree.root.remove_child(mock_driver)
	mock_driver.free()
	tree.root.remove_child(rover)
	rover.free()

func test_rover_throttle_and_steering() -> void:
	var rover = RoverScene.instantiate()
	tree.root.add_child(rover)
	rover._ready()
	
	# Throttle test
	rover.throttle_input = 0.8
	assert_almost_eq(rover.throttle_input, 0.8, 0.01, "Throttle input clamped and stored")
	assert_true(rover.engine_force > 0.0, "Engine force applied to chassis")
	if rover.wheel_fl:
		assert_true(rover.wheel_fl.engine_force > 0.0, "Engine force distributed to front-left wheel")
	if rover.wheel_rl:
		assert_true(rover.wheel_rl.engine_force > 0.0, "Engine force distributed to rear-left wheel")
		
	# Steering test
	rover.steer_input = 0.5
	assert_almost_eq(rover.steer_input, 0.5, 0.01, "Steer input stored")
	assert_true(rover.steering > 0.0, "Chassis steering angle is positive")
	if rover.wheel_fl and rover.wheel_fl.use_as_steering:
		assert_true(rover.wheel_fl.steering > 0.0, "Front-left wheel steered")
	if rover.wheel_rl:
		assert_almost_eq(rover.wheel_rl.steering, 0.0, 1e-4, "Rear wheels do not steer by default")
		
	# Brake test
	rover.brake_input = 1.0
	assert_almost_eq(rover.brake_input, 1.0, 0.01, "Brake input stored")
	assert_true(rover.brake > 0.0, "Brake force applied")
	
	tree.root.remove_child(rover)
	rover.free()

func test_rover_headlights_toggle() -> void:
	var rover = RoverScene.instantiate()
	tree.root.add_child(rover)
	rover._ready()
	
	var lights_signal_fired: Array = []
	rover.headlights_changed.connect(func(on): lights_signal_fired.append(on))
	
	# Toggle ON
	var state_on = rover.toggle_headlights()
	assert_true(state_on, "Toggle headlights returns true (ON)")
	assert_true(rover.headlights_on, "Headlights property is true")
	for light in rover.get_headlights():
		assert_true(light.visible, "Headlight SpotLight3D node is visible")
	assert_eq(lights_signal_fired.size(), 1, "Headlights changed signal fired")
	assert_true(lights_signal_fired[0], "Signal emitted true")
	
	# Toggle OFF
	var state_off = rover.toggle_headlights()
	assert_false(state_off, "Toggle headlights returns false (OFF)")
	assert_false(rover.headlights_on, "Headlights property is false")
	for light in rover.get_headlights():
		assert_false(light.visible, "Headlight SpotLight3D node is hidden")
	assert_eq(lights_signal_fired.size(), 2, "Headlights changed signal fired again")
	assert_false(lights_signal_fired[1], "Signal emitted false")
	
	tree.root.remove_child(rover)
	rover.free()
