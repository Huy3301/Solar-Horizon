extends "res://tests/test_case.gd"

const AudioManagerScript = preload("res://game/audio/audio_manager.gd")

func test_audio_manager_instantiation_and_stream_generation() -> void:
	var audio: AudioManager = AudioManagerScript.new()
	assert_true(audio != null, "AudioManager instantiates successfully")

	# Check channels exist
	assert_true(audio.engine_player != null, "Engine player exists")
	assert_true(audio.rcs_player != null, "RCS player exists")
	assert_true(audio.reentry_player != null, "Reentry player exists")
	assert_true(audio.ui_player != null, "UI player exists")

	# Check streams generated
	assert_true(audio.engine_stream != null, "Engine stream generated")
	assert_true(audio.rcs_stream != null, "RCS stream generated")
	assert_true(audio.reentry_stream != null, "Reentry stream generated")
	assert_true(audio.click_stream != null, "Click stream generated")
	assert_true(audio.alert_stream != null, "Alert stream generated")
	assert_true(audio.touchdown_stream != null, "Touchdown stream generated")

	# Verify PCM WAV format parameters
	for stream in [audio.engine_stream, audio.rcs_stream, audio.reentry_stream, audio.click_stream, audio.alert_stream, audio.touchdown_stream]:
		assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "Stream format is 16-bit PCM")
		assert_eq(stream.mix_rate, AudioManager.SAMPLE_RATE, "Stream mix rate matches AudioManager SAMPLE_RATE")
		assert_false(stream.stereo, "Stream is mono")
		assert_true(stream.data.size() > 0, "Stream has audio buffer data")

	# Verify loop properties
	assert_eq(audio.engine_stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "Engine stream loops forward")
	assert_eq(audio.reentry_stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "Reentry stream loops forward")
	assert_eq(audio.rcs_stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "RCS stream is one-shot")
	assert_eq(audio.click_stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "Click stream is one-shot")
	assert_eq(audio.alert_stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "Alert stream is one-shot")
	assert_eq(audio.touchdown_stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "Touchdown stream is one-shot")

	# Verify duration bounds
	var rcs_duration_sec: float = float(audio.rcs_stream.data.size() / 2) / float(audio.rcs_stream.mix_rate)
	assert_true(rcs_duration_sec >= 0.06 and rcs_duration_sec <= 0.08, "RCS puff duration between 60ms and 80ms")

	var click_duration_sec: float = float(audio.click_stream.data.size() / 2) / float(audio.click_stream.mix_rate)
	assert_true(click_duration_sec >= 0.03 and click_duration_sec <= 0.04, "UI click duration is approx 35ms")

	audio.free()

func test_engine_throttle_modulation() -> void:
	var audio: AudioManager = AudioManagerScript.new()

	# Zero throttle: muted / idle
	audio.set_engine_throttle(0.0)
	assert_eq(audio.current_throttle, 0.0, "Current throttle is 0.0")
	assert_true(audio.engine_player.volume_db <= -60.0, "Zero throttle volume is muted (<= -60 dB)")
	assert_almost_eq(audio.engine_player.pitch_scale, 0.6, 0.05, "Zero throttle pitch is lower bound")

	# Mid throttle: scaled volume and pitch
	audio.set_engine_throttle(0.5)
	assert_eq(audio.current_throttle, 0.5, "Current throttle is 0.5")
	assert_true(audio.engine_player.volume_db > -30.0 and audio.engine_player.volume_db < -5.0, "Mid throttle volume scales dynamically")
	assert_true(audio.engine_player.pitch_scale >= 0.95 and audio.engine_player.pitch_scale <= 1.05, "Mid throttle pitch is approx 1.0")

	# Max throttle: max volume and pitch
	audio.set_engine_throttle(1.0)
	assert_eq(audio.current_throttle, 1.0, "Current throttle is 1.0")
	assert_almost_eq(audio.engine_player.volume_db, 0.0, 0.01, "Max throttle volume is 0 dB")
	assert_almost_eq(audio.engine_player.pitch_scale, 1.35, 0.01, "Max throttle pitch is upper bound 1.35")

	# Out of bounds clamping
	audio.set_engine_throttle(-0.25)
	assert_eq(audio.current_throttle, 0.0, "Negative throttle clamps to 0.0")
	audio.set_engine_throttle(1.75)
	assert_eq(audio.current_throttle, 1.0, "Over-unity throttle clamps to 1.0")

	audio.free()

func test_reentry_pressure_modulation() -> void:
	var audio: AudioManager = AudioManagerScript.new()

	# Zero dynamic pressure
	audio.set_reentry_pressure(0.0)
	assert_eq(audio.current_reentry_q, 0.0, "Current reentry q is 0.0")
	assert_true(audio.reentry_player.volume_db <= -60.0, "Zero dynamic pressure volume is muted")

	# Moderate dynamic pressure (normalized 0.5)
	audio.set_reentry_pressure(0.5)
	assert_true(audio.reentry_player.volume_db > -30.0, "Reentry volume modulates with dynamic pressure")
	assert_true(audio.reentry_player.pitch_scale >= 0.9 and audio.reentry_player.pitch_scale <= 1.1, "Reentry pitch scales with dynamic pressure")

	# High dynamic pressure in Pascals (e.g. 50000 Pa)
	audio.set_reentry_pressure(50000.0)
	assert_almost_eq(audio.reentry_player.volume_db, 2.0, 0.01, "Max dynamic pressure volume reaches upper ceiling")
	assert_almost_eq(audio.reentry_player.pitch_scale, 1.3, 0.01, "Max dynamic pressure pitch reaches 1.3")

	audio.free()

func test_sound_triggers_without_errors() -> void:
	var audio: AudioManager = AudioManagerScript.new()

	# RCS burst trigger
	audio.play_rcs_burst()
	assert_almost_eq(audio.rcs_player.volume_db, -4.0, 0.01, "RCS burst sets volume")
	assert_true(audio.rcs_player.pitch_scale >= 0.95 and audio.rcs_player.pitch_scale <= 1.05, "RCS burst pitch has slight jitter")

	# UI click trigger
	audio.play_ui_click()
	assert_eq(audio.ui_player.stream, audio.click_stream, "UI player assigned click stream")
	assert_almost_eq(audio.ui_player.volume_db, -6.0, 0.01, "Click volume is -6 dB")

	# Warning alert trigger
	audio.play_alert("warning")
	assert_eq(audio.ui_player.stream, audio.alert_stream, "UI player assigned alert stream")
	assert_eq(audio.last_alert_type, "warning", "Last alert type matches")

	audio.play_alert("critical")
	assert_eq(audio.last_alert_type, "critical", "Critical alert recorded")
	assert_almost_eq(audio.ui_player.pitch_scale, 1.15, 0.01, "Critical alert scales pitch higher")

	# Touchdown chime trigger
	audio.play_touchdown()
	assert_eq(audio.ui_player.stream, audio.touchdown_stream, "UI player assigned touchdown stream")
	assert_almost_eq(audio.ui_player.volume_db, -3.0, 0.01, "Touchdown chime volume is -3 dB")

	audio.free()

func test_tree_playback_and_headless_safety() -> void:
	var audio: AudioManager = AudioManagerScript.new()
	if tree != null and tree.root != null:
		tree.root.add_child(audio)
		# Trigger all channels when inside tree
		audio.set_engine_throttle(0.75)
		audio.play_rcs_burst()
		audio.set_reentry_pressure(25000.0)
		audio.play_ui_click()
		audio.play_alert("warning")
		audio.play_touchdown()

		tree.root.remove_child(audio)

	audio.free()
