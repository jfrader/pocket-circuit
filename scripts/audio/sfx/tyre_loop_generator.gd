class_name TyreLoopGenerator
extends RefCounted

## Builds the shared PCM loops used by positional vehicle emitters. Generation
## happens once per surface profile; opponents only pitch and fade WAV playback.

const DriftSynthScript := preload("res://scripts/audio/sfx/drift_synth.gd")
const SAMPLE_RATE := 22050
const LOOP_FRAMES := 16384
const SETTLE_FRAMES := 4096
const CROSSFADE_FRAMES := 1024
const BLOCK := 256


static func generate(profile: Dictionary, seed_value: int = 1037) -> AudioStreamWAV:
	var synth = DriftSynthScript.new()
	synth.configure(SAMPLE_RATE, seed_value)
	synth.set_surface_profile(profile)
	var rendered := PackedFloat32Array()
	rendered.resize(LOOP_FRAMES + CROSSFADE_FRAMES)
	for index in SETTLE_FRAMES + rendered.size():
		if index % BLOCK == 0:
			synth.set_state(0.82, 0.32, 0.72, 1.0, float(BLOCK) / float(SAMPLE_RATE))
		if index >= SETTLE_FRAMES:
			rendered[index - SETTLE_FRAMES] = synth.render_sample()

	# Continue the generated noise across the loop boundary, then blend back to
	# the original opening. The final frame and first frame are consecutive DSP
	# samples, avoiding a click without normalizing away surface differences.
	for index in CROSSFADE_FRAMES:
		var blend := smoothstep(0.0, float(CROSSFADE_FRAMES - 1), float(index))
		rendered[index] = lerpf(rendered[LOOP_FRAMES + index], rendered[index], blend)

	var pcm := PackedByteArray()
	pcm.resize(LOOP_FRAMES * 2)
	for index in LOOP_FRAMES:
		pcm.encode_s16(index * 2, int(round(clampf(rendered[index], -1.0, 1.0) * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = LOOP_FRAMES - 1
	stream.data = pcm
	return stream
