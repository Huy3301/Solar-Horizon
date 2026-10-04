extends Node

## Controls if haptics are allowed to run.
var haptics_enabled: bool = true

## Scales the haptic intensity.
var haptics_intensity_multiplier: float = 1.0

## Triggers vibration on mobile or controller.
func trigger_haptic(intensity: float, duration_sec: float) -> void:
	if not haptics_enabled:
		return
		
	var final_intensity = clampf(intensity * haptics_intensity_multiplier, 0.0, 1.0)
	var duration_ms = int(duration_sec * 1000.0)
	
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)
	
	var joypads = Input.get_connected_joypads()
	for joy_id in joypads:
		Input.start_joy_vibration(joy_id, final_intensity, final_intensity, duration_sec)

func take_damage_haptic() -> void:
	trigger_haptic(1.0, 0.3)

func fire_laser_haptic() -> void:
	trigger_haptic(0.3, 0.1)

func hard_landing_haptic() -> void:
	trigger_haptic(0.8, 0.4)
