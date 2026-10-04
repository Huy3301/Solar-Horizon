class_name SkyEnvironmentVisual
extends Node3D
## Self-contained, reusable deep space sky, HDR sun glare, and WorldEnvironment node.
## Integrates procedural starfield, Milky Way, and optional StarCatalog constellation stars.

@export var sun_direction: Vector3 = Vector3(0.707, 0.35, 0.612):
	set(val):
		sun_direction = val.normalized() if val.length_squared() > 0.0001 else Vector3.UP
		_update_sun_direction()

@export var sun_energy: float = 2.4:
	set(val):
		sun_energy = val
		if sun_node:
			sun_node.sun_energy = val

@export var quality_tier: int = 1:
	set(val):
		quality_tier = clampi(val, 0, 1)
		_update_quality_tier()

@export var sky_material: ShaderMaterial
@export var star_catalog_node: Node

@onready var world_env_node: WorldEnvironment = get_node_or_null("WorldEnvironment")
@onready var sun_node: SunController = get_node_or_null("Sun")

func _ready() -> void:
	if not world_env_node:
		world_env_node = get_node_or_null("WorldEnvironment")
	if not sun_node:
		sun_node = get_node_or_null("Sun")

	if not sky_material and world_env_node and world_env_node.environment and world_env_node.environment.sky:
		if world_env_node.environment.sky.sky_material is ShaderMaterial:
			sky_material = world_env_node.environment.sky.sky_material

	if not star_catalog_node:
		star_catalog_node = get_node_or_null("/root/StarCatalog")

	_update_sun_direction()
	_update_quality_tier()
	_update_from_star_catalog()

func _process(_delta: float) -> void:
	var clock = get_node_or_null("/root/SimulationClock")
	if clock and clock.has_method("get_sun_direction"):
		var new_sun_dir: Vector3 = clock.get_sun_direction(global_position)
		if new_sun_dir.distance_squared_to(sun_direction) > 0.0001:
			sun_direction = new_sun_dir

func set_sun_direction(dir: Vector3) -> void:
	sun_direction = dir

func set_quality_tier(tier: int) -> void:
	quality_tier = tier

func _update_sun_direction() -> void:
	if sky_material:
		sky_material.set_shader_parameter("sun_direction", sun_direction)
	if sun_node:
		sun_node.set_sun_direction(sun_direction)

func _update_quality_tier() -> void:
	if sun_node:
		sun_node.set_quality_tier(quality_tier)

func _update_from_star_catalog() -> void:
	if not star_catalog_node or not star_catalog_node.has_method("get_stars_for_skybox"):
		return
	var stars: Array[Dictionary] = star_catalog_node.get_stars_for_skybox()
	if stars.is_empty() or not sky_material:
		return

	var packed := PackedVector4Array()
	var count: int = mini(stars.size(), 16)
	for i in range(count):
		var s = stars[i]
		var rel_pos: Vector3 = s.get("relative_pos", Vector3.ZERO)
		var dir = rel_pos.normalized() if rel_pos.length_squared() > 0.001 else Vector3.FORWARD
		var lum: float = float(s.get("luminosity", 1.0))
		packed.append(Vector4(dir.x, dir.y, dir.z, clampf(lum, 0.5, 3.0)))

	sky_material.set_shader_parameter("catalog_stars", packed)
	sky_material.set_shader_parameter("catalog_star_count", count)
