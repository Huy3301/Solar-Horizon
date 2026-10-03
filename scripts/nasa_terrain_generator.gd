extends Node3D
class_name NASATerrainGenerator

@export_group("Planetary Body Configuration")
@export var planet_name: String = "Earth"
@export var base_radius_m: float = 6371000.0
@export var max_elevation_m: float = 8848.0
@export var min_elevation_m: float = -11034.0

@export_group("LOD & Mesh Settings")
@export var max_lod_levels: int = 5
@export var chunk_resolution: int = 16
@export var player_camera_path: NodePath
@export var heightmap_texture: Texture2D

var player_node: Node3D
var chunk_meshes: Array[MeshInstance3D] = []

const FACE_NORMALS: Array[Vector3] = [
	Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK
]

func _ready() -> void:
	if not player_camera_path.is_empty():
		player_node = get_node_or_null(player_camera_path)
		
	var body_data: Dictionary = SolarSystemData.get_body_data(planet_name)
	if not body_data.is_empty():
		base_radius_m = body_data.get("radius", base_radius_m)
		
	_generate_base_sphere()

func _generate_base_sphere() -> void:
	for face_idx in range(6):
		var face_normal: Vector3 = FACE_NORMALS[face_idx]
		var mesh_inst: MeshInstance3D = _create_face_chunk(face_normal, chunk_resolution)
		add_child(mesh_inst)
		chunk_meshes.append(mesh_inst)

func _create_face_chunk(normal: Vector3, resolution: int) -> MeshInstance3D:
	var axis_a: Vector3 = Vector3(normal.y, normal.z, normal.x)
	var axis_b: Vector3 = normal.cross(axis_a)
	
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for y in range(resolution):
		for x in range(resolution):
			var percent_x: float = float(x) / float(resolution - 1)
			var percent_y: float = float(y) / float(resolution - 1)
			
			var point_on_cube: Vector3 = normal + (percent_x - 0.5) * 2.0 * axis_a + (percent_y - 0.5) * 2.0 * axis_b
			var unit_sphere_point: Vector3 = point_on_cube.normalized()
			
			var lat_lon: Vector2 = _cartesian_to_lat_lon(unit_sphere_point)
			var elevation: float = sample_nasa_elevation(lat_lon.x, lat_lon.y)
			
			var final_pos: Vector3 = unit_sphere_point * (base_radius_m + elevation)
			var uv_coord: Vector2 = Vector2((lat_lon.y + 180.0) / 360.0, (lat_lon.x + 90.0) / 180.0)
			
			surface_tool.set_uv(uv_coord)
			surface_tool.set_normal(unit_sphere_point)
			surface_tool.add_vertex(final_pos)
			
	for y in range(resolution - 1):
		for x in range(resolution - 1):
			var idx_0: int = x + y * resolution
			var idx_1: int = (x + 1) + y * resolution
			var idx_2: int = x + (y + 1) * resolution
			var idx_3: int = (x + 1) + (y + 1) * resolution
			
			surface_tool.add_index(idx_0)
			surface_tool.add_index(idx_2)
			surface_tool.add_index(idx_1)
			
			surface_tool.add_index(idx_1)
			surface_tool.add_index(idx_2)
			surface_tool.add_index(idx_3)
			
	surface_tool.generate_normals()
	var array_mesh: ArrayMesh = surface_tool.commit()
	
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.roughness = 0.9
	mat.albedo_color = Color(0.4, 0.45, 0.5)
	mesh_instance.material_override = mat
	
	return mesh_instance

func _cartesian_to_lat_lon(p: Vector3) -> Vector2:
	var lat_deg: float = rad_to_deg(asin(clamp(p.y, -1.0, 1.0)))
	var lon_deg: float = rad_to_deg(atan2(p.x, p.z))
	return Vector2(lat_deg, lon_deg)

func sample_nasa_elevation(lat_deg: float, lon_deg: float) -> float:
	if heightmap_texture:
		var img: Image = heightmap_texture.get_image()
		if img:
			var u: float = clamp((lon_deg + 180.0) / 360.0, 0.0, 1.0)
			var v: float = clamp((90.0 - lat_deg) / 180.0, 0.0, 1.0)
			var pixel_x: int = int(u * float(img.get_width() - 1))
			var pixel_y: int = int(v * float(img.get_height() - 1))
			var col: Color = img.get_pixel(pixel_x, pixel_y)
			return lerp(min_elevation_m, max_elevation_m, col.r)
			
	var phi: float = deg_to_rad(lat_deg)
	var lambda: float = deg_to_rad(lon_deg)
	var elevation: float = sin(lambda * 2.0) * cos(phi) * 1200.0 + cos(lambda * 3.0 + 1.2) * 800.0
	elevation += sin(phi * 8.0) * sin(lambda * 8.0) * 1400.0
	return elevation
