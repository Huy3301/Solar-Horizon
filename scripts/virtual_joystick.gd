extends Control
class_name SolarVirtualJoystick

## Cross-platform mobile touch virtual thumbstick for analog pitch and roll control.
## Automatically toggles visibility on mobile devices or touch screens.

signal joystick_vector_changed(vector: Vector2)

@export var max_radius: float = 80.0
@export var deadzone: float = 0.08
@export var auto_detect_mobile: bool = true

var is_active: bool = false
var touch_index: int = -1
var stick_center_pos: Vector2 = Vector2.ZERO
var current_output: Vector2 = Vector2.ZERO

@onready var base_circle: Control = $Base
@onready var thumb_knob: Control = $Base/Knob

func _ready() -> void:
	if auto_detect_mobile:
		var is_mobile_os: bool = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
		visible = is_mobile_os or DisplayServer.is_touchscreen_available()
	stick_center_pos = size * 0.5
	_reset_knob()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			touch_index = event.index
			is_active = true
			_update_stick_position(event.position)
		elif not event.pressed and event.index == touch_index:
			_release_joystick()
			
	elif event is InputEventScreenDrag and event.index == touch_index:
		_update_stick_position(event.position)

func _update_stick_position(touch_pos: Vector2) -> void:
	var delta_pos: Vector2 = touch_pos - stick_center_pos
	var distance: float = delta_pos.length()
	
	if distance > max_radius:
		delta_pos = delta_pos.normalized() * max_radius
		
	# Calculate normalized output (-1.0 to 1.0)
	var norm_vec: Vector2 = delta_pos / max_radius
	if norm_vec.length() < deadzone:
		norm_vec = Vector2.ZERO
		
	current_output = norm_vec
	
	if thumb_knob:
		thumb_knob.position = (stick_center_pos + delta_pos) - thumb_knob.size * 0.5
		
	joystick_vector_changed.emit(current_output)

func _release_joystick() -> void:
	is_active = false
	touch_index = -1
	current_output = Vector2.ZERO
	_reset_knob()
	joystick_vector_changed.emit(Vector2.ZERO)

func _reset_knob() -> void:
	if thumb_knob:
		thumb_knob.position = stick_center_pos - thumb_knob.size * 0.5

func get_output() -> Vector2:
	return current_output
