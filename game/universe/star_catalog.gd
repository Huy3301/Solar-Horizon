extends Node
## Acts as a skybox coordinate provider for nearby stars.

var galaxy_generator: GalaxyGenerator
var scan_radius_sectors: int = 10
var current_sector: Vector3i = Vector3i.ZERO
var sector_size_ly: float = 1.0

# Cache of nearby stars: array of Dict { "sector": Vector3i, "seed": int, "class": StarClass, "luminosity": float, "relative_pos": Vector3 }
var nearby_stars: Array[Dictionary] = []

func _ready() -> void:
	if galaxy_generator == null:
		galaxy_generator = GalaxyGenerator.new(123456789)
	_update_catalog()

func set_seed(p_seed: int) -> void:
	if galaxy_generator == null:
		galaxy_generator = GalaxyGenerator.new(p_seed)
	else:
		galaxy_generator.seed = p_seed
	_update_catalog()

func update_current_sector(sector: Vector3i) -> void:
	if current_sector != sector:
		current_sector = sector
		_update_catalog()

func _update_catalog() -> void:
	nearby_stars.clear()
	for x in range(-scan_radius_sectors, scan_radius_sectors + 1):
		for y in range(-scan_radius_sectors, scan_radius_sectors + 1):
			for z in range(-scan_radius_sectors, scan_radius_sectors + 1):
				var s = current_sector + Vector3i(x, y, z)
				var star_seed = galaxy_generator.get_star_seed(s)
				if star_seed != 0:
					var sys = StarSystemGenerator.new(star_seed)
					nearby_stars.append({
						"sector": s,
						"seed": star_seed,
						"class": sys.star_class,
						"luminosity": sys.luminosity,
						"relative_pos": Vector3(s.x, s.y, s.z) * sector_size_ly
					})

## Returns a list of nearby stars for skybox rendering
func get_stars_for_skybox() -> Array[Dictionary]:
	return nearby_stars
