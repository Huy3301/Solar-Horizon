class_name TouchControls extends Control

## Mobile on-screen touch controls for flight and on-foot exploration.
## Provides touchscreen buttons for jump, jetpack, interact, scan, visor, and flight controls.

@onready var movement_joystick: Control = get_node_or_null("MovementJoystick")
@onready var jump_button: TouchScreenButton = get_node_or_null("JumpButton")
@onready var jetpack_button: TouchScreenButton = get_node_or_null("JetpackButton")
@onready var interact_button: TouchScreenButton = get_node_or_null("InteractButton")
@onready var scan_button: TouchScreenButton = get_node_or_null("ScanButton")
@onready var visor_button: TouchScreenButton = get_node_or_null("VisorButton")

var is_flight_mode: bool = false
var _stick_touch_index: int = -1
var _stick_vector: Vector2 = Vector2.ZERO
var _stick_visual_offset: Vector2 = Vector2.ZERO
var _pressed_stick_actions: Dictionary = {}
var _hud_scale: float = 1.0
var _touch_visuals_built: bool = false

## Flight buttons: [label, action]. Hold = press while touched; the action names are real InputMap actions so
## the ship needs no touch-specific code.
const FLIGHT_BUTTONS: Array = [
	["BOOST", "boost"], ["PULSE", "pulse_drive"], ["LIFT", "vtol_up"], ["DOWN", "vtol_down"],
	["THR +", "throttle_up"], ["THR -", "throttle_down"], ["GEAR", "toggle_gear"],
]
const ON_FOOT_BUTTONS: Array = [
	["JUMP", "JumpButton"], ["JET", "JetpackButton"], ["USE", "InteractButton"],
	["SCAN", "ScanButton"], ["VISOR", "VisorButton"],
]
var flight_buttons: Array[TouchScreenButton] = []
var _flight_root: Node2D

func _build_flight_buttons() -> void:
	_flight_root = Node2D.new()
	_flight_root.name = "FlightButtons"
	add_child(_flight_root)
	for spec in FLIGHT_BUTTONS:
		var btn := TouchScreenButton.new()
		btn.name = "Flight_" + String(spec[1])
		btn.action = String(spec[1])
		var img := Image.create_empty(150, 90, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.05, 0.15, 0.25, 0.55))
		btn.texture_normal = ImageTexture.create_from_image(img)
		var img_p := Image.create_empty(150, 90, false, Image.FORMAT_RGBA8)
		img_p.fill(Color(0.2, 0.7, 1.0, 0.8))
		btn.texture_pressed = ImageTexture.create_from_image(img_p)
		var label := Label.new()
		label.text = String(spec[0])
		label.position = Vector2(-75, -17)
		label.size = Vector2(150, 34)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
		label.add_theme_font_size_override("font_size", 18)
		btn.add_child(label)
		_flight_root.add_child(btn)
		flight_buttons.append(btn)
	_build_on_foot_button_visuals()
	_layout_touch_controls()
	get_viewport().size_changed.connect(_layout_touch_controls)

func _build_on_foot_button_visuals() -> void:
	if _touch_visuals_built:
		return
	_touch_visuals_built = true
	for spec in ON_FOOT_BUTTONS:
		var button: TouchScreenButton = get_node_or_null(String(spec[1])) as TouchScreenButton
		if not button:
			continue
		var normal_image := Image.create_empty(96, 96, false, Image.FORMAT_RGBA8)
		normal_image.fill(Color(0.035, 0.105, 0.16, 0.82))
		button.texture_normal = ImageTexture.create_from_image(normal_image)
		var pressed_image := Image.create_empty(96, 96, false, Image.FORMAT_RGBA8)
		pressed_image.fill(Color(0.08, 0.48, 0.7, 0.94))
		button.texture_pressed = ImageTexture.create_from_image(pressed_image)
		var hit_shape := CircleShape2D.new()
		hit_shape.radius = 48.0
		button.shape = hit_shape
		var label := Label.new()
		label.name = "TouchLabel"
		label.text = String(spec[0])
		label.position = Vector2(-48, -16)
		label.size = Vector2(96, 32)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0))
		label.add_theme_font_size_override("font_size", 15)
		button.add_child(label)

func _layout_touch_controls() -> void:
	if not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	_hud_scale = _calculate_hud_scale(viewport_size)
	if movement_joystick:
		var stick_size := 150.0 * _hud_scale
		movement_joystick.anchor_left = 0.0
		movement_joystick.anchor_top = 0.0
		movement_joystick.anchor_right = 0.0
		movement_joystick.anchor_bottom = 0.0
		movement_joystick.size = Vector2(stick_size, stick_size)
		movement_joystick.position = Vector2(28.0 * _hud_scale, viewport_size.y - stick_size - 28.0 * _hud_scale)
	_layout_on_foot_buttons(viewport_size)
	_layout_flight_buttons()
	queue_redraw()

func _calculate_hud_scale(viewport_size: Vector2) -> float:
	var desired := compute_s26_hud_scale(Vector2i(viewport_size))
	var margin := 24.0
	var gap := 12.0
	var short_side := minf(viewport_size.x, viewport_size.y)
	if short_side <= 0.0:
		return 1.0
	var portrait := viewport_size.y > viewport_size.x
	# Leave a clear band between the flight controls (top right) and the movement stick (bottom left).
	if portrait:
		desired = minf(desired, viewport_size.y / (405.0 + 150.0 + gap + 2.0 * margin))
		desired = minf(desired, viewport_size.y / 480.0)
	else:
		desired = minf(desired, (viewport_size.x - 2.0 * margin - gap) / 315.0)
		desired = minf(desired, (viewport_size.y - 2.0 * margin - 2.0 * gap) / 288.0)
	return clampf(desired, 0.5, 1.45)

func _layout_on_foot_buttons(viewport_size: Vector2) -> void:
	var portrait := viewport_size.y > viewport_size.x
	var button_size := 96.0 * _hud_scale
	var gap := (12.0 if not portrait else 10.0) * _hud_scale
	var margin := 24.0 * _hud_scale
	for i in range(ON_FOOT_BUTTONS.size()):
		var button: TouchScreenButton = get_node_or_null(String(ON_FOOT_BUTTONS[i][1])) as TouchScreenButton
		if not button:
			continue
		var col := (0 if portrait else i % 2)
		var row := i if portrait else i / 2
		button.scale = Vector2.ONE * (_hud_scale * (0.75 if portrait else 1.0))
		var actual_size := button_size * (0.75 if portrait else 1.0)
		if portrait:
			button.position = Vector2(
				viewport_size.x - margin - actual_size * 0.5,
				viewport_size.y - margin - actual_size * 0.5 - float(row) * (actual_size + gap)
			)
		else:
			button.position = Vector2(
				viewport_size.x - margin - actual_size * 0.5 - float(1 - col) * (actual_size + gap),
				viewport_size.y - margin - actual_size * 0.5 - float(row) * (actual_size + gap)
			)

func _layout_flight_buttons() -> void:
	if not is_inside_tree():
		return
	var size: Vector2 = get_viewport_rect().size
	var portrait := size.y > size.x
	var button_width := 150.0 * _hud_scale
	var button_height := 90.0 * _hud_scale
	var gap_x := 15.0 * _hud_scale
	var gap_y := 15.0 * _hud_scale
	var margin := 24.0 * _hud_scale
	for i in range(flight_buttons.size()):
		var col: int = i % 2
		var row: int = i / 2
		flight_buttons[i].scale = Vector2.ONE * _hud_scale
		if portrait:
			flight_buttons[i].position = Vector2(
				size.x - margin - button_width * (0.5 + float(1 - col)) - gap_x * float(1 - col),
				margin + button_height * 0.5 + float(row) * (button_height + gap_y)
			)
		else:
			flight_buttons[i].position = Vector2(
				size.x - margin - button_width * (0.5 + float(1 - col)) - gap_x * float(1 - col),
				size.y - margin - button_height * 0.5 - float(row) * (button_height + gap_y)
			)

func _ready() -> void:
	var touch_available = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	visible = touch_available
	if movement_joystick:
		movement_joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_flight_buttons()
	set_flight_mode(is_flight_mode)
	_layout_touch_controls()

func _exit_tree() -> void:
	_release_stick_input()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree() or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release_stick_input()

func _release_stick_input() -> void:
	_stick_touch_index = -1
	_stick_vector = Vector2.ZERO
	_stick_visual_offset = Vector2.ZERO
	for action: String in _pressed_stick_actions:
		Input.action_release(action)
	_pressed_stick_actions.clear()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible or not movement_joystick:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_stick_touch(touch.index, make_canvas_position_local(touch.position))
		elif touch.canceled or touch.index == _stick_touch_index:
			_end_stick_touch(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_touch_index:
			_update_stick_touch(drag.index, make_canvas_position_local(drag.position))

func _stick_center() -> Vector2:
	return movement_joystick.position + movement_joystick.size * 0.5

func _stick_max_radius() -> float:
	return maxf(1.0, minf(movement_joystick.size.x, movement_joystick.size.y) * 0.5 - 16.0)

func _begin_stick_touch(index: int, local_position: Vector2) -> bool:
	if _stick_touch_index >= 0 or not movement_joystick:
		return false
	if not Rect2(movement_joystick.position, movement_joystick.size).has_point(local_position):
		return false
	_stick_touch_index = index
	_update_stick_touch(index, local_position)
	return true

func _update_stick_touch(index: int, local_position: Vector2) -> bool:
	if index != _stick_touch_index or not movement_joystick:
		return false
	_stick_visual_offset = local_position - _stick_center()
	_stick_vector = compute_touch_steering_vector(_stick_visual_offset, _stick_max_radius())
	_apply_stick_actions()
	queue_redraw()
	return true

func _end_stick_touch(index: int) -> bool:
	if index != _stick_touch_index:
		return false
	_release_stick_input()
	return true

func _apply_stick_actions() -> void:
	var desired: Dictionary
	if is_flight_mode:
		desired = {
			"roll_right": maxf(_stick_vector.x, 0.0),
			"roll_left": maxf(-_stick_vector.x, 0.0),
			"pitch_up": maxf(-_stick_vector.y, 0.0),
			"pitch_down": maxf(_stick_vector.y, 0.0),
		}
	else:
		desired = {
			"move_left": maxf(-_stick_vector.x, 0.0),
			"move_right": maxf(_stick_vector.x, 0.0),
			"move_forward": maxf(-_stick_vector.y, 0.0),
			"move_back": maxf(_stick_vector.y, 0.0),
		}
	for action: String in desired:
		var strength: float = float(desired[action])
		if strength > 0.001 and InputMap.has_action(action):
			Input.action_press(action, strength)
			_pressed_stick_actions[action] = true
		elif _pressed_stick_actions.has(action):
			Input.action_release(action)
			_pressed_stick_actions.erase(action)
	for action: String in _pressed_stick_actions.keys():
		if not desired.has(action):
			Input.action_release(action)
			_pressed_stick_actions.erase(action)

func _draw() -> void:
	if not movement_joystick or not movement_joystick.is_visible_in_tree():
		return
	var center := _stick_center()
	var radius := _stick_max_radius() + 12.0
	draw_circle(center, radius, Color(0.03, 0.08, 0.13, 0.42))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.45, 0.78, 1.0, 0.75), 2.0, true)
	var knob_offset := _stick_visual_offset
	if knob_offset.length() > _stick_max_radius():
		knob_offset = knob_offset.normalized() * _stick_max_radius()
	var knob_color := Color(0.22, 0.62, 0.88, 0.78)
	if _stick_touch_index >= 0:
		knob_color = Color(0.35, 0.82, 1.0, 0.92)
	draw_circle(center + knob_offset, 20.0, knob_color)

func is_touch_active() -> bool:
	return visible

func set_flight_mode(flight: bool) -> void:
	if is_flight_mode != flight:
		_release_stick_input()
	is_flight_mode = flight
	# When in flight mode, on-foot specific buttons can be toggled
	var on_foot_buttons = [jump_button, jetpack_button, scan_button, visor_button]
	for btn in on_foot_buttons:
		if btn:
			btn.visible = not flight
	if _flight_root:
		_flight_root.visible = flight
	queue_redraw()


## S2e: Touch steering (stick + gyro) & Samsung Galaxy S26+ safe-area scaling.
const S2E_STICK_DEADZONE: float = 0.12
const S2E_GYRO_GAIN: float = 0.65
const S2E_S26_PLUS_WIDTH_PX: float = 3120.0
const S2E_S26_PLUS_HEIGHT_PX: float = 1440.0


## Computes radial deadzoned steering vector (X = roll, Y = pitch) with response curve.
static func compute_touch_steering_vector(
	raw_offset_px: Vector2,
	max_radius_px: float,
	gyro_rad_s: Vector3 = Vector3.ZERO,
	use_gyro: bool = false
) -> Vector2:
	var result: Vector2 = Vector2.ZERO
	if max_radius_px > 0.001:
		var length_px: float = raw_offset_px.length()
		var norm: float = clampf(length_px / max_radius_px, 0.0, 1.0)
		if norm > S2E_STICK_DEADZONE:
			var remapped: float = (norm - S2E_STICK_DEADZONE) / (1.0 - S2E_STICK_DEADZONE)
			var curved: float = pow(remapped, 1.6)
			result = (raw_offset_px / length_px) * curved
	if use_gyro:
		result.x = clampf(result.x - gyro_rad_s.z * S2E_GYRO_GAIN, -1.0, 1.0)
		result.y = clampf(result.y + gyro_rad_s.x * S2E_GYRO_GAIN, -1.0, 1.0)
	return result


## Computes UI scale factor for high-DPI mobile displays like Samsung Galaxy S26+ (3120x1440).
static func compute_s26_hud_scale(viewport_size: Vector2i) -> float:
	var short_edge: float = float(mini(viewport_size.x, viewport_size.y))
	if short_edge <= 0.0:
		return 1.0
	return clampf(short_edge / 1080.0, 0.85, 1.45)
