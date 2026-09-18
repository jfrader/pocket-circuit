extends SceneTree

## A single live score must be shared globally across all contexts. Context
## switches (like menu -> race and back) must cue sections instead of
## regenerating the score, ensuring the engine's internal bar-quantized
## crossfades work smoothly.

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
	if not _expect(after_menu == 1, "a cold start should generate exactly one score"):
		return

	director.call("play_race_music")
	await process_frame
	var after_race: int = director.call("get_live_score_generations")
	if not _expect(after_race == after_menu, "starting a race must not regenerate the score"):
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
