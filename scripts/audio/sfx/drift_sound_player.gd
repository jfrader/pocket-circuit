class_name DriftSoundPlayer
extends Node

## Owns the local car's continuous drift voice: one DriftSynth performed through
## an AudioStreamGenerator on the SFX bus. AudioDirector feeds it slip, speed and
## grip; it renders nothing once the slide has died away.

signal buffer_underrun(count: int)

const SAMPLE_RATE := 22050
const BUFFER_SECONDS := 0.12
const MAX_FRAMES_PER_FILL := 4096
## A queue with all but this many frames free has run dry; the priming frame is
## excluded.
const STARVATION_SLACK_FRAMES := 8
## Mix trim for the scrub bed. Measured against the engine voice at full chat
## (-14.0 dBFS): a full slide lands with it while ordinary cornering stays below.
const MIX_DB := -2.0
const SILENCE_DB := -80.0
## Below this the voice renders nothing at all, so a car tracking straight costs
## no DSP.
const AUDIBLE_THRESHOLD := 0.01

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _synth := DriftSynth.new()
var _buffer := PackedVector2Array()
var _scrub := 0.0
var _screech := 0.0
var _speed_ratio := 0.0
var _grip := 1.15
var _prepared := false
var _headless := false
var _underruns := 0
var _capacity := 0
var _primed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name().to_lower() == "headless"
	_synth.configure(SAMPLE_RATE, 20260921)


## Called by AudioDirector once per frame with the local car's state.
func set_state(scrub: float, screech: float, speed_ratio: float, grip: float, surface_profile: Dictionary, delta: float) -> void:
	_scrub = clampf(scrub, 0.0, 1.0)
	_screech = clampf(screech, 0.0, 1.0)
	_speed_ratio = clampf(speed_ratio, 0.0, 1.0)
	_grip = grip
	_synth.set_surface_profile(surface_profile)
	_synth.set_state(_scrub, _screech, _speed_ratio, _grip, delta)
	if _synth.get_level() <= AUDIBLE_THRESHOLD:
		stop()
		return
	start()


func start() -> void:
	if _headless or not _ensure_player():
		return
	if not _player.playing:
		_player.play()
		_primed = false


func stop() -> void:
	if _player != null and _player.playing:
		_player.stop()
	_primed = false


func is_audible() -> bool:
	return _player != null and _player.playing


func get_underrun_count() -> int:
	return _underruns


func _process(_delta: float) -> void:
	if _headless or not _prepared or not is_audible():
		return
	var available := _playback.get_frames_available()
	# get_frames_available() is free space: 0 is a full queue, which is healthy.
	if _primed and available >= _capacity - STARVATION_SLACK_FRAMES:
		_underruns += 1
		buffer_underrun.emit(_underruns)
	if available <= 0:
		return
	_fill_buffer(mini(available, MAX_FRAMES_PER_FILL))
	if _playback.push_buffer(_buffer):
		_primed = true


func _ensure_player() -> bool:
	if _player != null:
		return _prepared
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = float(SAMPLE_RATE)
	stream.buffer_length = BUFFER_SECONDS
	_capacity = int(BUFFER_SECONDS * float(SAMPLE_RATE))
	_player = AudioStreamPlayer.new()
	_player.name = "DriftVoicePlayer"
	_player.bus = &"SFX"
	_player.stream = stream
	_player.volume_db = MIX_DB
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		_player.stop()
		return false
	_prepared = true
	return true


func _fill_buffer(frames: int) -> void:
	_buffer.resize(frames)
	for index in frames:
		var sample := _synth.render_sample()
		_buffer[index] = Vector2(sample, sample)


func _exit_tree() -> void:
	if _player != null:
		_player.stop()
		_player.stream = null
