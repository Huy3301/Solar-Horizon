class_name GalaxyMap extends Control

## Interactive Galaxy Map UI.
## Supports gamepad and touch controls for panning around procedural galaxy sectors.

@export var pan_speed: float = 500.0
@export var zoom_speed: float = 0.1

var map_offset: Vector2 = Vector2.ZERO
var map_zoom: float = 1.0

var selected_star_id: String = ""

@onready var info_panel: Panel = $InfoPanel
@onready var star_name_label: Label = $InfoPanel/VBoxContainer/StarNameLabel
@onready var star_class_label: Label = $InfoPanel/VBoxContainer/StarClassLabel

func _ready() -> void:
	set_process_input(true)
	set_process(true)
	info_panel.hide()

func _process(delta: float) -> void:
	# Handle Gamepad / Keyboard panning
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		map_offset += input_dir * pan_speed * delta * map_zoom
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		map_offset -= event.relative * map_zoom
		queue_redraw()
	elif event is InputEventPanGesture:
		map_offset -= event.delta * 20.0 * map_zoom
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(1.0)

func _apply_zoom(direction: float) -> void:
	map_zoom += direction * zoom_speed
	map_zoom = clampf(map_zoom, 0.5, 5.0)
	queue_redraw()

func select_star(star_id: String, star_class: String, planet_count: int) -> void:
	selected_star_id = star_id
	info_panel.show()
	star_name_label.text = "System: " + star_id
	star_class_label.text = "Class: %s | Planets: %d" % [star_class, planet_count]

func _draw() -> void:
	# DEFERRED(phase 5): Draw actual star data points based on map_offset and map_zoom
	draw_circle(Vector2(500, 300) - map_offset / map_zoom, 10.0 / map_zoom, Color.YELLOW)
