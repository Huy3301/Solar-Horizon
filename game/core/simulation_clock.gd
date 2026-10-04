extends Node

signal warp_changed(factor: int, on_rails: bool)
signal time_jumped

const WARP_LEVELS = [1, 2, 5, 10, 50, 100, 1000, 10000, 100000]

var sim_time_s: float = 0.0
var warp_index: int = 0
var physics_warp_allowed: bool = true

func set_warp_index(idx: int) -> void:
	if idx < 0:
		idx = 0
	if idx >= WARP_LEVELS.size():
		idx = WARP_LEVELS.size() - 1
		
	warp_index = idx
	var factor = WARP_LEVELS[warp_index]
	physics_warp_allowed = (warp_index <= 4)
	
	warp_changed.emit(factor, not physics_warp_allowed)

func advance(delta: float) -> void:
	var factor = WARP_LEVELS[warp_index]
	sim_time_s += float(delta) * float(factor)

func _physics_process(delta: float) -> void:
	advance(delta)

func can_warp(conditions: Dictionary) -> bool:
	if conditions.has("atmosphere") and conditions["atmosphere"]:
		return false
	if conditions.has("thrust") and conditions["thrust"]:
		return false
	return true
