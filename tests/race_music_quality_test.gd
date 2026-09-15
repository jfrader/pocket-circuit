extends SceneTree

const RACE_PATH := "res://assets/audio/race_loop.wav"
const MIN_DURATION_SECONDS := 15.9
const MAX_PEAK := 0.85
const MIN_RMS := 0.015
const MAX_RMS := 0.18
const MAX_DC_OFFSET := 0.001
const MAX_SEAM_DELTA := 0.01
const MIN_HALF_SECOND_VARIATION := 0.08


func _initialize() -> void:
	var stream := load(RACE_PATH) as AudioStreamWAV
	if stream == null or stream.stereo:
		_fail("race music should import as mono audio")
		return
	var samples := _decode_stream(stream)
	if samples.is_empty():
		_fail("race music should contain PCM samples")
		return

	var peak := 0.0
	var total := 0.0
	var square_total := 0.0
	for sample: float in samples:
		peak = maxf(peak, absf(sample))
		total += sample
		square_total += sample * sample
	var duration := float(samples.size()) / float(stream.mix_rate)
	var dc_offset := total / float(samples.size())
	var rms := sqrt(square_total / float(samples.size()))
	var seam_delta := absf(samples[0] - samples[samples.size() - 1])
	var half_second_variation := _envelope_variation(samples, stream.mix_rate, 0.5)
	print(
		"RACE_MUSIC_METRICS duration=%.3f peak=%.5f rms=%.5f dc=%.6f seam=%.6f half_second_variation=%.4f"
		% [duration, peak, rms, dc_offset, seam_delta, half_second_variation]
	)

	var failures := PackedStringArray()
	_check(duration >= MIN_DURATION_SECONDS, "race music should run for at least 16 seconds before repeating", failures)
	_check(peak <= MAX_PEAK, "race music should not clip", failures)
	_check(rms >= MIN_RMS and rms <= MAX_RMS, "race music should have a useful, controlled listening level", failures)
	_check(absf(dc_offset) <= MAX_DC_OFFSET, "race music should not carry audible DC offset", failures)
	_check(seam_delta <= MAX_SEAM_DELTA, "race music loop boundary should not click", failures)
	_check(
		half_second_variation >= MIN_HALF_SECOND_VARIATION,
		"race music should not be a short motor pulse under the engine",
		failures
	)
	if not failures.is_empty():
		_fail("; ".join(failures))
		return
	print("RACE_MUSIC_QUALITY_TEST PASS")
	quit(0)


func _decode_stream(stream: AudioStreamWAV) -> PackedFloat32Array:
	var sample_count := roundi(stream.get_length() * float(stream.mix_rate))
	var playback := stream.instantiate_playback()
	playback.start()
	var frames := playback.mix_audio(1.0, sample_count)
	var samples := PackedFloat32Array()
	samples.resize(frames.size())
	for index in frames.size():
		samples[index] = frames[index].x
	return samples


func _envelope_variation(samples: PackedFloat32Array, sample_rate: int, lag_seconds: float) -> float:
	var window_size := maxi(1, roundi(float(sample_rate) * 0.02))
	var window_count := floori(float(samples.size()) / float(window_size))
	var envelope := PackedFloat32Array()
	envelope.resize(window_count)
	for window_index in window_count:
		var absolute_total := 0.0
		var start := window_index * window_size
		for sample_index in range(start, start + window_size):
			absolute_total += absf(samples[sample_index])
		envelope[window_index] = absolute_total / float(window_size)

	var lag_windows := maxi(1, roundi(lag_seconds * float(sample_rate) / float(window_size)))
	var difference_total := 0.0
	var level_total := 0.0
	for window_index in envelope.size() - lag_windows:
		var current := envelope[window_index]
		var delayed := envelope[window_index + lag_windows]
		difference_total += absf(current - delayed)
		level_total += maxf(current, delayed)
	return difference_total / maxf(level_total, 0.000001)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _fail(message: String) -> void:
	push_error("RACE_MUSIC_QUALITY_TEST FAIL: " + message)
	quit(1)
