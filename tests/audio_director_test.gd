extends SceneTree

const AUDIO_DIRECTOR_SCRIPT := preload("res://scripts/audio/audio_director.gd")


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
	var music_player := director.get_node("MusicPlayer") as AudioStreamPlayer
	var music_player_id := music_player.get_instance_id()
	director.play_menu_music()
	director.play_menu_music()
	if not _expect(director.get_music_context() == &"menu" and director.get_node("MusicPlayer").get_instance_id() == music_player_id, "re-entering a context should reuse its single music player"):
		return
	var live := director.get_node_or_null("GamestrumentsPlayer")
	var engine_stream := (director.get_node("EnginePlayer") as AudioStreamPlayer).stream as AudioStreamWAV
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
	director.set_race_paused(true)
	if not _expect(is_equal_approx(music_player.volume_db, -9.0), "pausing should duck race music"):
		return
	director.set_race_paused(false)
	if not _expect(is_zero_approx(music_player.volume_db), "resuming should restore race music cleanly"):
		return
	if not _expect(director.play_sfx(&"ui_confirm", 0.5) and not director.play_sfx(&"missing"), "named SFX should reject unknown identifiers"):
		return
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


func _loop_spans_stream(stream: AudioStreamWAV) -> bool:
	var expected_end := maxi(0, roundi(stream.get_length() * float(stream.mix_rate)) - 1)
	return stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == expected_end


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AUDIO_DIRECTOR_TEST FAIL: " + message)
	quit(1)
	return false
