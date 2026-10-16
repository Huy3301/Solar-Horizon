class_name TestTutorialSlice
extends TestCase

func test_key_labels_come_from_the_input_map() -> void:
	assert_true(TutorialDirector.key_label(&"throttle_up") != "[throttle_up]", "throttle_up has a key label")
	assert_true(TutorialDirector.key_label(&"pulse_drive") != "[pulse_drive]", "pulse_drive has a key label")
	assert_true(TutorialDirector.key_label(&"no_such_action") == "[no_such_action]", "unknown action falls back to its name")

func test_launch_prompt_names_the_real_throttle_key() -> void:
	var td := TutorialDirector.new()
	td._init_steps()
	var text: String = td.steps[0]["instruction"]
	assert_true(text.contains(TutorialDirector.key_label(&"throttle_up")), "step 1 names the real throttle key: " + text)
	td.free()

func test_no_step_is_complete_without_a_ship() -> void:
	var td := TutorialDirector.new()
	td._init_steps()
	for i in range(3):
		assert_false(bool(td.steps[i]["check"].call()), "step '%s' is not complete with no ship" % td.steps[i]["id"])
	td.free()

func test_terrain_skirts_are_not_mountain_sized() -> void:
	# Skirts 40% of the tallest mountain deep (3.5 km) showed up as giant wall-like wedges from the ground.
	var src: String = FileAccess.get_file_as_string("res://shaders/terrain/terrain_splat.gdshader")
	assert_true(src.length() > 100, "terrain shader readable")
	assert_false(src.contains("max_height * 0.4"), "skirt depth no longer scales with max_height")

func test_earth_relief_has_one_source_of_truth() -> void:
	var scene_text: String = FileAccess.get_file_as_string("res://scenes/main.tscn")
	var expected: String = "max_height_m = %s" % str(float(BodyFrames.MAX_HEIGHT_M[&"Earth"]))
	assert_true(scene_text.contains(expected), "main.tscn Earth max_height_m matches BodyFrames (%s)" % expected)

func test_touch_flight_buttons_drive_real_actions() -> void:
	require_completion()
	await tree.process_frame
	var tc: TouchControls = load("res://game/ui/touch_controls.tscn").instantiate()
	tree.root.add_child(tc)
	await tree.process_frame
	assert_true(tc.flight_buttons.size() >= 7, "flight buttons exist (%d)" % tc.flight_buttons.size())
	for b in tc.flight_buttons:
		assert_true(InputMap.has_action(b.action), "touch button action exists: " + b.action)
	assert_false(tc._flight_root.visible, "flight buttons hidden while on foot")
	tc.set_flight_mode(true)
	assert_true(tc._flight_root.visible, "flight buttons shown in flight")
	for need in ["boost", "pulse_drive", "vtol_up", "throttle_up"]:
		var found := false
		for b in tc.flight_buttons:
			found = found or b.action == need
		assert_true(found, "touch button for " + need)
	tc.queue_free()
	complete()

func test_audio_manager_is_created_for_the_ship() -> void:
	require_completion()
	await tree.process_frame
	var w = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(w)
	for i in range(5):
		await tree.process_frame
	assert_true(tree.get_first_node_in_group("audio_manager") != null, "AudioManager exists in the world (the ship looks it up)")
	w.queue_free()
	complete()

func test_terrain_patches_have_culling_bounds_that_cover_their_geometry() -> void:
	require_completion()
	await tree.process_frame
	var w = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(w)
	for i in range(30):
		await tree.process_frame
	var q = w.get_node("EarthGlobe").get_node("PlanetRuntime").quadtree
	assert_true(q.last_leaves.size() > 0, "patches exist")
	var bad: int = 0
	for node in q.last_leaves:
		if node.instance == null:
			continue
		var half: Vector3 = node.instance.custom_aabb.size * 0.5
		if half.x < node.bounds_radius or half.x < q.max_height_m:
			bad += 1
	assert_eq(bad, 0, "every patch's custom_aabb covers its patch size and relief")
	w.queue_free()
	complete()
