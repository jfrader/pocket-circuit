extends SceneTree

const AUDIO_DIRECTOR_SCRIPT := preload("res://scripts/audio/audio_director.gd")


class FakeVehicle extends Node:
	var speed := 0.0
	var engine_load := 0.0

	func get_engine_load() -> float:
		return engine_load


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var director := AUDIO_DIRECTOR_SCRIPT.new()
	root.add_child(director)
	await process_frame
	var bus_count := AudioServer.bus_count
	director.ensure_buses()
	director.ensure_buses()
	if not _expect(AudioServer.bus_count == bus_count, "repeated bus setup should be idempotent"):
		return
	if not _expect(_bus_occurrences(&"Music") == 1 and _bus_occurrences(&"SFX") == 1, "Music and SFX buses should each exist exactly once"):
		return
	var master := AudioServer.get_bus_index(&"Master")
	var master_limiter_count := 0
	for index in AudioServer.get_bus_effect_count(master):
		var effect := AudioServer.get_bus_effect(master, index)
		if effect is AudioEffectHardLimiter:
			master_limiter_count += 1
			if not _expect((effect as AudioEffectHardLimiter).ceiling_db <= -1.0, "Master hard limiter should keep the summed output below 0 dBFS"):
				return
	if not _expect(master_limiter_count == 1, "Master bus should carry exactly one hard limiter"):
		return
	var music_player := director.get_node("MusicPlayer") as AudioStreamPlayer
	var music_player_id := music_player.get_instance_id()
	director.play_menu_music()
	director.play_menu_music()
	if not _expect(director.get_music_context() == &"menu" and director.get_node("MusicPlayer").get_instance_id() == music_player_id, "re-entering a context should reuse its single music player"):
		return
	var live := director.get_node_or_null("GamestrumentsPlayer")
	if live != null:
		var live_stream := live.get_node_or_null("LiveStream") as AudioStreamPlayer
		if not _expect(is_instance_valid(live_stream), "GamestrumentsPlayer/LiveStream must exist as AudioStreamPlayer on live path after play_menu_music()"):
			return
		if not _expect(String(live.get("recipe")) == "racing", "live music should use recipe \"racing\" after play_menu_music()"):
			return
		if not _expect(String(live.get("arrangement")) == "extended", "live music should use arrangement \"extended\" after play_menu_music()"):
			return
		if not _expect(live.get("autoplay") == false, "play_menu_music live path should use autoplay false for garage"):
			return
	var engine_stream: AudioStream = (director.get_node("EnginePlayer") as AudioStreamPlayer).stream
	if live == null:
		var menu_stream := music_player.stream as AudioStreamWAV
		if not _expect(_loop_spans_stream(menu_stream) and _loop_spans_stream(engine_stream), "menu and engine loops should span decoded samples instead of compressed bytes"):
			return
	elif not _expect(_loop_spans_stream(engine_stream), "engine loop should span decoded samples"):
		return
	director.play_race_music()
	director.play_race_music()
	if not _expect(director.get_music_context() == &"race" and director.get_sfx_player_count() == 6, "race music and the fixed SFX pool should remain singletons"):
		return
	if live == null:
		if not _expect(_loop_spans_stream(music_player.stream as AudioStreamWAV), "race music should span decoded samples when import metadata is absent"):
			return
	elif not _expect(live.get("autoplay") == true, "play_race_music live path should use autoplay true for extended arc"):
		return
	if live != null and not _expect(director.cue_live_section("cooldown"), "cue_live_section should forward a known Extended section to the live player"):
		return
	director.set_race_paused(true)
	if not _expect(is_equal_approx(music_player.volume_db, -9.0), "pausing should duck race music"):
		return
	director.set_race_paused(false)
	if not _expect(is_zero_approx(music_player.volume_db), "resuming should restore race music cleanly"):
		return
	if not _expect(director.play_sfx(&"ui_confirm", 0.5) and not director.play_sfx(&"missing"), "named SFX should reject unknown identifiers"):
		return
	var idle := FakeVehicle.new()
	idle.speed = 0.0
	idle.engine_load = 0.0
	var engine_player := director.get_node("EnginePlayer") as AudioStreamPlayer
	director.set_local_vehicle(idle)
	director.call("_update_engine", 1.0)
	var idle_pitch := engine_player.pitch_scale
	var revs := FakeVehicle.new()
	revs.speed = 80.0
	revs.engine_load = 1.0
	director.set_local_vehicle(revs)
	director.call("_update_engine", 1.0)
	if not _expect(engine_player.pitch_scale > idle_pitch + 0.35, "throttle should spool engine pitch into a higher rev range"):
		return
	if not _expect(engine_player.pitch_scale >= 1.55, "wide-open throttle should sit near the high-rev ceiling"):
		return
	director.set_live_race_state("finish", 0.0, 0.0, false, "win")
	idle.free()
	revs.free()
	root.remove_child(director)
	director.free()
	await process_frame
	print("AUDIO_DIRECTOR_TEST PASS")
	quit(0)


func _bus_occurrences(bus_name: StringName) -> int:
	var matches := 0
	for index in AudioServer.bus_count:
		if AudioServer.get_bus_name(index) == bus_name:
			matches += 1
	return matches


func _loop_spans_stream(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		var expected_end := maxi(0, roundi(wav.get_length() * float(wav.mix_rate)) - 1)
		return wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_begin == 0 and wav.loop_end == expected_end
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		return ogg.loop and is_zero_approx(ogg.loop_offset)
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AUDIO_DIRECTOR_TEST FAIL: " + message)
	quit(1)
	return false
