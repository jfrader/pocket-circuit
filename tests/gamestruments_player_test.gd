extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not ClassDB.class_exists("GamestrumentsPlayer"):
		print("GAMESTRUMENTS_PLAYER_TEST SKIP: GDExtension not loaded")
		quit(0)
		return
	var player := ClassDB.instantiate("GamestrumentsPlayer") as Node
	player.set("project_secret", "guri-pc-qa-salt")
	player.set("style", "funk")
	player.set("melody_voice", "pluck")
	player.set("harmony_voice", "warm")
	player.set("drive_voice", "pluck")
	player.set("bass_voice", "bass")
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
	root.remove_child(player)
	player.free()
	await process_frame
	print("GAMESTRUMENTS_PLAYER_TEST PASS")
	quit(0)
