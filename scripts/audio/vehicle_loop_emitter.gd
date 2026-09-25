class_name VehicleLoopEmitter
extends Node2D

## Reusable positional loop host for non-local vehicle voices. It follows one
## vehicle, culls outside listener range, and only exposes stream/level/pitch —
## tyre and future engine systems keep their own state models outside this node.

const AUDIBLE_THRESHOLD := 0.01

var _source: Node2D
var _player: AudioStreamPlayer2D
var _max_distance := 1100.0
var _voice_trim_db := -7.0
var _headless := false
var _distance_culled := true
var _voiced := false
var _bus: StringName = &"Tyre"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name().to_lower() == "headless"
	_player = AudioStreamPlayer2D.new()
	_player.name = "LoopPlayer"
	_player.bus = &"Tyre"
	_player.max_distance = _max_distance
	_player.attenuation = 1.25
	_player.panning_strength = 1.0
	add_child(_player)


func configure(source: Node2D, max_distance: float = 1100.0, voice_trim_db: float = -7.0, bus: StringName = &"Tyre") -> void:
	_source = source
	_max_distance = maxf(max_distance, 1.0)
	_voice_trim_db = voice_trim_db
	_bus = bus
	if is_instance_valid(_player):
		_player.max_distance = _max_distance
		_player.bus = _bus


func set_stream(stream: AudioStream) -> void:
	if not is_instance_valid(_player) or _player.stream == stream:
		return
	var was_playing := _player.playing
	_player.stop()
	_player.stream = stream
	if was_playing and not _headless:
		_player.play()


func update_voice(listener_position: Vector2, level: float, pitch: float, enabled: bool = true) -> void:
	if not is_instance_valid(_source) or not is_instance_valid(_player):
		stop()
		return
	global_position = _source.global_position
	_distance_culled = global_position.distance_squared_to(listener_position) > _max_distance * _max_distance
	_voiced = enabled and not _distance_culled and level > AUDIBLE_THRESHOLD and _player.stream != null
	if not _voiced:
		stop()
		return
	_player.volume_db = _voice_trim_db + linear_to_db(clampf(level, 0.01, 1.0))
	_player.pitch_scale = clampf(pitch, 0.65, 1.5)
	if not _headless and not _player.playing:
		_player.play()


func stop() -> void:
	if is_instance_valid(_player) and _player.playing:
		_player.stop()


func is_distance_culled() -> bool:
	return _distance_culled


func is_voiced() -> bool:
	return _voiced


func get_player() -> AudioStreamPlayer2D:
	return _player


func get_source() -> Node2D:
	return _source


func _exit_tree() -> void:
	stop()
	if is_instance_valid(_player):
		_player.stream = null
