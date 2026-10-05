extends Node

## Monitors performance and thermal state to dynamically adjust quality settings.

const CHECK_INTERVAL_SEC: float = 2.0
const TARGET_FPS: float = 60.0
const MIN_FSR_SCALE: float = 0.5
const MAX_FSR_SCALE: float = 1.0
const MOBILE_MAX_FSR_SCALE: float = 0.75
const ADJUSTMENT_HYSTERESIS_SEC: float = 10.0
const ADJUSTMENT_STEP: float = 0.05

# Predictive and hysteresis band thresholds
const THERMAL_PREDICTIVE_THRESHOLD: float = 0.7  # Act before severe throttling collapses FPS
const THERMAL_RECOVERY_THRESHOLD: float = 0.5    # Lower bound for thermal recovery
const FPS_DOWNSCALE_THRESHOLD: float = 54.0      # Lower hysteresis limit (TARGET_FPS - 6)
const FPS_UPSCALE_THRESHOLD: float = 59.0        # Upper hysteresis limit
const FRAMETIME_VARIANCE_SPIKE_MS: float = 5.0   # Jitter/stutter detection threshold in ms
const UPSCALE_STABILITY_INTERVALS: int = 2       # Consecutive stable checks required to upscale

const PRESETS: Dictionary = {
	"performance": {
		"target_fps": 60.0,
		"min_scale": 0.67,
		"max_scale": 0.75,
	},
	"battery_saver": {
		"target_fps": 30.0,
		"min_scale": 0.5,
		"max_scale": 0.6,
	}
}

var _check_timer: float = 0.0
var _stable_good_intervals: int = 0
var time_since_last_adjustment: float = ADJUSTMENT_HYSTERESIS_SEC

var current_preset: String = "performance"
var target_fps: float = 60.0
var min_fsr_scale: float = 0.5
var fps_downscale_threshold: float = 54.0
var fps_upscale_threshold: float = 59.0

var _is_mobile: bool = false
var is_mobile: bool:
	get:
		return _is_mobile
	set(value):
		_is_mobile = value
		if _is_mobile:
			_max_fsr_scale = minf(_max_fsr_scale, MOBILE_MAX_FSR_SCALE)
			_fsr_scale = minf(_fsr_scale, MOBILE_MAX_FSR_SCALE)

var _max_fsr_scale: float = 1.0
var max_fsr_scale: float:
	get:
		if _is_mobile:
			return minf(_max_fsr_scale, MOBILE_MAX_FSR_SCALE)
		return _max_fsr_scale
	set(value):
		if _is_mobile:
			_max_fsr_scale = minf(value, MOBILE_MAX_FSR_SCALE)
		else:
			_max_fsr_scale = value
		_fsr_scale = minf(_fsr_scale, get_effective_max_scale())

var _fsr_scale: float = 1.0
var fsr_scale: float:
	get:
		return _fsr_scale
	set(value):
		var cap = get_effective_max_scale()
		_fsr_scale = clampf(value, min_fsr_scale, cap)

var scatter_density: float = 1.0
var cloud_render_distance: float = 10000.0

var thermal_plugin: Object = null

# Performance & thermal metrics
var smoothed_frametime_ms: float = 16.67
var frametime_variance_ms: float = 0.0
var thermal_headroom: float = 0.0
var _frame_count: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	
	if Engine.has_singleton("AndroidPerformanceHints"):
		thermal_plugin = Engine.get_singleton("AndroidPerformanceHints")
		
	if not is_mobile:
		# Safe defaults for Desktop
		target_fps = 60.0
		min_fsr_scale = 0.6
		max_fsr_scale = 1.0
		fsr_scale = 1.0
		fps_downscale_threshold = 54.0
		fps_upscale_threshold = 59.0
		scatter_density = 1.0
		cloud_render_distance = 20000.0
		_apply_settings()
	else:
		set_preset("performance")
		scatter_density = 0.6
		cloud_render_distance = 8000.0
		_apply_settings()

func set_preset(preset_name: String) -> void:
	current_preset = preset_name
	match preset_name:
		"battery_saver":
			target_fps = 30.0
			min_fsr_scale = 0.5
			max_fsr_scale = 0.6
			fps_downscale_threshold = 27.0
			fps_upscale_threshold = 29.5
			fsr_scale = clampf(fsr_scale, min_fsr_scale, max_fsr_scale)
		"performance", _:
			current_preset = "performance"
			target_fps = 60.0
			min_fsr_scale = 0.67
			max_fsr_scale = 0.75
			fps_downscale_threshold = 54.0
			fps_upscale_threshold = 59.0
			fsr_scale = clampf(fsr_scale, min_fsr_scale, max_fsr_scale)
	if is_mobile:
		max_fsr_scale = minf(max_fsr_scale, MOBILE_MAX_FSR_SCALE)
		fsr_scale = minf(fsr_scale, max_fsr_scale)
	_apply_settings()

func apply_preset(preset_name: String) -> void:
	set_preset(preset_name)

func get_preset() -> String:
	return current_preset

func get_effective_max_scale() -> float:
	if _is_mobile:
		return minf(_max_fsr_scale, MOBILE_MAX_FSR_SCALE)
	return _max_fsr_scale

func get_max_scale() -> float:
	return get_effective_max_scale()

func get_min_scale() -> float:
	return min_fsr_scale

func advance_time(delta: float) -> void:
	time_since_last_adjustment += delta
	_check_timer += delta

func record_frame_time(delta: float) -> void:
	if delta <= 0.0:
		return
	var dt_ms: float = clampf(delta * 1000.0, 1.0, 500.0)
	_frame_count += 1
	if _frame_count == 1:
		smoothed_frametime_ms = dt_ms
		frametime_variance_ms = 0.0
	else:
		var alpha: float = 0.05
		var diff: float = dt_ms - smoothed_frametime_ms
		smoothed_frametime_ms = lerpf(smoothed_frametime_ms, dt_ms, alpha)
		var dev_sq: float = diff * diff
		frametime_variance_ms = sqrt(lerpf(frametime_variance_ms * frametime_variance_ms, dev_sq, alpha))

func _process(delta: float) -> void:
	record_frame_time(delta)
	time_since_last_adjustment += delta
	
	if not is_mobile:
		return
		
	_check_timer += delta
	if _check_timer >= CHECK_INTERVAL_SEC:
		_check_timer = 0.0
		_evaluate_performance()

func evaluate_performance() -> void:
	_evaluate_performance()

func _evaluate_performance() -> void:
	var effective_fps: float = target_fps
	if smoothed_frametime_ms > 0.0:
		effective_fps = 1000.0 / smoothed_frametime_ms
	else:
		var raw_fps: float = Engine.get_frames_per_second()
		if raw_fps > 0.0:
			effective_fps = raw_fps
			
	thermal_headroom = 0.0
	var has_plugin: bool = false
	if thermal_plugin and thermal_plugin.has_method("get_thermal_headroom"):
		thermal_headroom = thermal_plugin.get_thermal_headroom()
		has_plugin = true
	
	# 1. Predictive thermal scaling: act when thermal_headroom >= 0.7
	var thermal_pressure: bool = has_plugin and (thermal_headroom >= THERMAL_PREDICTIVE_THRESHOLD)
	
	# 2. Performance degradation: FPS below hysteresis threshold or variance spike
	# When AndroidPerformanceHints is absent, smoothed frame times and frametime variance
	# detect thermal throttling before complete FPS collapse.
	var fps_low: bool = effective_fps < fps_downscale_threshold
	var variance_spike: bool = frametime_variance_ms >= FRAMETIME_VARIANCE_SPIKE_MS
	
	var needs_downscale: bool = thermal_pressure or fps_low or variance_spike
	
	# 3. Hysteresis band for recovery / upscaling:
	# Thermal headroom must be safely below 0.5 (deadband [0.5, 0.7] prevents oscillating adjustments)
	var thermal_safe: bool = (not has_plugin) or (thermal_headroom < THERMAL_RECOVERY_THRESHOLD)
	var fps_good: bool = effective_fps >= fps_upscale_threshold
	var variance_low: bool = frametime_variance_ms < (FRAMETIME_VARIANCE_SPIKE_MS * 0.5)
	
	var can_upscale: bool = thermal_safe and fps_good and variance_low
	
	if needs_downscale:
		_stable_good_intervals = 0
		if time_since_last_adjustment >= ADJUSTMENT_HYSTERESIS_SEC:
			var min_scale = get_min_scale()
			if fsr_scale > min_scale:
				time_since_last_adjustment = 0.0
				fsr_scale = snappedf(maxf(min_scale, fsr_scale - ADJUSTMENT_STEP), 0.001)
				scatter_density = snappedf(maxf(0.2, scatter_density - (ADJUSTMENT_STEP * 2.0)), 0.001)
				cloud_render_distance = maxf(4000.0, cloud_render_distance - (ADJUSTMENT_STEP * 20000.0))
				_apply_settings()
	elif can_upscale:
		_stable_good_intervals += 1
		if _stable_good_intervals >= UPSCALE_STABILITY_INTERVALS:
			if time_since_last_adjustment >= ADJUSTMENT_HYSTERESIS_SEC:
				_stable_good_intervals = 0
				var max_scale = get_effective_max_scale()
				if fsr_scale < max_scale:
					time_since_last_adjustment = 0.0
					fsr_scale = snappedf(minf(max_scale, fsr_scale + ADJUSTMENT_STEP), 0.001)
					scatter_density = snappedf(minf(1.0, scatter_density + 0.05), 0.001)
					cloud_render_distance = minf(10000.0, cloud_render_distance + 500.0)
					_apply_settings()
	else:
		# In hysteresis deadband: hold current state without oscillation
		_stable_good_intervals = 0

func _apply_settings() -> void:
	if get_viewport():
		get_viewport().scaling_3d_scale = fsr_scale
	
	if is_inside_tree():
		get_tree().call_group("quality_listeners", "on_quality_changed", {
			"scatter_density": scatter_density,
			"cloud_render_distance": cloud_render_distance
		})
