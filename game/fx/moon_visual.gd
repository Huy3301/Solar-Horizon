class_name MoonVisual
extends Node3D
## Self-contained, reusable Moon planetary visual presentation.
## Features procedural lunar regolith, maria basalts, crater normal relief, and Hapke surge.
## Calibrated for 1:10 scale (radius = 173,740 m).

@export var radius: float = 173740.0:
	set(val):
		radius = val
		_update_mesh_size()

@export var rotation_speed_deg_per_sec: float = 0.0
@export var sun_direction: Vector3 = Vector3(0.707, 0.35, 0.612):
	set(val):
		sun_direction = val.normalized() if val.length_squared() > 0.0001 else Vector3.UP
		_update_sun_direction()

@export var quality_tier: int = 1:
	set(val):
		quality_tier = clampi(val, 0, 1)
		_update_quality_tier()

@export var surface_material: ShaderMaterial

@onready var surface_mesh_node: MeshInstance3D = get_node_or_null("Surface")

var _current_rotation_rad: float = 0.0

func _ready() -> void:
	if not surface_mesh_node:
		surface_mesh_node = get_node_or_null("Surface")
	if not surface_material and surface_mesh_node and surface_mesh_node.material_override is ShaderMaterial:
		surface_material = surface_mesh_node.material_override

	_update_mesh_size()
	_update_sun_direction()
	_update_quality_tier()

func _process(delta: float) -> void:
	if rotation_speed_deg_per_sec != 0.0:
		_current_rotation_rad += deg_to_rad(rotation_speed_deg_per_sec) * delta
		if _current_rotation_rad > TAU:
			_current_rotation_rad -= TAU
		elif _current_rotation_rad < -TAU:
			_current_rotation_rad += TAU
		rotation.y = _current_rotation_rad

func set_sun_direction(dir: Vector3) -> void:
	sun_direction = dir

func set_quality_tier(tier: int) -> void:
	quality_tier = tier

func _update_sun_direction() -> void:
	if surface_material:
		surface_material.set_shader_parameter("sun_direction", sun_direction)

func _update_quality_tier() -> void:
	if surface_material:
		surface_material.set_shader_parameter("quality_tier", quality_tier)

func _update_mesh_size() -> void:
	if surface_mesh_node and surface_mesh_node.mesh is SphereMesh:
		var sm = surface_mesh_node.mesh as SphereMesh
		sm.radius = radius
		sm.height = radius * 2.0
