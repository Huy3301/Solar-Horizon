class_name TouchControls
extends Control

## Mobile on-screen touch controls for on-foot exploration.
## Provides touchscreen buttons for jump, jetpack, interact, scan, and visor.

@onready var movement_joystick: Control = get_node_or_null("MovementJoystick")
@onready var jump_button: TouchScreenButton = get_node_or_null("JumpButton")
@onready var jetpack_button: TouchScreenButton = get_node_or_null("JetpackButton")
@onready var interact_button: TouchScreenButton = get_node_or_null("InteractButton")
@onready var scan_button: TouchScreenButton = get_node_or_null("ScanButton")
@onready var visor_button: TouchScreenButton = get_node_or_null("VisorButton")

func _ready() -> void:
	var touch_available = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	visible = touch_available

func is_touch_active() -> bool:
	return visible
