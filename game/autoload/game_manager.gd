extends Node

class_name GameManagerAutoload

var planet_runtime: PlanetRuntime
var in_orbit: bool = true

func _ready() -> void:
	pass

func transition_to_surface() -> void:
	in_orbit = false
	if planet_runtime:
		# Test the chunk streamer during transition
		planet_runtime.update_from_universe(UniversePosition.new())
		print("Transitioning to surface...")
