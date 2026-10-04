extends Node

## Monitors performance and thermal state to dynamically adjust quality settings.

const CHECK_INTERVAL_SEC: float = 2.0
const TARGET_FPS: float = 60.0
const MIN_FSR_SCALE: float = 0.6
const MAX_FSR_SCALE: float = 1.0

var _check_timer: float = 0.0

var fsr_scale: float = 1.0
var scatter_density: float = 1.0
var cloud_render_distance: float = 10000.0

var is_mobile: bool = false
var thermal_plugin: Object = null

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

func _process(delta: float) -> void:
	if not is_mobile:
		return
		
	_check_timer += delta
	if _check_timer >= CHECK_INTERVAL_SEC:
		_check_timer = 0.0
		_evaluate_performance()

func _evaluate_performance() -> void:
	var fps: float = Engine.get_frames_per_second()
	var thermal_headroom: float = 0.0
	
	if thermal_plugin and thermal_plugin.has_method("get_thermal_headroom"):
		thermal_headroom = thermal_plugin.get_thermal_headroom()
	
	var needs_downscale: bool = fps < (TARGET_FPS - 5.0) or thermal_headroom > 0.8
	var can_upscale: bool = fps >= TARGET_FPS and thermal_headroom < 0.5
	
	if needs_downscale:
		fsr_scale = maxf(MIN_FSR_SCALE, fsr_scale - 0.05)
		scatter_density = maxf(0.2, scatter_density - 0.1)
		cloud_render_distance = maxf(4000.0, cloud_render_distance - 1000.0)
		_apply_settings()
	elif can_upscale:
		fsr_scale = minf(MAX_FSR_SCALE, fsr_scale + 0.02)
		scatter_density = minf(1.0, scatter_density + 0.05)
		cloud_render_distance = minf(10000.0, cloud_render_distance + 500.0)
		_apply_settings()

func _apply_settings() -> void:
	if get_viewport():
		get_viewport().scaling_3d_scale = fsr_scale
	
	if is_inside_tree():
		get_tree().call_group("quality_listeners", "on_quality_changed", {
			"scatter_density": scatter_density,
			"cloud_render_distance": cloud_render_distance
		})
