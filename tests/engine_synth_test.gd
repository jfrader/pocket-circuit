extends SceneTree

const RUSTBUG_STATS := preload("res://data/vehicles/rustbug.tres")
const RECIPE_LIBRARY := preload("res://scripts/audio/engine/engine_recipe_library.gd")
const SAMPLE_RATE := 22050
const BLOCK := 256


func _initialize() -> void:
	var recipe := RECIPE_LIBRARY.resolve("rustbug", RUSTBUG_STATS)
	var voice := EngineVoiceGenerator.new().generate(recipe)
	var errors := PackedStringArray()
	errors.append_array(_check_idle(voice))
	errors.append_array(_check_rev(voice))
	errors.append_array(_check_extremes(voice))
	errors.append_array(_check_determinism(voice))
	if errors.is_empty():
		print("ENGINE_SYNTH_TEST PASS")
		quit(0)
		return
	for error in errors:
		push_error("ENGINE_SYNTH_TEST FAIL: " + error)
	quit(1)


func _check_idle(voice: EngineVoice) -> PackedStringArray:
	var errors := PackedStringArray()
	var stats := _run(voice, voice.recipe.idle_rpm, 0.05, 0.0, 8)
	errors.append_array(_expect(stats["finite"], "idle output must be finite"))
	errors.append_array(_expect(float(stats["peak"]) <= 1.0, "idle output must stay inside full scale; peak %.4f" % float(stats["peak"])))
	errors.append_array(_expect(float(stats["rms"]) > 0.001, "idle output must not be silent; rms %.5f" % float(stats["rms"])))
	return errors


func _check_rev(voice: EngineVoice) -> PackedStringArray:
	var errors := PackedStringArray()
	var idle := _run(voice, voice.recipe.idle_rpm, 0.05, 0.0, 8)
	var redline := _run(voice, voice.recipe.redline_rpm, 1.0, 1.0, 8)
	errors.append_array(_expect(float(redline["rms"]) > float(idle["rms"]) * 1.2, "full throttle must be louder than idle; %.4f vs %.4f" % [float(redline["rms"]), float(idle["rms"])]))
	errors.append_array(_expect(float(redline["peak"]) <= 1.0, "redline output must stay inside full scale; peak %.4f" % float(redline["peak"])))
	errors.append_array(_expect(String(redline["digest"]) != String(idle["digest"]), "rpm and load must change the waveform"))
	var coast := _run(voice, voice.recipe.redline_rpm, 0.0, 0.0, 8)
	errors.append_array(_expect(String(coast["digest"]) != String(redline["digest"]), "coasting must sound different from load"))
	errors.append_array(_expect(float(coast["rms"]) < float(redline["rms"]), "coasting must be quieter than load"))
	return errors


func _check_extremes(voice: EngineVoice) -> PackedStringArray:
	var errors := PackedStringArray()
	var stats := _run(voice, 0.0, 4.0, -3.0, 8)
	errors.append_array(_expect(stats["finite"], "out-of-range controls must not produce NaN or inf"))
	errors.append_array(_expect(float(stats["peak"]) <= 1.0, "out-of-range controls must stay inside full scale; peak %.4f" % float(stats["peak"])))
	var above := _run(voice, voice.recipe.redline_rpm * 4.0, 1.0, 1.0, 4)
	errors.append_array(_expect(above["finite"], "over-rev controls must not produce NaN or inf"))
	errors.append_array(_expect(float(above["peak"]) <= 1.0, "over-rev controls must stay inside full scale; peak %.4f" % float(above["peak"])))
	return errors


func _check_determinism(voice: EngineVoice) -> PackedStringArray:
	var errors := PackedStringArray()
	var first := _run(voice, voice.recipe.redline_rpm * 0.6, 0.5, 0.7, 4)
	var second := _run(voice, voice.recipe.redline_rpm * 0.6, 0.5, 0.7, 4)
	errors.append_array(_expect(String(first["digest"]) == String(second["digest"]), "the synth must be deterministic"))
	return errors


func _run(voice: EngineVoice, rpm: float, load: float, throttle: float, seconds: int) -> Dictionary:
	var synth := EngineSynth.new()
	synth.configure(voice, SAMPLE_RATE)
	synth.set_controls(rpm, load, throttle)
	var total := SAMPLE_RATE * seconds
	var peak := 0.0
	var sum_squares := 0.0
	var finite := true
	var digest := 2166136261
	for index in total:
		if index % BLOCK == 0:
			synth.set_controls(rpm, load, throttle)
		var sample := synth.render_sample()
		if is_nan(sample) or is_inf(sample):
			finite = false
			break
		peak = maxf(peak, absf(sample))
		sum_squares += sample * sample
		digest = ((digest ^ int(absf(sample) * 1000000.0)) * 16777619) & 0xffffffff
	return {
		"finite": finite,
		"peak": peak,
		"rms": sqrt(sum_squares / float(maxi(total, 1))),
		"digest": "%08x" % digest,
	}


func _expect(condition: bool, message: String) -> PackedStringArray:
	if condition:
		return PackedStringArray()
	return PackedStringArray([message])
