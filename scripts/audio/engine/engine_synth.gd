class_name EngineSynth
extends RefCounted

## Performs a generated EngineVoice. `set_controls` runs once per audio block
## and pre-blends the band tables; `render_sample` is the hot path and contains
## no trig, no exp, no allocation and no dictionary lookup.

const TABLE_SIZE := 1024
const SINE_SIZE := 1024
const OUTPUT_GAIN := 0.72
## The generated tables are a 720-degree firing cycle, so one cycle is 120/rpm
## seconds regardless of cylinder count.
const CYCLE_REVOLUTIONS := 120.0

var _tables: Array = []
var _mechanical: PackedFloat32Array = PackedFloat32Array()
var _rpm_bands: PackedFloat32Array = PackedFloat32Array()
var _load_bands: PackedFloat32Array = PackedFloat32Array()
var _blended := PackedFloat32Array()
var _sine_table := PackedFloat32Array()
var _sample_rate := 48000.0
var _idle_rpm := 1050.0
var _redline_rpm := 7600.0
var _turbo_amount := 0.0
var _exhaust_body := 0.44
var _cycle_phase := 0.0
var _cycle_increment := 0.0
var _turbo_phase := 0.0
var _turbo_increment := 0.0
var _noise_state := 1
var _exhaust_lp := 0.0
var _body_lp := 0.0
var _noise_lp := 0.0
var _last_exhaust := 0.0
var _exhaust_alpha := 0.2
var _body_alpha := 0.01
var _noise_alpha := 0.1
var _load := 0.0
var _throttle := 0.0
var _rpm_ratio := 0.0


func configure(voice: EngineVoice, sample_rate: int) -> void:
	var recipe := voice.recipe
	_tables = voice.tables
	_mechanical = voice.mechanical
	_rpm_bands = voice.rpm_bands
	_load_bands = voice.load_bands
	_sample_rate = float(maxi(sample_rate, 1))
	_idle_rpm = recipe.idle_rpm
	_redline_rpm = recipe.redline_rpm
	_turbo_amount = recipe.turbo
	_exhaust_body = recipe.exhaust_body
	_cycle_phase = 0.0
	_turbo_phase = 0.0
	_noise_state = _seed_from_signature(voice.signature)
	_exhaust_lp = 0.0
	_body_lp = 0.0
	_noise_lp = 0.0
	_last_exhaust = 0.0
	_blended.resize(TABLE_SIZE)
	_sine_table.resize(SINE_SIZE)
	for index in SINE_SIZE:
		_sine_table[index] = sin(TAU * float(index) / float(SINE_SIZE))
	set_controls(_idle_rpm, 0.1, 0.0)


## Called once per generated audio block, not per sample.
func set_controls(rpm: float, load: float, throttle: float) -> void:
	var bounded_rpm := clampf(rpm, _idle_rpm * 0.72, _redline_rpm * 1.04)
	_load = clampf(load, 0.0, 1.0)
	_throttle = clampf(throttle, 0.0, 1.0)
	_rpm_ratio = bounded_rpm / _redline_rpm
	_cycle_increment = bounded_rpm / CYCLE_REVOLUTIONS / _sample_rate
	_turbo_increment = (680.0 + _rpm_ratio * 4200.0) / _sample_rate
	_exhaust_alpha = _one_pole_alpha(850.0 + _rpm_ratio * 4300.0 + _load * 1800.0)
	_body_alpha = _one_pole_alpha(72.0 + _exhaust_body * 95.0)
	_noise_alpha = _one_pole_alpha(500.0 + bounded_rpm * 0.42)
	_blend_bands(bounded_rpm)


func render_sample() -> float:
	var position := _cycle_phase * float(TABLE_SIZE)
	var index := int(position) % TABLE_SIZE
	var next_index := (index + 1) % TABLE_SIZE
	var fraction: float = position - floor(position)
	var exhaust := lerpf(_blended[index], _blended[next_index], fraction)
	var exhaust_delta := exhaust - _last_exhaust
	_last_exhaust = exhaust
	var mechanical := lerpf(_mechanical[index], _mechanical[next_index], fraction)

	_exhaust_lp += (exhaust - _exhaust_lp) * _exhaust_alpha
	_body_lp += (_exhaust_lp - _body_lp) * _body_alpha
	var exhaust_band := _exhaust_lp - _body_lp * 0.42 + exhaust_delta * (0.9 + _load * 1.1)

	_noise_state = int((1664525 * _noise_state + 1013904223) & 0xffffffff)
	var raw_noise := float(_noise_state) / 2147483647.5 - 1.0
	_noise_lp += (raw_noise - _noise_lp) * _noise_alpha
	var air_noise := _noise_lp * (0.015 + _load * _rpm_ratio * 0.055)

	var turbo_position := _turbo_phase * float(SINE_SIZE)
	var turbo_index := int(turbo_position) % SINE_SIZE
	var turbo_next := (turbo_index + 1) % SINE_SIZE
	var turbo_wave := lerpf(_sine_table[turbo_index], _sine_table[turbo_next], turbo_position - floor(turbo_position))
	var turbo := turbo_wave * _turbo_amount * _throttle * _rpm_ratio * _rpm_ratio * 0.075

	var mechanical_gain := 0.035 + _rpm_ratio * 0.055 + (1.0 - _load) * 0.018
	var mixed := exhaust_band * (0.72 + _load * 0.34) + mechanical * mechanical_gain + air_noise + turbo
	var saturated := mixed / (1.0 + absf(mixed) * (0.30 + _load * 0.18))
	_cycle_phase = fposmod(_cycle_phase + _cycle_increment * (1.0 + _noise_lp * 0.0015), 1.0)
	_turbo_phase = fposmod(_turbo_phase + _turbo_increment, 1.0)
	return saturated * OUTPUT_GAIN


func _blend_bands(bounded_rpm: float) -> void:
	var rpm_mix := _band_mix(_rpm_bands, bounded_rpm)
	var load_mix := _band_mix(_load_bands, _load)
	var r0 := int(rpm_mix.x)
	var r1 := int(rpm_mix.y)
	var l0 := int(load_mix.x)
	var l1 := int(load_mix.y)
	var rt := rpm_mix.z
	var lt := load_mix.z
	var t00: PackedFloat32Array = _tables[r0][l0]
	var t01: PackedFloat32Array = _tables[r0][l1]
	var t10: PackedFloat32Array = _tables[r1][l0]
	var t11: PackedFloat32Array = _tables[r1][l1]
	for index in TABLE_SIZE:
		var low := lerpf(t00[index], t01[index], lt)
		var high := lerpf(t10[index], t11[index], lt)
		_blended[index] = lerpf(low, high, rt)


## Returns (lower_band, upper_band, mix) for a value between band centres.
func _band_mix(bands: PackedFloat32Array, value: float) -> Vector3:
	for index in bands.size() - 1:
		if value <= bands[index + 1]:
			var width := maxf(0.000001, bands[index + 1] - bands[index])
			return Vector3(index, index + 1, clampf((value - bands[index]) / width, 0.0, 1.0))
	var last := bands.size() - 1
	return Vector3(last, last, 0.0)


func _one_pole_alpha(cutoff_hz: float) -> float:
	return 1.0 - exp(-TAU * minf(cutoff_hz, _sample_rate * 0.42) / _sample_rate)


func _seed_from_signature(text: String) -> int:
	var result := 2166136261
	for byte in text.to_utf8_buffer():
		result = ((result ^ int(byte)) * 16777619) & 0xffffffff
	return maxi(1, result)
