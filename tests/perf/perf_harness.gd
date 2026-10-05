extends SceneTree

## Solar Horizon - Performance Benchmark Harness (Phase C).
## Standalone runnable script simulating a 300-frame orbital trajectory pass.
## Measures min/max/average frame times, frame time jitter, and peak memory,
## writing results to stdout and user://perf_baseline.csv.

const TOTAL_FRAMES: int = 300
const CSV_FILE_PATH: String = "user://perf_baseline.csv"

var current_frame: int = 0
var frame_times: Array[float] = []
var memory_samples: Array[float] = []
var telemetry_samples: Array[Dictionary] = []
var last_frame_ticks: int = 0
var ship_ref: Node = null

func _initialize() -> void:
	print("============================================================")
	print("Solar Horizon — Performance Benchmark Harness")
	print("Simulating 300-frame orbital trajectory pass in headless engine...")
	print("============================================================")
	change_scene_to_file("res://scenes/main.tscn")
	last_frame_ticks = Time.get_ticks_usec()

func _process(_delta: float) -> bool:
	var now = Time.get_ticks_usec()
	var dt_us = now - last_frame_ticks
	last_frame_ticks = now

	# Frame 0 is scene load and initial setup, start measuring on frame 1
	if current_frame == 0:
		current_frame += 1
		return false

	var frame_ms = float(dt_us) / 1000.0
	frame_times.append(frame_ms)

	var mem_mb = float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	memory_samples.append(mem_mb)

	if ship_ref == null and root.get_child_count() > 0:
		var scene = root.get_child(0)
		ship_ref = scene.get_node_or_null("Ship")

	var alt_m = 0.0
	var speed_ms = 0.0
	if ship_ref and is_instance_valid(ship_ref):
		if "linear_velocity" in ship_ref:
			speed_ms = (ship_ref.linear_velocity as Vector3).length()
		if "global_position" in ship_ref:
			alt_m = (ship_ref.global_position as Vector3).length()

	telemetry_samples.append({
		"alt": alt_m,
		"speed": speed_ms
	})

	current_frame += 1
	if current_frame > TOTAL_FRAMES:
		_process_and_output_results()
		quit(0)
		return true

	return false

func _process_and_output_results() -> void:
	var n = frame_times.size()
	if n == 0:
		printerr("Error: No frame samples recorded.")
		quit(1)
		return

	# Calculate min, max, average frame times
	var min_ms: float = frame_times[0]
	var max_ms: float = frame_times[0]
	var sum_ms: float = 0.0
	for t in frame_times:
		if t < min_ms:
			min_ms = t
		if t > max_ms:
			max_ms = t
		sum_ms += t
	var avg_ms: float = sum_ms / float(n)

	# Calculate frame time jitter:
	# 1. Standard Deviation
	var variance: float = 0.0
	for t in frame_times:
		variance += pow(t - avg_ms, 2)
	variance /= float(n)
	var jitter_stddev_ms: float = sqrt(variance)

	# 2. Mean Absolute Successive Difference (MASD)
	var sum_successive_diff: float = 0.0
	for i in range(1, n):
		sum_successive_diff += abs(frame_times[i] - frame_times[i - 1])
	var jitter_masd_ms: float = sum_successive_diff / float(max(1, n - 1))

	# Calculate peak memory
	var peak_mem_mb: float = 0.0
	for m in memory_samples:
		if m > peak_mem_mb:
			peak_mem_mb = m
	var os_peak_mb: float = float(OS.get_static_memory_peak_usage()) / (1024.0 * 1024.0)
	if os_peak_mb > peak_mem_mb:
		peak_mem_mb = os_peak_mb

	# Output to stdout
	print("\n============================================================")
	print("BENCHMARK RESULTS (300 Frames Orbital Trajectory Pass)")
	print("============================================================")
	print("Total Frames:           %d" % n)
	print("Min Frame Time:         %.3f ms" % min_ms)
	print("Max Frame Time:         %.3f ms" % max_ms)
	print("Average Frame Time:     %.3f ms" % avg_ms)
	print("Frame Time Jitter (SD): %.3f ms" % jitter_stddev_ms)
	print("Frame Time Jitter(MASD):%.3f ms" % jitter_masd_ms)
	print("Peak Static Memory:     %.2f MB" % peak_mem_mb)
	print("============================================================")

	# Write to user://perf_baseline.csv
	var file = FileAccess.open(CSV_FILE_PATH, FileAccess.WRITE)
	if not file:
		printerr("Failed to open %s for writing: error %s" % [CSV_FILE_PATH, str(FileAccess.get_open_error())])
		return

	# Write summary header comments
	file.store_line("# Solar Horizon Performance Baseline (Phase C)")
	file.store_line("# frames=%d,min_ms=%.4f,max_ms=%.4f,avg_ms=%.4f,jitter_stddev_ms=%.4f,jitter_masd_ms=%.4f,peak_memory_mb=%.4f" % [
		n, min_ms, max_ms, avg_ms, jitter_stddev_ms, jitter_masd_ms, peak_mem_mb
	])
	file.store_line("frame,frame_time_ms,jitter_delta_ms,memory_mb,altitude_m,speed_ms")

	for i in range(n):
		var prev_t = frame_times[i - 1] if i > 0 else frame_times[i]
		var delta_jitter = abs(frame_times[i] - prev_t)
		var tel = telemetry_samples[i] if i < telemetry_samples.size() else {"alt": 0.0, "speed": 0.0}
		file.store_line("%d,%.4f,%.4f,%.4f,%.2f,%.2f" % [
			i + 1,
			frame_times[i],
			delta_jitter,
			memory_samples[i],
			tel["alt"],
			tel["speed"]
		])

	file.close()
	var global_path = ProjectSettings.globalize_path(CSV_FILE_PATH)
	print("Performance baseline CSV successfully written to:")
	print("  URI:  %s" % CSV_FILE_PATH)
	print("  Disk: %s\n" % global_path)
