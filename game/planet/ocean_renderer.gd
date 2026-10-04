class_name OceanRenderer
extends Node3D
## Renders a spherical ocean mesh for a planetary body with Gerstner waves.
## Fully collision-free at sea level, supporting floating origin rebasing,
## mobile/desktop quality tiers, and solar glint direction updates.

@export var radius: float = 637100.0 # 1:10 scaled Earth radius
@export var mesh_resolution: int = 64
@export var quality_tier: int = 1
@export var sun_direction: Vector3 = Vector3(0.707, 0.35, 0.612):
	set(val):
		sun_direction = val.normalized() if val.length_squared() > 1e-4 else Vector3.UP
		_update_shader_parameters()

@export var ocean_material: Material

var _mesh_instance: MeshInstance3D

func _ready() -> void:
	if OS.has_feature("mobile"):
		quality_tier = 0
		mesh_resolution = 33
	_create_ocean_mesh()

func _create_ocean_mesh() -> void:
	if _mesh_instance:
		_mesh_instance.queue_free()
		
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "OceanMesh"
	add_child(_mesh_instance)
	
	# Create a sphere mesh at sea level
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	sphere_mesh.radial_segments = mesh_resolution
	sphere_mesh.rings = mesh_resolution / 2
	_mesh_instance.mesh = sphere_mesh
	
	if ocean_material:
		_mesh_instance.material_override = ocean_material
	else:
		var mat := ShaderMaterial.new()
		var shader := load("res://shaders/ocean/ocean_gerstner.gdshader") as Shader
		if shader:
			mat.shader = shader
		_mesh_instance.material_override = mat
		
	_update_shader_parameters()

func set_quality_tier(tier: int) -> void:
	quality_tier = clampi(tier, 0, 1)
	mesh_resolution = 33 if quality_tier == 0 else 64
	if _mesh_instance and _mesh_instance.mesh is SphereMesh:
		var sm := _mesh_instance.mesh as SphereMesh
		sm.radial_segments = mesh_resolution
		sm.rings = mesh_resolution / 2
	_update_shader_parameters()

func set_sun_direction(dir: Vector3) -> void:
	sun_direction = dir

func _update_shader_parameters() -> void:
	if _mesh_instance and _mesh_instance.material_override is ShaderMaterial:
		var mat := _mesh_instance.material_override as ShaderMaterial
		mat.set_shader_parameter("quality_tier", quality_tier)
		mat.set_shader_parameter("sun_direction", sun_direction)

## Called by the origin rebase system to shift the rendering offset.
func apply_origin_shift(shift_amount: Vector3) -> void:
	global_position += shift_amount
	if _mesh_instance and _mesh_instance.material_override is ShaderMaterial:
		var mat := _mesh_instance.material_override as ShaderMaterial
		var current_offset = mat.get_shader_parameter("origin_offset")
		if current_offset == null:
			current_offset = Vector3.ZERO
		mat.set_shader_parameter("origin_offset", current_offset + shift_amount)

## Set planet parameters that affect the ocean
func setup(ocean_radius: float, material: Material = null) -> void:
	radius = ocean_radius
	if material:
		ocean_material = material
	
	if _mesh_instance and _mesh_instance.mesh is SphereMesh:
		var sm := _mesh_instance.mesh as SphereMesh
		sm.radius = radius
		sm.height = radius * 2.0
	_update_shader_parameters()
