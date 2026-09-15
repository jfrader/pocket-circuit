extends SceneTree

const SAMPLE_RATE := 22050
const OUTPUT_DIR := "res://assets/audio"
const MENU_SCORE_PATH := "res://data/music/tiny_torque_level_004.score.json"
const MENU_SECTION_ID := "grid"
const RACE_SECTION_ID := "cruise"
const MENU_PHRASE_LOOPS := 3
const RACE_PHRASE_LOOPS := 3
const TAU_F := TAU

var _menu_events: Array[Dictionary] = []
var _race_events: Array[Dictionary] = []
var _menu_phrase_seconds := 16.0
var _race_phrase_seconds := 16.0
var _menu_duration := 16.0
var _race_duration := 16.0
var _ticks_per_second := 2160.0


func _initialize() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("AUDIO_GENERATOR FAIL: could not create %s: %s" % [OUTPUT_DIR, error_string(directory_error)])
		quit(1)
		return
	if not _load_catalog_score():
		quit(1)
		return

	var definitions: Array[Dictionary] = [
		{"name": "menu_loop", "duration": _menu_duration, "loop": true, "kind": "menu"},
		{"name": "race_loop", "duration": _race_duration, "loop": true, "kind": "race"},
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


func _load_catalog_score() -> bool:
	var raw := FileAccess.get_file_as_string(MENU_SCORE_PATH)
	if raw.is_empty():
		push_error("AUDIO_GENERATOR FAIL: missing catalog score %s" % MENU_SCORE_PATH)
		return false
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("AUDIO_GENERATOR FAIL: catalog score is not an object")
		return false
	var score: Dictionary = parsed
	var bpm := float(score.get("bpm", 0.0))
	var ticks_per_beat := float(score.get("ticksPerBeat", 0.0))
	if bpm <= 0.0 or ticks_per_beat <= 0.0:
		push_error("AUDIO_GENERATOR FAIL: catalog score missing tempo")
		return false
	_ticks_per_second = bpm * ticks_per_beat / 60.0
	_menu_events = _events_for_section(score, MENU_SECTION_ID)
	_race_events = _events_for_section(score, RACE_SECTION_ID)
	if _menu_events.is_empty() or _race_events.is_empty():
		return false
	_menu_phrase_seconds = _phrase_seconds_for_section(score, MENU_SECTION_ID)
	_race_phrase_seconds = _phrase_seconds_for_section(score, RACE_SECTION_ID)
	if _menu_phrase_seconds <= 0.0 or _race_phrase_seconds <= 0.0:
		push_error("AUDIO_GENERATOR FAIL: catalog phrase has no length")
		return false
	_menu_duration = _menu_phrase_seconds * float(MENU_PHRASE_LOOPS)
	_race_duration = _race_phrase_seconds * float(RACE_PHRASE_LOOPS)
	return true


func _section_named(score: Dictionary, section_id: String) -> Dictionary:
	for candidate: Variant in score.get("sections", []):
		if typeof(candidate) == TYPE_DICTIONARY and String(candidate.get("id", "")) == section_id:
			return candidate
	push_error("AUDIO_GENERATOR FAIL: catalog score missing section %s" % section_id)
	return {}


func _phrase_seconds_for_section(score: Dictionary, section_id: String) -> float:
	var section := _section_named(score, section_id)
	if section.is_empty():
		return 0.0
	return float(section.get("lengthTicks", 0.0)) / _ticks_per_second


func _events_for_section(score: Dictionary, section_id: String) -> Array[Dictionary]:
	var section := _section_named(score, section_id)
	var events: Array[Dictionary] = []
	if section.is_empty():
		return events
	for event_value: Variant in section.get("events", []):
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		events.append({
			"kind": String(event.get("kind", "")),
			"voice": String(event.get("voice", "")),
			"role": String(event.get("role", "")),
			"pitch": int(event.get("pitch", 0)),
			"velocity": clampf(float(event.get("velocity", 0.5)), 0.05, 1.0),
			"start": float(event.get("startTick", 0.0)) / _ticks_per_second,
			"duration": maxf(0.04, float(event.get("durationTicks", 1.0)) / _ticks_per_second),
		})
	if events.is_empty():
		push_error("AUDIO_GENERATOR FAIL: catalog section %s has no events" % section_id)
	return events


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
			return _score_music(_menu_events, _menu_phrase_seconds, time, duration, index)
		"race":
			return _score_music(_race_events, _race_phrase_seconds, time, duration, index)
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


func _score_music(events: Array[Dictionary], phrase_seconds: float, time: float, duration: float, index: int) -> float:
	var local := fmod(time, phrase_seconds)
	if local < 0.0:
		local += phrase_seconds
	var mix := 0.0
	for event: Dictionary in events:
		mix += _render_menu_event(event, local, index)
	var seam_fade := minf(smoothstep(0.0, 0.01, time), smoothstep(0.0, 0.01, duration - time))
	return mix * seam_fade


func _render_menu_event(event: Dictionary, time: float, index: int) -> float:
	var start := float(event["start"])
	var hold := float(event["duration"])
	var local := time - start
	if local < 0.0 or local > hold + 0.09:
		return 0.0
	var velocity := float(event["velocity"])
	var kind := String(event["kind"])
	var voice := String(event["voice"])
	if kind == "percussion":
		return _menu_percussion(voice, local, hold, velocity, index)
	var frequency := _midi_frequency(int(event["pitch"]))
	var is_lead := String(event["role"]) == "melody"
	if voice == "bass":
		var envelope := _attack_release(local, hold + 0.06, 0.008, 0.05)
		return (_sine(frequency, local) + 0.22 * _sine(frequency * 2.0, local)) * envelope * velocity * 0.11
	var attack := 0.006 if is_lead else 0.004
	var release := 0.05 if is_lead else 0.035
	var envelope := _attack_release(local, hold + 0.04, attack, release)
	var gain := 0.07 if is_lead else 0.028
	return (
		_sine(frequency, local)
		+ 0.28 * _sine(frequency * 2.0, local)
		+ 0.08 * _sine(frequency * 3.0, local)
	) * envelope * velocity * gain


func _menu_percussion(voice: String, local: float, hold: float, velocity: float, index: int) -> float:
	match voice:
		"kick":
			var envelope := exp(-14.0 * local) * minf(1.0, local / 0.004)
			var frequency := lerpf(148.0, 52.0, clampf(local / 0.09, 0.0, 1.0))
			return _sine(frequency, local) * envelope * velocity * 0.22
		"snare":
			var envelope := _attack_release(local, maxf(hold, 0.08), 0.002, 0.05)
			return (_noise(index) * 0.78 + _sine(198.0, local) * 0.22) * envelope * velocity * 0.12
		"hat":
			var envelope := _attack_release(local, 0.05, 0.001, 0.03)
			return _noise(index + 17) * envelope * velocity * 0.045
		"tom":
			var envelope := exp(-10.0 * local) * minf(1.0, local / 0.005)
			return _sine(lerpf(160.0, 90.0, clampf(local / 0.12, 0.0, 1.0)), local) * envelope * velocity * 0.14
	return 0.0


func _midi_frequency(midi_note: int) -> float:
	return 440.0 * pow(2.0, (float(midi_note) - 69.0) / 12.0)


func _sine(frequency: float, time: float) -> float:
	return sin(TAU_F * frequency * time)


func _noise(index: int) -> float:
	var value := sin(float(index) * 12.9898 + 4.1414) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0


func _attack_release(time: float, duration: float, attack: float, release: float) -> float:
	var attack_gain := clampf(time / maxf(attack, 0.0001), 0.0, 1.0)
	var release_gain := clampf((duration - time) / maxf(release, 0.0001), 0.0, 1.0)
	return attack_gain * release_gain
