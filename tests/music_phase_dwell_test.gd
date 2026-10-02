extends SceneTree

## Moving quickly between screens used to change the music section every time, so
## finishing a race and going to the menu and back left the music switching
## constantly. A section now has to play for a while before another replaces it;
## the request is dropped rather than queued, because a late switch is the abrupt
## change we are avoiding.

const AUDIO_DIRECTOR := preload("res://scripts/audio/audio_director.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var director := AUDIO_DIRECTOR.new()
	root.add_child(director)
	await process_frame
	director.call("ensure_buses")

	if not ClassDB.class_exists("GamestrumentsPlayer"):
		push_error("MUSIC_PHASE_DWELL_TEST FAIL: GamestrumentsPlayer extension is required; no WAV fallback")
		quit(1)
		return

	director.call("play_menu_music")
	await process_frame
	if not _expect(bool(director.call("has_live_score")), "a menu start should load a live score"):
		return
	var opening := String(director.call("get_live_requested_section"))
	if not _expect(opening == "grid", "the menu should open on the grid section, saw %s" % opening):
		return

	# A change is only allowed once the playing section has had its dwell, so let
	# the opening section settle first.
	director.call("_process", float(director.call("get_live_section_dwell")) + 1.0)
	if not _expect(bool(director.call("cue_live_section", "victory")), "a change after the dwell window should be accepted"):
		return
	var after_change := String(director.call("get_live_requested_section"))
	if not _expect(after_change == "victory", "the accepted change should be playing, saw %s" % after_change):
		return

	# Anything inside the dwell window must be dropped, keeping the current section.
	director.call("cue_live_section", "defeat")
	var too_soon := String(director.call("get_live_requested_section"))
	if not _expect(too_soon == "victory", "a change inside the dwell window must be dropped, saw %s" % too_soon):
		return
	director.call("cue_live_section", "grid")
	var still := String(director.call("get_live_requested_section"))
	if not _expect(still == "victory", "rapid screen changes must not flap the music, saw %s" % still):
		return

	# Re-requesting the section already playing is not a change and never restarts it.
	if not _expect(bool(director.call("cue_live_section", "victory")), "re-requesting the playing section should be a no-op, not a rejection"):
		return
	if not _expect(String(director.call("get_live_requested_section")) == "victory", "re-requesting must not restart or change the section"):
		return

	# Once the dwell has passed again, a genuinely different section takes effect.
	director.call("_process", float(director.call("get_live_section_dwell")) + 1.0)
	if not _expect(bool(director.call("cue_live_section", "defeat")), "a change after the dwell window should be accepted"):
		return
	var settled := String(director.call("get_live_requested_section"))
	if not _expect(settled == "defeat", "the section should change once the dwell has passed, saw %s" % settled):
		return

	director.queue_free()
	print("MUSIC_PHASE_DWELL_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("MUSIC_PHASE_DWELL_TEST FAIL: " + message)
	quit(1)
	return false
