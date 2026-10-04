class_name ShipVFX
extends Node3D

## Ship VFX Controller (WP 3.6)
## Manages atmospheric expansion and shock diamonds on engine plumes,
## RCS thruster puff bursts at sockets, and atmospheric re-entry plasma/heat glow.

const RCS_PUFF_SHADER = preload("res://shaders/fx/rcs_puff.gdshader")
const REENTRY_PLASMA_SHADER = preload("res://shaders/fx/reentry_plasma.gdshader")

@export var ship_node: RigidBody3D = null
@export var expansion_factor: float = 1.0
@export var reentry_threshold: float = 16000.0  ## Dynamic pressure (q) * Mach for peak plasma glow
@export var heat_rise_speed: float = 1.6        ## Thermal heating rise rate
@export var heat_cool_speed: float = 0.55       ## Thermal dissipation cooling rate
@export var rcs_puff_duration: float = 0.18     ## RCS puff burst duration (seconds)

var current_reentry_heat: float = 0.0
var target_reentry_heat: float = 0.0
var current_atmosphere_density: float = 0.0
var current_throttle: float = 0.0

var left_plume: MeshInstance3D = null
var right_plume: MeshInstance3D = null
var reentry_sheath: MeshInstance3D = null

var rcs_nodes: Dictionary = {}         ## socket_name -> MeshInstance3D
var rcs_active_timers: Dictionary = {}  ## socket_name -> float remaining time
var rcs_intensities: Dictionary = {}    ## socket_name -> float intensity

var _initialized: bool = false

const RCS_SOCKET_NAMES: Array[String] = [
	"SOCKET_rcs_nose_pitch_up",
	"SOCKET_rcs_nose_pitch_down",
	"SOCKET_rcs_nose_yaw_port",
	"SOCKET_rcs_nose_yaw_stbd",
	"SOCKET_rcs_tail_port",
	"SOCKET_rcs_tail_stbd",
	"SOCKET_rcs_tail_up"
]

func _ready() -> void:
	ensure_initialized()
	if ship_node and ship_node.has_signal("flight_data_updated"):
		if not ship_node.flight_data_updated.is_connected(_on_flight_data_updated):
			ship_node.flight_data_updated.connect(_on_flight_data_updated)

func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	
	if ship_node == null:
		if get_parent() is RigidBody3D:
			ship_node = get_parent() as RigidBody3D
		elif has_node("..") and get_node("..") is RigidBody3D:
			ship_node = get_node("..") as RigidBody3D
			
	_setup_plumes()
	_setup_rcs_sockets()
	_setup_reentry_sheath()
	_update_plume_shaders()

func _setup_plumes() -> void:
	if ship_node:
		left_plume = ship_node.get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_L/LeftEnginePlume") as MeshInstance3D
		if left_plume == null:
			left_plume = ship_node.get_node_or_null("VisualModel/LeftEnginePlume") as MeshInstance3D
			
		right_plume = ship_node.get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_R/RightEnginePlume") as MeshInstance3D
		if right_plume == null:
			right_plume = ship_node.get_node_or_null("VisualModel/RightEnginePlume") as MeshInstance3D
	else:
		left_plume = get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_L/LeftEnginePlume") as MeshInstance3D
		right_plume = get_node_or_null("VisualModel/OrbiterModel/SOCKET_engine_R/RightEnginePlume") as MeshInstance3D
		
	# Duplicate plume material for per-instance parameter variation
	_make_unique_plume_material(left_plume)
	_make_unique_plume_material(right_plume)

func _make_unique_plume_material(plume: MeshInstance3D) -> void:
	if plume:
		if plume.material_override and plume.material_override is ShaderMaterial:
			plume.material_override = plume.material_override.duplicate()
		elif plume.mesh and plume.mesh.material is ShaderMaterial:
			plume.material_override = plume.mesh.material.duplicate()

func _setup_rcs_sockets() -> void:
	var orbiter_node: Node = null
	if ship_node:
		orbiter_node = ship_node.get_node_or_null("VisualModel/OrbiterModel")
	if orbiter_node == null:
		orbiter_node = get_node_or_null("VisualModel/OrbiterModel")
		
	for socket_name in RCS_SOCKET_NAMES:
		rcs_active_timers[socket_name] = 0.0
		rcs_intensities[socket_name] = 0.0
		
		var socket: Node3D = null
		if orbiter_node:
			socket = orbiter_node.get_node_or_null(socket_name) as Node3D
			
		if socket:
			var existing_puff = socket.get_node_or_null("RCSPuff") as MeshInstance3D
			if existing_puff:
				rcs_nodes[socket_name] = existing_puff
				existing_puff.visible = false
			else:
				var new_puff = _create_rcs_puff_mesh(socket_name)
				socket.add_child(new_puff)
				rcs_nodes[socket_name] = new_puff
				new_puff.visible = false

func _create_rcs_puff_mesh(socket_name: String) -> MeshInstance3D:
	var puff = MeshInstance3D.new()
	puff.name = "RCSPuff"
	
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.22
	mesh.bottom_radius = 0.03
	mesh.height = 0.75
	mesh.radial_segments = 12
	mesh.rings = 4
	puff.mesh = mesh
	
	var mat = ShaderMaterial.new()
	mat.shader = RCS_PUFF_SHADER
	mat.set_shader_parameter("puff_intensity", 2.2)
	puff.material_override = mat
	
	# Position and orientation based on thruster socket direction
	puff.position = Vector3(0, 0.375, 0)
	
	if socket_name.ends_with("nose_pitch_down"):
		puff.rotation_degrees = Vector3(180, 0, 0)
		puff.position = Vector3(0, -0.375, 0)
	elif socket_name.ends_with("yaw_port") or socket_name.ends_with("tail_port"):
		puff.rotation_degrees = Vector3(0, 0, 90)
		puff.position = Vector3(-0.375, 0, 0)
	elif socket_name.ends_with("yaw_stbd") or socket_name.ends_with("tail_stbd"):
		puff.rotation_degrees = Vector3(0, 0, -90)
		puff.position = Vector3(0.375, 0, 0)
	elif socket_name.ends_with("tail_up") or socket_name.ends_with("nose_pitch_up"):
		puff.rotation_degrees = Vector3(0, 0, 0)
		puff.position = Vector3(0, 0.375, 0)
		
	return puff

func _setup_reentry_sheath() -> void:
	if ship_node:
		reentry_sheath = ship_node.get_node_or_null("VisualModel/ReentrySheath") as MeshInstance3D
		if reentry_sheath == null:
			var visual_model = ship_node.get_node_or_null("VisualModel")
			if visual_model:
				reentry_sheath = _create_reentry_sheath_mesh()
				visual_model.add_child(reentry_sheath)
	else:
		reentry_sheath = get_node_or_null("VisualModel/ReentrySheath") as MeshInstance3D
		if reentry_sheath == null:
			var visual_model = get_node_or_null("VisualModel")
			if visual_model:
				reentry_sheath = _create_reentry_sheath_mesh()
				visual_model.add_child(reentry_sheath)
				
	if reentry_sheath:
		reentry_sheath.visible = false

func _create_reentry_sheath_mesh() -> MeshInstance3D:
	var sheath = MeshInstance3D.new()
	sheath.name = "ReentrySheath"
	
	var box = BoxMesh.new()
	box.size = Vector3(14.2, 1.6, 14.8)
	sheath.mesh = box
	sheath.transform.origin = Vector3(0.0, -0.35, 0.5)
	
	var mat = ShaderMaterial.new()
	mat.shader = REENTRY_PLASMA_SHADER
	mat.set_shader_parameter("heat_intensity", 0.0)
	sheath.material_override = mat
	sheath.visible = false
	return sheath

func _on_flight_data_updated(telemetry: Dictionary) -> void:
	ensure_initialized()
	var q: float = telemetry.get("dynamic_pressure_pa", 0.0)
	var mach: float = telemetry.get("mach", 0.0)
	var air_density: float = telemetry.get("air_density", 0.0)
	var throttle_pct: float = telemetry.get("throttle_pct", 0.0)
	
	set_reentry_parameters(q, mach)
	set_atmosphere_density(air_density / 1.225)
	set_throttle(clamp(throttle_pct / 100.0, 0.0, 1.0))

func set_reentry_parameters(dynamic_pressure_pa: float, mach: float) -> void:
	ensure_initialized()
	var q_mach = dynamic_pressure_pa * mach
	target_reentry_heat = clamp(q_mach / max(1.0, reentry_threshold), 0.0, 1.0)

func set_atmosphere_density(density: float) -> void:
	ensure_initialized()
	current_atmosphere_density = clamp(density, 0.0, 2.0)
	_update_plume_shaders()

func set_throttle(throttle: float) -> void:
	ensure_initialized()
	current_throttle = clamp(throttle, 0.0, 1.0)
	if ship_node and "current_throttle" in ship_node:
		ship_node.set("current_throttle", current_throttle)
	_update_plume_shaders()

func trigger_rcs_puff(socket_name: String, intensity: float = 1.0) -> void:
	ensure_initialized()
	rcs_active_timers[socket_name] = rcs_puff_duration
	rcs_intensities[socket_name] = clamp(intensity, 0.1, 1.0)
	if rcs_nodes.has(socket_name):
		var puff = rcs_nodes[socket_name] as MeshInstance3D
		if puff:
			puff.visible = true

func _process(delta: float) -> void:
	ensure_initialized()
	_update_flight_control_inputs()
	_update_reentry_heat(delta)
	_update_rcs_puffs(delta)
	_update_plume_shaders()

func _update_flight_control_inputs() -> void:
	if ship_node == null:
		return
		
	# Detect flight controller inputs
	var pitch: float = 0.0
	var yaw: float = 0.0
	var roll: float = 0.0
	var vtol: float = 0.0
	
	if "control_pitch" in ship_node:
		pitch = ship_node.get("control_pitch")
	if "control_yaw" in ship_node:
		yaw = ship_node.get("control_yaw")
	if "control_roll" in ship_node:
		roll = ship_node.get("control_roll")
	if "control_vtol" in ship_node:
		vtol = ship_node.get("control_vtol")
	if "current_throttle" in ship_node:
		var ship_thr = ship_node.get("current_throttle")
		if ship_thr != null:
			current_throttle = clamp(float(ship_thr), 0.0, 1.0)
		
	# Wire translation/rotation to RCS sockets
	if pitch > 0.05:
		trigger_rcs_puff("SOCKET_rcs_nose_pitch_up", abs(pitch))
	elif pitch < -0.05:
		trigger_rcs_puff("SOCKET_rcs_nose_pitch_down", abs(pitch))
		
	if yaw > 0.05:
		trigger_rcs_puff("SOCKET_rcs_nose_yaw_port", abs(yaw))
		trigger_rcs_puff("SOCKET_rcs_tail_stbd", abs(yaw))
	elif yaw < -0.05:
		trigger_rcs_puff("SOCKET_rcs_nose_yaw_stbd", abs(yaw))
		trigger_rcs_puff("SOCKET_rcs_tail_port", abs(yaw))
		
	if roll > 0.05:
		trigger_rcs_puff("SOCKET_rcs_tail_stbd", abs(roll))
	elif roll < -0.05:
		trigger_rcs_puff("SOCKET_rcs_tail_port", abs(roll))
		
	if vtol > 0.05:
		trigger_rcs_puff("SOCKET_rcs_tail_up", vtol)
		trigger_rcs_puff("SOCKET_rcs_nose_pitch_up", vtol * 0.7)

func _update_reentry_heat(delta: float) -> void:
	# Smoothly heat up and cool down with thermal inertia
	if target_reentry_heat > current_reentry_heat:
		current_reentry_heat = move_toward(current_reentry_heat, target_reentry_heat, delta * heat_rise_speed)
	else:
		current_reentry_heat = move_toward(current_reentry_heat, target_reentry_heat, delta * heat_cool_speed)
		
	if reentry_sheath:
		if current_reentry_heat > 0.005:
			reentry_sheath.visible = true
			var mat = reentry_sheath.material_override as ShaderMaterial
			if mat:
				mat.set_shader_parameter("heat_intensity", current_reentry_heat)
		else:
			reentry_sheath.visible = false

func _update_rcs_puffs(delta: float) -> void:
	for socket_name in rcs_active_timers.keys():
		var timer: float = rcs_active_timers[socket_name]
		if timer > 0.0:
			timer = max(0.0, timer - delta)
			rcs_active_timers[socket_name] = timer
			
			if rcs_nodes.has(socket_name):
				var puff = rcs_nodes[socket_name] as MeshInstance3D
				if puff:
					puff.visible = true
					var progress = 1.0 - (timer / rcs_puff_duration)
					var mat = puff.material_override as ShaderMaterial
					if mat:
						mat.set_shader_parameter("burst_progress", progress)
						mat.set_shader_parameter("puff_intensity", rcs_intensities[socket_name] * 2.2)
		else:
			if rcs_nodes.has(socket_name):
				var puff = rcs_nodes[socket_name] as MeshInstance3D
				if puff and puff.visible:
					puff.visible = false

func _update_plume_shaders() -> void:
	_apply_plume_uniforms(left_plume)
	_apply_plume_uniforms(right_plume)

func _apply_plume_uniforms(plume: MeshInstance3D) -> void:
	if plume == null:
		return
	var mat = plume.material_override as ShaderMaterial
	if mat == null and plume.mesh and plume.mesh.material is ShaderMaterial:
		mat = plume.mesh.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("atmosphere_density", current_atmosphere_density)
		mat.set_shader_parameter("expansion_factor", expansion_factor)
		mat.set_shader_parameter("thrust_intensity", current_throttle)

func get_reentry_heat() -> float:
	ensure_initialized()
	return current_reentry_heat

func get_rcs_active(socket_name: String) -> bool:
	ensure_initialized()
	return rcs_active_timers.get(socket_name, 0.0) > 0.0

func get_atmosphere_density() -> float:
	ensure_initialized()
	return current_atmosphere_density
