class_name GalaxyGenerator extends RefCounted
## Maps sector coordinates to star presence.

const STAR_DENSITY_PER_MILLE: int = 8

var seed: int = 0

func _init(p_seed: int = 0) -> void:
	seed = p_seed

## Generates a deterministic hash for a given sector coordinate
func _hash_sector(sector: Vector3i) -> int:
	var h: int = seed
	h = h ^ (sector.x * 73856093)
	h = h ^ (sector.y * 19349663)
	h = h ^ (sector.z * 83492791)
	h = (h ^ (h >> 16)) * 2246822507
	# Force 64-bit integer wrapping workaround for Godot 4
	h = h & 0x7FFFFFFFFFFFFFFF
	h = (h ^ (h >> 13)) * 3266489909
	h = h & 0x7FFFFFFFFFFFFFFF
	return h ^ (h >> 16)

## Determines if a star exists in the given sector.
func has_star(sector: Vector3i) -> bool:
	# Realistic solar neighbourhood density (~0.008 stars/ly^3)
	var h = _hash_sector(sector)
	return (h % 1000) < STAR_DENSITY_PER_MILLE

## Returns the star system seed if it exists, otherwise 0
func get_star_seed(sector: Vector3i) -> int:
	if has_star(sector):
		return _hash_sector(sector)
	return 0

## Returns the star class as a string (O, B, A, F, G, K, M)
func get_star_class(sector: Vector3i) -> String:
	var system_seed = get_star_seed(sector)
	if system_seed == 0:
		return ""
	var val = abs(((system_seed >> 16) ^ 0x4B3C9A) % 100)
	if val < 60: return "M" # 60% Red Dwarf
	if val < 75: return "K" # 15% Orange Dwarf
	if val < 85: return "G" # 10% Yellow Dwarf
	if val < 92: return "F" # 7% Yellow-White
	if val < 96: return "A" # 4% White
	if val < 99: return "B" # 3% Blue-White
	return "O"              # 1% Blue Giant
