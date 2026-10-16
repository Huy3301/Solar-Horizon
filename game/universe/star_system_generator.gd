class_name StarSystemGenerator extends RefCounted
## Generates a star system's details from a seed.

enum StarClass { O, B, A, F, G, K, M }

var system_seed: int = 0
var rng: RandomNumberGenerator

var star_class: StarClass
var luminosity: float
var mass_solar: float
var habitable_zone_inner_au: float
var habitable_zone_outer_au: float
var planets: Array[CelestialBodyDef] = []

func _init(p_seed: int) -> void:
	system_seed = p_seed
	rng = RandomNumberGenerator.new()
	rng.seed = system_seed
	_generate_system()

func _generate_system() -> void:
	_generate_star()
	_generate_planets()

func _generate_star() -> void:
	# Simple distribution favoring M class stars (red dwarfs are common)
	var roll = rng.randf()
	if roll < 0.00003:
		star_class = StarClass.O
		mass_solar = rng.randf_range(16.0, 90.0)
		luminosity = rng.randf_range(30000.0, 1000000.0)
	elif roll < 0.0013:
		star_class = StarClass.B
		mass_solar = rng.randf_range(2.1, 16.0)
		luminosity = rng.randf_range(25.0, 30000.0)
	elif roll < 0.0073:
		star_class = StarClass.A
		mass_solar = rng.randf_range(1.4, 2.1)
		luminosity = rng.randf_range(5.0, 25.0)
	elif roll < 0.0373:
		star_class = StarClass.F
		mass_solar = rng.randf_range(1.04, 1.4)
		luminosity = rng.randf_range(1.5, 5.0)
	elif roll < 0.1133:
		star_class = StarClass.G
		mass_solar = rng.randf_range(0.8, 1.04)
		luminosity = rng.randf_range(0.6, 1.5)
	elif roll < 0.2343:
		star_class = StarClass.K
		mass_solar = rng.randf_range(0.45, 0.8)
		luminosity = rng.randf_range(0.08, 0.6)
	else:
		star_class = StarClass.M
		mass_solar = rng.randf_range(0.08, 0.45)
		luminosity = rng.randf_range(0.0001, 0.08)
	
	# Habitable zone approx based on luminosity
	# Distance ~ sqrt(L/L_sun)
	var center = sqrt(luminosity)
	habitable_zone_inner_au = center * 0.95
	habitable_zone_outer_au = center * 1.37

func _generate_planets() -> void:
	planets.clear()
	var num_planets = rng.randi_range(0, 10)
	var current_distance_au = rng.randf_range(0.1, 0.5) * mass_solar
	
	var au_in_m: float = 1.496e11
	var earth_mass_in_kg: float = 5.972e24
	
	for i in range(num_planets):
		var planet = CelestialBodyDef.new()
		planet.display_name = "Planet %d" % (i + 1)
		planet.semi_major_axis_m = current_distance_au * au_in_m
		
		# Inner planets tend to be rocky, outer tend to be gas giants
		var frost_line_au = 2.7 * sqrt(luminosity)
		
		if current_distance_au > frost_line_au and rng.randf() < 0.8:
			planet.body_type = CelestialBodyDef.BodyType.GAS_GIANT
			planet.mass_kg = rng.randf_range(10.0, 3000.0) * earth_mass_in_kg
			planet.radius_m = rng.randf_range(15000.0, 80000.0) * 1000.0
		else:
			planet.body_type = CelestialBodyDef.BodyType.PLANET
			var mass_earth = rng.randf_range(0.05, 10.0)
			planet.mass_kg = mass_earth * earth_mass_in_kg
			planet.radius_m = pow(mass_earth, 0.333) * 6371000.0
			
		planets.append(planet)
		
		current_distance_au += rng.randf_range(0.4, 2.0) * current_distance_au


## S4: Deterministic 64-bit SplitMix64 spectral class selector (fixes all-M-star bug).
const S4_SPECTRAL_CLASSES: Array[String] = ["O", "B", "A", "F", "G", "K", "M"]


static func splitmix64_hash(seed_value: int, salt: int) -> int:
	var z: int = seed_value + salt + 0x6A09E667F3BCC909
	z = (z ^ (z >> 30)) * -4658895280553007687
	z = (z ^ (z >> 27)) * -7723592293110705685
	return absi(z ^ (z >> 31))


## Returns deterministic star class ("O", "B", "A", "F", "G", "K", "M") from `system_seed`.
static func select_spectral_class_code(system_seed: int) -> String:
	var bucket: int = splitmix64_hash(system_seed, 404) % 1000
	if bucket < 10:
		return "O"
	elif bucket < 40:
		return "B"
	elif bucket < 105:
		return "A"
	elif bucket < 230:
		return "F"
	elif bucket < 460:
		return "G"
	elif bucket < 720:
		return "K"
	return "M"


## Generates deterministic per-body terrain parameters from body seed and equilibrium temperature.
static func generate_body_terrain_params(body_seed: int, equilibrium_temp_k: float) -> Dictionary:
	var h1: int = splitmix64_hash(body_seed, 11)
	var h2: int = splitmix64_hash(body_seed, 29)
	var max_relief_m: float = 1200.0 + float(h1 % 4800)
	var roughness: float = 0.35 + float(h2 % 550) / 1000.0
	var biome_family: String = "temperate"
	if equilibrium_temp_k > 360.0:
		biome_family = "scorched"
	elif equilibrium_temp_k < 210.0:
		biome_family = "frozen"
	return {
		"max_relief_m": max_relief_m,
		"roughness": roughness,
		"biome_family": biome_family
	}
