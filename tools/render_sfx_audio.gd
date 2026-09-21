extends SceneTree

## Renders review WAVs for the generated sound effects from the runtime code.
##
##   godot --headless --path . --script tools/render_sfx_audio.gd
##
## Output defaults to /tmp/opencode/sfx-audio; override with SFX_AUDIO_OUT.
## Nothing is written into the repository.

const DriftSynthScript := preload("res://scripts/audio/sfx/drift_synth.gd")
const CrashVoiceGeneratorScript := preload("res://scripts/audio/sfx/crash_voice_generator.gd")
const BoostVoiceGeneratorScript := preload("res://scripts/audio/sfx/boost_voice_generator.gd")

const SAMPLE_RATE := 22050
const BLOCK := 256
const TARGET_PEAK := 0.70794578
const DRIFT_SECONDS := 4.0

var _out_dir := ""


func _initialize() -> void:
	_out_dir = OS.get_environment("SFX_AUDIO_OUT")
	if _out_dir.is_empty():
		_out_dir = "/tmp/opencode/sfx-audio"
	var error := DirAccess.make_dir_recursive_absolute(_out_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("SFX_RENDER FAIL: could not create %s: %s" % [_out_dir, error_string(error)])
		quit(1)
		return
	if not _render_drift():
		return
	if not _render_crashes():
		return
	if not _render_boost():
		return
	print("SFX_RENDER COMPLETE -> " + _out_dir)
	quit(0)


## A drift as the game drives it: bite, sustained slide, release.
func _render_drift() -> bool:
	var synth = DriftSynthScript.new()
	synth.configure(SAMPLE_RATE, 20260921)
	var count := int(DRIFT_SECONDS * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	for index in count:
		var time := float(index) / float(SAMPLE_RATE)
		if index % BLOCK == 0:
			var intensity := _drift_intensity(time)
			var speed_ratio := _drift_speed(time)
			synth.set_state(intensity, speed_ratio, 1.15, float(BLOCK) / float(SAMPLE_RATE))
		samples[index] = synth.render_sample()
	return _write("drift_arc.wav", samples, true)


func _render_crashes() -> bool:
	var rustbug := load("res://data/vehicles/rustbug.tres") as VehicleStats
	var anvil := load("res://data/vehicles/anvil.tres") as VehicleStats
	var light := CrashVoiceGeneratorScript.new().generate(rustbug, "rustbug")
	if not _write("crash_rustbug_light.wav", light.tiers[0], true):
		return false
	if not _write("crash_rustbug_heavy.wav", light.tiers[3], true):
		return false
	var heavy_car := CrashVoiceGeneratorScript.new().generate(anvil, "anvil")
	if not _write("crash_anvil_heavy.wav", heavy_car.tiers[3], true):
		return false
	return true


func _render_boost() -> bool:
	var rustbug := load("res://data/vehicles/rustbug.tres") as VehicleStats
	var voice := BoostVoiceGeneratorScript.new().generate(rustbug, "rustbug")
	return _write("boost.wav", voice.tiers[0], true)


func _drift_intensity(time: float) -> float:
	if time < 0.25:
		return smoothstep(0.0, 0.25, time)
	if time < 2.6:
		return 0.72 + 0.28 * sin(TAU * 0.7 * time)
	return maxf(0.0, 1.0 - smoothstep(2.6, 3.3, time))


func _drift_speed(time: float) -> float:
	return clampf(lerpf(0.45, 0.9, smoothstep(0.0, 3.0, time)), 0.0, 1.0)


func _write(name: String, samples: PackedFloat32Array, normalize: bool) -> bool:
	var peak := 0.0001
	for sample in samples:
		peak = maxf(peak, absf(sample))
	var gain := (TARGET_PEAK / peak) if normalize else 1.0
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for index in samples.size():
		pcm.encode_s16(index * 2, int(round(clampf(samples[index] * gain, -1.0, 1.0) * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm
	var path := _out_dir.path_join(name)
	var error := wav.save_to_wav(path)
	if error != OK:
		push_error("SFX_RENDER FAIL: %s: %s" % [path, error_string(error)])
		quit(1)
		return false
	var sum_squares := 0.0
	for index in samples.size():
		var value := clampf(samples[index] * gain, -1.0, 1.0)
		sum_squares += value * value
	var rms := sqrt(sum_squares / float(maxi(samples.size(), 1)))
	print("%-26s %5.2fs  rms=%.5f (%.2f dBFS)  peak=%.3f" % [name, float(samples.size()) / SAMPLE_RATE, rms, linear_to_db(maxf(rms, 1e-9)), TARGET_PEAK if normalize else peak])
	return true
