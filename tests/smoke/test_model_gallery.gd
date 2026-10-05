class_name TestModelGallery
extends TestCase

func test_model_gallery_scene_structure() -> void:
	var gallery_scene = load("res://scenes/dev/model_gallery.tscn") as PackedScene
	assert_true(gallery_scene != null, "model_gallery.tscn loads successfully")
	if not gallery_scene:
		return

	var gallery = gallery_scene.instantiate()
	assert_true(gallery != null, "model_gallery.tscn instantiates successfully")
	if not gallery:
		return

	# Showroom root
	var showroom = gallery.get_node_or_null("Showroom")
	assert_true(showroom != null, "Showroom container node exists")

	# Turntable platform floor
	var floor_mesh = gallery.get_node_or_null("Showroom/ShowroomFloor") as MeshInstance3D
	assert_true(floor_mesh != null, "ShowroomFloor mesh instance exists")
	if floor_mesh and floor_mesh.mesh is CylinderMesh:
		var cyl = floor_mesh.mesh as CylinderMesh
		assert_almost_eq(cyl.top_radius, 16.0, 1.5, "Showroom floor turntable platform radius ~15m")
		assert_almost_eq(cyl.height, 0.4, 0.05, "Showroom floor platform height 0.4m")

	# Lighting
	var dir_light = gallery.get_node_or_null("Showroom/DirectionalLight3D") as DirectionalLight3D
	assert_true(dir_light != null, "DirectionalLight3D key light exists")
	if dir_light:
		assert_true(dir_light.shadow_enabled, "Key directional light has shadow enabled")

	var fill_light = gallery.get_node_or_null("Showroom/FillLight")
	assert_true(fill_light != null, "FillLight exists")

	# World Environment
	var world_env = gallery.get_node_or_null("Showroom/WorldEnvironment") as WorldEnvironment
	assert_true(world_env != null, "WorldEnvironment exists")
	if world_env and world_env.environment:
		assert_eq(world_env.environment.tonemap_mode, Environment.TONE_MAPPER_ACES, "Studio environment uses ACES tonemapper")
		assert_true(world_env.environment.glow_enabled, "Studio environment has glow enabled")

	# Camera rig
	var cam_pivot = gallery.get_node_or_null("CameraPivot") as Node3D
	assert_true(cam_pivot != null, "CameraPivot node exists")

	var camera = gallery.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	assert_true(camera != null, "Camera3D node exists")
	if camera:
		assert_true(camera.current, "Camera3D is marked current")
		assert_almost_eq(camera.position.z, 18.0, 0.1, "Camera3D initial distance is 18m")

	# HUD
	var info_label = gallery.get_node_or_null("CanvasLayer/InfoLabel") as Label
	assert_true(info_label != null, "CanvasLayer/InfoLabel exists")

	gallery.free()

func test_orbiter_sockets_and_animation() -> void:
	var gallery_scene = load("res://scenes/dev/model_gallery.tscn") as PackedScene
	assert_true(gallery_scene != null, "model_gallery.tscn loads")
	if not gallery_scene:
		return

	var gallery = gallery_scene.instantiate()
	if not gallery:
		return

	var orbiter = gallery.get_node_or_null("Showroom/OrbiterInstance") as Node3D
	assert_true(orbiter != null, "OrbiterInstance present in showroom")

	if orbiter:
		# Main Propulsion sockets
		assert_true(orbiter.get_node_or_null("SOCKET_engine_L") != null, "Orbiter has SOCKET_engine_L")
		assert_true(orbiter.get_node_or_null("SOCKET_engine_R") != null, "Orbiter has SOCKET_engine_R")

		# RCS sockets
		assert_true(orbiter.get_node_or_null("SOCKET_rcs_nose_pitch_up") != null, "Orbiter has SOCKET_rcs_nose_pitch_up")
		assert_true(orbiter.get_node_or_null("SOCKET_rcs_nose_pitch_down") != null, "Orbiter has SOCKET_rcs_nose_pitch_down")
		assert_true(orbiter.get_node_or_null("SOCKET_rcs_nose_yaw_port") != null, "Orbiter has SOCKET_rcs_nose_yaw_port")
		assert_true(orbiter.get_node_or_null("SOCKET_rcs_nose_yaw_stbd") != null, "Orbiter has SOCKET_rcs_nose_yaw_stbd")
		assert_true(orbiter.get_node_or_null("SOCKET_rcs_tail_port") != null, "Orbiter has SOCKET_rcs_tail_port")
		assert_true(orbiter.get_node_or_null("SOCKET_rcs_tail_stbd") != null, "Orbiter has SOCKET_rcs_tail_stbd")
		assert_true(orbiter.get_node_or_null("SOCKET_rcs_tail_up") != null, "Orbiter has SOCKET_rcs_tail_up")

		# Navigation and camera sockets
		assert_true(orbiter.get_node_or_null("SOCKET_nav_port") != null, "Orbiter has SOCKET_nav_port")
		assert_true(orbiter.get_node_or_null("SOCKET_nav_stbd") != null, "Orbiter has SOCKET_nav_stbd")
		assert_true(orbiter.get_node_or_null("SOCKET_cockpit_cam") != null, "Orbiter has SOCKET_cockpit_cam")
		assert_true(orbiter.get_node_or_null("SOCKET_chase_cam") != null, "Orbiter has SOCKET_chase_cam")

		# AnimationPlayer & gear deployment
		var anim = orbiter.get_node_or_null("AnimationPlayer") as AnimationPlayer
		assert_true(anim != null, "Orbiter has AnimationPlayer")
		if anim:
			assert_true(anim.has_animation("gear_deploy"), "Orbiter has gear_deploy animation")

		# LOD meshes
		assert_true(orbiter.get_node_or_null("Orbiter_LOD0") != null, "Orbiter has Orbiter_LOD0")
		assert_true(orbiter.get_node_or_null("Orbiter_LOD1") != null, "Orbiter has Orbiter_LOD1")

	gallery.free()

func test_lander_sockets() -> void:
	var gallery_scene = load("res://scenes/dev/model_gallery.tscn") as PackedScene
	assert_true(gallery_scene != null, "model_gallery.tscn loads")
	if not gallery_scene:
		return

	var gallery = gallery_scene.instantiate()
	if not gallery:
		return

	var lander = gallery.get_node_or_null("Showroom/LanderInstance") as Node3D
	assert_true(lander != null, "LanderInstance present in showroom")

	if lander:
		# RCS sockets (1 to 4)
		assert_true(lander.get_node_or_null("SOCKET_rcs_1") != null, "Lander has SOCKET_rcs_1")
		assert_true(lander.get_node_or_null("SOCKET_rcs_2") != null, "Lander has SOCKET_rcs_2")
		assert_true(lander.get_node_or_null("SOCKET_rcs_3") != null, "Lander has SOCKET_rcs_3")
		assert_true(lander.get_node_or_null("SOCKET_rcs_4") != null, "Lander has SOCKET_rcs_4")

		# Docking collar and descent engine sockets
		assert_true(lander.get_node_or_null("SOCKET_docking") != null, "Lander has SOCKET_docking")
		assert_true(lander.get_node_or_null("SOCKET_engine_descent") != null, "Lander has SOCKET_engine_descent")

		# LOD meshes
		assert_true(lander.get_node_or_null("LunarLander_LOD0") != null, "Lander has LunarLander_LOD0")
		assert_true(lander.get_node_or_null("LunarLander_LOD1") != null, "Lander has LunarLander_LOD1")

		# Verify Rover presence in Showroom
		var rover = gallery.get_node_or_null("Showroom/RoverInstance") as Node3D
		assert_true(rover != null, "RoverInstance present in showroom")
		if rover:
			assert_true(rover.get_node_or_null("SOCKET_cargo") != null, "Rover has SOCKET_cargo")
			assert_true(rover.get_node_or_null("SOCKET_seat_driver") != null, "Rover has SOCKET_seat_driver")
			assert_true(rover.get_node_or_null("SOCKET_headlight_L") != null, "Rover has SOCKET_headlight_L")
			assert_true(rover.get_node_or_null("SOCKET_wheel_FL") != null, "Rover has SOCKET_wheel_FL")
			assert_true(rover.get_node_or_null("Rover_LOD0") != null, "Rover has Rover_LOD0")
			assert_true(rover.get_node_or_null("Rover_LOD1") != null, "Rover has Rover_LOD1")

	gallery.free()

func test_gallery_controls_and_hud() -> void:
	var gallery_scene = load("res://scenes/dev/model_gallery.tscn") as PackedScene
	assert_true(gallery_scene != null, "model_gallery.tscn loads")
	if not gallery_scene:
		return

	var gallery = gallery_scene.instantiate()
	if not gallery:
		return

	if tree:
		tree.root.add_child(gallery)
	gallery.notification(Node.NOTIFICATION_READY)

	# Initial HUD text
	var info_label = gallery.get_node_or_null("CanvasLayer/InfoLabel") as Label
	assert_true(info_label != null, "InfoLabel exists")
	if info_label:
		assert_true(info_label.text.contains("SPACECRAFT SHOWROOM"), "HUD has showroom header")

	# Test Focus Orbiter (Key 1)
	var ev1 = InputEventKey.new()
	ev1.keycode = KEY_1
	ev1.pressed = true
	gallery._unhandled_input(ev1)
	assert_almost_eq(gallery.target_pivot_pos.x, 0.0, 0.1, "Focusing orbiter sets pivot X to 0")
	assert_almost_eq(gallery.camera_distance, 18.0, 0.1, "Focusing orbiter sets camera distance to 18")

	# Test Focus Lunar Lander (Key 2)
	var ev2 = InputEventKey.new()
	ev2.keycode = KEY_2
	ev2.pressed = true
	gallery._unhandled_input(ev2)
	assert_almost_eq(gallery.target_pivot_pos.x, 14.0, 0.1, "Focusing lander sets pivot X to 14")
	assert_almost_eq(gallery.camera_distance, 12.0, 0.1, "Focusing lander sets camera distance to 12")

	# Test Focus Lunar Rover (Key 3)
	var ev3 = InputEventKey.new()
	ev3.keycode = KEY_3
	ev3.pressed = true
	gallery._unhandled_input(ev3)
	assert_almost_eq(gallery.target_pivot_pos.x, -12.0, 0.1, "Focusing rover sets pivot X to -12")
	assert_almost_eq(gallery.camera_distance, 6.0, 0.1, "Focusing rover sets camera distance to 6")

	# Test Toggle Turntable Auto-rotate (Space)
	var initial_auto = gallery.auto_rotate
	var ev_space = InputEventKey.new()
	ev_space.keycode = KEY_SPACE
	ev_space.pressed = true
	gallery._unhandled_input(ev_space)
	assert_eq(gallery.auto_rotate, not initial_auto, "Turntable auto-rotate toggled")

	# Test Toggle Gear Deploy Animation (Key G)
	var initial_gear = gallery.gear_deployed
	var ev_g = InputEventKey.new()
	ev_g.keycode = KEY_G
	ev_g.pressed = true
	gallery._unhandled_input(ev_g)
	assert_eq(gallery.gear_deployed, not initial_gear, "Orbiter landing gear toggle changed state")

	# Test process tick does not crash
	gallery._process(0.016)

	if tree and gallery.get_parent() == tree.root:
		tree.root.remove_child(gallery)
	gallery.free()
