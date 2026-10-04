class_name WeatherSystem
extends Node3D
## Periodically transitions between clear skies, dust storms, or rain based on the planet's atmospheric properties.
## Modifies the player's hazard exposure accordingly.

enum WeatherState {
	CLEAR,
	DUST_STORM,
	RAIN
}

@export var atmosphere_system: AtmosphereSystem

var current_state: WeatherState = WeatherState.CLEAR
var transition_time: float = 0.0
var max_transition_time: float = 10.0

var time_in_state: float = 0.0
var next_weather_time: float = 60.0

var current_hazard_exposure: float = 0.0

var _target_fog_density: float = 0.0
var _target_sun_intensity: float = 1.0

func _ready() -> void:
	if not atmosphere_system:
		atmosphere_system = get_node_or_null("../AtmosphereSystem")
		
	_apply_weather_state(WeatherState.CLEAR)

func _process(delta: float) -> void:
	time_in_state += delta
	if time_in_state >= next_weather_time:
		_pick_next_weather()
		
	if transition_time < max_transition_time:
		transition_time += delta
		var t: float = clampf(transition_time / max_transition_time, 0.0, 1.0)
		_lerp_atmosphere_properties(t)

func _pick_next_weather() -> void:
	time_in_state = 0.0
	next_weather_time = randf_range(30.0, 120.0)
	
	# Basic probabilistic pick
	var rand_val: float = randf()
	var next_state: WeatherState = WeatherState.CLEAR
	
	if rand_val < 0.2:
		next_state = WeatherState.DUST_STORM
	elif rand_val < 0.4:
		next_state = WeatherState.RAIN
		
	if next_state != current_state:
		_apply_weather_state(next_state)

func _apply_weather_state(state: WeatherState) -> void:
	current_state = state
	transition_time = 0.0
	
	match current_state:
		WeatherState.CLEAR:
			_target_fog_density = 0.01
			_target_sun_intensity = 1.0
			current_hazard_exposure = 0.0
		WeatherState.DUST_STORM:
			_target_fog_density = 0.8
			_target_sun_intensity = 0.3
			current_hazard_exposure = 5.0 # High hazard
		WeatherState.RAIN:
			_target_fog_density = 0.3
			_target_sun_intensity = 0.6
			current_hazard_exposure = 1.0 # Mild hazard

func _lerp_atmosphere_properties(_t: float) -> void:
	if atmosphere_system:
		# Modify internal AtmosphereSystem values (or rely on a setter if refactored)
		atmosphere_system._sun_intensity = move_toward(atmosphere_system._sun_intensity, _target_sun_intensity, 0.01)
		atmosphere_system.needs_update = true
	
	var env = get_viewport().world_3d.environment
	if env:
		env.volumetric_fog_density = lerpf(env.volumetric_fog_density, _target_fog_density, 0.05)
