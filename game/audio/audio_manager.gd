class_name AudioManager extends Node

## Procedural audio manager synthesizing spacecraft sounds and UI effects in memory.
## Uses AudioStreamWAV 16-bit PCM mono waveforms.

const SAMPLE_RATE: int = 22050

# Audio player nodes for dedicated channels
var engine_player: AudioStreamPlayer
var rcs_player: AudioStreamPlayer
var reentry_player: AudioStreamPlayer
var ui_player: AudioStreamPlayer

# Procedural audio stream buffers
var engine_stream: AudioStreamWAV
var rcs_stream: AudioStreamWAV
var reentry_stream: AudioStreamWAV
var click_stream: AudioStreamWAV
var alert_stream: AudioStreamWAV
var touchdown_stream: AudioStreamWAV

# State tracking
var current_throttle: float = 0.0
var current_reentry_q: float = 0.0
var last_alert_type: String = ""

func _init() -> void:
	_generate_audio_streams()
	_setup_audio_players()

func _enter_tree() -> void:
	# Resume continuous channel playback if state was set before entering tree
	if current_throttle > 0.001:
		_safe_play(engine_player)
	if current_reentry_q > 0.001:
		_safe_play(reentry_player)

## Set engine throttle (0.0 to 1.0) and dynamically modulate pitch and volume.
func set_engine_throttle(throttle: float) -> void:
	current_throttle = clampf(throttle, 0.0, 1.0)
	if engine_player == null:
		return
	if current_throttle <= 0.001:
		engine_player.volume_db = -80.0
		engine_player.pitch_scale = 0.6
	else:
		engine_player.volume_db = lerpf(-30.0, 0.0, current_throttle)
		engine_player.pitch_scale = lerpf(0.65, 1.35, current_throttle)
		if not engine_player.playing:
			_safe_play(engine_player)

## Play brief RCS thruster burst noise.
func play_rcs_burst() -> void:
	if rcs_player == null:
		return
	rcs_player.volume_db = -4.0
	rcs_player.pitch_scale = randf_range(0.96, 1.04)
	if rcs_player.playing:
		rcs_player.stop()
	_safe_play(rcs_player)

## Set dynamic pressure q and modulate turbulent re-entry buffet volume and pitch.
func set_reentry_pressure(q: float) -> void:
	current_reentry_q = maxf(q, 0.0)
	if reentry_player == null:
		return
	var norm_q: float = clampf(current_reentry_q if current_reentry_q <= 1.0 else current_reentry_q / 50000.0, 0.0, 1.0)
	if norm_q <= 0.001:
		reentry_player.volume_db = -80.0
		reentry_player.pitch_scale = 0.7
	else:
		reentry_player.volume_db = lerpf(-36.0, 2.0, norm_q)
		reentry_player.pitch_scale = lerpf(0.7, 1.3, norm_q)
		if not reentry_player.playing:
			_safe_play(reentry_player)

## Play subtle UI click blip (~880 Hz sine burst).
func play_ui_click() -> void:
	_play_ui(click_stream, -6.0, 1.0)

## Play cockpit warning alert (dual tone 600/900 Hz).
func play_alert(warning_type: String = "") -> void:
	last_alert_type = warning_type
	var pitch: float = 1.0
	if warning_type == "critical":
		pitch = 1.15
	elif warning_type == "caution":
		pitch = 0.95
	_play_ui(alert_stream, -2.0, pitch)

## Play celebratory landing / touchdown chime (arpeggio / chord).
func play_touchdown() -> void:
	_play_ui(touchdown_stream, -3.0, 1.0)

## Internal helper to play UI stream on the UI channel.
func _play_ui(stream: AudioStreamWAV, volume_db: float, pitch: float) -> void:
	if ui_player == null or stream == null:
		return
	ui_player.stream = stream
	ui_player.volume_db = volume_db
	ui_player.pitch_scale = pitch
	if ui_player.playing:
		ui_player.stop()
	_safe_play(ui_player)

## Checks whether audio playback is safe in current environment.
static func is_audio_supported() -> bool:
	if AudioServer == null:
		return false
	if AudioServer.get_mix_rate() <= 0.0:
		return false
	return true

## Safely initiates playback on an AudioStreamPlayer node.
func _safe_play(player: AudioStreamPlayer, from_pos: float = 0.0) -> void:
	if not is_instance_valid(player):
		return
	if not player.is_inside_tree():
		return
	if not is_audio_supported():
		return
	player.play(from_pos)

## Set up child AudioStreamPlayer nodes.
func _setup_audio_players() -> void:
	engine_player = AudioStreamPlayer.new()
	engine_player.name = "EnginePlayer"
	engine_player.stream = engine_stream
	engine_player.volume_db = -80.0
	engine_player.bus = "Master"
	add_child(engine_player)

	rcs_player = AudioStreamPlayer.new()
	rcs_player.name = "RCSPlayer"
	rcs_player.stream = rcs_stream
	rcs_player.volume_db = -4.0
	rcs_player.bus = "Master"
	add_child(rcs_player)

	reentry_player = AudioStreamPlayer.new()
	reentry_player.name = "ReentryPlayer"
	reentry_player.stream = reentry_stream
	reentry_player.volume_db = -80.0
	reentry_player.bus = "Master"
	add_child(reentry_player)

	ui_player = AudioStreamPlayer.new()
	ui_player.name = "UIPlayer"
	ui_player.stream = click_stream
	ui_player.volume_db = -6.0
	ui_player.bus = "Master"
	add_child(ui_player)

## Synthesize procedural waveforms for all sounds.
func _generate_audio_streams() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	
	engine_stream = _generate_engine_stream(rng)
	rcs_stream = _generate_rcs_stream(rng)
	reentry_stream = _generate_reentry_stream(rng)
	click_stream = _generate_click_stream()
	alert_stream = _generate_alert_stream()
	touchdown_stream = _generate_touchdown_stream()

## Rocket engine roar loop: low-pass filtered noise buffer with seamless crossfade.
func _generate_engine_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var duration_sec: float = 1.0
	var sample_count: int = int(duration_sec * SAMPLE_RATE)
	var crossfade_len: int = 1024
	var total_samples: int = sample_count + crossfade_len

	var raw_noise: PackedFloat32Array = PackedFloat32Array()
	raw_noise.resize(total_samples)
	for i in range(total_samples):
		raw_noise[i] = rng.randf_range(-1.0, 1.0)

	# 2-pole low-pass filter (approx 160 Hz cutoff)
	var filtered: PackedFloat32Array = PackedFloat32Array()
	filtered.resize(total_samples)
	var y1: float = 0.0
	var y2: float = 0.0
	var alpha: float = 0.045
	for i in range(total_samples):
		y1 += alpha * (raw_noise[i] - y1)
		y2 += alpha * (y1 - y2)
		filtered[i] = y2 + raw_noise[i] * 0.06

	# Seamless loop crossfade
	var final_samples: PackedFloat32Array = PackedFloat32Array()
	final_samples.resize(sample_count)
	for i in range(sample_count):
		final_samples[i] = filtered[i]
	for j in range(crossfade_len):
		var blend: float = float(j) / float(crossfade_len)
		final_samples[j] = lerpf(filtered[sample_count + j], final_samples[j], blend)

	_normalize_samples(final_samples, 0.85)
	return _samples_to_wav(final_samples, true)

## RCS puff: brief noise burst (70 ms) with exponential decay envelope.
func _generate_rcs_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var duration_sec: float = 0.070
	var sample_count: int = int(duration_sec * SAMPLE_RATE)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(sample_count)

	var attack_samples: int = int(0.003 * SAMPLE_RATE)
	var lpf: float = 0.0
	var alpha: float = 0.25 # High-pass filter reference

	for i in range(sample_count):
		var raw: float = rng.randf_range(-1.0, 1.0)
		lpf += alpha * (raw - lpf)
		var hpf: float = raw - lpf # Crisp hissing noise

		var env: float = 0.0
		if i < attack_samples:
			env = float(i) / float(attack_samples)
		else:
			var t_decay: float = float(i - attack_samples) / float(SAMPLE_RATE)
			env = exp(-t_decay / 0.016)

		# Fade tail smoothly to zero at the last 20 samples
		if i >= sample_count - 20:
			var fade: float = float(sample_count - 1 - i) / 20.0
			env *= fade

		samples[i] = hpf * env

	_normalize_samples(samples, 0.8)
	return _samples_to_wav(samples, false)

## Atmospheric re-entry buffet: deep turbulent noise scaled by dynamic pressure.
func _generate_reentry_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var duration_sec: float = 1.0
	var sample_count: int = int(duration_sec * SAMPLE_RATE)
	var crossfade_len: int = 1024
	var total_samples: int = sample_count + crossfade_len

	var raw_noise: PackedFloat32Array = PackedFloat32Array()
	raw_noise.resize(total_samples)
	for i in range(total_samples):
		raw_noise[i] = rng.randf_range(-1.0, 1.0)

	# Deep low-pass filter (approx 90 Hz cutoff) with turbulent rumble modulation
	var filtered: PackedFloat32Array = PackedFloat32Array()
	filtered.resize(total_samples)
	var y1: float = 0.0
	var alpha: float = 0.025
	for i in range(total_samples):
		y1 += alpha * (raw_noise[i] - y1)
		var t: float = float(i) / float(SAMPLE_RATE)
		var buffet: float = 0.65 + 0.25 * sin(TAU * 7.5 * t) + 0.15 * sin(TAU * 13.0 * t)
		filtered[i] = y1 * buffet

	# Seamless loop crossfade
	var final_samples: PackedFloat32Array = PackedFloat32Array()
	final_samples.resize(sample_count)
	for i in range(sample_count):
		final_samples[i] = filtered[i]
	for j in range(crossfade_len):
		var blend: float = float(j) / float(crossfade_len)
		final_samples[j] = lerpf(filtered[sample_count + j], final_samples[j], blend)

	_normalize_samples(final_samples, 0.85)
	return _samples_to_wav(final_samples, true)

## UI click blip: sine burst ~880 Hz, 35 ms.
func _generate_click_stream() -> AudioStreamWAV:
	var duration_sec: float = 0.035
	var sample_count: int = int(duration_sec * SAMPLE_RATE)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(sample_count)

	var freq: float = 880.0
	var attack_samples: int = int(0.003 * SAMPLE_RATE)

	for i in range(sample_count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = 0.0
		if i < attack_samples:
			env = 0.5 * (1.0 - cos(PI * float(i) / float(attack_samples)))
		else:
			var t_decay: float = float(i - attack_samples) / float(SAMPLE_RATE)
			env = exp(-t_decay / 0.010)

		if i >= sample_count - 15:
			env *= float(sample_count - 1 - i) / 15.0

		samples[i] = sin(TAU * freq * t) * env

	_normalize_samples(samples, 0.75)
	return _samples_to_wav(samples, false)

## UI warning alert: dual tone 600/900 Hz dual pulse.
func _generate_alert_stream() -> AudioStreamWAV:
	var duration_sec: float = 0.260
	var sample_count: int = int(duration_sec * SAMPLE_RATE)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(sample_count)

	var f1: float = 600.0
	var f2: float = 900.0

	for i in range(sample_count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = 0.0
		# Dual pulse: [0.00 .. 0.11] and [0.14 .. 0.25]
		if t >= 0.0 and t < 0.11:
			env = _calc_pulse_envelope(t, 0.0, 0.11)
		elif t >= 0.14 and t < 0.25:
			env = _calc_pulse_envelope(t, 0.14, 0.25)

		var tone: float = 0.5 * sin(TAU * f1 * t) + 0.5 * sin(TAU * f2 * t)
		samples[i] = tone * env

	_normalize_samples(samples, 0.8)
	return _samples_to_wav(samples, false)

## Helper to calculate pulse envelope with 4ms rise and fall.
func _calc_pulse_envelope(t: float, start_t: float, end_t: float) -> float:
	var ramp: float = 0.004
	if t < start_t + ramp:
		return (t - start_t) / ramp
	elif t > end_t - ramp:
		return (end_t - t) / ramp
	return 1.0

## UI touchdown chime: ascending arpeggio chord (C5, E5, G5, C6).
func _generate_touchdown_stream() -> AudioStreamWAV:
	var duration_sec: float = 0.650
	var sample_count: int = int(duration_sec * SAMPLE_RATE)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(sample_count)

	var notes: Array = [
		{"freq": 523.25, "start": 0.00, "decay": 0.14},
		{"freq": 659.25, "start": 0.10, "decay": 0.15},
		{"freq": 783.99, "start": 0.20, "decay": 0.16},
		{"freq": 1046.50, "start": 0.30, "decay": 0.22}
	]

	for i in range(sample_count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var sum_val: float = 0.0

		for note in notes:
			var note_start: float = note["start"]
			if t >= note_start:
				var t_rel: float = t - note_start
				var f: float = note["freq"]
				var decay: float = note["decay"]
				var env: float = 0.0
				if t_rel < 0.004:
					env = t_rel / 0.004
				else:
					env = exp(-(t_rel - 0.004) / decay)

				var note_wave: float = sin(TAU * f * t_rel) + 0.22 * sin(TAU * (f * 2.0) * t_rel)
				sum_val += note_wave * env * 0.4

		# Fade tail out
		if i >= sample_count - 30:
			sum_val *= float(sample_count - 1 - i) / 30.0

		samples[i] = sum_val

	_normalize_samples(samples, 0.8)
	return _samples_to_wav(samples, false)

## Normalizes samples so peak value equals target_peak.
func _normalize_samples(samples: PackedFloat32Array, target_peak: float) -> void:
	var max_val: float = 0.00001
	for s in samples:
		var a: float = absf(s)
		if a > max_val:
			max_val = a
	var scale_factor: float = target_peak / max_val
	for i in range(samples.size()):
		samples[i] *= scale_factor

## Converts float samples into 16-bit PCM AudioStreamWAV.
func _samples_to_wav(samples: PackedFloat32Array, is_loop: bool) -> AudioStreamWAV:
	var sample_count: int = samples.size()
	var byte_data: PackedByteArray = PackedByteArray()
	byte_data.resize(sample_count * 2)

	for i in range(sample_count):
		var s: float = clampf(samples[i], -1.0, 1.0)
		var val: int = clampi(int(s * 32767.0), -32768, 32767)
		byte_data.encode_s16(i * 2, val)

	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = byte_data
	if is_loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = sample_count
	else:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED

	return wav
