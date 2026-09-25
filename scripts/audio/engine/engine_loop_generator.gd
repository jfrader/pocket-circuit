class_name EngineLoopGenerator
extends RefCounted

## One looping WAV per engine recipe, for opponent cars. The local car keeps the
## real-time synth. Generation is offline and cached by recipe signature.

const EngineSynthScript := preload("res://scripts/audio/engine/engine_synth.gd")
const EngineVoiceGeneratorScript := preload("res://scripts/audio/engine/engine_voice_generator.gd")
const SAMPLE_RATE := 22050
const SETTLE_FRAMES := 2048
const LOOP_CYCLES := 4
const CACHE_LIMIT := 8
const MIN_PITCH := 0.5
const MAX_PITCH := 1.7

static var _cache: Dictionary = {}


static func generate_cached(recipe: EngineRecipe) -> AudioStreamWAV:
	var key := recipe.signature()
	if _cache.has(key):
		return _cache[key] as AudioStreamWAV
	var stream := generate(recipe)
	if _cache.size() >= CACHE_LIMIT:
		_cache.erase(_cache.keys()[0])
	_cache[key] = stream
	return stream


static func clear_cache() -> void:
	_cache.clear()


static func pitch_for_rpm(rpm: float, base_rpm: float) -> float:
	return clampf(rpm / maxf(base_rpm, 1.0), MIN_PITCH, MAX_PITCH)


static func base_rpm_for(recipe: EngineRecipe) -> float:
	return lerpf(recipe.idle_rpm, recipe.redline_rpm, 0.55)


static func generate(recipe: EngineRecipe) -> AudioStreamWAV:
	var voice := EngineVoiceGeneratorScript.generate_cached(recipe)
	var synth := EngineSynthScript.new()
	synth.configure(voice, SAMPLE_RATE)
	var base_rpm := base_rpm_for(recipe)
	synth.set_controls(base_rpm, 0.55, 0.7)
	var cycle_frames := maxi(1, roundi(120.0 / base_rpm * float(SAMPLE_RATE)))
	var loop_frames := cycle_frames * LOOP_CYCLES
	var fade := mini(128, maxi(8, cycle_frames / 8))
	for _index in SETTLE_FRAMES:
		synth.render_sample()
	var rendered := PackedFloat32Array()
	rendered.resize(loop_frames + fade)
	for index in rendered.size():
		rendered[index] = synth.render_sample()
	for index in fade:
		var blend := float(index) / float(fade)
		rendered[index] = lerpf(rendered[loop_frames + index], rendered[index], blend)
	var pcm := PackedByteArray()
	pcm.resize(loop_frames * 2)
	for index in loop_frames:
		pcm.encode_s16(index * 2, int(round(clampf(rendered[index], -1.0, 1.0) * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = loop_frames - 1
	stream.data = pcm
	stream.set_meta("base_rpm", base_rpm)
	stream.set_meta("recipe_signature", recipe.signature())
	return stream
