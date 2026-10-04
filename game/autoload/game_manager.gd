extends Node

class_name GameManagerAutoload

var planet_runtime: PlanetRuntime
var in_orbit: bool = true
var ship_position: UniversePosition = null

func _ready() -> void:
	pass

func is_in_orbit() -> bool:
	return in_orbit

func set_ship_position(pos: UniversePosition) -> void:
	ship_position = pos

func transition_to_surface(target_pos: UniversePosition = null) -> void:
	in_orbit = false
	var effective_pos = target_pos if target_pos != null else (ship_position if ship_position != null else UniversePosition.new())
	if planet_runtime:
		planet_runtime.update_from_universe(effective_pos)
		print("Transitioning to surface...")

func transition_to_orbit() -> void:
	in_orbit = true
