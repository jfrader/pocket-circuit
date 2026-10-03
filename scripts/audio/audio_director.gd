extends Node

const ENGINE_LOOP := preload("res://assets/audio/engine_loop.ogg")
const RaceMusicPlan := preload("res://scripts/audio/race_music_plan.gd")
const EngineSoundPlayerScript := preload("res://scripts/audio/engine/engine_sound_player.gd")
const EngineRecipeLibraryScript := preload("res://scripts/audio/engine/engine_recipe_library.gd")
const EngineLoopGeneratorScript := preload("res://scripts/audio/engine/engine_loop_generator.gd")
const EngineDrivetrainModelScript := preload("res://scripts/audio/engine/engine_drivetrain_model.gd")
const TyreSurfaceProfilesScript := preload("res://scripts/audio/sfx/tyre_surface_profiles.gd")
const TyreLoopGeneratorScript := preload("res://scripts/audio/sfx/tyre_loop_generator.gd")
const VehicleLoopEmitterScript := preload("res://scripts/audio/vehicle_loop_emitter.gd")
const CrashVoiceGeneratorScript := preload("res://scripts/audio/sfx/crash_voice_generator.gd")
const BoostVoiceGeneratorScript := preload("res://scripts/audio/sfx/boost_voice_generator.gd")
const UiVoiceGeneratorScript := preload("res://scripts/audio/sfx/ui_voice_generator.gd")
const ChampionshipCatalogScript := preload("res://data/championship/catalog.gd")
## The engine ducks while the tyres slide. A broadband scrub at the same level as
## the tonal engine is masked by it, and ducking reads better than raising the
## tyre further.
const ENGINE_SLIDE_DUCK_DB := -1.5
## Settled tyre level. A slide sits under the engine; a small steer stays silent.
const TYRE_LEVEL_CEILING := 0.40
const TYRE_RISE_PER_SEC := 0.55
const TYRE_FALL_PER_SEC := 0.8
const TYRE_PLAY_THRESHOLD := 0.045
const ENGINE_EMITTER_LIMIT := 3
const ENGINE_EMITTER_INTERVAL := 0.05
const ENGINE_MAX_DISTANCE := 1400.0
const ENGINE_VOICE_TRIM_DB := -6.0
const SFX_PLAYER_COUNT := 6
const SILENCE_DB := -80.0
const PAUSED_MUSIC_DB := -9.0

## Ceiling for the Master-bus hard limiter. Music and engine are mastered to
## -1.0 dBTP individually, but their sum can exceed full scale, so the mix needs
## its own ceiling to guarantee the output never reaches 0 dBFS.
const MASTER_CEILING_DB := -1.0

var _music_player: AudioStreamPlayer
var _engine_player: AudioStreamPlayer
## Generated engine voice for the local car. Null stream player keeps the legacy
## pitched loop in charge, so the old path stays a real fallback.
var _engine_voice: EngineSoundPlayer
## Continuous tyre scrub for the local car, driven by its slip angle.
var _local_tyre_player: AudioStreamPlayer
var _local_tyre_level := 0.0
var _tyre_state: Dictionary = {}
## Positional WAV-loop voices for AI and remote cars. The local car alone keeps
## the per-sample generator above.
var _positional_tyre_emitters: Array[Node] = []
var _positional_engine_emitters: Array[Node] = []
var _engine_emitter_models: Dictionary = {}
var _engine_emitter_clock := 0.0
var _tyre_loop_streams: Dictionary = {}
## Generated one-shots keyed by SFX name: the global interface blips at boot,
## plus the current car's crash and boost on vehicle handoff.
var _generated_streams: Dictionary = {}
var _generated_voices: Dictionary = {}
var _crash_voice: OneShotVoice
var _boost_voice: OneShotVoice
## Deterministic per-play pitch spread so repeats do not machine-gun.
var _sfx_variation := 0
## Vehicle whose generated one-shots are currently loaded.
var _sfx_vehicle_id := ""
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player := 0
var _music_context: StringName = &""
var _local_vehicle: Node
var _vehicle_max_speed := 680.0
var _race_paused := false
var _engine_loop: AudioStream
var _engine_rpm := 0.08
var _headless := false
## Live music: score generation, section cues, and the phase rotation.
var _live: LiveMusic
## Chosen once per launch so the title piece is not the same score every time.
var _menu_launch_seed := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name().to_lower() == "headless"
	ensure_buses()
	_engine_loop = _make_runtime_loop(ENGINE_LOOP)
	_build_players()
	_build_interface_sfx()
	_live = LiveMusic.new(self)

func _process(delta: float) -> void:
	_update_engine(delta)
	_update_drift(delta)
	_update_positional_tyres()
	_engine_emitter_clock += delta
	if _engine_emitter_clock >= ENGINE_EMITTER_INTERVAL:
		var step := _engine_emitter_clock
		_engine_emitter_clock = 0.0
		_update_positional_engines(step)
	_live.tick(delta)

func _exit_tree() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
	if is_instance_valid(_engine_player):
		_engine_player.stop()
		_engine_player.stream = null
	if is_instance_valid(_engine_voice):
		_engine_voice.stop()
	_stop_local_tyre()
	_clear_positional_emitters()
	for player: AudioStreamPlayer in _sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_local_vehicle = null
	_engine_loop = null
	# Godot only retires a stopped playback on a later audio mix, and shutdown
	# stops the audio driver after this teardown. Wait (bounded) for the mixer to
	# process the stops above so the engine voice and the other players do not
	# outlive the audio server (godot#76745).
	var deadline := Time.get_ticks_msec() + 500
	var last := AudioServer.get_time_since_last_mix()
	var mixes := 0
	while mixes < 2 and Time.get_ticks_msec() < deadline:
		OS.delay_msec(2)
		var current := AudioServer.get_time_since_last_mix()
		if current < last:
			mixes += 1
		last = current

func ensure_buses() -> void:
	_ensure_bus(&"Music")
	_ensure_bus(&"SFX")
	_ensure_bus(&"Engine")
	_ensure_bus(&"Tyre")
	_ensure_master_limiter()

## The music loop and the engine loop each respect their own ceiling, but they
## are summed at the Master bus and that sum can exceed full scale (a full-rev
## simulated race mix peaks slightly above 0 dBTP). A hard limiter on Master is
## the game-side guarantee that the output never reaches 0 dBFS.
func _ensure_master_limiter() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	if master < 0:
		return
	for index in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, index) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = MASTER_CEILING_DB
	AudioServer.add_bus_effect(master, limiter)

func play_menu_music() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
	_music_context = &"menu"
	_live.context = &"menu"
	clear_local_vehicle()
	set_race_paused(false)
	# The menu reuses whatever score is already playing; it only generates the
	# title score on a cold start. Starting Grid then holds until a race completes
	# its opening lap.
	if not _live.has_score():
		_live.play(_session_menu_seed(), RaceMusicPlan.menu_profile(), RaceMusicPlan.OPENING_PHASE)
	else:
		_live.set_race_state(RaceMusicPlan.OPENING_PHASE, 0.28, 0.0, false)
	_live.stop_rotation()

func play_race_music() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
	_music_context = &"race"
	_live.context = &"race"
	set_race_paused(false)
	stop_live_rotation()
	var event := _current_event()
	_live.play(RaceMusicPlan.seed_for_event(event), RaceMusicPlan.race_profile(event), RaceMusicPlan.OPENING_PHASE)

## Test/introspection: the generate seed backing the loaded score.
func get_live_seed() -> String:
	return _live.seed()


func _session_menu_seed() -> String:
	if _menu_launch_seed.is_empty():
		var random := RandomNumberGenerator.new()
		random.randomize()
		_menu_launch_seed = "pc_menu_%d" % random.randi()
	return _menu_launch_seed

## Start or resume the automatic phase rotation. The deck is a loop; empty
## disables rotation. `first` overrides the opening phase when provided.
func begin_live_rotation(deck: Array[String], dwell: float, first: String = "") -> void:
	_live.rotate(deck, dwell, first)

func stop_live_rotation() -> void:
	_live.stop_rotation()

## Step the rotation now, but only when the current phase has had at least half
## its dwell. Used for lap boundaries and meaningful position changes so the
## score re-evaluates without churning through transitions.
func advance_live_rotation() -> void:
	_live.advance_rotation()

func set_local_vehicle(vehicle: Node, vehicle_id: String = "") -> void:
	_local_vehicle = vehicle
	_vehicle_max_speed = 680.0
	if not is_instance_valid(vehicle):
		return
	var vehicle_stats: Variant = vehicle.get("stats")
	if vehicle_stats is Object:
		_vehicle_max_speed = maxf(1.0, float((vehicle_stats as Object).get("max_speed")))
	if _headless:
		return
	if vehicle_stats is VehicleStats:
		_prepare_vehicle_sfx(vehicle_stats, vehicle_id)
	if not _prepare_engine_voice(vehicle, vehicle_id) and not _headless and not _engine_player.playing:
		_engine_player.play()


## Interface and race blips are global and fixed, so they are built once at boot.
func _build_interface_sfx() -> void:
	var generator = UiVoiceGeneratorScript.new()
	for sound_name in generator.names():
		_register_voice(StringName(sound_name), generator.generate(String(sound_name)))


func _register_voice(sound_name: StringName, voice: OneShotVoice) -> void:
	_generated_voices[sound_name] = voice
	_generated_streams[sound_name] = _make_tier_streams(voice)


## Generates this car's crash and boost one-shots behind the loading screen.
func _prepare_vehicle_sfx(stats: VehicleStats, vehicle_id: String) -> void:
	var resolved_id := vehicle_id
	if resolved_id.is_empty():
		resolved_id = EngineRecipeLibraryScript.UNIDENTIFIED_VEHICLE_ID
	if resolved_id == _sfx_vehicle_id and _crash_voice != null:
		return
	_sfx_vehicle_id = resolved_id
	_crash_voice = CrashVoiceGeneratorScript.new().generate(stats, resolved_id)
	_boost_voice = BoostVoiceGeneratorScript.new().generate(stats, resolved_id)
	_register_voice(&"impact", _crash_voice)
	_register_voice(&"boost", _boost_voice)


func _make_tier_streams(voice: OneShotVoice) -> Array[AudioStreamWAV]:
	var streams: Array[AudioStreamWAV] = []
	for tier in voice.tiers:
		var pcm := PackedByteArray()
		pcm.resize(tier.size() * 2)
		for index in tier.size():
			pcm.encode_s16(index * 2, int(round(clampf(tier[index], -1.0, 1.0) * 32767.0)))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = voice.mix_rate
		stream.stereo = false
		stream.data = pcm
		streams.append(stream)
	return streams


## Generates (or reuses) the local car's engine voice. Returns false when the
## voice is unavailable, which leaves the legacy pitched loop in charge.
## `vehicle_id` comes from the race, not from the stats resource: the catalog
## hands out duplicated VehicleStats whose resource_path is empty, so the file
## name cannot identify the car.
func _prepare_engine_voice(vehicle: Node, vehicle_id: String) -> bool:
	if not is_instance_valid(_engine_voice) or not is_instance_valid(vehicle):
		return false
	var stats: Variant = vehicle.get("stats")
	if not (stats is VehicleStats):
		return false
	var resolved_id := vehicle_id
	if resolved_id.is_empty():
		resolved_id = String(EngineRecipeLibraryScript.vehicle_id_for(stats))
	if resolved_id.is_empty():
		resolved_id = EngineRecipeLibraryScript.UNIDENTIFIED_VEHICLE_ID
	var recipe := EngineRecipeLibraryScript.resolve(resolved_id, stats)
	if not _engine_voice.prepare(recipe, resolved_id):
		return false
	_engine_voice.start()
	if is_instance_valid(_engine_player) and _engine_player.playing:
		_engine_player.stop()
		_engine_player.volume_db = SILENCE_DB
	return true

func clear_local_vehicle() -> void:
	_local_vehicle = null
	_engine_rpm = 0.08
	if is_instance_valid(_engine_player):
		_engine_player.stop()
		_engine_player.volume_db = SILENCE_DB
	if is_instance_valid(_engine_voice):
		_engine_voice.stop()
	_stop_local_tyre()
	_clear_positional_emitters()


func set_positional_vehicles(vehicles: Array[Node]) -> void:
	_clear_positional_emitters()
	for vehicle: Node in vehicles:
		if not is_instance_valid(vehicle) or not vehicle is Node2D or vehicle == _local_vehicle:
			continue
		var source := vehicle as Node2D
		var tyre_emitter := VehicleLoopEmitterScript.new()
		tyre_emitter.name = "VehicleTyreEmitter%d" % _positional_tyre_emitters.size()
		add_child(tyre_emitter)
		tyre_emitter.configure(source)
		_positional_tyre_emitters.append(tyre_emitter)
		var engine_emitter := VehicleLoopEmitterScript.new()
		engine_emitter.name = "VehicleEngineEmitter%d" % _positional_engine_emitters.size()
		add_child(engine_emitter)
		engine_emitter.configure(source, ENGINE_MAX_DISTANCE, ENGINE_VOICE_TRIM_DB, &"Engine")
		var recipe := _recipe_for_vehicle(vehicle)
		if recipe != null and not _headless:
			engine_emitter.set_stream(EngineLoopGeneratorScript.generate_cached(recipe))
		var model := EngineDrivetrainModelScript.new()
		if recipe != null:
			model.configure(recipe)
		_engine_emitter_models[engine_emitter.get_instance_id()] = model
		_positional_engine_emitters.append(engine_emitter)

func set_race_paused(paused: bool) -> void:
	_race_paused = paused
	_live.set_paused(paused)
	var music_db := PAUSED_MUSIC_DB if paused and _music_context == &"race" else 0.0
	if is_instance_valid(_music_player):
		_music_player.volume_db = music_db
	if paused and is_instance_valid(_engine_player):
		_engine_player.volume_db = SILENCE_DB
	if is_instance_valid(_engine_voice):
		_engine_voice.set_paused(paused)

func play_sfx(sound_name: StringName, volume_scale: float = 1.0, pitch_scale: float = 1.0) -> bool:
	if _sfx_players.is_empty() or volume_scale <= 0.0:
		return false
	if not _generated_streams.has(sound_name):
		return false
	var player := _sfx_players[_next_sfx_player]
	_next_sfx_player = (_next_sfx_player + 1) % _sfx_players.size()
	player.stop()
	var tiers: Array = _generated_streams[sound_name]
	player.stream = tiers[_tier_index_for(sound_name, volume_scale)]
	player.volume_db = linear_to_db(clampf(volume_scale, 0.05, 1.0))
	player.pitch_scale = clampf(pitch_scale * _next_variation(), 0.65, 1.5)
	if not _headless:
		player.play()
	return true


## Generated one-shots carry strength tiers, so a light hit is duller and a heavy
## one rings longer instead of the same sound played louder.
func _tier_index_for(sound_name: StringName, volume_scale: float) -> int:
	var voice: OneShotVoice = _generated_voices.get(sound_name)
	if voice == null or voice.tiers.is_empty():
		return 0
	return clampi(voice.tier_for(volume_scale), 0, voice.tiers.size() - 1)


## Deterministic pitch spread of about +/-3.5%, so repeated hits vary without
## giving up replay determinism.
func _next_variation() -> float:
	_sfx_variation = (_sfx_variation + 1) % 7
	return 1.0 + (float(_sfx_variation) - 3.0) * 0.012

## Test introspection: how many times a live score has been generated this
## session. Re-entering a context with the same seed must not increase it.
func get_live_score_generations() -> int:
	return _live.generations()

func has_live_score() -> bool:
	return _live.has_score()

func get_music_context() -> StringName:
	return _music_context

func get_live_requested_section() -> String:
	return _live.requested_section()

func get_live_section() -> String:
	return _live.current_section()

func get_sfx_player_count() -> int:
	return _sfx_players.size()

## How long a section must play before another may replace it. Exposed so callers
## and tests can reason about the music's settling time without duplicating it.
func get_live_section_dwell() -> float:
	return LiveMusic.SECTION_CHANGE_DWELL


func set_live_race_state(phase: String, intensity: float, pressure: float, final_lap: bool, finish_result: String = "") -> void:
	_live.set_race_state(phase, intensity, pressure, final_lap, finish_result)

func cue_live_section(section: String) -> bool:
	return _live.cue(section)

## Cue a section and guarantee it holds for at least `hold_seconds` before the
## rotation may step on, so a sting or reprise is not immediately replaced.
func cue_live_section_timed(section: String, hold_seconds: float) -> bool:
	return _live.cue(section, hold_seconds)

func _build_players() -> void:
	if is_instance_valid(_music_player):
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = &"Music"
	add_child(_music_player)

	_engine_player = AudioStreamPlayer.new()
	_engine_player.name = "EnginePlayer"
	_engine_player.bus = &"Engine"
	_engine_player.stream = _engine_loop
	_engine_player.volume_db = SILENCE_DB
	add_child(_engine_player)

	_engine_voice = EngineSoundPlayerScript.new()
	_engine_voice.name = "EngineVoice"
	add_child(_engine_voice)

	_local_tyre_player = AudioStreamPlayer.new()
	_local_tyre_player.name = "LocalTyreVoice"
	_local_tyre_player.bus = &"Tyre"
	_local_tyre_player.volume_db = SILENCE_DB
	add_child(_local_tyre_player)

	for index in SFX_PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%d" % index
		player.bus = &"SFX"
		add_child(player)
		_sfx_players.append(player)

func _current_event() -> Dictionary:
	var app := get_node_or_null("/root/App")
	if app == null:
		return {}
	var session: Variant = app.get("current_race_session")
	if session is Dictionary:
		var event: Variant = (session as Dictionary).get("event", {})
		if event is Dictionary:
			return event as Dictionary
	return {}

func _update_engine(delta: float = 1.0 / 60.0) -> void:
	if not is_instance_valid(_engine_player):
		return
	if not is_instance_valid(_local_vehicle):
		if _engine_player.playing:
			_engine_player.stop()
		if is_instance_valid(_engine_voice):
			_engine_voice.stop()
		return
	if is_instance_valid(_engine_voice) and not _engine_voice.is_using_fallback():
		_drive_engine_voice(delta)
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
		# Music is mastered to -14 LUFS (Gamestruments 0.1.3) and lands near
		# -15.9 LUFS after the default Music bus gain. The engine loop measures
		# -16.7 LUFS, so this curve is set to sit roughly 4 dB under the music at
		# full rev (about -19.6 LUFS) and fall away to near-silence when parked.
		# Raising the old -24.0 floor was required: against the previously
		# unmastered -30 LUFS music the engine dominated by ~12 dB, but once the
		# music was mastered to a real level that same curve buried it instead.
		# These are mix-balance values, tunable by ear.
		_engine_player.volume_db = lerpf(-18.0, -2.0, rev)


## Feeds the generated voice from the vehicle each frame. The player owns the
## drivetrain model, the synth controls and its own loudness curve.
func _drive_engine_voice(delta: float) -> void:
	if _race_paused:
		_engine_voice.set_paused(true)
		return
	_engine_voice.set_paused(false)
	var speed := maxf(0.0, float(_local_vehicle.get("speed")))
	var load := 0.0
	if _local_vehicle.has_method("get_engine_load"):
		load = clampf(float(_local_vehicle.call("get_engine_load")), 0.0, 1.0)
	var throttle := load
	if _local_vehicle.has_method("get_throttle_input"):
		throttle = clampf(float(_local_vehicle.call("get_throttle_input")), 0.0, 1.0)
	_engine_voice.set_vehicle_state(speed, _vehicle_max_speed, load, throttle, delta)


## Test introspection: true while the local car runs the generated voice.
func has_engine_voice() -> bool:
	return is_instance_valid(_engine_voice) and not _engine_voice.is_using_fallback()


## Test introspection: true when this effect is voiced by a generated one-shot.
func has_generated_sfx(sound_name: StringName) -> bool:
	return _generated_streams.has(sound_name)


## Test introspection: the local car's generated crash and boost identities.
func get_crash_voice_signature() -> String:
	return _crash_voice.signature if _crash_voice != null else ""


func get_boost_voice_signature() -> String:
	return _boost_voice.signature if _boost_voice != null else ""


## Drives the continuous scrub from the local car's slip. Independent of the
## engine voice, so a drift still sounds if the engine fell back to its loop.
func _update_drift(_delta: float) -> void:
	if not is_instance_valid(_local_vehicle) or _race_paused:
		_stop_local_tyre()
		if is_instance_valid(_engine_voice):
			_engine_voice.set_duck_db(0.0)
		return
	if not _local_vehicle.has_method("get_tyre_state"):
		_stop_local_tyre()
		if is_instance_valid(_engine_voice):
			_engine_voice.set_duck_db(0.0)
		return
	var tyre_state := _read_tyre_state(_local_vehicle)
	_drive_local_tyre(tyre_state, maxf(0.0, float(_local_vehicle.get("speed"))), _delta)
	if is_instance_valid(_engine_voice):
		var duck := ENGINE_SLIDE_DUCK_DB * clampf(_local_tyre_level / TYRE_LEVEL_CEILING, 0.0, 1.0)
		_engine_voice.set_duck_db(duck)


func _tyre_target_level(tyre_state: Dictionary) -> float:
	var screech := clampf(float(tyre_state["screech"]), 0.0, 1.0)
	if bool(tyre_state["sliding"]):
		return clampf(0.18 + screech * 0.22, 0.0, TYRE_LEVEL_CEILING)
	var cornering := clampf(float(tyre_state["cornering"]), 0.0, 1.0)
	return clampf(maxf(cornering - 0.72, 0.0) * 0.04, 0.0, 0.04)


func _drive_local_tyre(tyre_state: Dictionary, speed: float, delta: float) -> void:
	if not is_instance_valid(_local_tyre_player):
		return
	var target := _tyre_target_level(tyre_state)
	var rate := TYRE_RISE_PER_SEC if target > _local_tyre_level else TYRE_FALL_PER_SEC
	_local_tyre_level = move_toward(_local_tyre_level, target, rate * maxf(delta, 0.0))
	if _local_tyre_level <= TYRE_PLAY_THRESHOLD:
		_silence_local_tyre()
		return
	var profile: Dictionary = TyreSurfaceProfilesScript.profile_for(tyre_state["surface"])
	var stream := _tyre_loop_for(profile)
	if _local_tyre_player.stream != stream:
		_local_tyre_player.stop()
		_local_tyre_player.stream = stream
	var max_speed := _max_speed_for(_local_vehicle)
	var speed_ratio := clampf(speed / max_speed, 0.0, 1.0)
	var screech := clampf(float(tyre_state["screech"]), 0.0, 1.0)
	_local_tyre_player.volume_db = linear_to_db(clampf(_local_tyre_level, 0.01, 1.0))
	_local_tyre_player.pitch_scale = clampf(0.70 + speed_ratio * 0.08 + screech * 0.06, 0.65, 1.15)
	if not _headless and not _local_tyre_player.playing:
		_local_tyre_player.play()


func _silence_local_tyre() -> void:
	if not is_instance_valid(_local_tyre_player):
		return
	if _local_tyre_player.playing:
		_local_tyre_player.stop()
	_local_tyre_player.volume_db = SILENCE_DB


func _stop_local_tyre() -> void:
	_silence_local_tyre()
	_local_tyre_level = 0.0


func _update_positional_tyres() -> void:
	var listener_position := Vector2.ZERO
	var listener_camera := get_viewport().get_camera_2d()
	if is_instance_valid(listener_camera):
		listener_position = listener_camera.global_position
	elif is_instance_valid(_local_vehicle) and _local_vehicle is Node2D:
		listener_position = (_local_vehicle as Node2D).global_position
	for emitter: Node in _positional_tyre_emitters:
		var vehicle := emitter.call("get_source") as Node
		if not is_instance_valid(vehicle) or not vehicle.has_method("get_tyre_state"):
			emitter.stop()
			continue
		var tyre_state := _read_tyre_state(vehicle)
		var profile: Dictionary = TyreSurfaceProfilesScript.profile_for(tyre_state["surface"])
		emitter.set_stream(_tyre_loop_for(profile))
		var screech := clampf(float(tyre_state["screech"]), 0.0, 1.0)
		var speed := maxf(0.0, float(vehicle.get("speed")))
		var max_speed := _max_speed_for(vehicle)
		var speed_ratio := clampf(speed / max_speed, 0.0, 1.0)
		var level := _tyre_target_level(tyre_state)
		var pitch := 0.70 + speed_ratio * 0.08 + screech * 0.06
		emitter.update_voice(listener_position, level, pitch, not _race_paused)


func _read_tyre_state(vehicle: Node) -> Dictionary:
	# Test doubles retain the snapshot API; real vehicles fill our reusable buffer.
	if vehicle.has_method("write_tyre_state"):
		vehicle.call("write_tyre_state", _tyre_state)
		return _tyre_state
	return vehicle.call("get_tyre_state")


func _tyre_loop_for(profile: Dictionary) -> AudioStreamWAV:
	var profile_id: StringName = profile["id"]
	if not _tyre_loop_streams.has(profile_id):
		_tyre_loop_streams[profile_id] = TyreLoopGeneratorScript.generate(profile, 1037 + _tyre_loop_streams.size() * 97)
	return _tyre_loop_streams[profile_id] as AudioStreamWAV


func _max_speed_for(vehicle: Node) -> float:
	var vehicle_stats: Variant = vehicle.get("stats")
	if vehicle_stats is Object:
		return maxf(1.0, float((vehicle_stats as Object).get("max_speed")))
	return 680.0


func _clear_positional_emitters() -> void:
	for emitter: Node in _positional_tyre_emitters:
		if is_instance_valid(emitter):
			emitter.queue_free()
	_positional_tyre_emitters.clear()
	for emitter: Node in _positional_engine_emitters:
		if is_instance_valid(emitter):
			emitter.queue_free()
	_positional_engine_emitters.clear()
	_engine_emitter_models.clear()


func get_positional_tyre_emitters() -> Array[Node]:
	return _positional_tyre_emitters


func get_positional_engine_emitters() -> Array[Node]:
	return _positional_engine_emitters


func _recipe_for_vehicle(vehicle: Node) -> EngineRecipe:
	var stats: Variant = vehicle.get("stats")
	if not (stats is VehicleStats):
		return null
	var vehicle_id := ""
	if vehicle.has_meta("audio_vehicle_id"):
		vehicle_id = String(vehicle.get_meta("audio_vehicle_id"))
	if vehicle_id.is_empty():
		vehicle_id = EngineRecipeLibraryScript.vehicle_id_for(stats as VehicleStats)
	if vehicle_id.is_empty():
		vehicle_id = EngineRecipeLibraryScript.UNIDENTIFIED_VEHICLE_ID
	return EngineRecipeLibraryScript.resolve(vehicle_id, stats as VehicleStats)


func _listener_position() -> Vector2:
	var listener_camera := get_viewport().get_camera_2d()
	if is_instance_valid(listener_camera):
		return listener_camera.global_position
	if is_instance_valid(_local_vehicle) and _local_vehicle is Node2D:
		return (_local_vehicle as Node2D).global_position
	return Vector2.ZERO


func _update_positional_engines(delta: float) -> void:
	var listener_position := _listener_position()
	var ranked: Array[Dictionary] = []
	for emitter: Node in _positional_engine_emitters:
		var source := emitter.call("get_source") as Node2D
		if not is_instance_valid(source):
			emitter.call("update_voice", listener_position, 0.0, 1.0, false)
			continue
		ranked.append({
			"emitter": emitter,
			"source": source,
			"distance": source.global_position.distance_to(listener_position),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	for index in ranked.size():
		var entry: Dictionary = ranked[index]
		var emitter: Node = entry["emitter"]
		var source: Node = entry["source"]
		var in_earshot := index < ENGINE_EMITTER_LIMIT and float(entry["distance"]) <= ENGINE_MAX_DISTANCE
		var model: Variant = _engine_emitter_models.get(emitter.get_instance_id())
		var rpm := 0.0
		if model != null:
			var speed := maxf(0.0, float(source.get("speed")))
			var load := float(source.call("get_engine_load")) if source.has_method("get_engine_load") else 0.0
			var throttle := float(source.call("get_throttle_input")) if source.has_method("get_throttle_input") else load
			model.step(speed, _max_speed_for(source), load, throttle, delta)
			rpm = float(model.get_rpm())
		var player := emitter.call("get_player") as AudioStreamPlayer2D
		var stream: AudioStream = player.stream if player != null else null
		var base_rpm := rpm
		if stream != null and stream.has_meta("base_rpm"):
			base_rpm = float(stream.get_meta("base_rpm"))
		var pitch := EngineLoopGeneratorScript.pitch_for_rpm(rpm if rpm > 0.0 else base_rpm, base_rpm)
		var load_now := float(source.call("get_engine_load")) if source.has_method("get_engine_load") else 0.0
		var level := 0.3 + clampf(load_now, 0.0, 1.0) * 0.7
		emitter.call("update_voice", listener_position, level, pitch, in_earshot and not _race_paused and stream != null)


## Generates and caches a vehicle's engine voice and one-shots ahead of the race
## scene, so the first race frame never pays for synthesis. Headless runs generate
## nothing: there is no listener and tests should not pay the cost.
## Loading callers provide a checkpoint to separate the synthesis stages.
func warm_vehicle_audio(vehicle_id: String, progress: Callable = Callable()) -> bool:
	if _headless or vehicle_id.is_empty():
		return false
	var entry: Dictionary = ChampionshipCatalogScript.get_vehicle(vehicle_id)
	if entry.is_empty():
		return false
	var stats := load(String(entry.get("stats_path", ""))) as VehicleStats
	if stats == null:
		return false
	var recipe := EngineRecipeLibraryScript.resolve(vehicle_id, stats)
	var voice := await EngineVoiceGenerator.prepare_cached(recipe, progress)
	if progress.is_valid():
		await progress.call()
	EngineLoopGeneratorScript.generate_cached(recipe)
	if progress.is_valid():
		await progress.call()
	_prepare_vehicle_sfx(stats, vehicle_id)
	return voice != null


func get_engine_voice_signature() -> String:
	if not is_instance_valid(_engine_voice):
		return ""
	return _engine_voice.get_voice_signature()


func _ensure_bus(bus_name: StringName) -> int:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, &"Master")
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
