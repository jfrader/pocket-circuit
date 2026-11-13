extends SceneTree

const STORE := preload("res://scripts/persistence/save_store.gd")
const WALK := preload("res://tests/support/run_walk.gd")
const EXPECTED_COPY := "W / UP / RT: ACCELERATE · S / DOWN / LT: BRAKE\nA / D / LEFT / RIGHT / LEFT STICK: STEER\nSPACE / A: DRIFT TO CHARGE BOOST\nSHIFT / B: BOOST ON THE STRAIGHT\nR / Y TO RECOVER\nESC / START TO PAUSE"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_default_bindings():
		return
	var legacy := STORE.new().default_data()
	legacy.erase("run_intro_seen")
	if not _expect(bool(STORE.new().call("_normalize", legacy).get("run_intro_seen", false)), "existing saves normalize to seen"):
		return
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 4:
		await process_frame
	var app := root.get_node("App")
	var shell := app.get("_shell") as CanvasLayer
	if not _expect(not bool((app.call("get_save_data") as Dictionary).get("run_intro_seen", true)), "fresh profile starts unseen"):
		return
	app.call("update_setting", "reduced_motion", true)
	shell.call("_on_art_action", &"new_run")
	for frame in 4:
		await process_frame
	var note := shell.find_child("RunIntro", true, false) as Control
	if not _expect(note != null and shell.find_child("RunDrivingCopy", true, false) == null, "board has its original note but no driving slip"):
		return
	var session: RunSession = app.call("current_run_session")
	var first_stop := session.current_node_id
	shell.call("_go_to_run_stop", first_stop, false)
	await process_frame
	var screen := shell.find_child("RunDrivingIntro", true, false) as Control
	var copy := shell.find_child("RunDrivingCopy", true, false) as Label
	if not _expect(screen != null and copy != null and copy.is_visible_in_tree() and copy.text == EXPECTED_COPY and copy.get_line_count() == 6, "confirming first travel shows all six controls lines"):
		return
	var paper: Rect2 = screen.get("_paper")
	if not _expect(paper.grow(-16).encloses(copy.get_rect()) and screen.modulate == Color.WHITE and not bool(shell.get("_run_going")) and (app.get("current_race_session") as Dictionary).is_empty(), "static paper contains the copy and blocks travel before race creation"):
		return
	await _pad(JOY_BUTTON_B)
	if not _expect(shell.get("_screen") == "run_board" and not bool((app.call("get_save_data") as Dictionary).get("run_intro_seen", true)) and (app.get("current_race_session") as Dictionary).is_empty() and session.current_node_id == first_stop, "controller B returns to board without marking seen or starting a race"):
		return
	shell.call("_go_to_run_stop", first_stop, false)
	await process_frame
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	if not _expect(shell.get("_screen") == "run_board" and not bool((app.call("get_save_data") as Dictionary).get("run_intro_seen", true)) and (app.get("current_race_session") as Dictionary).is_empty(), "ESC also returns without starting or marking seen"):
		return
	shell.call("_go_to_run_stop", first_stop, false)
	await process_frame
	(shell.find_child("DrivingReady", true, false) as Button).pressed.emit()
	await create_timer(0.2).timeout
	if not _expect(shell.find_child("RunDrivingIntro", true, false) == null and String((app.get("current_race_session") as Dictionary).get("run_node_id", "")) == first_stop, "READY resumes travel into exactly the requested first race"):
		return
	var store := app.get("_save_store") as SaveStore
	var saved := STORE.new(store.save_path).load_data()
	if not _expect(bool(saved.get("run_intro_seen", false)), "seen flag survives disk reload"):
		return
	app.call("report_race_result", 1, 1.0, [], false, {})
	if not _expect(WALK.walk_to(app, session, "race"), "a second race is reachable"):
		return
	shell.call("show_run_board")
	await process_frame
	shell.call("_go_to_run_stop", session.current_node_id, false)
	await create_timer(0.2).timeout
	if not _expect(shell.find_child("RunDrivingIntro", true, false) == null and String((app.get("current_race_session") as Dictionary).get("run_node_id", "")) == session.current_node_id, "second race skips the screen"):
		return
	app.call("report_race_result", 1, 1.0, [], false, {})
	app.set("_save_data", STORE.new().call("_normalize", legacy))
	shell.call("_on_art_action", &"new_run")
	await process_frame
	session = app.call("current_run_session")
	shell.call("_go_to_run_stop", session.current_node_id, false)
	await create_timer(0.2).timeout
	if not _expect(shell.find_child("RunDrivingIntro", true, false) == null and not (app.get("current_race_session") as Dictionary).is_empty(), "existing saves skip the screen"):
		return
	app.call("report_race_result", 1, 1.0, [], false, {})
	var fresh: Dictionary = app.call("get_save_data")
	fresh["run_intro_seen"] = false
	app.set("_save_data", fresh)
	shell.call("_on_art_action", &"new_run")
	await process_frame
	session = app.call("current_run_session")
	shell.call("_go_to_run_stop", session.current_node_id, false)
	await process_frame
	await _pad(JOY_BUTTON_A)
	await create_timer(0.2).timeout
	if not _expect(shell.find_child("RunDrivingIntro", true, false) == null and bool((app.call("get_save_data") as Dictionary).get("run_intro_seen", false)) and not (app.get("current_race_session") as Dictionary).is_empty(), "controller A accepts and starts the race"):
		return
	print("RUN_DRIVING_INTRO_TEST PASS")
	quit(0)


func _pad(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _test_default_bindings() -> bool:
	var keys := {
		"accelerate": [KEY_W, KEY_UP], "brake": [KEY_S, KEY_DOWN],
		"steer_left": [KEY_A, KEY_LEFT], "steer_right": [KEY_D, KEY_RIGHT],
		"handbrake": [KEY_SPACE], "boost": [KEY_SHIFT], "reset": [KEY_R],
	}
	for action: String in keys:
		for key: int in keys[action]:
			var event := InputEventKey.new()
			event.keycode = key
			if not _expect(InputMap.action_has_event(action, event), "printed key matches " + action):
				return false
	var pause := InputEventKey.new()
	pause.physical_keycode = KEY_ESCAPE
	if not _expect(InputMap.action_has_event("pause", pause), "printed ESC matches pause"):
		return false
	var buttons := {"handbrake": JOY_BUTTON_A, "boost": JOY_BUTTON_B, "reset": JOY_BUTTON_Y, "pause": JOY_BUTTON_START}
	for action: String in buttons:
		var event := InputEventJoypadButton.new()
		event.button_index = buttons[action]
		if not _expect(InputMap.action_has_event(action, event), "printed pad button matches " + action):
			return false
	var axes := {"accelerate": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "brake": [JOY_AXIS_TRIGGER_LEFT, 1.0], "steer_left": [JOY_AXIS_LEFT_X, -1.0], "steer_right": [JOY_AXIS_LEFT_X, 1.0]}
	for action: String in axes:
		var event := InputEventJoypadMotion.new()
		event.axis = axes[action][0]
		event.axis_value = axes[action][1]
		if not _expect(InputMap.action_has_event(action, event), "printed pad axis matches " + action):
			return false
	return true


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RUN_DRIVING_INTRO_TEST FAIL: " + message)
		quit(1)
	return condition
