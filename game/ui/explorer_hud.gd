class_name ExplorerHUD
extends Control

@onready var life_support_bar: ProgressBar = $VBoxContainer/LifeSupportBar
@onready var hazard_bar: ProgressBar = $VBoxContainer/HazardBar
@onready var jetpack_bar: ProgressBar = $VBoxContainer/JetpackBar
@onready var compass: Label = $Compass

func update_life_support(value: float) -> void:
	life_support_bar.value = value

func update_hazard(value: float) -> void:
	hazard_bar.value = value

func update_jetpack(value: float) -> void:
	jetpack_bar.value = value

func update_compass(heading: float) -> void:
	compass.text = "Heading: " + str(int(heading))
