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

	# Exercise set_race_state (real API via director) + cue with explicit time
	# advances (via _process which drives _section_elapsed). Same-phase via set
	# never restarts or counts as change; inside cooldown drops (newest dropped);
	# after window different still switches. Matches cue() semantics.
	director.call("_process", float(director.call("get_live_section_dwell")) + 1.0)
	director.call("set_live_race_state", "grid", 0.5, 0.0, false)
	var set1 := String(director.call("get_live_requested_section"))
	if not _expect(set1 == "grid", "set_race_state after dwell should switch, saw %s" % set1):
		return

	# same-phase request via set_race_state is not a change and does not restart
	director.call("set_live_race_state", "grid", 0.5, 0.0, false)
	if not _expect(String(director.call("get_live_requested_section")) == "grid", "re-set_race_state same phase must not count as change or restart"):
		return

	# different phase inside cooldown is dropped (consistent with cue drop choice)
	director.call("set_live_race_state", "ignition", 0.7, 0.1, false)
	var set_dropped := String(director.call("get_live_requested_section"))
	if not _expect(set_dropped == "grid", "set_race_state different inside dwell must drop, saw %s" % set_dropped):
		return

	# also cue inside drops (mixing the two protected APIs)
	director.call("cue_live_section", "attack")
	if not _expect(String(director.call("get_live_requested_section")) == "grid", "cue inside dwell after set must also drop"):
		return

	# after dwell window, set different phase succeeds
	director.call("_process", float(director.call("get_live_section_dwell")) + 1.0)
	director.call("set_live_race_state", "redline", 0.9, 0.4, false)
	var set2 := String(director.call("get_live_requested_section"))
	if not _expect(set2 == "redline", "set_race_state after dwell window switches, saw %s" % set2):
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
