class_name EngineVoiceGenerator
extends RefCounted

## Turns an EngineRecipe into an EngineVoice: a bank of phase-locked
## firing-cycle wavetables plus one mechanical-order table. Everything is a pure
## function of the recipe (seed included), so the same recipe always generates
## the same bank. The generator is deliberately offline-quality DSP: it is the
## only place that may use exp/sin per sample, and it runs once per voice.

const TABLE_SIZE := 1024
## RPM reference bands as fractions of idle..redline, so a 6300 rpm engine is
## not banded at a 7600 rpm redline.
const RPM_BAND_RATIOS: Array[float] = [0.0, 0.267, 0.603, 1.0]
const LOAD_BANDS: Array[float] = [0.0, 0.35, 0.70, 1.0]
## How many past firing cycles contribute to one table; the tail of a pulse
## crosses the cycle seam and must wrap.
const HISTORY_CYCLES := 3
const MAX_IMPULSE_SECONDS := 0.075
const TABLE_GAIN := 0.76
## Voice banks are pure functions of the recipe signature. Keep the four most
## recently used voices so warming a new field does not evict its player voice.
const CACHE_LIMIT := 4

static var _cache: Dictionary = {}

var _rng_state := 1
var _runner_gains := PackedFloat32Array()
var _runner_detune := PackedFloat32Array()
var _global_peak := 0.000001


## Generates a voice, reusing one already in memory for the same recipe. This is
## the entry point gameplay uses; the raw `generate` stays for tools and tests.
static func generate_cached(recipe: EngineRecipe) -> EngineVoice:
	var key := recipe.signature()
	if _cache.has(key):
		return _reuse_cached(key)
	return _store_cached(key, EngineVoiceGenerator.new().generate(recipe))


## Loading callers yield between RPM banks; synchronous callers use generate_cached.
static func prepare_cached(recipe: EngineRecipe, progress: Callable) -> EngineVoice:
	var key := recipe.signature()
	if _cache.has(key):
		return _reuse_cached(key)
	if not progress.is_valid():
		return generate_cached(recipe)
	var generator := EngineVoiceGenerator.new()
	var voice := generator._begin(recipe)
	for rpm in voice.rpm_bands:
		generator._append_band(voice, rpm)
		await progress.call()
	return _store_cached(key, generator._finish(voice))


static func _store_cached(key: String, voice: EngineVoice) -> EngineVoice:
	if _cache.has(key):
		return _reuse_cached(key)
	if _cache.size() >= CACHE_LIMIT:
		_cache.erase(_cache.keys()[0])
	_cache[key] = voice
	return voice


static func _reuse_cached(key: String) -> EngineVoice:
	var voice := _cache[key] as EngineVoice
	_cache.erase(key)
	_cache[key] = voice
	return voice


static func clear_cache() -> void:
	_cache.clear()


func generate(recipe: EngineRecipe) -> EngineVoice:
	var voice := _begin(recipe)
	for rpm in voice.rpm_bands:
		_append_band(voice, rpm)
	return _finish(voice)


func _begin(recipe: EngineRecipe) -> EngineVoice:
	var voice := EngineVoice.new(recipe.signature(), recipe)
	voice.sample_count = TABLE_SIZE
	voice.load_bands = PackedFloat32Array(LOAD_BANDS)
	voice.rpm_bands = _rpm_bands_for(recipe)
	_rng_state = _stable_seed(recipe.identity_seed)
	_runner_gains.clear()
	_runner_detune.clear()
	_global_peak = 0.000001
	for cylinder in recipe.cylinder_count:
		_runner_gains.append(0.88 + _random_unit() * 0.24)
		_runner_detune.append((_random_unit() * 2.0 - 1.0) * 0.035)
	return voice


func _append_band(voice: EngineVoice, rpm: float) -> void:
	var layers: Array = []
	for load in voice.load_bands:
		var table := _build_cycle_table(voice.recipe, rpm, load, _runner_gains, _runner_detune)
		for sample in table:
			_global_peak = maxf(_global_peak, absf(sample))
		layers.append(table)
	voice.tables.append(layers)


func _finish(voice: EngineVoice) -> EngineVoice:
	var table_gain := TABLE_GAIN / _global_peak
	for rpm_index in voice.tables.size():
		for load_index in (voice.tables[rpm_index] as Array).size():
			var table: PackedFloat32Array = voice.tables[rpm_index][load_index]
			for index in table.size():
				table[index] *= table_gain
	voice.mechanical = _build_mechanical_table(voice.recipe)
	return voice


func _rpm_bands_for(recipe: EngineRecipe) -> PackedFloat32Array:
	var bands := PackedFloat32Array()
	for ratio in RPM_BAND_RATIOS:
		bands.append(lerpf(recipe.idle_rpm, recipe.redline_rpm, ratio))
	return bands


func _build_cycle_table(
	recipe: EngineRecipe,
	rpm: float,
	load: float,
	runner_gains: PackedFloat32Array,
	runner_detune: PackedFloat32Array
) -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(TABLE_SIZE)
	var cylinder_count := recipe.cylinder_count
	var cycle_seconds := 120.0 / rpm
	var combustion_gain := 0.28 + load * 0.72
	for index in TABLE_SIZE:
		var phase := float(index) / float(TABLE_SIZE)
		var sample := 0.0
		for firing_slot in cylinder_count:
			var cylinder := recipe.firing_order[firing_slot]
			var event_phase := float(firing_slot) / float(cylinder_count)
			event_phase = fposmod(event_phase + runner_detune[cylinder] / float(cylinder_count), 1.0)
			var elapsed_phase := fposmod(phase - event_phase, 1.0)
			for history in HISTORY_CYCLES:
				var elapsed := (elapsed_phase + float(history)) * cycle_seconds
				if elapsed <= MAX_IMPULSE_SECONDS:
					sample += _exhaust_impulse(elapsed, recipe, load) * runner_gains[cylinder] * combustion_gain
		table[index] = sample / float(cylinder_count)
	_remove_dc(table)
	return table


## One exhaust event: a fast pressure front, a negative reflection, and three
## decaying resonances (chamber volume, primary pipe, and the cam/load-driven
## bark and crack). Frequencies come from the recipe, not from a fixed palette.
func _exhaust_impulse(time: float, recipe: EngineRecipe, load: float) -> float:
	var primary_hz := 343.0 / (4.0 * maxf(recipe.exhaust_primary_m, 0.12))
	var chamber_hz := 92.0 + 72.0 / maxf(recipe.displacement_l, 0.25) + recipe.exhaust_body * 56.0
	var bark_hz := primary_hz * (1.78 + recipe.cam * 0.24)
	var crack_hz := primary_hz * (3.15 + recipe.cam * 0.55)
	var pressure_front := exp(-time / (0.0014 + recipe.cam * 0.0009))
	var pressure_back := -0.58 * exp(-time / (0.0035 + recipe.exhaust_body * 0.0020))
	var chamber := 0.72 * exp(-time / (0.020 + recipe.exhaust_body * 0.018)) * sin(TAU * chamber_hz * time + 0.18)
	var primary := 0.56 * exp(-time / (0.014 + recipe.exhaust_body * 0.010)) * sin(TAU * primary_hz * time + 0.65)
	var bark := (0.20 + load * 0.16) * exp(-time / 0.010) * sin(TAU * bark_hz * time + 0.30)
	var crack := recipe.cam * load * 0.13 * exp(-time / 0.005) * sin(TAU * crack_hz * time)
	return pressure_front + pressure_back + chamber + primary + bark + crack


func _build_mechanical_table(recipe: EngineRecipe) -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(TABLE_SIZE)
	var cylinders := float(recipe.cylinder_count)
	for index in TABLE_SIZE:
		var phase := float(index) / float(TABLE_SIZE)
		var crank := sin(TAU * phase * 2.0)
		var valvetrain := sin(TAU * phase * cylinders * 2.0 + 0.4)
		var gear := sin(TAU * phase * (cylinders * 3.0 + 1.0))
		table[index] = crank * 0.38 + valvetrain * (0.38 + recipe.cam * 0.18) + gear * 0.12
	return table


func _remove_dc(table: PackedFloat32Array) -> void:
	var mean := 0.0
	for sample in table:
		mean += sample
	mean /= float(table.size())
	for index in table.size():
		table[index] -= mean


## FNV-1a over the identity seed. Deliberately not RandomNumberGenerator: the
## sequence must stay stable across Godot versions for cached voices and tests.
func _stable_seed(text: String) -> int:
	var hash_value := 2166136261
	for byte in text.to_utf8_buffer():
		hash_value = ((hash_value ^ int(byte)) * 16777619) & 0xffffffff
	return maxi(1, hash_value)


func _random_unit() -> float:
	_rng_state = int((1664525 * _rng_state + 1013904223) & 0xffffffff)
	return float(_rng_state) / 4294967295.0
