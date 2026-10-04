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
