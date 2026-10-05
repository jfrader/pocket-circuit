class_name PursuitVoiceGenerator
extends RefCounted

const OneShotVoice := preload("res://scripts/audio/sfx/one_shot_voice.gd")

## Generates a pursuit tension cue: a low pulsing tone that rises in pitch and urgency
## as capture exposure grows. One voice, strength controls the character (pitch sweep,
## pulse rate, brightness). Played with volume=exposure from controller.
## Cuts immediately when exposure resets (gap opens).
## Headless safe, no external assets. Deterministic.

const SAMPLE_RATE := 22050
const DURATION := 0.18  # short pulse, retriggered by caller for rising feel
const TARGET_PEAK := 0.75

var _rng_state := 1

func generate(seed_text: String) -> OneShotVoice:
	_rng_state = _stable_seed(seed_text)
	var voice := OneShotVoice.new(_signature(seed_text), SAMPLE_RATE)
	var thresholds := PackedFloat32Array([1.0])
	voice.tier_thresholds = thresholds
	voice.tiers.append(_render(0.5))  # base, strength applied at play via tier/volume
	return voice

func generate_stinger(name: String) -> OneShotVoice:
	_rng_state = _stable_seed(name)
	var voice := OneShotVoice.new(_signature(name), SAMPLE_RATE)
	var thresholds := PackedFloat32Array([1.0])
	voice.tier_thresholds = thresholds
	voice.tiers.append(_render_stinger(name))
	return voice

func _render(strength: float) -> PackedFloat32Array:
	var count := int(DURATION * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var base_hz := lerpf(180.0, 320.0, strength)
	var pulse_rate := lerpf(4.0, 12.0, strength)
	for index in count:
		var time := float(index) / float(SAMPLE_RATE)
		var env := smoothstep(0.0, 0.01, time) * (1.0 - smoothstep(0.12, DURATION, time))
		var pulse := sin(TAU * pulse_rate * time) * 0.5 + 0.5
		var tone := sin(TAU * base_hz * time) * env * pulse * 0.6
		tone += _noise_click(time, strength) * 0.15
		samples[index] = tone
	_normalize(samples, TARGET_PEAK)
	return samples

func _render_stinger(name: String) -> PackedFloat32Array:
	var count := int(0.4 * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var hz := 660.0 if "won" in name.to_lower() else 520.0
	var end_hz := 880.0 if "won" in name.to_lower() else 420.0
	for index in count:
		var time := float(index) / float(SAMPLE_RATE)
		var env := smoothstep(0.0, 0.01, time) * (1.0 - smoothstep(0.25, 0.4, time))
		var f := lerpf(hz, end_hz, smoothstep(0.0, 0.3, time))
		var tone := sin(TAU * f * time) * env * 0.8
		if "capture" in name.to_lower():
			tone += sin(TAU * (f*1.5) * time) * env * 0.3 * (1.0 - time*2)
		samples[index] = tone
	_apply_fade(samples)
	_normalize(samples, 0.9)
	return samples

func _noise_click(time: float, s: float) -> float:
	if time > 0.03: return 0.0
	_rng_state = int((1664525 * _rng_state + 1013904223) & 0xffffffff)
	return float(_rng_state) / 2147483647.5 * s * (1.0 - time/0.03)

func _apply_fade(samples: PackedFloat32Array) -> void:
	var fade := int(0.02 * float(SAMPLE_RATE))
	for index in fade:
		var pos := samples.size() - fade + index
		if pos >= 0:
			samples[pos] *= 1.0 - float(index) / float(fade)

func _normalize(samples: PackedFloat32Array, peak: float) -> void:
	var cur := 0.000001
	for s in samples:
		cur = maxf(cur, absf(s))
	var g := peak / cur
	for i in samples.size():
		samples[i] = clampf(samples[i] * g, -1.0, 1.0)

func _stable_seed(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xffffffff
	return maxi(1, h)

func _signature(text: String) -> String:
	return "pursuit-v1:%08x" % _stable_seed(text)
