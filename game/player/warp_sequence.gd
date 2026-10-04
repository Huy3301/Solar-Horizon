class_name WarpSequence extends Node

## Handles the hyperdrive warp transition sequence
## Yields while WorkerThreadPool generates the new system chunks.

signal warp_started
signal warp_finished

enum WarpState { IDLE, INITIATING, TUNNEL, GENERATING, FADING_IN }
var current_state: WarpState = WarpState.IDLE

## The ID of the target star system
var target_system_id: String = ""

func start_warp(target_id: String) -> void:
	if current_state != WarpState.IDLE:
		return
		
	target_system_id = target_id
	current_state = WarpState.INITIATING
	warp_started.emit()
	
	_transition_routine()

func _transition_routine() -> void:
	# 1. Hide old system
	_hide_old_system()
	
	# 2. Play tunnel effect
	current_state = WarpState.TUNNEL
	_play_tunnel_effect()
	
	# 3. Generate new system (simulated wait)
	current_state = WarpState.GENERATING
	await _generate_new_system()
	
	# 4. Fade in
	current_state = WarpState.FADING_IN
	await _fade_in()
	
	current_state = WarpState.IDLE
	warp_finished.emit()

func _hide_old_system() -> void:
	print("Hiding old system...")
	# DEFERRED(phase 5): Interface with actual scene manager

func _play_tunnel_effect() -> void:
	print("Playing tunnel effect...")
	# DEFERRED(phase 5): Enable UI/post-processing mask for shader

func _generate_new_system() -> void:
	print("Generating new system...")
	# DEFERRED(phase 5): Poll WorkerThreadPool for GalaxyGenerator completion
	await get_tree().create_timer(2.0).timeout

func _fade_in() -> void:
	print("Fading in...")
	await get_tree().create_timer(1.0).timeout
