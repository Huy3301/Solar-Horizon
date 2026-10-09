extends Node
## Acts as a skybox coordinate provider for nearby stars.

var galaxy_generator: GalaxyGenerator
var scan_radius_sectors: int = 10
var current_sector: Vector3i = Vector3i.ZERO
var sector_size_ly: float = 1.0

# Cache of nearby stars: array of Dict { "sector": Vector3i, "seed": int, "class": StarClass, "luminosity": float, "relative_pos": Vector3 }
var nearby_stars: Array[Dictionary] = []

var _cached_systems: Dictionary = {}

func _ready() -> void:
	if galaxy_generator == null:
		galaxy_generator = GalaxyGenerator.new(123456789)
	_update_catalog()

func set_seed(p_seed: int) -> void:
	_cached_systems.clear()
	if galaxy_generator == null:
		galaxy_generator = GalaxyGenerator.new(p_seed)
	else:
		galaxy_generator.seed = p_seed
	_update_catalog()

func update_current_sector(sector: Vector3i) -> void:
	if current_sector != sector:
		current_sector = sector
		_update_catalog()

## Analytically derives star class directly from seed or sector without instantiating StarSystemGenerator.
func get_star_class(seed_or_sector: Variant) -> int:
	var s: int = _resolve_seed(seed_or_sector)
	var h: int = _hash_seed(s)
	var roll: float = float(h & 0xFFFFFFFF) / 4294967296.0
	if roll < 0.00003:
		return StarSystemGenerator.StarClass.O
	elif roll < 0.0013:
		return StarSystemGenerator.StarClass.B
	elif roll < 0.0073:
		return StarSystemGenerator.StarClass.A
	elif roll < 0.0373:
		return StarSystemGenerator.StarClass.F
	elif roll < 0.1133:
		return StarSystemGenerator.StarClass.G
	elif roll < 0.2343:
		return StarSystemGenerator.StarClass.K
	return StarSystemGenerator.StarClass.M

## Analytically derives star luminosity directly from seed or sector without instantiating StarSystemGenerator.
func get_star_luminosity(seed_or_sector: Variant) -> float:
	var s: int = _resolve_seed(seed_or_sector)
	var h: int = _hash_seed(s)
	var roll: float = float(h & 0xFFFFFFFF) / 4294967296.0
	var h2: int = (h ^ 0x5DEECE66D) * 3266489909 & 0x7FFFFFFFFFFFFFFF
	var frac: float = float((h2 >> 16) & 0xFFFFFFFF) / 4294967296.0
	
	if roll < 0.00003:
		return lerpf(30000.0, 1000000.0, frac)
	elif roll < 0.0013:
		return lerpf(25.0, 30000.0, frac)
	elif roll < 0.0073:
		return lerpf(5.0, 25.0, frac)
	elif roll < 0.0373:
		return lerpf(1.5, 5.0, frac)
	elif roll < 0.1133:
		return lerpf(0.6, 1.5, frac)
	elif roll < 0.2343:
		return lerpf(0.08, 0.6, frac)
	else:
		return lerpf(0.0001, 0.08, frac)

func _resolve_seed(seed_or_sector: Variant) -> int:
	if seed_or_sector is Vector3i:
		return galaxy_generator.get_star_seed(seed_or_sector) if galaxy_generator else 0
	return int(seed_or_sector)

func _hash_seed(seed_val: int) -> int:
	var h: int = seed_val ^ 0x6C62272E07BB0142
	h = (h ^ (h >> 16)) * 2246822507 & 0x7FFFFFFFFFFFFFFF
	h = (h ^ (h >> 13)) * 3266489909 & 0x7FFFFFFFFFFFFFFF
	return h ^ (h >> 16)

## Lazily instantiates and caches StarSystemGenerator only when queried by player/scanner.
func query_system(sector: Vector3i) -> StarSystemGenerator:
	if _cached_systems.has(sector):
		return _cached_systems[sector]
	if galaxy_generator == null:
		return null
	var star_seed = galaxy_generator.get_star_seed(sector)
	if star_seed == 0:
		return null
	var sys = StarSystemGenerator.new(star_seed)
	_cached_systems[sector] = sys
	return sys

func get_star_system(sector: Vector3i) -> StarSystemGenerator:
	return query_system(sector)

func get_system(sector: Vector3i) -> StarSystemGenerator:
	return query_system(sector)

func _update_catalog() -> void:
	nearby_stars.clear()
	for x in range(-scan_radius_sectors, scan_radius_sectors + 1):
		for y in range(-scan_radius_sectors, scan_radius_sectors + 1):
			for z in range(-scan_radius_sectors, scan_radius_sectors + 1):
				var s = current_sector + Vector3i(x, y, z)
				var star_seed = galaxy_generator.get_star_seed(s)
				if star_seed != 0:
					nearby_stars.append({
						"sector": s,
						"seed": star_seed,
						"class": get_star_class(star_seed),
						"luminosity": get_star_luminosity(star_seed),
						"relative_pos": Vector3(s.x, s.y, s.z) * sector_size_ly
					})

## Returns a list of nearby stars for skybox rendering
func get_stars_for_skybox() -> Array[Dictionary]:
	return nearby_stars
