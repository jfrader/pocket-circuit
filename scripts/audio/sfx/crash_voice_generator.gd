class_name CrashVoiceGenerator
extends RefCounted

## Generates a toy-car crash: a sharp onset, five inharmonic body resonances, a
## mass-scaled thud and a metal/plastic rattle. Heavier cars ring lower, battered
## cars rattle more, and the voice is seeded by the vehicle id so a car always
## crashes the same way.
##
## Each resonance is an exponentially decaying sinusoid rendered by recurrence
## (two multiplies per sample) rather than sin/exp per sample, so a full voice
## costs tens of milliseconds and can be warmed at the loading boundary.

const SAMPLE_RATE := 22050
const DURATION := 0.55
const TARGET_PEAK := 0.85
## Representative strength, and the upper bound that selects, each tier.
const TIER_STRENGTHS: Array[float] = [0.15, 0.40, 0.70, 1.0]
const TIER_THRESHOLDS: Array[float] = [0.30, 0.58, 0.82, 1.0]
const MODE_RATIOS: Array[float] = [1.0, 2.41, 4.31, 7.34, 11.2]
const MODE_DECAYS: Array[float] = [0.105, 0.072, 0.048, 0.030, 0.018]
const MODE_AMPS: Array[float] = [1.0, 0.58, 0.33, 0.18, 0.10]
## Modes at or above this index are the bright, brittle part of the strike: held
## back on a light tap, opened up on a hard hit, so strength changes timbre and
## not only loudness.
const BRIGHT_MODE_FIRST := 2
const RATTLE_MAX := 9
const ONSET_SECONDS := 0.02

var _rng_state := 1


func generate(stats: VehicleStats, seed_text: String) -> OneShotVoice:
	var voice := OneShotVoice.new(_signature(seed_text), SAMPLE_RATE)
	var thresholds := PackedFloat32Array()
	for value in TIER_THRESHOLDS:
		thresholds.append(value)
	voice.tier_thresholds = thresholds
	for tier_index in TIER_STRENGTHS.size():
		_rng_state = _stable_seed("%s|%d" % [seed_text, tier_index])
		voice.tiers.append(_render_tier(stats, TIER_STRENGTHS[tier_index]))
	return voice


func _render_tier(stats: VehicleStats, strength: float) -> PackedFloat32Array:
	var count := int(DURATION * float(SAMPLE_RATE))
	var mass_norm := clampf(inverse_lerp(0.65, 1.30, stats.mass), 0.0, 1.0)
	var fragility := clampf(inverse_lerp(80.0, 40.0, stats.durability), 0.0, 1.0)
	var base_hz := lerpf(430.0, 235.0, mass_norm)
	var detune := _random_unit() * 2.0 - 1.0
	var mode_count := MODE_RATIOS.size() + 1
	var mode_c1 := PackedFloat32Array()
	var mode_c2 := PackedFloat32Array()
	var mode_previous := PackedFloat32Array()
	var mode_current := PackedFloat32Array()
	mode_c1.resize(mode_count)
	mode_c2.resize(mode_count)
	mode_previous.resize(mode_count)
	mode_current.resize(mode_count)
	_configure_mode(mode_c1, mode_c2, mode_previous, mode_current, 0, base_hz, MODE_DECAYS[0], MODE_AMPS[0] * (0.6 + 0.4 * strength) * 0.55)
	for mode in MODE_RATIOS.size():
		var mode_gain := (0.6 + 0.4 * strength) if mode < BRIGHT_MODE_FIRST else lerpf(0.30, 1.25, strength)
		_configure_mode(mode_c1, mode_c2, mode_previous, mode_current, mode, base_hz * MODE_RATIOS[mode] * (1.0 + detune * 0.02), MODE_DECAYS[mode], MODE_AMPS[mode] * mode_gain * 0.55)
	var thud_index := mode_count - 1
	_configure_mode(mode_c1, mode_c2, mode_previous, mode_current, thud_index, lerpf(135.0, 78.0, mass_norm), 0.085, 0.42 * (0.55 + 0.45 * strength) * lerpf(0.9, 1.15, mass_norm))
	# The rattle is rendered separately and only inside each click's short window,
	# so the main loop never scans inactive clicks.
	var rattle := _render_rattle(count, strength, fragility)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var onset_end := int(ONSET_SECONDS * float(SAMPLE_RATE))
	for index in count:
		var sample := _onset(float(index) / float(SAMPLE_RATE), strength) if index < onset_end else 0.0
		for mode in mode_count:
			var value := mode_c1[mode] * mode_current[mode] + mode_c2[mode] * mode_previous[mode]
			mode_previous[mode] = mode_current[mode]
			mode_current[mode] = value
			sample += value
		samples[index] = sample + rattle[index]
	_apply_tail_fade(samples)
	# Every tier is normalized to the same peak: strength changes the timbre, and
	# the caller's volume_scale owns how loud the hit actually is.
	_normalize(samples, TARGET_PEAK)
	return samples


## Sets one exponentially decaying sinusoid's recurrence coefficients and seed.
func _configure_mode(c1: PackedFloat32Array, c2: PackedFloat32Array, previous: PackedFloat32Array, current: PackedFloat32Array, index: int, freq: float, decay: float, amp: float) -> void:
	var w := TAU * clampf(freq, 1.0, float(SAMPLE_RATE) * 0.45) / float(SAMPLE_RATE)
	var envelope := exp(-1.0 / maxf(decay, 0.0001) / float(SAMPLE_RATE))
	c1[index] = 2.0 * cos(w) * envelope
	c2[index] = -envelope * envelope
	previous[index] = 0.0
	current[index] = amp * envelope * sin(w)


## Renders the debris clicks into their own buffer so the main loop only adds.
func _render_rattle(count: int, strength: float, fragility: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(count)
	var rattle := _build_rattle(strength, fragility)
	var times: PackedFloat32Array = rattle["times"]
	var tones: PackedFloat32Array = rattle["tones"]
	var amp := 0.30 * (0.35 + 0.65 * strength) * lerpf(0.5, 1.0, fragility)
	for click in times.size():
		var start := int(times[click] * float(SAMPLE_RATE))
		var span := int(0.046 * float(SAMPLE_RATE))
		for offset in span:
			var index := start + offset
			if index < 0 or index >= count:
				continue
			var elapsed := float(offset) / float(SAMPLE_RATE)
			buffer[index] += sin(TAU * tones[click] * (float(index) / float(SAMPLE_RATE))) * exp(-elapsed / 0.006) * amp
	return buffer


## Broadband strike transient. A harder hit cracks slightly longer.
func _onset(time: float, strength: float) -> float:
	if time > ONSET_SECONDS:
		return 0.0
	return _noise() * exp(-time / (0.0012 + 0.0008 * strength)) * (0.6 + 0.4 * strength)


func _build_rattle(strength: float, fragility: float) -> Dictionary:
	var count := int(round(lerpf(3.0, float(RATTLE_MAX), strength * (0.35 + 0.65 * fragility))))
	var times := PackedFloat32Array()
	var tones := PackedFloat32Array()
	for index in count:
		times.append(0.02 + pow(_random_unit(), 1.6) * 0.22)
		tones.append(lerpf(1400.0, 3200.0, _random_unit()))
	return {"times": times, "tones": tones}


func _apply_tail_fade(samples: PackedFloat32Array) -> void:
	var fade := int(0.012 * float(SAMPLE_RATE))
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


func _random_unit() -> float:
	_rng_state = int((1664525 * _rng_state + 1013904223) & 0xffffffff)
	return float(_rng_state) / 4294967295.0


func _stable_seed(text: String) -> int:
	var hash_value := 2166136261
	for byte in text.to_utf8_buffer():
		hash_value = ((hash_value ^ int(byte)) * 16777619) & 0xffffffff
	return maxi(1, hash_value)


func _signature(seed_text: String) -> String:
	return "crash-v1:%08x" % _stable_seed(seed_text)

