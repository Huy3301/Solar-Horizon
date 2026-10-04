class_name BiomeSystem
extends RefCounted
## Defines rules for Biome Families based on planet physical properties.

enum BiomeFamily {
	LUSH,
	ARID,
	FROZEN,
	TOXIC,
	SCORCHED,
	RADIOACTIVE,
	EXOTIC,
	BARREN
}

## Determines the planet's primary biome family.
## Uses temperature (K), atmospheric pressure (atm), and sun distance (AU).
static func determine_biome_family(temperature_k: float, pressure_atm: float, sun_distance_au: float) -> BiomeFamily:
	# No atmosphere usually means barren, but we can have exotic if close to sun
	if pressure_atm < 0.05:
		if sun_distance_au < 0.2:
			return BiomeFamily.EXOTIC
		return BiomeFamily.BARREN
		
	if temperature_k < 230.0:
		return BiomeFamily.FROZEN
	elif temperature_k > 360.0:
		if pressure_atm > 3.0:
			return BiomeFamily.TOXIC
		return BiomeFamily.SCORCHED
		
	# Moderate temperatures
	if pressure_atm > 2.0:
		if sun_distance_au > 2.0:
			return BiomeFamily.RADIOACTIVE
		return BiomeFamily.TOXIC
	elif pressure_atm >= 0.5:
		# Ideal pressure and temp
		if temperature_k >= 270.0 and temperature_k <= 310.0:
			return BiomeFamily.LUSH
		return BiomeFamily.ARID
	
	return BiomeFamily.ARID
