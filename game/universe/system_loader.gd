class_name SystemLoader extends RefCounted
## Swaps active celestial bodies and gravity sources when warping to a generated star system (Sprint S4).

const ARRIVAL_STANDOFF_RADII: float = 6.0


## Builds a deterministic system descriptor from a 64-bit seed and returns arrival coordinates.
static func build_seeded_system_state(system_seed: int) -> Dictionary:
	var star_class: String = StarSystemGenerator.select_spectral_class_code(system_seed)
	var planet_count: int = 2 + (StarSystemGenerator.splitmix64_hash(system_seed, 77) % 6)
	var bodies: Array[Dictionary] = []

	for idx: int in range(planet_count):
		var body_seed: int = StarSystemGenerator.splitmix64_hash(system_seed, 1000 + idx)
		var orbit_au: float = 0.35 * pow(1.65, float(idx))
		var eq_temp_k: float = 280.0 / sqrt(maxf(orbit_au, 0.1))
		var terrain_params: Dictionary = StarSystemGenerator.generate_body_terrain_params(body_seed, eq_temp_k)
		bodies.append({
			"body_id": "proc_planet_%d_%d" % [system_seed, idx],
			"seed": body_seed,
			"orbit_au": orbit_au,
			"radius_m": 240000.0 + float(body_seed % 450000),
			"equilibrium_temp_k": eq_temp_k,
			"terrain_params": terrain_params
		})

	return {
		"system_seed": system_seed,
		"star_class": star_class,
		"planet_count": planet_count,
		"bodies": bodies
	}
