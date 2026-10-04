class_name WeatherSystem
extends Node3D
## Periodically transitions between clear skies, dust storms, or rain based on the planet's atmospheric properties.
## Modifies cloud coverage, drift, and the player's hazard exposure accordingly.

enum WeatherState {
	CLEAR,
	DUST_STORM,
	RAIN
}

@export var atmosphere_system: AtmosphereSystem
@export var cloud_material: ShaderMaterial
@export var wind_speed: float = 0.0002

var current_state: WeatherState = WeatherState.CLEAR
var transition_time: float = 0.0
var max_transition_time: float = 10.0

var time_in_state: float = 0.0
var next_weather_time: float = 60.0

var current_hazard_exposure: float = 0.0

var _target_fog_density: float = 0.0
var _target_sun_intensity: float = 1.0
var _target_cloud_coverage: float = 1.0
var _target_cloud_color: Color = Color.WHITE

var _current_cloud_rotation: float = 0.0
var _current_cloud_coverage: float = 1.0
var _current_cloud_color: Color = Color.WHITE

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

	# Continuous cloud rotation drift
	_current_cloud_rotation += wind_speed * delta
	if _current_cloud_rotation > TAU:
		_current_cloud_rotation -= TAU
	elif _current_cloud_rotation < -TAU:
		_current_cloud_rotation += TAU

	if cloud_material:
		cloud_material.set_shader_parameter("cloud_rotation", _current_cloud_rotation)

func _pick_next_weather() -> void:
	time_in_state = 0.0
	next_weather_time = randf_range(30.0, 120.0)
	
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
			_target_cloud_coverage = 1.05
			_target_cloud_color = Color(1.0, 1.0, 1.0, 1.0)
			current_hazard_exposure = 0.0
		WeatherState.DUST_STORM:
			_target_fog_density = 0.8
			_target_sun_intensity = 0.3
			_target_cloud_coverage = 1.6
			_target_cloud_color = Color(0.85, 0.65, 0.45, 1.0)
			current_hazard_exposure = 5.0 # High hazard
		WeatherState.RAIN:
			_target_fog_density = 0.3
			_target_sun_intensity = 0.6
			_target_cloud_coverage = 1.4
			_target_cloud_color = Color(0.65, 0.70, 0.75, 1.0)
			current_hazard_exposure = 1.0 # Mild hazard

func _lerp_atmosphere_properties(_t: float) -> void:
	if atmosphere_system:
		atmosphere_system.sun_intensity = move_toward(atmosphere_system.sun_intensity, _target_sun_intensity, 0.01)
	
	_current_cloud_coverage = move_toward(_current_cloud_coverage, _target_cloud_coverage, 0.01)
	_current_cloud_color = _current_cloud_color.lerp(_target_cloud_color, 0.02)
	
	if cloud_material:
		cloud_material.set_shader_parameter("cloud_coverage", _current_cloud_coverage)
		cloud_material.set_shader_parameter("cloud_color", _current_cloud_color)
	
	var vp = get_viewport()
	if vp and vp.world_3d and vp.world_3d.environment:
		var env = vp.world_3d.environment
		env.volumetric_fog_density = lerpf(env.volumetric_fog_density, _target_fog_density, 0.05)

func get_cloud_shadow(surface_uv: Vector2) -> float:
	if not cloud_material:
		return 0.0
	var tex: Texture2D = cloud_material.get_shader_parameter("cloud_texture")
	if not tex:
		return 0.0
	var rot: float = _current_cloud_rotation
	var cuv = Vector2(fmod(surface_uv.x + rot / TAU, 1.0), surface_uv.y)
	var img = tex.get_image()
	if not img:
		return 0.0
	var px = clampi(int(cuv.x * img.get_width()), 0, img.get_width() - 1)
	var py = clampi(int(cuv.y * img.get_height()), 0, img.get_height() - 1)
	var a = img.get_pixel(px, py).a
	return clampf(a * _current_cloud_coverage * 0.75, 0.0, 1.0)
