class_name SunController
extends Node3D
## Controls the solar directional light, HDR sun glare billboard, and dynamic eclipse calculations.

@export var sun_direction: Vector3 = Vector3(0.707, 0.35, 0.612):
	set(val):
		sun_direction = val.normalized() if val.length_squared() > 0.0001 else Vector3.UP
		_update_sun_transform()

@export var sun_color: Color = Color(1.0, 0.98, 0.92, 1.0):
	set(val):
		sun_color = val
		_update_materials()

@export var sun_energy: float = 2.4:
	set(val):
		sun_energy = val
		_update_light()

@export var billboard_distance: float = 10000.0
@export var billboard_size: float = 800.0
@export var quality_tier: int = 1:
	set(val):
		quality_tier = clampi(val, 0, 1)
		_update_materials()

@export var flare_material: ShaderMaterial
@export var directional_light: DirectionalLight3D
@export var glare_mesh_instance: MeshInstance3D

## Optional occluders for eclipse calculations.
## Array of dictionaries or Node3D objects: { "node": Node3D, "radius": float }
var occluders: Array[Dictionary] = []

var current_eclipse_factor: float = 1.0

func _ready() -> void:
	if not directional_light:
		directional_light = get_node_or_null("DirectionalLight3D")
	if not glare_mesh_instance:
		glare_mesh_instance = get_node_or_null("SunGlareBillboard")
	if not flare_material and glare_mesh_instance and glare_mesh_instance.material_override is ShaderMaterial:
		flare_material = glare_mesh_instance.material_override
	
	_update_sun_transform()
	_update_light()
	_update_materials()

func set_sun_direction(dir: Vector3) -> void:
	sun_direction = dir

func set_quality_tier(tier: int) -> void:
	quality_tier = tier

func add_occluder(node: Node3D, radius_m: float) -> void:
	occluders.append({
		"node": node,
		"radius": radius_m
	})

func clear_occluders() -> void:
	occluders.clear()

func _process(_delta: float) -> void:
	_calculate_eclipse()
	_update_billboard_position()

func _update_sun_transform() -> void:
	if directional_light:
		# DirectionalLight3D shines along -Z in local space
		# Orient light so -Z points towards sun_direction
		var target = -sun_direction
		var up = Vector3.UP if abs(target.y) < 0.99 else Vector3.RIGHT
		directional_light.look_at(directional_light.global_position + target, up)

func _update_light() -> void:
	if directional_light:
		directional_light.light_color = sun_color
		directional_light.light_energy = sun_energy * current_eclipse_factor

func _update_materials() -> void:
	if flare_material:
		flare_material.set_shader_parameter("sun_color", sun_color)
		flare_material.set_shader_parameter("quality_tier", quality_tier)
		flare_material.set_shader_parameter("eclipse_factor", current_eclipse_factor)

func _update_billboard_position() -> void:
	var cam = get_viewport().get_camera_3d() if get_viewport() else null
	var cam_pos = cam.global_position if cam else global_position
	
	if glare_mesh_instance:
		glare_mesh_instance.global_position = cam_pos + sun_direction * billboard_distance

func _calculate_eclipse() -> void:
	if occluders.is_empty():
		current_eclipse_factor = 1.0
		_update_eclipse_state()
		return

	var cam = get_viewport().get_camera_3d() if get_viewport() else null
	if not cam:
		current_eclipse_factor = 1.0
		_update_eclipse_state()
		return

	var cam_pos: Vector3 = cam.global_position
	var ray_dir: Vector3 = sun_direction
	var min_factor: float = 1.0

	for occluder in occluders:
		var node: Node3D = occluder.get("node")
		if not is_instance_valid(node):
			continue
		var radius: float = float(occluder.get("radius", 0.0))
		if radius <= 0.0:
			continue

		var to_body: Vector3 = node.global_position - cam_pos
		var dist_along_ray: float = to_body.dot(ray_dir)

		# Only occludes if body is in front of the camera towards the sun
		if dist_along_ray > 0.0:
			var d_sq: float = to_body.length_squared() - (dist_along_ray * dist_along_ray)
			var body_dist: float = to_body.length()
			if body_dist > 0.0:
				var body_ang_rad: float = asin(clampf(radius / body_dist, 0.0, 1.0))
				var sun_ang_rad: float = 0.0093 # ~0.53 deg solar disk angular radius
				var perp_dist: float = sqrt(maxf(0.0, d_sq))
				var sep_angle: float = atan2(perp_dist, dist_along_ray)

				if sep_angle >= body_ang_rad + sun_ang_rad:
					# No occlusion
					pass
				elif sep_angle <= maxf(0.0, body_ang_rad - sun_ang_rad):
					# Total eclipse
					min_factor = 0.0
					break
				else:
					# Partial eclipse: smoothstep between total and none
					var overlap_t: float = (sep_angle - (body_ang_rad - sun_ang_rad)) / (2.0 * sun_ang_rad)
					var factor: float = clampf(overlap_t, 0.0, 1.0)
					if factor < min_factor:
						min_factor = factor

	current_eclipse_factor = min_factor
	_update_eclipse_state()

func _update_eclipse_state() -> void:
	if flare_material:
		flare_material.set_shader_parameter("eclipse_factor", current_eclipse_factor)
	if directional_light:
		directional_light.light_energy = sun_energy * current_eclipse_factor
