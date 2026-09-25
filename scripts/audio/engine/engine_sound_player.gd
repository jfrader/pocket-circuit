class_name EngineSoundPlayer
extends Node

## Owns the local car's engine voice: one generated EngineVoice performed through
## an AudioStreamGenerator on the SFX bus. AudioDirector drives it and falls back
## to the legacy pitched loop when generation fails or the recipe is invalid.

signal voice_ready(signature: String)
signal generation_failed(reason: String)
signal fallback_activated(reason: String)
signal buffer_underrun(count: int)

const SAMPLE_RATE := 22050
const BUFFER_SECONDS := 0.12
## Bound one frame's fill so a stalled audio server cannot allocate unbounded.
const MAX_FRAMES_PER_FILL := 4096
## A buffer with all but this many frames free has run dry: the server drained
## everything queued before this frame rendered. Slack absorbs the priming frame.
const STARVATION_SLACK_FRAMES := 8
## Mix-balance curve, matching the range the legacy loop was tuned to.
const IDLE_DB := -18.0
const PEAK_DB := -2.0
const REV_EXPONENT := 0.68
const SILENCE_DB := -80.0
## How fast the duck follows the tyres, per frame. Smooth so it cannot click.
const DUCK_SMOOTHING := 0.18

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _synth: EngineSynth
var _drivetrain: EngineDrivetrainModel
var _voice: EngineVoice
var _buffer := PackedVector2Array()
var _prepared := false
var _fallback_reason := ""
var _paused := false
var _headless := false
var _underruns := 0
var _duck_db := 0.0
var _duck_target_db := 0.0
var _capacity := 0
## True once the first buffer has been queued, so the priming frame is not
## mistaken for a starvation event.
var _primed := false
var _state_speed := 0.0
var _state_max_speed := 680.0
var _state_load := 0.0
var _state_throttle := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name().to_lower() == "headless"
	_synth = EngineSynth.new()
	_drivetrain = EngineDrivetrainModel.new()


func _process(delta: float) -> void:
	if not _prepared or _paused or _headless:
		return
	if _playback == null or not _player.playing:
		return
	_drivetrain.step(_state_speed, _state_max_speed, _state_load, _state_throttle, delta)
	_synth.set_controls(_drivetrain.get_rpm(), _drivetrain.get_load(), _drivetrain.get_throttle())
	_duck_db = lerpf(_duck_db, _duck_target_db, DUCK_SMOOTHING)
	_player.volume_db = _current_volume_db()
	var available := _playback.get_frames_available()
	# get_frames_available() is free space: 0 means the queue is full, which is
	# the healthy steady state, not a fault.
	if _primed and available >= _capacity - STARVATION_SLACK_FRAMES:
		_underruns += 1
		buffer_underrun.emit(_underruns)
	if available <= 0:
		return
	_fill_buffer(mini(available, MAX_FRAMES_PER_FILL))
	if _playback.push_buffer(_buffer):
		_primed = true


## Generates the voice and wires the generator stream. Returns false (and leaves
## the caller on the legacy path) when the recipe cannot produce a voice.
func prepare(recipe: EngineRecipe, vehicle_id: String) -> bool:
	if recipe == null or not recipe.is_valid():
		_activate_fallback("invalid engine recipe for %s" % vehicle_id)
		return false
	var voice := EngineVoiceGenerator.generate_cached(recipe)
	if voice.tables.is_empty() or voice.mechanical.is_empty():
		_activate_fallback("voice generation produced no tables for %s" % vehicle_id)
		return false
	_voice = voice
	_synth.configure(_voice, SAMPLE_RATE)
	_drivetrain.configure(recipe)
	if not _ensure_player():
		_activate_fallback("AudioStreamGenerator unavailable")
		return false
	_prepared = true
	_fallback_reason = ""
	voice_ready.emit(_voice.signature)
	return true


## Called by AudioDirector every frame; the model is stepped in _process.
func set_vehicle_state(speed: float, max_speed: float, load: float, throttle: float, delta: float) -> void:
	_state_speed = maxf(0.0, speed)
	_state_max_speed = maxf(1.0, max_speed)
	_state_load = clampf(load, 0.0, 1.0)
	_state_throttle = clampf(throttle, 0.0, 1.0)
	# Drive the model here as well so tests and tools can advance state without
	# an audio server consuming buffers.
	if _prepared and not _paused:
		_drivetrain.step(_state_speed, _state_max_speed, _state_load, _state_throttle, delta)
		_synth.set_controls(_drivetrain.get_rpm(), _drivetrain.get_load(), _drivetrain.get_throttle())


## Duck applied while the tyres are sliding, so the scrub is not masked by the
## engine sitting at the same level.
func set_duck_db(decibels: float) -> void:
	_duck_target_db = minf(decibels, 0.0)


func start() -> void:
	if not _prepared:
		return
	if _headless or _player == null:
		return
	_player.volume_db = _current_volume_db()
	_bind_playback()


func stop() -> void:
	if _player != null and _player.playing:
		_player.stop()
	if _player != null:
		_player.volume_db = SILENCE_DB
	# The playback died with the player; writing into it after a later play()
	# would leave the voice silent while the player still reports playing.
	_playback = null
	_primed = false


func set_paused(paused: bool) -> void:
	_paused = paused
	if _player == null:
		return
	if paused:
		_player.volume_db = SILENCE_DB
	else:
		_player.volume_db = _current_volume_db()


func is_using_fallback() -> bool:
	return not _prepared


func get_fallback_reason() -> String:
	return _fallback_reason


func get_voice_signature() -> String:
	return _voice.signature if _voice != null else ""


func get_rpm() -> float:
	return _drivetrain.get_rpm() if _drivetrain != null else 0.0


func get_gear() -> int:
	return _drivetrain.get_gear() if _drivetrain != null else 0


func get_underrun_count() -> int:
	return _underruns


func get_voice_bytes() -> int:
	return _voice.table_bytes() if _voice != null else 0


func _ensure_player() -> bool:
	if _player == null:
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = float(SAMPLE_RATE)
		stream.buffer_length = BUFFER_SECONDS
		_capacity = int(BUFFER_SECONDS * float(SAMPLE_RATE))
		_player = AudioStreamPlayer.new()
		_player.name = "EngineVoicePlayer"
		_player.bus = &"Engine"
		_player.stream = stream
		_player.volume_db = SILENCE_DB
		add_child(_player)
	return _bind_playback()


## get_stream_playback() is only valid while the player is active, and every
## (re)play hands back a fresh playback. The voice must always write into the
## playback the server is mixing now: a reference kept across a stop() reports a
## full buffer that never drains, so the player looks alive while the bus is
## silent.
func _bind_playback() -> bool:
	if not _player.playing:
		_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_primed = false
	if _playback == null:
		_player.stop()
	return _playback != null


func _fill_buffer(frames: int) -> void:
	_buffer.resize(frames)
	for index in frames:
		var sample := _synth.render_sample()
		_buffer[index] = Vector2(sample, sample)


func _current_volume_db() -> float:
	if _voice == null:
		return SILENCE_DB
	var rev := pow(clampf(_drivetrain.get_rpm() / maxf(_voice.recipe.redline_rpm, 1.0), 0.0, 1.0), REV_EXPONENT)
	return lerpf(IDLE_DB, PEAK_DB, rev) + _voice.recipe.output_trim_db + _duck_db


func _activate_fallback(reason: String) -> void:
	_prepared = false
	_fallback_reason = reason
	stop()
	generation_failed.emit(reason)
	fallback_activated.emit(reason)
