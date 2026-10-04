extends Node3D
class_name TrajectoryRenderer

@export var vessel_path: NodePath
@export var parent_body_name: String = "Earth"
@export var is_visible_in_flight: bool = true
@export var trajectory_line_color: Color = Color(0.15, 0.75, 1.0, 0.9)
@export var atmospheric_entry_color: Color = Color(1.0, 0.25, 0.15, 0.95)
@export var vector_prograde_color: Color = Color(0.2, 1.0, 0.4, 0.85)
@export var vector_retrograde_color: Color = Color(1.0, 0.3, 0.3, 0.85)

var vessel: Node3D
var mesh_instance: MeshInstance3D
var immediate_mesh: ImmediateMesh
var line_material: StandardMaterial3D

var current_orbit: OrbitalMechanics.OrbitElements
var celestial_center: Vector3 = Vector3.ZERO
var body_radius: float = 6371000.0
var body_mu: float = 3.986004418e14

var ap_marker: Label3D
var pe_marker: Label3D

func _ready() -> void:
	if not vessel_path.is_empty():
		vessel = get_node_or_null(vessel_path)
		
	var body_data: Dictionary = SolarSystemData.get_body_data(parent_body_name)
	if not body_data.is_empty():
		body_radius = body_data.get("radius", 6371000.0)
		body_mu = body_data.get("mu", 3.986004418e14)
		
	_setup_rendering_nodes()

func _setup_rendering_nodes() -> void:
	mesh_instance = MeshInstance3D.new()
	immediate_mesh = ImmediateMesh.new()
	mesh_instance.mesh = immediate_mesh
	
	line_material = StandardMaterial3D.new()
	line_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = line_material
	add_child(mesh_instance)
	
	ap_marker = Label3D.new()
	ap_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ap_marker.modulate = Color(0.3, 0.9, 1.0)
	ap_marker.font_size = 28
	ap_marker.outline_size = 6
	ap_marker.visible = false
	add_child(ap_marker)
	
	pe_marker = Label3D.new()
	pe_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pe_marker.modulate = Color(1.0, 0.8, 0.2)
	pe_marker.font_size = 28
	pe_marker.outline_size = 6
	pe_marker.visible = false
	add_child(pe_marker)

func _process(_delta: float) -> void:
	if not is_visible_in_flight or not is_instance_valid(vessel):
		if mesh_instance: mesh_instance.visible = false
		if ap_marker: ap_marker.visible = false
		if pe_marker: pe_marker.visible = false
		return
		
	mesh_instance.visible = true
	_update_and_render_orbit()

func _update_and_render_orbit() -> void:
	var ship_pos: Vector3 = vessel.global_position
	var r_vec: Vector3 = ship_pos - celestial_center
	var v_vec: Vector3 = Vector3.FORWARD
	
	if vessel is RigidBody3D:
		v_vec = (vessel as RigidBody3D).linear_velocity
	
	current_orbit = OrbitalMechanics.calculate_orbit(r_vec, v_vec, body_mu, body_radius)
	if not current_orbit or current_orbit.semi_major_axis <= 0:
		immediate_mesh.clear_surfaces()
		ap_marker.visible = false
		pe_marker.visible = false
		return
		
	var trajectory_points: PackedVector3Array = OrbitalMechanics.generate_trajectory_path(current_orbit, 96)
	if trajectory_points.size() < 2:
		return
		
	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, line_material)
	
	var has_atmospheric_entry: bool = current_orbit.periapsis_alt < 85000.0
	
	for i in range(trajectory_points.size()):
		var pt: Vector3 = trajectory_points[i] + celestial_center
		var alt: float = pt.length() - body_radius
		
		if has_atmospheric_entry and alt < 85000.0:
			immediate_mesh.surface_set_color(atmospheric_entry_color)
		else:
			var alpha: float = clamp(1.0 - float(i) / float(trajectory_points.size()) * 0.4, 0.4, 0.95)
			var col: Color = trajectory_line_color
			col.a = alpha
			immediate_mesh.surface_set_color(col)
			
		immediate_mesh.surface_add_vertex(pt)
		
	if current_orbit.is_closed_orbit and trajectory_points.size() > 0:
		immediate_mesh.surface_set_color(trajectory_line_color)
		immediate_mesh.surface_add_vertex(trajectory_points[0] + celestial_center)
		
	immediate_mesh.surface_end()
	_render_velocity_vectors(ship_pos, v_vec)
	_update_markers()

func _render_velocity_vectors(pos: Vector3, vel: Vector3) -> void:
	if vel.length() < 5.0:
		return
		
	var prograde_dir: Vector3 = vel.normalized()
	var vector_length: float = clamp(vel.length() * 0.4, 15.0, 60.0)
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	immediate_mesh.surface_set_color(vector_prograde_color)
	immediate_mesh.surface_add_vertex(pos)
	immediate_mesh.surface_add_vertex(pos + prograde_dir * vector_length)
	
	immediate_mesh.surface_set_color(vector_retrograde_color)
	immediate_mesh.surface_add_vertex(pos)
	immediate_mesh.surface_add_vertex(pos - prograde_dir * (vector_length * 0.5))
	immediate_mesh.surface_end()

func _update_markers() -> void:
	if not current_orbit:
		return
		
	if current_orbit.periapsis_radius > 0:
		var pe_dir: Vector3 = current_orbit.e_vector.normalized()
		var pe_pos: Vector3 = celestial_center + pe_dir * current_orbit.periapsis_radius
		pe_marker.global_position = pe_pos
		var pe_km: float = current_orbit.periapsis_alt / 1000.0
		pe_marker.text = "Pe: %5.1f km" % pe_km
		pe_marker.visible = true
		if pe_km < 85.0:
			pe_marker.modulate = Color.RED
		else:
			pe_marker.modulate = Color(1.0, 0.85, 0.2)
			
	if current_orbit.is_closed_orbit and current_orbit.apoapsis_radius > 0:
		var ap_dir: Vector3 = -current_orbit.e_vector.normalized()
		var ap_pos: Vector3 = celestial_center + ap_dir * current_orbit.apoapsis_radius
		ap_marker.global_position = ap_pos
		var ap_km: float = current_orbit.apoapsis_alt / 1000.0
		ap_marker.text = "Ap: %5.1f km" % ap_km
		ap_marker.visible = true
	else:
		ap_marker.visible = false

func toggle_visibility() -> void:
	is_visible_in_flight = not is_visible_in_flight

func get_current_orbit() -> OrbitalMechanics.OrbitElements:
	return current_orbit

func get_ap_position() -> Vector3:
	if ap_marker:
		return ap_marker.global_position
	return Vector3.ZERO

func get_pe_position() -> Vector3:
	if pe_marker:
		return pe_marker.global_position
	return Vector3.ZERO
