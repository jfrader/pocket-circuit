extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not ClassDB.class_exists("GamestrumentsPlayer"):
		push_error("GAMESTRUMENTS_PLAYER_TEST FAIL: GamestrumentsPlayer extension is required; no WAV fallback")
		quit(1)
		return
	var player := ClassDB.instantiate("GamestrumentsPlayer") as Node
	player.set("project_secret", "guri-pc-qa-salt")
	player.set("style", "funk")
	player.set("melody_voice", "pluck")
	player.set("harmony_voice", "warm")
	player.set("drive_voice", "pluck")
	player.set("bass_voice", "bass")
	player.set("recipe", "racing")
	player.set("arrangement", "extended")
	root.add_child(player)
	await process_frame
	player.call("generate", "menu")
	player.call("set_race_state", "garage", 0.35, 0.2, false)
	player.call("set_race_state", "race", 0.7, 0.5, false)
	await process_frame
	await process_frame
	if player.get_child_count() < 1:
		push_error("GAMESTRUMENTS_PLAYER_TEST FAIL: missing audio stream player")
		quit(1)
		return
	# verify extended contains the four new sections (reached via cue_section)
	for sec: String in ["ignition", "slipstream", "redline", "cooldown"]:
		if not (player.call("cue_section", sec) as bool):
			push_error("GAMESTRUMENTS_PLAYER_TEST FAIL: extended score missing or rejected section " + sec)
			quit(1)
			return
	if not (player.call("cue_section", "redline") as bool):
		push_error("GAMESTRUMENTS_PLAYER_TEST FAIL: cue_section(\"redline\") not accepted on extended")
		quit(1)
		return
	if not (player.call("set_race_state", "finish", 0.0, 0.0, false, "win") as bool):
		push_error("GAMESTRUMENTS_PLAYER_TEST FAIL: set_race_state with finish_result \"win\" not accepted")
		quit(1)
		return
	# The game drives the seeded racing arrangement, which must carry the whole
	# pool (including the drumless breather) and the incident/outro signals.
	var seeded := ClassDB.instantiate("GamestrumentsPlayer") as Node
	seeded.set("project_secret", "guri-pc-qa-salt")
	seeded.set("style", "neon")
	seeded.set("recipe", "racing")
	seeded.set("arrangement", "seeded")
	root.add_child(seeded)
	await process_frame
	if not (seeded.call("generate", "circuit") as bool):
		push_error("GAMESTRUMENTS_PLAYER_TEST FAIL: seeded racing score failed to generate")
		quit(1)
		return
	await process_frame
	if not (seeded.call("set_form_hold", true) as bool):
		push_error("GAMESTRUMENTS_PLAYER_TEST FAIL: seeded score should carry a holdable tour form")
		quit(1)
		return
	for sec: String in ["breather", "ignition", "slipstream", "redline", "cooldown", "final-lap", "victory", "defeat", "recovery", "wrong-way"]:
		if not (seeded.call("cue_section", sec) as bool):
			push_error("GAMESTRUMENTS_PLAYER_TEST FAIL: seeded score missing or rejected section " + sec)
			quit(1)
			return
	root.remove_child(seeded)
	seeded.free()
	root.remove_child(player)
	player.free()
	await process_frame
	print("GAMESTRUMENTS_PLAYER_TEST PASS")
	quit(0)
