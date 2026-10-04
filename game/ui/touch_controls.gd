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

func _ready() -> void:
	var touch_available = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	visible = touch_available

func is_touch_active() -> bool:
	return visible

func set_flight_mode(flight: bool) -> void:
	is_flight_mode = flight
	# When in flight mode, on-foot specific buttons can be toggled
	var on_foot_buttons = [jump_button, jetpack_button, scan_button, visor_button]
	for btn in on_foot_buttons:
		if btn:
			btn.visible = not flight
