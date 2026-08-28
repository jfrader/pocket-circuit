extends SceneTree

const SAMPLE_RATE := 22050
const OUTPUT_DIR := "res://assets/audio"
const TAU_F := TAU
const MENU_DURATION := 16.0
const MENU_CHORD_SECONDS := 2.0
const MENU_NOTE_SECONDS := 0.5
const MENU_CHORDS := [
	[57, 60, 64, 69],
	[53, 57, 60, 65],
	[48, 55, 60, 64],
	[55, 59, 62, 67],
	[50, 53, 57, 62],
	[52, 57, 60, 64],
	[53, 57, 60, 65],
	[55, 59, 62, 67],
]
const MENU_BASS_NOTES := [
	45, 52, 57, 52,
	41, 48, 53, 48,
	36, 43, 48, 43,
	43, 50, 55, 50,
	38, 45, 50, 45,
	40, 47, 52, 47,
	41, 48, 53, 48,
	43, 50, 55, 50,
]
const MENU_MELODY_NOTES := [
	69, -1, 72, 76,
	72, 69, -1, 67,
	67, -1, 72, 76,
	74, 71, -1, 67,
	69, -1, 65, 69,
	71, 72, 76, -1,
	72, 69, 67, 65,
	67, 71, 74, -1,
]


func _initialize() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("AUDIO_GENERATOR FAIL: could not create %s: %s" % [OUTPUT_DIR, error_string(directory_error)])
		quit(1)
		return

	var definitions: Array[Dictionary] = [
		{"name": "menu_loop", "duration": MENU_DURATION, "loop": true, "kind": "menu"},
		{"name": "race_loop", "duration": 4.0, "loop": true, "kind": "race"},
		{"name": "engine_loop", "duration": 0.5, "loop": true, "kind": "engine"},
		{"name": "countdown", "duration": 0.24, "loop": false, "kind": "countdown"},
		{"name": "go", "duration": 0.46, "loop": false, "kind": "go"},
		{"name": "ui_move", "duration": 0.075, "loop": false, "kind": "ui_move"},
		{"name": "ui_confirm", "duration": 0.14, "loop": false, "kind": "ui_confirm"},
		{"name": "drift", "duration": 0.34, "loop": false, "kind": "drift"},
		{"name": "boost", "duration": 0.42, "loop": false, "kind": "boost"},
		{"name": "impact", "duration": 0.28, "loop": false, "kind": "impact"},
		{"name": "hazard_warning", "duration": 0.52, "loop": false, "kind": "hazard_warning"},
	]

	for definition: Dictionary in definitions:
		var save_error := _render_sound(definition)
		if save_error != OK:
			push_error("AUDIO_GENERATOR FAIL: %s: %s" % [definition["name"], error_string(save_error)])
			quit(1)
			return
		print("Generated %s/%s.wav" % [OUTPUT_DIR, definition["name"]])
	quit(0)


func _render_sound(definition: Dictionary) -> Error:
	var duration := float(definition["duration"])
	var sample_count := maxi(2, int(round(duration * SAMPLE_RATE)))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	for index in sample_count:
		var time := float(index) / float(SAMPLE_RATE)
		var sample := clampf(_sample(String(definition["kind"]), time, duration, index), -0.92, 0.92)
		pcm.encode_s16(index * 2, int(round(sample * 32767.0)))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	if bool(definition["loop"]):
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = sample_count - 1
	return stream.save_to_wav("%s/%s.wav" % [OUTPUT_DIR, definition["name"]])


func _sample(kind: String, time: float, duration: float, index: int) -> float:
	match kind:
		"menu":
			return _menu_music(time, duration)
		"race":
			var drive := _sine(62.0, time) + 0.48 * _sine(124.0, time) + 0.16 * _sine(248.0, time)
			var motor_gate := 0.52 + 0.48 * cos(TAU_F * 4.0 * time)
			var grit := _sine(403.0, time) * _sine(17.0, time)
			return drive * (0.055 + motor_gate * 0.045) + grit * 0.025
		"engine":
			return (_sine(72.0, time) + 0.5 * _sine(144.0, time) + 0.22 * _sine(288.0, time)) * 0.105
		"countdown":
			var envelope := _attack_release(time, duration, 0.012, 0.09)
			return (_sine(330.0, time) + 0.26 * _sine(660.0, time)) * envelope * 0.21
		"go":
			var envelope := _attack_release(time, duration, 0.018, 0.18)
			var frequency := lerpf(280.0, 540.0, time / duration)
			return (_sine(frequency, time) + 0.24 * _sine(frequency * 2.0, time)) * envelope * 0.23
		"ui_move":
			return _sine(510.0, time) * _attack_release(time, duration, 0.004, 0.045) * 0.12
		"ui_confirm":
			var envelope := _attack_release(time, duration, 0.005, 0.065)
			return (_sine(420.0, time) + 0.38 * _sine(630.0, time)) * envelope * 0.16
		"drift":
			var envelope := _attack_release(time, duration, 0.025, 0.16)
			return (_noise(index) * 0.7 + _sine(190.0, time) * 0.3) * envelope * 0.16
		"boost":
			var envelope := _attack_release(time, duration, 0.018, 0.2)
			var sweep := _sine(lerpf(95.0, 310.0, time / duration), time)
			return (sweep * 0.62 + _noise(index) * 0.38) * envelope * 0.2
		"impact":
			var envelope := exp(-18.0 * time) * minf(1.0, time / 0.003)
			return (_sine(74.0, time) * 0.72 + _noise(index) * 0.28) * envelope * 0.3
		"hazard_warning":
			var envelope := _attack_release(time, duration, 0.012, 0.1)
			var alternating := 360.0 if fmod(time, 0.24) < 0.12 else 270.0
			return (_sine(alternating, time) + 0.22 * _sine(alternating * 2.0, time)) * envelope * 0.18
	return 0.0


func _menu_music(time: float, duration: float) -> float:
	var chord_position := time / MENU_CHORD_SECONDS
	var chord_index := posmod(floori(chord_position), MENU_CHORDS.size())
	var next_chord_index := (chord_index + 1) % MENU_CHORDS.size()
	var chord_phase := fmod(time, MENU_CHORD_SECONDS) / MENU_CHORD_SECONDS
	var chord_blend := smoothstep(0.72, 1.0, chord_phase)
	var current_chord := _menu_chord(MENU_CHORDS[chord_index], time, duration)
	var next_chord := _menu_chord(MENU_CHORDS[next_chord_index], time, duration)
	var pad := lerpf(current_chord, next_chord, chord_blend) * 0.085

	var note_index := posmod(floori(time / MENU_NOTE_SECONDS), MENU_BASS_NOTES.size())
	var note_time := fmod(time, MENU_NOTE_SECONDS)
	var note_envelope := _attack_release(note_time, MENU_NOTE_SECONDS, 0.025, 0.16)
	var bass_frequency := _midi_frequency(MENU_BASS_NOTES[note_index])
	var bass := (_sine(bass_frequency, note_time) + 0.2 * _sine(bass_frequency * 2.0, note_time)) * note_envelope * 0.035

	var melody_note: int = MENU_MELODY_NOTES[note_index]
	var melody := 0.0
	if melody_note >= 0:
		var melody_frequency := _midi_frequency(melody_note)
		var melody_envelope := _attack_release(note_time, MENU_NOTE_SECONDS, 0.035, 0.14)
		melody = (_sine(melody_frequency, note_time) + 0.16 * _sine(melody_frequency * 2.0, note_time)) * melody_envelope * 0.052
	var seam_fade := minf(smoothstep(0.0, 0.008, time), smoothstep(0.0, 0.008, duration - time))
	return (pad + bass + melody) * seam_fade


func _menu_chord(chord: Array, time: float, duration: float) -> float:
	var sample := 0.0
	for midi_note: int in chord:
		var frequency := _loop_frequency(_midi_frequency(midi_note), duration)
		sample += _sine(frequency, time) + 0.14 * _sine(frequency * 2.0, time)
	return sample / float(chord.size())


func _midi_frequency(midi_note: int) -> float:
	return 440.0 * pow(2.0, (float(midi_note) - 69.0) / 12.0)


func _loop_frequency(frequency: float, duration: float) -> float:
	return round(frequency * duration) / duration


func _sine(frequency: float, time: float) -> float:
	return sin(TAU_F * frequency * time)


func _noise(index: int) -> float:
	var value := sin(float(index) * 12.9898 + 4.1414) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0


func _attack_release(time: float, duration: float, attack: float, release: float) -> float:
	var attack_gain := clampf(time / maxf(attack, 0.0001), 0.0, 1.0)
	var release_gain := clampf((duration - time) / maxf(release, 0.0001), 0.0, 1.0)
	return attack_gain * release_gain
