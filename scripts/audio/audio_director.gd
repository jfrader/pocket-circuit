extends Node

const MENU_LOOP := preload("res://assets/audio/menu_loop.wav")
const RACE_LOOP := preload("res://assets/audio/race_loop.wav")
const ENGINE_LOOP := preload("res://assets/audio/engine_loop.ogg")
const SFX_STREAMS := {
	&"countdown": preload("res://assets/audio/countdown.ogg"),
	&"go": preload("res://assets/audio/go.ogg"),
	&"ui_move": preload("res://assets/audio/ui_move.ogg"),
	&"ui_confirm": preload("res://assets/audio/ui_confirm.ogg"),
	&"drift": preload("res://assets/audio/drift.ogg"),
	&"boost": preload("res://assets/audio/boost.ogg"),
	&"impact": preload("res://assets/audio/impact.ogg"),
	&"hazard_warning": preload("res://assets/audio/hazard_warning.ogg"),
}
const SFX_PLAYER_COUNT := 6
const SILENCE_DB := -80.0
const PAUSED_MUSIC_DB := -9.0

const LIVE_RECIPE := "racing"
const LIVE_ARRANGEMENT := "extended"

var _music_player: AudioStreamPlayer
var _engine_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player := 0
var _music_context: StringName = &""
var _local_vehicle: Node
var _vehicle_max_speed := 680.0
var _race_paused := false
var _menu_loop: AudioStream
var _race_loop: AudioStream
var _engine_loop: AudioStream
var _engine_rpm := 0.08
var _headless := false
var _live_music: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name().to_lower() == "headless"
	ensure_buses()
	_menu_loop = _make_runtime_loop(MENU_LOOP)
	_race_loop = _make_runtime_loop(RACE_LOOP)
	_engine_loop = _make_runtime_loop(ENGINE_LOOP)
	_build_players()
	_bind_live_music()


func _process(delta: float) -> void:
	_update_engine(delta)


func _exit_tree() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
	if is_instance_valid(_engine_player):
		_engine_player.stop()
		_engine_player.stream = null
	for player: AudioStreamPlayer in _sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_local_vehicle = null
	_menu_loop = null
	_race_loop = null
	_engine_loop = null


func ensure_buses() -> void:
	_ensure_bus(&"Music")
	_ensure_bus(&"SFX")


func play_menu_music() -> void:
	if _start_live_music("menu", "garage"):
		clear_local_vehicle()
		set_race_paused(false)
		return
	_set_music(&"menu", _menu_loop)
	clear_local_vehicle()
	set_race_paused(false)


func play_race_music() -> void:
	var race_seed := "race"
	var app := get_node_or_null("/root/App")
	if app != null:
		var session: Variant = app.get("current_race_session")
		if session is Dictionary and not (session as Dictionary).is_empty():
			race_seed = String((session as Dictionary).get("event_id", "race"))
	if _start_live_music(race_seed, "grid"):
		set_race_paused(false)
		return
	_set_music(&"race", _race_loop)
	set_race_paused(false)


func set_local_vehicle(vehicle: Node) -> void:
	_local_vehicle = vehicle
	_vehicle_max_speed = 680.0
	if is_instance_valid(vehicle):
		var vehicle_stats: Variant = vehicle.get("stats")
		if vehicle_stats is Object:
			_vehicle_max_speed = maxf(1.0, float((vehicle_stats as Object).get("max_speed")))
		if not _headless and not _engine_player.playing:
			_engine_player.play()


func clear_local_vehicle() -> void:
	_local_vehicle = null
	_engine_rpm = 0.08
	if is_instance_valid(_engine_player):
		_engine_player.stop()
		_engine_player.volume_db = SILENCE_DB


func set_race_paused(paused: bool) -> void:
	_race_paused = paused
	var music_db := PAUSED_MUSIC_DB if paused and _music_context == &"race" else 0.0
	if is_instance_valid(_music_player):
		_music_player.volume_db = music_db
	if is_instance_valid(_live_music):
		for child in _live_music.get_children():
			if child is AudioStreamPlayer:
				(child as AudioStreamPlayer).volume_db = music_db
	if paused and is_instance_valid(_engine_player):
		_engine_player.volume_db = SILENCE_DB


func play_sfx(sound_name: StringName, volume_scale: float = 1.0, pitch_scale: float = 1.0) -> bool:
	if not SFX_STREAMS.has(sound_name) or _sfx_players.is_empty() or volume_scale <= 0.0:
		return false
	var player := _sfx_players[_next_sfx_player]
	_next_sfx_player = (_next_sfx_player + 1) % _sfx_players.size()
	player.stop()
	player.stream = SFX_STREAMS[sound_name]
	player.volume_db = linear_to_db(clampf(volume_scale, 0.05, 1.0))
	player.pitch_scale = clampf(pitch_scale, 0.65, 1.5)
	if not _headless:
		player.play()
	return true


func get_music_context() -> StringName:
	return _music_context


func get_sfx_player_count() -> int:
	return _sfx_players.size()


func set_live_race_state(phase: String, intensity: float, pressure: float, final_lap: bool, finish_result: String = "") -> void:
	# Music-only adaptive state for the live procedural engine.
	# WAV loop path remains completely unchanged (no calls to _set_music or players here).
	if _live_music != null and _live_music.has_method("set_race_state"):
		_live_music.call("set_race_state", phase, intensity, pressure, final_lap, finish_result)


func cue_live_section(section: String) -> bool:
	if _live_music != null and _live_music.has_method("cue_section"):
		return _live_music.call("cue_section", section) as bool
	return false


func _bind_live_music() -> void:
	if not ClassDB.class_exists("GamestrumentsPlayer"):
		return
	_live_music = ClassDB.instantiate("GamestrumentsPlayer")
	_live_music.name = "GamestrumentsPlayer"
	_live_music.set("project_secret", "guri-pc-dev-salt")
	_live_music.set("recipe", LIVE_RECIPE)
	_live_music.set("arrangement", LIVE_ARRANGEMENT)
	_live_music.set("style", "funk")
	_live_music.set("melody_voice", "pluck")
	_live_music.set("harmony_voice", "warm")
	_live_music.set("drive_voice", "pluck")
	_live_music.set("bass_voice", "bass")
	_live_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_live_music)


func _start_live_music(seed: String, phase: String) -> bool:
	if _live_music == null or not _live_music.has_method("generate"):
		return false
	if not bool(_live_music.call("generate", seed)):
		return false
	if is_instance_valid(_music_player):
		_music_player.stop()
	_music_context = &"menu" if phase == "garage" else &"race"
	_live_music.set("autoplay", phase != "garage")
	_live_music.call("set_race_state", phase, 0.35, 0.2, false)
	return true


func _build_players() -> void:
	if is_instance_valid(_music_player):
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = &"Music"
	add_child(_music_player)

	_engine_player = AudioStreamPlayer.new()
	_engine_player.name = "EnginePlayer"
	_engine_player.bus = &"SFX"
	_engine_player.stream = _engine_loop
	_engine_player.volume_db = SILENCE_DB
	add_child(_engine_player)

	for index in SFX_PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%d" % index
		player.bus = &"SFX"
		add_child(player)
		_sfx_players.append(player)


func _set_music(context: StringName, stream: AudioStream) -> void:
	if not is_instance_valid(_music_player):
		return
	if _music_context == context and _music_player.stream == stream and (_music_player.playing or _headless):
		return
	_music_context = context
	_music_player.stop()
	_music_player.stream = stream
	_music_player.volume_db = 0.0
	if not _headless:
		_music_player.play()


func _update_engine(delta: float = 1.0 / 60.0) -> void:
	if not is_instance_valid(_engine_player):
		return
	if not is_instance_valid(_local_vehicle):
		if _engine_player.playing:
			_engine_player.stop()
		return
	if not _headless and not _engine_player.playing:
		_engine_player.play()
	var speed := maxf(0.0, float(_local_vehicle.get("speed")))
	var speed_ratio := clampf(speed / _vehicle_max_speed, 0.0, 1.2)
	var engine_load := 0.0
	if _local_vehicle.has_method("get_engine_load"):
		engine_load = clampf(float(_local_vehicle.call("get_engine_load")), 0.0, 1.0)
	var target_rpm := clampf(speed_ratio * 0.46 + engine_load * 0.82, 0.06, 1.2)
	if engine_load < 0.12:
		target_rpm = minf(target_rpm, maxf(speed_ratio * 0.62, 0.08))
	var spool := 4.8 if target_rpm > _engine_rpm else 2.4
	_engine_rpm = move_toward(_engine_rpm, target_rpm, spool * maxf(delta, 0.0))
	var rev := pow(clampf(_engine_rpm, 0.0, 1.0), 0.68)
	_engine_player.pitch_scale = lerpf(0.58, 1.95, rev)
	if _race_paused:
		_engine_player.volume_db = SILENCE_DB
	else:
		_engine_player.volume_db = lerpf(-24.0, -3.5, rev)


func _ensure_bus(bus_name: StringName) -> int:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		return bus_index
	AudioServer.add_bus()
	bus_index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, bus_name)
	return bus_index


func _make_runtime_loop(source: AudioStream) -> AudioStream:
	var looped := source.duplicate() as AudioStream
	if looped is AudioStreamWAV:
		var wav := looped as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = maxi(0, roundi(wav.get_length() * float(wav.mix_rate)) - 1)
	elif looped is AudioStreamOggVorbis:
		var ogg := looped as AudioStreamOggVorbis
		ogg.loop = true
		ogg.loop_offset = 0.0
	return looped
