class_name DriftSynth
extends RefCounted

## Continuous tyre-scrub voice. A slip-driven, speed-brightened noise bed with a
## squeal that only appears at high slip, so a long drift evolves instead of
## retriggering a one-shot. Call `set_state` once per audio block; the block
## smoothing keeps the per-sample path free of extra work.

const SCRUB_CUT_MIN := 700.0
const SCRUB_CUT_MAX := 2600.0
const SQUEAL_CUT_MIN := 1900.0
const SQUEAL_CUT_MAX := 3400.0
const RUMBLE_CUT := 150.0
const SCRUB_Q := 1.1
const SQUEAL_Q := 7.0
## How fast the voice follows the car, in seconds. Fast enough to bite on drift
## entry, slow enough that per-block control updates cannot click.
const FOLLOW_TAU := 0.05
const DRIVE := 1.6
const GAIN := 1.0

var _sample_rate := 22050.0
var _noise_state := 1
var _scrub := BandPass.new()
var _squeal := BandPass.new()
var _rumble := LowPass.new()
var _scrub_level := 0.0
var _screech_level := 0.0
var _speed_ratio := 0.0
var _grip_ratio := 1.0


func configure(sample_rate: int, seed_value: int = 1) -> void:
	_sample_rate = float(maxi(sample_rate, 1))
	_noise_state = maxi(1, seed_value)
	_scrub_level = 0.0
	_screech_level = 0.0
	_speed_ratio = 0.0
	_grip_ratio = 1.0
	_scrub.configure(SCRUB_CUT_MIN, SCRUB_Q, _sample_rate)
	_squeal.configure(SQUEAL_CUT_MIN, SQUEAL_Q, _sample_rate)
	_rumble.configure(RUMBLE_CUT, _sample_rate)


## `scrub` is cornering load, `screech` is how hard a tyre is sliding, `speed_ratio`
## is 0..1 of top speed and `grip` the surface multiplier. `delta` is the block
## length in seconds. Keeping the two levels separate is what lets a corner stay
## subtle while a drift is loud.
func set_state(scrub: float, screech: float, speed_ratio: float, grip: float, delta: float) -> void:
	var blend := 1.0 - exp(-maxf(delta, 0.0) / FOLLOW_TAU)
	_scrub_level += (clampf(scrub, 0.0, 1.0) - _scrub_level) * blend
	_screech_level += (clampf(screech, 0.0, 1.0) - _screech_level) * blend
	_speed_ratio += (clampf(speed_ratio, 0.0, 1.0) - _speed_ratio) * blend
	_grip_ratio += (clampf(inverse_lerp(0.85, 1.40, grip), 0.0, 1.0) - _grip_ratio) * blend
	_scrub.set_cutoff(lerpf(SCRUB_CUT_MIN, SCRUB_CUT_MAX, _speed_ratio) * lerpf(1.0, 1.15, _grip_ratio))
	_squeal.set_cutoff(lerpf(SQUEAL_CUT_MIN, SQUEAL_CUT_MAX, _screech_level))


func render_sample() -> float:
	_noise_state = int((1664525 * _noise_state + 1013904223) & 0xffffffff)
	var noise := float(_noise_state) / 2147483647.5 - 1.0
	var scrub_amp := _scrub_level * (0.35 + 0.75 * _speed_ratio) * lerpf(0.85, 1.15, _grip_ratio)
	var squeal_amp := _screech_level * (0.15 + 0.5 * _speed_ratio)
	var rumble_amp := _scrub_level * _speed_ratio * 0.5
	var mixed := _scrub.process(noise) * scrub_amp * 0.9
	mixed += _squeal.process(noise) * squeal_amp * 0.5
	mixed += _rumble.process(noise) * rumble_amp * 0.7
	return tanh(mixed * DRIVE) * GAIN


## Loudest of the two layers, for deciding when the voice can stop rendering.
func get_level() -> float:
	return maxf(_scrub_level, _screech_level)


## Two-pole band-pass in transposed direct form II. Coefficients are rebuilt on
## control changes only, never per sample.
class BandPass extends RefCounted:
	var _a0 := 1.0
	var _a1 := 0.0
	var _a2 := 0.0
	var _b1 := 0.0
	var _b2 := 0.0
	var _z1 := 0.0
	var _z2 := 0.0
	var _freq := 1000.0
	var _q := 1.0
	var _rate := 22050.0

	func configure(freq: float, q: float, sample_rate: float) -> void:
		_freq = freq
		_q = maxf(q, 0.1)
		_rate = maxf(sample_rate, 1.0)
		_rebuild()

	func set_cutoff(freq: float) -> void:
		_freq = freq
		_rebuild()

	func process(x: float) -> float:
		var y := _a0 * x + _z1
		_z1 = _a1 * x - _b1 * y + _z2
		_z2 = _a2 * x - _b2 * y
		return y

	func _rebuild() -> void:
		var w0 := TAU * clampf(_freq, 20.0, _rate * 0.45) / _rate
		var alpha := sin(w0) / (2.0 * _q)
		var cos_w := cos(w0)
		var a0_inv := 1.0 / (1.0 + alpha)
		_a0 = alpha * a0_inv
		_a1 = 0.0
		_a2 = -alpha * a0_inv
		_b1 = -2.0 * cos_w * a0_inv
		_b2 = (1.0 - alpha) * a0_inv


## One-pole low-pass.
class LowPass extends RefCounted:
	var _alpha := 0.05
	var _z := 0.0

	func configure(freq: float, sample_rate: float) -> void:
		_alpha = clampf(TAU * freq / maxf(sample_rate, 1.0), 0.0, 1.0)

	func process(x: float) -> float:
		_z += (x - _z) * _alpha
		return _z
