extends "res://tests/test_case.gd"

const FlightTelemetryScript = preload("res://game/ui/components/flight_telemetry.gd")
const SuitBarsScript = preload("res://game/ui/components/suit_bars.gd")
const OrbitMapScript = preload("res://game/ui/orbit_map.gd")
const TouchControlsScript = preload("res://game/ui/touch_controls.gd")

func test_flight_telemetry_display() -> void:
	var ftel_scene = preload("res://game/ui/components/flight_telemetry.tscn")
	var ftel = ftel_scene.instantiate()
	ftel._ready()
	
	var data = {
		"speed_ms": 1250.0,
		"mach": 3.67,
		"altitude_agl_m": 15400.0,
		"altitude_asl_m": 25000.0,
		"ap_km": 185.0,
		"pe_km": 95.0,
		"throttle_pct": 75.0,
		"gear_down": true,
		"is_landed": false,
		"is_crashed": false
	}
	ftel.update_telemetry(data)
	
	assert_eq(ftel.get_telemetry_value("speed_ms"), 1250.0, "Telemetry speed matches")
	assert_eq(ftel.label_gear.text, "DEPLOYED", "Landing gear text shows DEPLOYED")
	assert_eq(ftel.bar_throttle.value, 75.0, "Throttle bar matches 75%")
	assert_eq(ftel.label_status.text, "NOMINAL FLIGHT", "Status shows nominal flight")
	
	ftel.free()

func test_suit_bars_display() -> void:
	var suit_scene = preload("res://game/ui/components/suit_bars.tscn")
	var suit = suit_scene.instantiate()
	suit._ready()
	
	suit.update_life_support(80.0, 100.0)
	assert_almost_eq(suit.current_life_support, 80.0, 0.01, "Life support matches 80%")
	assert_eq(suit.bar_life_support.value, 80.0, "Life support bar matches 80")
	
	suit.update_hazard(45.0, 100.0)
	assert_almost_eq(suit.current_hazard, 45.0, 0.01, "Hazard level matches 45%")
	assert_eq(suit.bar_hazard.value, 45.0, "Hazard bar matches 45")
	
	suit.update_jetpack(90.0, 100.0)
	assert_almost_eq(suit.current_jetpack, 90.0, 0.01, "Jetpack fuel matches 90%")
	assert_eq(suit.bar_jetpack.value, 90.0, "Jetpack bar matches 90")
	
	suit.update_heading(180.0)
	assert_true(suit.compass_label.text.contains("180°"), "Compass heading formatted correctly")
	
	suit.free()

func test_orbit_map_zoom_and_pan() -> void:
	var omap = OrbitMapScript.new()
	omap._ready()
	var initial_zoom = omap.zoom_level
	
	omap.zoom_in(0.5)
	assert_true(omap.zoom_level > initial_zoom, "Zoom in increases zoom level")
	
	omap.zoom_out(0.5)
	omap.zoom_out(0.5)
	assert_true(omap.zoom_level < initial_zoom, "Zoom out decreases zoom level")
	
	omap.pan_offset = Vector2(100.0, -50.0)
	omap.reset_view()
	assert_eq(omap.pan_offset, Vector2.ZERO, "Reset view zeroes pan offset")
	
	omap.free()

func test_touch_controls_mode_toggle() -> void:
	var tc = TouchControlsScript.new()
	var btn_jump = TouchScreenButton.new()
	var btn_jet = TouchScreenButton.new()
	tc.jump_button = btn_jump
	tc.jetpack_button = btn_jet
	tc.add_child(btn_jump)
	tc.add_child(btn_jet)
	
	tc.set_flight_mode(true)
	assert_true(tc.is_flight_mode, "Mode is flight")
	assert_false(btn_jump.visible, "Jump button hidden in flight mode")
	assert_false(btn_jet.visible, "Jetpack button hidden in flight mode")
	
	tc.set_flight_mode(false)
	assert_false(tc.is_flight_mode, "Mode is on foot")
	assert_true(btn_jump.visible, "Jump button visible in on-foot mode")
	assert_true(btn_jet.visible, "Jetpack button visible in on-foot mode")
	
	tc.free()

func test_touch_controls_stick_drives_movement_and_flight_actions() -> void:
	var tc = TouchControlsScript.new()
	var stick = Control.new()
	stick.position = Vector2(100.0, 300.0)
	stick.size = Vector2(150.0, 150.0)
	tc.movement_joystick = stick
	tc.add_child(stick)
	var center: Vector2 = stick.position + stick.size * 0.5

	assert_false(tc._begin_stick_touch(2, center + Vector2(200.0, 0.0)), "Touches outside the stick base are ignored")
	assert_true(tc._begin_stick_touch(2, center), "A touch on the stick base starts steering")
	assert_true(tc._update_stick_touch(2, center + Vector2(100.0, 0.0)), "The active touch can drag beyond the stick base")
	assert_almost_eq(Input.get_action_strength("move_right"), 1.0, 1e-4, "Right stick deflection drives on-foot movement")
	assert_almost_eq(Input.get_action_strength("move_left"), 0.0, 1e-4, "Opposite movement action stays released")

	tc._update_stick_touch(2, center + Vector2(0.0, -100.0))
	assert_almost_eq(Input.get_action_strength("move_forward"), 1.0, 1e-4, "Up stick deflection drives forward movement")
	assert_true(tc._end_stick_touch(2), "Releasing the active touch ends steering")
	assert_almost_eq(Input.get_action_strength("move_right"), 0.0, 1e-4, "Movement actions release when the stick is released")
	assert_almost_eq(Input.get_action_strength("move_forward"), 0.0, 1e-4, "Forward action releases when the stick is released")

	tc.set_flight_mode(true)
	assert_true(tc._begin_stick_touch(3, center), "The stick remains usable in flight mode")
	tc._update_stick_touch(3, center + Vector2(100.0, -100.0))
	assert_almost_eq(Input.get_action_strength("roll_right"), sqrt(0.5), 1e-4, "Right stick deflection drives flight roll")
	assert_almost_eq(Input.get_action_strength("pitch_up"), sqrt(0.5), 1e-4, "Up stick deflection drives flight pitch")
	assert_true(tc._end_stick_touch(3), "Flight stick touch can be released")
	assert_almost_eq(Input.get_action_strength("roll_right"), 0.0, 1e-4, "Flight roll releases when the stick is released")
	assert_almost_eq(Input.get_action_strength("pitch_up"), 0.0, 1e-4, "Flight pitch releases when the stick is released")
	tc.free()

func test_touch_controls_release_stick_on_cancel_mode_change_and_focus_loss() -> void:
	var tc = TouchControlsScript.new()
	var stick = Control.new()
	stick.position = Vector2(100.0, 300.0)
	stick.size = Vector2(150.0, 150.0)
	tc.movement_joystick = stick
	tc.add_child(stick)
	var center: Vector2 = stick.position + stick.size * 0.5

	assert_true(tc._begin_stick_touch(4, center), "Stick touch starts")
	tc._update_stick_touch(4, center + Vector2(100.0, 0.0))
	var canceled := InputEventScreenTouch.new()
	canceled.index = 4
	canceled.canceled = true
	tc._input(canceled)
	assert_almost_eq(Input.get_action_strength("move_right"), 0.0, 1e-4, "Canceled touch releases movement")
	assert_eq(tc._stick_touch_index, -1, "Canceled touch clears the active finger")

	assert_true(tc._begin_stick_touch(5, center), "Stick can be pressed again after cancellation")
	tc._update_stick_touch(5, center + Vector2(100.0, 0.0))
	tc._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_almost_eq(Input.get_action_strength("move_right"), 0.0, 1e-4, "Losing window focus releases movement")

	assert_true(tc._begin_stick_touch(6, center), "Stick can be pressed again after focus loss")
	tc._update_stick_touch(6, center + Vector2(100.0, 0.0))
	tc.set_flight_mode(true)
	assert_almost_eq(Input.get_action_strength("move_right"), 0.0, 1e-4, "Changing modes releases the previous mode's movement")
	tc.free()

func test_touch_controls_release_stick_when_parent_hides_hud() -> void:
	var parent := Control.new()
	var tc := TouchControlsScript.new()
	var stick := Control.new()
	stick.name = "MovementJoystick"
	stick.position = Vector2(100.0, 300.0)
	stick.size = Vector2(150.0, 150.0)
	tc.add_child(stick)
	parent.add_child(tc)
	tree.root.add_child(parent)
	await tree.process_frame
	tc.visible = true

	var center: Vector2 = stick.position + stick.size * 0.5
	assert_true(tc._begin_stick_touch(7, center), "Stick touch starts while the HUD is visible")
	tc._update_stick_touch(7, center + Vector2(100.0, 0.0))
	assert_almost_eq(Input.get_action_strength("move_right"), 1.0, 1e-4, "Visible HUD drives movement")

	parent.hide()
	tc._notification(Control.NOTIFICATION_VISIBILITY_CHANGED)
	assert_true(tc.visible, "Child visibility property remains unchanged when its parent hides")
	assert_false(tc.is_visible_in_tree(), "HUD is hidden through its parent")
	assert_almost_eq(Input.get_action_strength("move_right"), 0.0, 1e-4, "Parent hiding the HUD releases movement")

	parent.free()
	await tree.process_frame

func test_touch_controls_layout_scales_and_keeps_action_buttons_visible() -> void:
	var tc = preload("res://game/ui/touch_controls.tscn").instantiate()
	tree.root.add_child(tc)
	await tree.process_frame
	tc._layout_touch_controls()

	assert_true(tc._hud_scale > 0.0, "Touch controls have a usable display scale")
	assert_true(tc.jump_button.texture_normal != null, "Jump has a visible touch target")
	assert_true(tc.interact_button.shape != null, "Interact has a real touch hit area")
	assert_eq(tc.jump_button.action, "jump", "Jump touch target drives the existing gameplay action")
	assert_eq(tc.interact_button.action, "interact", "Interact touch target drives the existing gameplay action")
	assert_true(tc.jump_button.position.x < tree.root.get_visible_rect().size.x, "Jump target is positioned within the viewport")
	assert_true(TouchControlsScript.compute_s26_hud_scale(Vector2i(3120, 1440)) > 1.0, "High-resolution displays enlarge touch targets")
	assert_true(tc._calculate_hud_scale(Vector2(320.0, 480.0)) < tc._calculate_hud_scale(Vector2(1920.0, 1080.0)), "Portrait controls scale to fit the available screen")
	tc.queue_free()
	await tree.process_frame
