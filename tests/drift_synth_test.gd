extends SceneTree

const DRIFT_SYNTH := preload("res://scripts/audio/sfx/drift_synth.gd")
const SAMPLE_RATE := 22050
const BLOCK := 256
const BLOCK_SECONDS := float(BLOCK) / float(SAMPLE_RATE)


func _initialize() -> void:
	var errors := PackedStringArray()
	errors.append_array(_check_silence())
	errors.append_array(_check_response())
	errors.append_array(_check_bounds())
	errors.append_array(_check_determinism())
	if errors.is_empty():
		print("DRIFT_SYNTH_TEST PASS")
		quit(0)
		return
	for error in errors:
		push_error("DRIFT_SYNTH_TEST FAIL: " + error)
	quit(1)


func _check_silence() -> PackedStringArray:
	var errors := PackedStringArray()
	var synth := DRIFT_SYNTH.new()
	synth.configure(SAMPLE_RATE, 7)
	var peak := 0.0
	for index in SAMPLE_RATE:
		if index % BLOCK == 0:
			synth.set_state(0.0, 0.0, 0.8, 1.15, BLOCK_SECONDS)
		peak = maxf(peak, absf(synth.render_sample()))
	errors.append_array(_expect(peak < 0.001, "a car with no slip must be silent; peak %.5f" % peak))
	return errors


func _check_response() -> PackedStringArray:
	var errors := PackedStringArray()
	# The carve matters: an ordinary corner must be audible but far below a slide.
	var corner := _render(0.08, 0.0, 0.95, 1.15)
	var mid := _render(0.34, 0.0, 0.80, 1.15)
	var slide := _render(1.0, 0.9, 0.60, 1.15)
	errors.append_array(_expect(float(corner["rms"]) > 0.005, "a gentle corner must still be audible; rms %.5f" % float(corner["rms"])))
	errors.append_array(_expect(float(corner["rms"]) < float(mid["rms"]) * 0.6, "a gentle corner must be well below a mid corner"))
	errors.append_array(_expect(float(mid["rms"]) < float(slide["rms"]) * 0.75, "a mid corner must stay below a slide"))
	errors.append_array(_expect(float(slide["rms"]) > float(corner["rms"]) * 3.0, "a slide must be far louder than a corner"))
	errors.append_array(_expect(float(slide["brightness"]) > float(corner["brightness"]), "a faster slide must be brighter"))
	var low_grip := _render(0.6, 0.4, 0.7, 0.9)
	var high_grip := _render(0.6, 0.4, 0.7, 1.4)
	errors.append_array(_expect(float(high_grip["rms"]) != float(low_grip["rms"]), "surface grip must change the scrub"))
	return errors


func _check_bounds() -> PackedStringArray:
	var errors := PackedStringArray()
	var synth := DRIFT_SYNTH.new()
	synth.configure(SAMPLE_RATE, 3)
	var peak := 0.0
	var finite := true
	for index in SAMPLE_RATE * 2:
		if index % BLOCK == 0:
			var ramp := float(index) / float(SAMPLE_RATE * 2)
			synth.set_state(ramp, ramp, ramp, lerpf(0.85, 1.40, ramp), BLOCK_SECONDS)
		var sample := synth.render_sample()
		if is_nan(sample) or is_inf(sample):
			finite = false
			break
		peak = maxf(peak, absf(sample))
	errors.append_array(_expect(finite, "the drift voice must stay finite across a full sweep"))
	errors.append_array(_expect(peak <= 1.0, "the drift voice must stay inside full scale; peak %.4f" % peak))
	errors.append_array(_expect(peak > 0.2, "the drift voice must reach a usable level; peak %.4f" % peak))
	return errors


func _check_determinism() -> PackedStringArray:
	var errors := PackedStringArray()
	errors.append_array(_expect(_digest(_render(0.7, 0.5, 0.8, 1.2)) == _digest(_render(0.7, 0.5, 0.8, 1.2)), "the drift voice must be deterministic"))
	return errors


func _render(scrub: float, screech: float, speed_ratio: float, grip: float) -> Dictionary:
	var synth := DRIFT_SYNTH.new()
	synth.configure(SAMPLE_RATE, 11)
	var peak := 0.0
	var sum_squares := 0.0
	var delta_sum := 0.0
	var previous := 0.0
	var digest := 2166136261
	var total := SAMPLE_RATE
	for index in total:
		if index % BLOCK == 0:
			synth.set_state(scrub, screech, speed_ratio, grip, BLOCK_SECONDS)
		var sample := synth.render_sample()
		peak = maxf(peak, absf(sample))
		sum_squares += sample * sample
		delta_sum += absf(sample - previous)
		previous = sample
		digest = ((digest ^ int(absf(sample) * 1000000.0)) * 16777619) & 0xffffffff
	return {
		"peak": peak,
		"rms": sqrt(sum_squares / float(total)),
		"brightness": delta_sum / float(maxi(total, 1)),
		"digest": "%08x" % digest,
	}


func _digest(stats: Dictionary) -> String:
	return String(stats["digest"])


func _expect(condition: bool, message: String) -> PackedStringArray:
	if condition:
		return PackedStringArray()
	return PackedStringArray([message])
