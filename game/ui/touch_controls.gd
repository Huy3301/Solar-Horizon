class_name TouchControls
extends Control

func _ready() -> void:
	if not OS.has_feature("mobile"):
		hide()
