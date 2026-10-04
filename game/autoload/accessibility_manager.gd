extends Node

## Emitted when the user changes UI scale.
signal ui_scale_changed(new_scale: float)

## Emitted when the color blind mode changes.
signal color_blind_mode_changed(mode: int)

## Emitted when the user changes the toggle controls setting.
signal control_mode_changed(is_toggle: bool)

enum ColorBlindMode {
	NONE = 0,
	PROTANOPIA = 1,
	DEUTERANOPIA = 2,
	TRITANOPIA = 3
}

var ui_scale: float = 1.0:
	set(value):
		ui_scale = value
		ui_scale_changed.emit(ui_scale)
		_apply_ui_scale()

var color_blind_mode: int = ColorBlindMode.NONE:
	set(value):
		color_blind_mode = value
		color_blind_mode_changed.emit(color_blind_mode)
		_apply_color_blind_mode()

var use_toggle_controls: bool = false:
	set(value):
		use_toggle_controls = value
		control_mode_changed.emit(use_toggle_controls)

func _ready() -> void:
	pass

func _apply_ui_scale() -> void:
	# Applies UI scaling to the root window
	get_tree().root.content_scale_factor = ui_scale

func _apply_color_blind_mode() -> void:
	# Update global shaders or UI elements depending on active palettes
	pass
