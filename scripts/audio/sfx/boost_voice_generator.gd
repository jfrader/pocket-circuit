class_name BoostVoiceGenerator
extends RefCounted

## Generates a boost: an ignition transient, a sweeping whoosh, a rising whine
## and a low punch. The car's boost_power sets how long and how hard the whoosh
## reads, so a stronger machine has its own boost. One voice is enough: the call
## site always fires the same event, and playback adds small pitch variation.

const SAMPLE_RATE := 22050
const DURATION := 0.75
const TARGET_PEAK := 0.85
const SWEEP_STEP := 64

var _rng_state := 1


func generate(stats: VehicleStats, seed_text: String) -> OneShotVoice:
	_rng_state = _stable_seed(seed_text)
	var voice := OneShotVoice.new(_signature(seed_text), SAMPLE_RATE)
	var thresholds := PackedFloat32Array([1.0])
	voice.tier_thresholds = thresholds
	var power := clampf(inverse_lerp(450.0, 700.0, stats.boost_power), 0.0, 1.0)
	voice.tiers.append(_render(power))
	return voice


func _render(power: float) -> PackedFloat32Array:
	var count := int(DURATION * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var sweep := SweepBandPass.new()
	sweep.configure(SAMPLE_RATE)
	var whoosh_seconds := lerpf(0.42, 0.62, power)
	var whine_peak := lerpf(900.0, 1250.0, power)
	for index in count:
		var time := float(index) / float(SAMPLE_RATE)
		if index % SWEEP_STEP == 0:
			var sweep_t := clampf(time / maxf(whoosh_seconds, 0.001), 0.0, 1.0)
			sweep.set_cutoff(lerpf(320.0, 2400.0, smoothstep(0.0, 0.45, sweep_t)) * lerpf(1.0, 0.5, smoothstep(0.45, 1.0, sweep_t)))
		var whoosh_env := smoothstep(0.0, 0.03, time) * (1.0 - smoothstep(0.05, whoosh_seconds, time))
		var mix := sweep.process(_noise()) * whoosh_env * lerpf(0.8, 1.1, power)
		mix += _whine(time, whine_peak, power)
		mix += _punch(time, power)
		samples[index] = mix
	_apply_tail_fade(samples)
	_normalize(samples, TARGET_PEAK)
	return samples


func _whine(time: float, peak_hz: float, power: float) -> float:
	var freq := lerpf(220.0, peak_hz, smoothstep(0.0, 0.5, time))
	var env := smoothstep(0.0, 0.02, time) * (1.0 - smoothstep(0.08, 0.55, time))
	return sin(TAU * freq * time) * env * lerpf(0.12, 0.2, power)


func _punch(time: float, power: float) -> float:
	return sin(TAU * lerpf(85.0, 105.0, power) * time) * exp(-time / 0.07) * 0.35


func _apply_tail_fade(samples: PackedFloat32Array) -> void:
	var fade := int(0.02 * float(SAMPLE_RATE))
	for index in fade:
		var position := samples.size() - fade + index
		if position >= 0:
			samples[position] *= 1.0 - float(index) / float(fade)


func _normalize(samples: PackedFloat32Array, peak: float) -> void:
	var current := 0.000001
	for sample in samples:
		current = maxf(current, absf(sample))
	var gain := peak / current
	for index in samples.size():
		samples[index] = clampf(samples[index] * gain, -1.0, 1.0)


func _noise() -> float:
	_rng_state = int((1664525 * _rng_state + 1013904223) & 0xffffffff)
	return float(_rng_state) / 2147483647.5 - 1.0


func _stable_seed(text: String) -> int:
	var hash_value := 2166136261
	for byte in text.to_utf8_buffer():
		hash_value = ((hash_value ^ int(byte)) * 16777619) & 0xffffffff
	return maxi(1, hash_value)


func _signature(seed_text: String) -> String:
	return "boost-v1:%08x" % _stable_seed(seed_text)


## Band-pass whose centre frequency can follow a sweep while rendering.
class SweepBandPass extends RefCounted:
	var _a0 := 1.0
	var _a1 := 0.0
	var _a2 := 0.0
	var _b1 := 0.0
	var _b2 := 0.0
	var _z1 := 0.0
	var _z2 := 0.0
	var _q := 1.4
	var _rate := 22050.0
	var _freq := 320.0

	func configure(sample_rate: float, q: float = 1.4) -> void:
		_rate = maxf(sample_rate, 1.0)
		_q = maxf(q, 0.1)
		set_cutoff(_freq)

	func set_cutoff(freq: float) -> void:
		_freq = freq
		var w0 := TAU * clampf(_freq, 20.0, _rate * 0.45) / _rate
		var alpha := sin(w0) / (2.0 * _q)
		var cos_w := cos(w0)
		var a0_inv := 1.0 / (1.0 + alpha)
		_a0 = alpha * a0_inv
		_a1 = 0.0
		_a2 = -alpha * a0_inv
		_b1 = -2.0 * cos_w * a0_inv
		_b2 = (1.0 - alpha) * a0_inv

	func process(x: float) -> float:
		var y := _a0 * x + _z1
		_z1 = _a1 * x - _b1 * y + _z2
		_z2 = _a2 * x - _b2 * y
		return y
