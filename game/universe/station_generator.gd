class_name StationGenerator extends RefCounted
## Generates space stations orbiting populated planets in a star system.

var rng: RandomNumberGenerator

func _init(seed_val: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_val

## Generates a station definition for a given planet, if it is populated.
func generate_station_for_planet(planet: CelestialBodyDef, population_level: int) -> Dictionary:
	if population_level <= 0:
		return {}
		
	var station = {}
	station["name"] = planet.display_name + " Station"
	station["faction"] = _pick_faction(planet)
	station["docking_bays"] = rng.randi_range(2, 6) + population_level
	
	# Orbit parameters
	var planet_radius_m = planet.radius_m
	station["orbit_altitude_m"] = planet_radius_m * rng.randf_range(1.5, 3.0)
	station["orbit_inclination_rad"] = rng.randf_range(-PI/4, PI/4)
	
	# Layout metadata for later scene instantiation
	station["modules"] = _generate_interior_layout(station["docking_bays"])
	
	return station

func _pick_faction(_planet: CelestialBodyDef) -> String:
	var factions = ["Terran Alliance", "Free Traders", "Crimson Syndicate", "Independent"]
	return factions[rng.randi() % factions.size()]

func _generate_interior_layout(bays: int) -> Array:
	var modules = []
	modules.append({"type": "Core", "position": Vector3.ZERO})
	
	for i in range(bays):
		var angle = (float(i) / bays) * TAU
		var distance = 50.0
		var pos = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		modules.append({"type": "DockingBay", "position": pos, "rotation_y": -angle})
	
	# Add some flavor modules
	var extra_modules = ["TradeFloor", "Cantina", "Engineering"]
	var e_count = rng.randi_range(1, 3)
	for i in range(e_count):
		modules.append({
			"type": extra_modules[i % extra_modules.size()],
			"position": Vector3(0, (i + 1) * 20.0, 0)
		})
		
	return modules
