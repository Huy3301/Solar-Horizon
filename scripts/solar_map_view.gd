extends CanvasLayer
class_name SolarMapView

@export var is_map_open: bool = false
@export var active_vessel_path: NodePath
@export var zoom_level: float = 1.0

var active_vessel: Node3D
var time_warp_factor: float = 1.0

@onready var map_container: Control = $MapContainer
@onready var info_label: Label = $MapContainer/InfoPanel/VBox/InfoLabel
@onready var warp_label: Label = $MapContainer/WarpPanel/WarpLabel
@onready var btn_close_map: Button = $MapContainer/CloseButton

func _ready() -> void:
	if not active_vessel_path.is_empty():
		active_vessel = get_node_or_null(active_vessel_path)
		
	if btn_close_map:
		btn_close_map.pressed.connect(toggle_map_view)
		
	visible = is_map_open

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		toggle_map_view()
		
	if not is_map_open:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = clamp(zoom_level * 0.85, 0.05, 50.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = clamp(zoom_level * 1.15, 0.05, 50.0)
			
	if event.is_action_pressed("time_warp_increase"):
		_set_time_warp(time_warp_factor * 5.0)
	elif event.is_action_pressed("time_warp_decrease"):
		_set_time_warp(max(1.0, time_warp_factor / 5.0))

func toggle_map_view() -> void:
	is_map_open = not is_map_open
	visible = is_map_open

func _set_time_warp(warp: float) -> void:
	time_warp_factor = clamp(warp, 1.0, 10000.0)
	Engine.time_scale = time_warp_factor
	if warp_label:
		warp_label.text = "TIME WARP: %1.0fx" % time_warp_factor

func _process(_delta: float) -> void:
	if not is_map_open or not is_instance_valid(active_vessel):
		return
		
	_update_orbital_info()

func _update_orbital_info() -> void:
	if not info_label:
		return
		
	var v_vec: Vector3 = Vector3.ZERO
	if active_vessel is RigidBody3D:
		v_vec = (active_vessel as RigidBody3D).linear_velocity
		
	var r_vec: Vector3 = active_vessel.global_position
	var r_mag_km: float = r_vec.length() / 1000.0
	var v_mag_kms: float = v_vec.length() / 1000.0
	
	var orbit: OrbitalMechanics.OrbitElements = OrbitalMechanics.calculate_orbit(r_vec, v_vec)
	
	var text: String = "=== ORBITAL SCHEMATIC: THEORETICAL PHYSICS ===\n"
	text += "BODY: EARTH (mu = 3.986e14 m^3/s^2)\n"
	text += "RADIUS: %7.1f km | SPEED: %5.2f km/s\n" % [r_mag_km, v_mag_kms]
	text += "SEMI-MAJOR AXIS (a): %7.1f km\n" % (orbit.semi_major_axis / 1000.0)
	text += "ECCENTRICITY (e): %1.4f\n" % orbit.eccentricity
	text += "INCLINATION (i): %4.1f°\n" % rad_to_deg(orbit.inclination_rad)
	text += "APOAPSIS (Ap): %7.1f km\n" % (orbit.apoapsis_alt / 1000.0)
	text += "PERIAPSIS (Pe): %7.1f km\n" % (orbit.periapsis_alt / 1000.0)
	
	if orbit.period_seconds > 0:
		var mins: float = orbit.period_seconds / 60.0
		text += "PERIOD (T): %5.1f mins (%3.2f hrs)\n" % [mins, mins / 60.0]
	else:
		text += "TRAJECTORY: ESCAPE HYPERBOLA\n"
		
	info_label.text = text
