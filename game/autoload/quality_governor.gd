extends Node

## Monitors performance and thermal state to dynamically adjust quality settings.

const CHECK_INTERVAL_SEC: float = 2.0
const TARGET_FPS: float = 60.0
const MIN_FSR_SCALE: float = 0.6
const MAX_FSR_SCALE: float = 1.0

# Predictive and hysteresis band thresholds
const THERMAL_PREDICTIVE_THRESHOLD: float = 0.7  # Act before severe throttling collapses FPS
const THERMAL_RECOVERY_THRESHOLD: float = 0.5    # Lower bound for thermal recovery
const FPS_DOWNSCALE_THRESHOLD: float = 54.0      # Lower hysteresis limit (TARGET_FPS - 6)
const FPS_UPSCALE_THRESHOLD: float = 59.0        # Upper hysteresis limit
const FRAMETIME_VARIANCE_SPIKE_MS: float = 5.0   # Jitter/stutter detection threshold in ms
const UPSCALE_STABILITY_INTERVALS: int = 2       # Consecutive stable checks required to upscale

var _check_timer: float = 0.0
var _stable_good_intervals: int = 0

var fsr_scale: float = 1.0
var scatter_density: float = 1.0
var cloud_render_distance: float = 10000.0

var is_mobile: bool = false
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
		fsr_scale = 1.0
		scatter_density = 1.0
		cloud_render_distance = 20000.0
		_apply_settings()
	else:
		fsr_scale = 0.8
		scatter_density = 0.6
		cloud_render_distance = 8000.0
		_apply_settings()

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
	
	if not is_mobile:
		return
		
	_check_timer += delta
	if _check_timer >= CHECK_INTERVAL_SEC:
		_check_timer = 0.0
		_evaluate_performance()

func evaluate_performance() -> void:
	_evaluate_performance()

func _evaluate_performance() -> void:
	var effective_fps: float = TARGET_FPS
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
	var fps_low: bool = effective_fps < FPS_DOWNSCALE_THRESHOLD
	var variance_spike: bool = frametime_variance_ms >= FRAMETIME_VARIANCE_SPIKE_MS
	
	var needs_downscale: bool = thermal_pressure or fps_low or variance_spike
	
	# 3. Hysteresis band for recovery / upscaling:
	# Thermal headroom must be safely below 0.5 (deadband [0.5, 0.7] prevents oscillating adjustments)
	var thermal_safe: bool = (not has_plugin) or (thermal_headroom < THERMAL_RECOVERY_THRESHOLD)
	var fps_good: bool = effective_fps >= FPS_UPSCALE_THRESHOLD
	var variance_low: bool = frametime_variance_ms < (FRAMETIME_VARIANCE_SPIKE_MS * 0.5)
	
	var can_upscale: bool = thermal_safe and fps_good and variance_low
	
	if needs_downscale:
		_stable_good_intervals = 0
		var scale_step: float = 0.05
		if (has_plugin and thermal_headroom >= 0.85) or effective_fps < (TARGET_FPS - 15.0):
			scale_step = 0.08
		fsr_scale = maxf(MIN_FSR_SCALE, fsr_scale - scale_step)
		scatter_density = maxf(0.2, scatter_density - (scale_step * 2.0))
		cloud_render_distance = maxf(4000.0, cloud_render_distance - (scale_step * 20000.0))
		_apply_settings()
	elif can_upscale:
		_stable_good_intervals += 1
		if _stable_good_intervals >= UPSCALE_STABILITY_INTERVALS:
			_stable_good_intervals = 0
			fsr_scale = minf(MAX_FSR_SCALE, fsr_scale + 0.02)
			scatter_density = minf(1.0, scatter_density + 0.05)
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
