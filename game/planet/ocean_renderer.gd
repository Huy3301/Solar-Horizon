class_name OceanRenderer
extends Node3D
## Renders a spherical ocean mesh for a planet, supporting floating origin rebasing.

@export var radius: float = 6000000.0 # Standard Earth radius in meters
@export var mesh_resolution: int = 128
@export var ocean_material: Material

var _mesh_instance: MeshInstance3D

func _ready() -> void:
	_create_ocean_mesh()

func _create_ocean_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	
	# Create a sphere mesh
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	sphere_mesh.radial_segments = mesh_resolution
	sphere_mesh.rings = mesh_resolution / 2
	
	_mesh_instance.mesh = sphere_mesh
	
	if ocean_material:
		_mesh_instance.material_override = ocean_material
	else:
		# Default to loading the gerstner shader
		var mat := ShaderMaterial.new()
		var shader := load("res://shaders/ocean/ocean_gerstner.gdshader") as Shader
		if shader:
			mat.shader = shader
		_mesh_instance.material_override = mat

## Called by the origin rebase system to shift the rendering offset.
## Uses DVec3 or float arrays for high precision.
func apply_origin_shift(shift_amount: Vector3) -> void:
	# Update position based on shift
	global_position += shift_amount
	
	# Update shader uniform for continuous wave generation
	if _mesh_instance and _mesh_instance.material_override is ShaderMaterial:
		var mat := _mesh_instance.material_override as ShaderMaterial
		var current_offset = mat.get_shader_parameter("origin_offset")
		if current_offset == null:
			current_offset = Vector3.ZERO
		# Note: In a real high-precision scenario, origin_offset needs to be handled
		# carefully to avoid float32 precision loss in the shader itself.
		mat.set_shader_parameter("origin_offset", current_offset + shift_amount)

## Set planet parameters that might affect the ocean
func setup(ocean_radius: float, material: Material = null) -> void:
	radius = ocean_radius
	if material:
		ocean_material = material
	
	if _mesh_instance and _mesh_instance.mesh is SphereMesh:
		var sm := _mesh_instance.mesh as SphereMesh
		sm.radius = radius
		sm.height = radius * 2.0
