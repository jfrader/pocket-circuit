extends SceneTree

## Verifies the packaged race loop against the same contract the Gamestruments
## library masters to: a -14.0 LUFS integrated target and a -1.0 dBTP ceiling.
## This is the fallback heard when the live GDExtension is absent, which is what
## shipped builds use, so it is the asset that must hold the ceiling.

const AudioMastering := preload("res://tools/audio_mastering.gd")

const RACE_PATH := "res://assets/audio/race_loop.wav"
const TARGET_LUFS := -14.0
const LUFS_TOLERANCE := 1.5
const CEILING_DBTP := -1.0
const MIN_DURATION_SECONDS := 15.9
const MAX_DC_OFFSET := 0.001
const MAX_SEAM_DELTA := 0.01
const MIN_HALF_SECOND_VARIATION := 0.08


func _initialize() -> void:
	var stream := load(RACE_PATH) as AudioStreamWAV
	if stream == null or stream.stereo:
		_fail("race music should import as mono audio")
		return
	var samples := _decode_pcm(RACE_PATH)
	if samples.is_empty():
		_fail("race music should contain PCM samples")
		return

	var peak := 0.0
	var total := 0.0
	for sample: float in samples:
		peak = maxf(peak, absf(sample))
		total += sample
	var duration := float(samples.size()) / float(stream.mix_rate)
	var dc_offset := total / float(samples.size())
	var seam_delta := absf(samples[0] - samples[samples.size() - 1])
	var half_second_variation := _envelope_variation(samples, stream.mix_rate, 0.5)
	var loudness := AudioMastering.measure_integrated_loudness(samples, stream.mix_rate)
	var true_peak := AudioMastering.measure_true_peak_db(samples, stream.mix_rate)
	print(
		"RACE_MUSIC_METRICS duration=%.3f loudness=%.2f lufs true_peak=%.2f dbtp sample_peak=%.5f dc=%.6f seam=%.6f half_second_variation=%.4f"
		% [duration, loudness, true_peak, peak, dc_offset, seam_delta, half_second_variation]
	)

	var ceiling_linear := pow(10.0, CEILING_DBTP / 20.0)
	var failures := PackedStringArray()
	_check(duration >= MIN_DURATION_SECONDS, "race music should run for at least 16 seconds before repeating", failures)
	_check(peak <= ceiling_linear + 0.0001, "race music should not exceed the true-peak ceiling", failures)
	_check(true_peak <= CEILING_DBTP, "race music true peak should stay at or below %.1f dBTP" % CEILING_DBTP, failures)
	_check(
		absf(loudness - TARGET_LUFS) <= LUFS_TOLERANCE,
		"race music should sit within %.1f LU of %.1f LUFS" % [LUFS_TOLERANCE, TARGET_LUFS],
		failures
	)
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


func _decode_pcm(path: String) -> PackedFloat32Array:
	# Read the shipped WAV directly rather than through the imported resource:
	# the importer may store a converted stream, and this measurement must
	# describe the asset as shipped, not a decoded playback of it.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedFloat32Array()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var offset := 12
	while offset + 8 <= bytes.size():
		var chunk_id := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_size := int(bytes.decode_u32(offset + 4))
		if chunk_id == "data":
			var start := offset + 8
			var count := chunk_size / 2
			var samples := PackedFloat32Array()
			samples.resize(count)
			for index in count:
				samples[index] = float(bytes.decode_s16(start + index * 2)) / 32768.0
			return samples
		offset += 8 + chunk_size + (chunk_size % 2)
	return PackedFloat32Array()


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
