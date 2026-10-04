class_name OrbitMap extends Control

## 2D Orbital Map with Ap/Pe markers, trajectory rendering, and keyboard/gamepad navigation.
## Integrates directly with TrajectoryRenderer and OrbitalMechanics.

signal map_closed()

@export var center_body_name: String = "Earth"
@export var zoom_level: float = 1e-6
@export var min_zoom: float = 1e-8
@export var max_zoom: float = 1e-4
@export var pan_offset: Vector2 = Vector2.ZERO

var orbit_elements: OrbitalMechanics.OrbitElements = null
var trajectory_renderer: TrajectoryRenderer = null
var vessel_node: Node3D = null
var maneuver_node = null

var _cached_ap_text: String = ""
var _cached_pe_text: String = ""

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	_resolve_trajectory_renderer()

func _resolve_trajectory_renderer() -> void:
	if not is_inside_tree():
		return
	var tree = get_tree()
	if tree:
		trajectory_renderer = tree.get_first_node_in_group("trajectory_renderer") as TrajectoryRenderer
		if not trajectory_renderer:
			var candidate = tree.root.find_child("TrajectoryRenderer", true, false)
			if candidate is TrajectoryRenderer:
				trajectory_renderer = candidate

func set_trajectory_renderer(tr: TrajectoryRenderer) -> void:
	trajectory_renderer = tr

func set_orbit(elements: OrbitalMechanics.OrbitElements) -> void:
	orbit_elements = elements
	queue_redraw()

func set_vessel(vessel: Node3D) -> void:
	vessel_node = vessel

func _process(delta: float) -> void:
	if not visible:
		return
		
	# Gamepad / Keyboard navigation
	var pan_x = Input.get_axis("ui_left", "ui_right")
	var pan_y = Input.get_axis("ui_up", "ui_down")
	if abs(pan_x) > 0.1 or abs(pan_y) > 0.1:
		pan_offset += Vector2(-pan_x, -pan_y) * 400.0 * delta
		
	# Zoom inputs
	if Input.is_action_pressed("throttle_up"):
		zoom_in(delta * 2.0)
	elif Input.is_action_pressed("throttle_down"):
		zoom_out(delta * 2.0)
		
	# Update orbit from TrajectoryRenderer if attached
	if trajectory_renderer and "current_orbit" in trajectory_renderer:
		orbit_elements = trajectory_renderer.current_orbit
		
	queue_redraw()

func zoom_in(factor: float = 0.2) -> void:
	zoom_level = clamp(zoom_level * (1.0 + factor), min_zoom, max_zoom)
	queue_redraw()

func zoom_out(factor: float = 0.2) -> void:
	zoom_level = clamp(zoom_level / (1.0 + factor), min_zoom, max_zoom)
	queue_redraw()

func reset_view() -> void:
	pan_offset = Vector2.ZERO
	zoom_level = 1e-6
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		pan_offset += event.relative
		queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("toggle_map") or event.is_action_pressed("ui_cancel"):
		visible = false
		map_closed.emit()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	var center = size * 0.5 + pan_offset
	
	# Draw Celestial Body
	var body_radius_px = 63710.0 * zoom_level # Approx scaled Earth radius
	body_radius_px = max(12.0, body_radius_px)
	draw_circle(center, body_radius_px, Color(0.2, 0.45, 0.85, 0.9))
	draw_arc(center, body_radius_px, 0, TAU, 32, Color(0.4, 0.7, 1.0), 2.0)
	
	# Draw Orbit Path
	if orbit_elements and orbit_elements.semi_major_axis > 0:
		var pts = OrbitalMechanics.sample_orbit_points(orbit_elements, 96)
		var points_2d = PackedVector2Array()
		for p in pts:
			# Map X/Z orbital plane to 2D
			var p2 = Vector2(p.x, p.z) * zoom_level + center
			points_2d.append(p2)
		
		if points_2d.size() > 2:
			var orbit_col = Color(0.2, 0.8, 1.0, 0.8)
			if orbit_elements.periapsis_alt < 85000.0:
				orbit_col = Color(1.0, 0.4, 0.2, 0.8)
			draw_polyline(points_2d, orbit_col, 2.0, orbit_elements.is_closed_orbit)
			
		# Draw Apoapsis (Ap) Marker
		if orbit_elements.is_closed_orbit and orbit_elements.apoapsis_radius > 0:
			var ap_dir = -orbit_elements.e_vector.normalized()
			var ap_vec = Vector2(ap_dir.x, ap_dir.z) * orbit_elements.apoapsis_radius * zoom_level + center
			draw_circle(ap_vec, 6.0, Color(0.3, 0.9, 1.0))
			var ap_text = "Ap: %5.1f km" % (orbit_elements.apoapsis_alt / 1000.0)
			draw_string(ThemeDB.fallback_font, ap_vec + Vector2(10, 4), ap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 0.9, 1.0))

		# Draw Periapsis (Pe) Marker
		if orbit_elements.periapsis_radius > 0:
			var pe_dir = orbit_elements.e_vector.normalized()
			var pe_vec = Vector2(pe_dir.x, pe_dir.z) * orbit_elements.periapsis_radius * zoom_level + center
			var pe_km = orbit_elements.periapsis_alt / 1000.0
			var pe_color = Color.RED if pe_km < 85.0 else Color(1.0, 0.85, 0.2)
			draw_circle(pe_vec, 6.0, pe_color)
			var pe_text = "Pe: %5.1f km" % pe_km
			draw_string(ThemeDB.fallback_font, pe_vec + Vector2(10, 4), pe_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, pe_color)

	# Draw Vessel Marker
	if vessel_node and is_instance_valid(vessel_node):
		var vpos = vessel_node.global_position
		var v2 = Vector2(vpos.x, vpos.z) * zoom_level + center
		draw_circle(v2, 5.0, Color.YELLOW)
		draw_string(ThemeDB.fallback_font, v2 + Vector2(8, -8), "VESSEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.YELLOW)
