class_name UiVoiceGenerator
extends RefCounted

## Generates the interface and race blips: short, rounded, toy-scale tones with a
## fast attack and no sample material. Unlike the vehicle voices these are fixed
## and global — a menu tick should sound the same every time.

const SAMPLE_RATE := 22050
const TARGET_PEAK := 0.8
## Attack long enough to avoid a click, short enough to stay crisp.
const ATTACK_SECONDS := 0.002
const TAIL_SECONDS := 0.008
## name -> [start_hz, end_hz, seconds, decay, harmonic, click]
const VOICES := {
	"ui_move": [1180.0, 1180.0, 0.055, 0.012, 0.15, 0.25],
	"ui_confirm": [760.0, 1180.0, 0.130, 0.045, 0.30, 0.08],
	"countdown": [620.0, 620.0, 0.160, 0.070, 0.25, 0.05],
	"go": [880.0, 1320.0, 0.340, 0.160, 0.40, 0.12],
}

var _rng_state := 1


func names() -> Array:
	return VOICES.keys()


func generate(sound_name: String) -> OneShotVoice:
	if not VOICES.has(sound_name):
		return OneShotVoice.new("ui-v1:unknown", SAMPLE_RATE)
	var settings: Array = VOICES[sound_name]
	_rng_state = _stable_seed(sound_name)
	var voice := OneShotVoice.new("ui-v1:" + sound_name, SAMPLE_RATE)
	voice.tier_thresholds = PackedFloat32Array([1.0])
	voice.tiers.append(_render(settings))
	return voice


func _render(settings: Array) -> PackedFloat32Array:
	var start_hz := float(settings[0])
	var end_hz := float(settings[1])
	var duration := float(settings[2])
	var decay := float(settings[3])
	var harmonic := float(settings[4])
	var click := float(settings[5])
	var count := int(duration * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for index in count:
		var time := float(index) / float(SAMPLE_RATE)
		var progress := time / maxf(duration, 0.0001)
		phase += TAU * lerpf(start_hz, end_hz, progress) / float(SAMPLE_RATE)
		var envelope := smoothstep(0.0, ATTACK_SECONDS, time) * exp(-time / decay)
		var sample := sin(phase) + sin(phase * 2.0) * harmonic
		sample += _noise() * click * exp(-time / 0.0015)
		samples[index] = sample * envelope
	_apply_tail_fade(samples, duration)
	_normalize(samples, TARGET_PEAK)
	return samples


func _apply_tail_fade(samples: PackedFloat32Array, duration: float) -> void:
	var fade := mini(int(TAIL_SECONDS * float(SAMPLE_RATE)), samples.size())
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
