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

## Flight buttons: [label, action]. Hold = press while touched; the action names are real InputMap actions so
## the ship needs no touch-specific code. (A steering stick / gyro is still TODO.)
const FLIGHT_BUTTONS: Array = [
	["BOOST", "boost"], ["PULSE", "pulse_drive"], ["LIFT", "vtol_up"], ["DOWN", "vtol_down"],
	["THR +", "throttle_up"], ["THR -", "throttle_down"], ["GEAR", "toggle_gear"],
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
		label.position = Vector2(14, 28)
		btn.add_child(label)
		_flight_root.add_child(btn)
		flight_buttons.append(btn)
	_layout_flight_buttons()
	get_viewport().size_changed.connect(_layout_flight_buttons)

func _layout_flight_buttons() -> void:
	var size: Vector2 = get_viewport_rect().size
	# two columns bottom-right: [BOOST PULSE] [LIFT DOWN] [THR+ THR-] [GEAR]
	var col_w: float = 165.0
	var row_h: float = 105.0
	for i in range(flight_buttons.size()):
		var col: int = i % 2
		var row: int = i / 2
		flight_buttons[i].position = Vector2(size.x - 40.0 - col_w * float(2 - col), size.y - 40.0 - row_h * float(4 - row))

func _ready() -> void:
	var touch_available = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	visible = touch_available
	_build_flight_buttons()
	set_flight_mode(is_flight_mode)

func is_touch_active() -> bool:
	return visible

func set_flight_mode(flight: bool) -> void:
	is_flight_mode = flight
	# When in flight mode, on-foot specific buttons can be toggled
	var on_foot_buttons = [jump_button, jetpack_button, scan_button, visor_button]
	for btn in on_foot_buttons:
		if btn:
			btn.visible = not flight
	if _flight_root:
		_flight_root.visible = flight
