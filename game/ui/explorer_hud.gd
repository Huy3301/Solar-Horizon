class_name ExplorerHUD
extends Control

@onready var life_support_bar: ProgressBar = get_node_or_null("VBoxContainer/LifeSupportBar")
@onready var hazard_bar: ProgressBar = get_node_or_null("VBoxContainer/HazardBar")
@onready var jetpack_bar: ProgressBar = get_node_or_null("VBoxContainer/JetpackBar")
@onready var compass: Label = get_node_or_null("Compass")

func update_life_support(value: float) -> void:
	if life_support_bar:
		life_support_bar.value = value

func update_hazard(value: float) -> void:
	if hazard_bar:
		hazard_bar.value = value

func update_jetpack(value: float) -> void:
	if jetpack_bar:
		jetpack_bar.value = value

func update_compass(heading: float) -> void:
	if compass:
		compass.text = "Heading: " + str(int(heading))
