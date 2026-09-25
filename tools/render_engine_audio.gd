extends SceneTree

## Renders review WAVs from the runtime engine voice code. This tool owns demo
## programs only; every sample comes from EngineVoiceGenerator + EngineSynth, and
## the drive program is driven by the real EngineDrivetrainModel.
##
##   godot --headless --path . --script tools/render_engine_audio.gd
##
## Output directory defaults to /tmp/opencode/engine-sound/final; override with
## ENGINE_AUDIO_OUT. Nothing is written into the repository.

const RECIPE_LIBRARY := preload("res://scripts/audio/engine/engine_recipe_library.gd")
const SAMPLE_RATE := 48000
const BLOCK := 256
const TARGET_PEAK := 0.70794578
const MAX_SPEED := 692.0
const STEP := 1.0 / 60.0

var _out_dir := ""


func _initialize() -> void:
	_out_dir = OS.get_environment("ENGINE_AUDIO_OUT")
	if _out_dir.is_empty():
		_out_dir = "/tmp/opencode/engine-sound/final"
	var error := DirAccess.make_dir_recursive_absolute(_out_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("ENGINE_RENDER FAIL: could not create %s: %s" % [_out_dir, error_string(error)])
		quit(1)
		return
	if not _render("rustbug", "idle", 4.0):
		return
	if not _render("rustbug", "sweep", 6.0):
		return
	if not _render("rustbug", "drive", 10.0):
		return
	if not _render_variety(["pinbolt", "thimble", "anvil"], 3.0):
		return
	print("ENGINE_RENDER COMPLETE -> " + _out_dir)
	quit(0)


func _render(vehicle_id: String, program: String, duration: float) -> bool:
	var recipe := _recipe_for(vehicle_id)
	if recipe == null or not recipe.is_valid():
		push_error("ENGINE_RENDER FAIL: %s has no valid recipe" % vehicle_id)
		quit(1)
		return false
	var voice := EngineVoiceGenerator.new().generate(recipe)
	var synth := EngineSynth.new()
	synth.configure(voice, SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(int(duration * float(SAMPLE_RATE)))
	var drivetrain: EngineDrivetrainModel = null
	if program == "drive":
		drivetrain = EngineDrivetrainModel.new()
		drivetrain.configure(recipe)
	for index in samples.size():
		var time := float(index) / float(SAMPLE_RATE)
		if index % BLOCK == 0:
			if drivetrain != null:
				drivetrain.step(_speed_profile(time, duration), MAX_SPEED, 1.0, _throttle_profile(time, duration), float(BLOCK) / float(SAMPLE_RATE))
				synth.set_controls(drivetrain.get_rpm(), drivetrain.get_load(), drivetrain.get_throttle())
			else:
				var controls := _controls(program, time, duration)
				synth.set_controls(controls.x, controls.y, controls.z)
		var seam := minf(smoothstep(0.0, 0.012, time), smoothstep(0.0, 0.018, duration - time))
		samples[index] = synth.render_sample() * seam
	var path := _out_dir.path_join("%s_%s.wav" % [vehicle_id, program])
	if not _write_wav(path, samples):
		return false
	_report(vehicle_id, program, duration, samples)
	return true


func _render_variety(vehicle_ids: Array, seconds: float) -> bool:
	for vehicle_id in vehicle_ids:
		var recipe := _recipe_for(String(vehicle_id))
		if recipe == null or not recipe.is_valid():
			push_error("ENGINE_RENDER FAIL: %s has no valid recipe" % vehicle_id)
			quit(1)
			return false
		var voice := EngineVoiceGenerator.new().generate(recipe)
		var synth := EngineSynth.new()
		synth.configure(voice, SAMPLE_RATE)
		var count := int(seconds * float(SAMPLE_RATE))
		var samples := PackedFloat32Array()
		samples.resize(count)
		for index in count:
			var time := float(index) / float(SAMPLE_RATE)
			var rise := smoothstep(0.0, seconds * 0.7, time)
			if index % BLOCK == 0:
				synth.set_controls(lerpf(recipe.idle_rpm, recipe.redline_rpm, rise), lerpf(0.2, 1.0, rise), rise)
			var seam := minf(smoothstep(0.0, 0.02, time), smoothstep(0.0, 0.02, seconds - time))
			samples[index] = synth.render_sample() * seam
		var path := _out_dir.path_join("variety_%s.wav" % vehicle_id)
		if not _write_wav(path, samples):
			return false
		_report(String(vehicle_id), "variety", seconds, samples)
	return true


func _controls(program: String, time: float, duration: float) -> Vector3:
	match program:
		"idle":
			var wander := sin(TAU * 1.7 * time) * 18.0 + sin(TAU * 0.37 * time) * 11.0
			return Vector3(1050.0 + wander, 0.16 + 0.025 * sin(TAU * 2.1 * time), 0.08)
		"sweep":
			if time < 1.0:
				return Vector3(1050.0, 0.15, 0.05)
			if time < duration - 1.8:
				var rise := smoothstep(1.0, duration - 1.8, time)
				return Vector3(lerpf(1050.0, 7600.0, rise), lerpf(0.30, 1.0, rise), rise)
			var fall := smoothstep(duration - 1.8, duration, time)
			return Vector3(lerpf(7600.0, 1050.0, fall), lerpf(0.18, 0.10, fall), 0.0)
	return Vector3(1050.0, 0.5, 0.5)


func _speed_profile(time: float, duration: float) -> float:
	var pull := smoothstep(0.0, duration * 0.82, time)
	return MAX_SPEED * pull


func _throttle_profile(time: float, duration: float) -> float:
	if time > duration * 0.55 and time < duration * 0.68:
		return 0.0
	return 1.0


func _recipe_for(vehicle_id: String) -> EngineRecipe:
	var stats := load("res://data/vehicles/%s.tres" % vehicle_id) as VehicleStats
	return RECIPE_LIBRARY.resolve(vehicle_id, stats)


func _write_wav(path: String, samples: PackedFloat32Array) -> bool:
	var peak := 0.0001
	for sample in samples:
		peak = maxf(peak, absf(sample))
	var gain := TARGET_PEAK / peak
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for index in samples.size():
		pcm.encode_s16(index * 2, int(round(clampf(samples[index] * gain, -1.0, 1.0) * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm
	var error := wav.save_to_wav(path)
	if error != OK:
		push_error("ENGINE_RENDER FAIL: %s: %s" % [path, error_string(error)])
		quit(1)
		return false
	return true


## Reports the loudness a listener actually gets: every file is written
## peak-normalized to TARGET_PEAK, so the raw numbers would understate it.
func _report(vehicle_id: String, program: String, duration: float, samples: PackedFloat32Array) -> void:
	var peak := 0.0
	var sum_squares := 0.0
	for sample in samples:
		peak = maxf(peak, absf(sample))
		sum_squares += sample * sample
	var gain := TARGET_PEAK / maxf(peak, 0.0001)
	var rms := sqrt(sum_squares / float(maxi(samples.size(), 1))) * gain
	print("%s_%s.wav  %.1fs  normalized rms=%.5f (%.2f dBFS)" % [
		vehicle_id, program, duration, rms, linear_to_db(maxf(rms, 1e-9)),
	])
