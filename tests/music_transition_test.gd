extends SceneTree

## A return to the menu must segue, not restart. The live player keeps the
## generated score and cues its garage section, so the music moves home at a
## musical boundary instead of rebuilding the score from scratch.

const AUDIO_DIRECTOR := preload("res://scripts/audio/audio_director.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var director := AUDIO_DIRECTOR.new()
	root.add_child(director)
	await process_frame
	director.call("ensure_buses")

	director.call("play_menu_music")
	await process_frame
	if not _expect(bool(director.call("get_music_context") == &"menu"), "a cold start should report the menu context"):
		return

	if not ClassDB.class_exists("GamestrumentsPlayer"):
		# The packaged WAV fallback has no sections to cue, so only the context
		# switch is asserted here.
		director.call("play_race_music")
		await process_frame
		if not _expect(bool(director.call("get_music_context") == &"race"), "starting a race should report the race context"):
			return
		director.call("play_menu_music")
		await process_frame
		if not _expect(bool(director.call("get_music_context") == &"menu"), "returning to the menu should report the menu context"):
			return
		director.queue_free()
		await process_frame
		print("MUSIC_TRANSITION_TEST PASS packaged_wav_fallback_native_extension_absent")
		quit(0)
		return

	if not _expect(bool(director.call("has_live_score")), "a cold menu start should load a live score"):
		return
	var after_menu: int = director.call("get_live_score_generations")
	if not _expect(after_menu == 1, "a cold menu start should generate exactly one score"):
		return

	director.call("play_race_music")
	await process_frame
	var after_race: int = director.call("get_live_score_generations")
	if not _expect(after_race == after_menu + 1, "starting a race should generate the circuit score"):
		return

	director.call("play_menu_music")
	await process_frame
	if not _expect(
		director.call("get_live_score_generations") == after_race,
		"returning to the menu must not regenerate the score; it should cue the garage section"
	):
		return
	if not _expect(bool(director.call("get_music_context") == &"menu"), "the menu return should report the menu context"):
		return
	if not _expect(bool(director.call("has_live_score")), "the score should still be loaded after the menu return"):
		return

	# Test that prepare_race_music works during loading screen (Option 2)
	director.call("prepare_race_music", "different_seed")
	await create_timer(0.5).timeout
	
	var after_prepare: int = director.call("get_live_score_generations")
	if not _expect(after_prepare == after_race + 1, "prepare_race_music should generate the score ahead of time"):
		return
		
	# Test that it doesn't regenerate if already prepared
	director.call("prepare_race_music", "different_seed")
	await create_timer(0.5).timeout
	if not _expect(director.call("get_live_score_generations") == after_prepare, "prepare_race_music should not regenerate if already prepared"):
		return

	director.queue_free()
	await process_frame
	print("MUSIC_TRANSITION_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("MUSIC_TRANSITION_TEST FAIL: " + message)
	quit(1)
	return false
