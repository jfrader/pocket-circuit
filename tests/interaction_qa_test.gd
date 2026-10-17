extends SceneTree

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
var app: Node
var shell: CanvasLayer
var _failed := false
var _checks := 0
var _coverage: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	root.size = Vector2i(1280, 720)
	app = root.get_node("App")
	var boot := preload("res://scenes/boot/boot.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	await _settle()
	shell = app.get("_shell")
	var store := SAVE_STORE.new("user://tests/interaction_qa_test.json")
	store.remove_save()
	app.set("_save_store", store)
	app.call("update_setting", "reduced_motion", true)
	await _title_and_settings()
	await _board_confirmation()
	await _stops()
	await _offers()
	await _endings()
	await _race()
	for covered: String in _coverage:
		print("INTERACTION_QA_COVERED ", covered)
	store.remove_save()
	shell.call("show_title")
	await _settle()
	var leave := _text_button(shell, "QUIT")
	if not _expect(leave != null, "title QUIT exists"):
		_finish()
		return
	leave.pressed.connect(func() -> void:
		print("INTERACTION_QA_COVERED title QUIT (real input exits)")
		_finish())
	await _activate(leave)
	_expect(false, "QUIT must exit after real input")
	_finish()


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("INTERACTION_QA_TEST PASS checked=", _checks)
	quit(0)


func _title_and_settings() -> void:
	var destinations := {"PLAY": "run_board", "CHAMPIONSHIP": "map", "QUICK RACE": "quick_race", "QUICK STRIP": "quick_strip", "OPTIONS": "settings", "DISCOVERY": "discovery", "CREDITS": "credits"}
	for title: String in destinations:
		shell.call("show_title")
		await _settle()
		await _activate(_text_button(shell, title))
		_expect(shell.get("_screen") == destinations[title], "title " + title + " opens " + destinations[title])
		_coverage.append("title " + title)
	shell.call("show_settings")
	await _settle()
	var content: Control = shell.get("_content")
	var difficulty := content.find_child("Difficulty", true, false) as OptionButton
	if difficulty == null:
		for node: Node in content.find_children("*", "OptionButton", true, false):
			difficulty = node as OptionButton
	_expect(difficulty != null, "settings difficulty exists")
	if difficulty != null:
		var before := difficulty.selected
		var saved_before: String = app.call("get_save_data")["difficulty"]
		await _focus(difficulty)
		await _key(KEY_ENTER)
		await _key(KEY_DOWN)
		await _key(KEY_ENTER)
		_expect(difficulty.selected != before and app.call("get_save_data")["difficulty"] != saved_before, "difficulty changes saved setting through popup keyboard input")
	var volume_keys := ["master_volume", "music_volume", "sfx_volume", "engine_volume", "tyre_volume"]
	var slider_index := 0
	for node: Node in content.find_children("*", "HSlider", true, false):
		var slider := node as HSlider
		var before := slider.value
		await _focus(slider)
		await _key(KEY_LEFT if before > slider.min_value else KEY_RIGHT)
		_expect(not is_equal_approx(slider.value, before) and is_equal_approx(float(app.call("get_save_data")[volume_keys[slider_index]]), slider.value / slider.max_value), "settings saved slider " + volume_keys[slider_index] + " changes")
		slider_index += 1
	_expect(slider_index == volume_keys.size(), "all five audio rows exercised")
	var toggle_keys := {"Fullscreen": "fullscreen", "Reduced camera shake": "reduced_camera_shake", "Reduced motion": "reduced_motion"}
	for node: Node in content.find_children("*", "CheckButton", true, false):
		var toggle := node as CheckButton
		var before := toggle.button_pressed
		await _activate(toggle)
		_expect(toggle.button_pressed != before and app.call("get_save_data")[toggle_keys[toggle.text]] == toggle.button_pressed, "settings saved " + toggle.text + " toggles")
		# Restore immediately; the rest of the sweep needs reduced motion.
		await _activate(toggle)
	await _activate(_text_button(shell, "BACK"))
	_expect(shell.get("_screen") == "title", "settings BACK returns to title")
	_coverage.append("settings difficulty, five audio sliders, fullscreen, camera shake, reduced motion, BACK")


func _board_confirmation() -> void:
	app.call("start_new_run")
	shell.call("show_run_board")
	await _settle()
	await _click(_button("ActionAbandon"))
	var keep := _button("ActionKeepDriving")
	if not _expect(keep != null, "mouse ABANDON opens confirmation"):
		return
	_expect(keep.has_focus(), "safe choice receives focus")
	await _focus(keep)
	await _capture("abandon")
	await _click(keep)
	_expect(shell.find_child("AbandonConfirm", true, false) == null, "mouse KEEP DRIVING dismisses confirmation")
	_expect(_button("ActionAbandon").has_focus(), "KEEP DRIVING restores abandon focus")
	await _activate(_button("ActionAbandon"))
	await _key(KEY_TAB)
	_expect(_button("ActionConfirmAbandon").has_focus(), "Tab reaches destructive choice from safe choice")
	await _key(KEY_ENTER)
	_expect(app.call("current_run_session") == null and shell.get("_screen") == "title", "keyboard ABANDON THE NIGHT ends the run")
	app.call("start_new_run")
	shell.call("show_run_board")
	await _settle()
	await _activate(_button("ActionAbandon"))
	await _activate(_button("ActionKeepDriving"))
	_expect(_button("ActionAbandon").has_focus(), "keyboard KEEP DRIVING restores focus")
	await _click(_button("ActionAbandon"))
	await _focus(_button("ActionConfirmAbandon"))
	await _click(_button("ActionConfirmAbandon"))
	_expect(app.call("current_run_session") == null, "mouse ABANDON THE NIGHT ends the run")
	var session := _stop("bench")
	shell.call("show_run_board")
	await _settle()
	var board: Control = shell.get("_run_board")
	var marker: Control = board.call("marker", session.current_node_id)
	await _focus(marker)
	board.call("preview", String(session.current_map.get_children(session.current_node_id)[0]["id"]))
	await _click(marker)
	_expect(board.call("selected_id") == session.current_node_id, "board marker click selects a reachable stop")
	await _activate(_button("RunGo"))
	_expect(shell.get("_screen") == "run_bench", "board GO opens selected bench")
	await _activate(_button("ActionBack"))
	_expect(shell.get("_screen") == "run_board", "bench BACK returns to board")
	await _activate(_button("ActionBack"))
	_expect(shell.get("_screen") == "title", "board BACK returns to title")
	_coverage.append("board marker mouse, GO, BACK; abandon/keep/confirm mouse and keyboard; confirmation Tab traversal")


func _stops() -> void:
	for action: String in ["repair", "fit", "bank", "swap", "back"]:
		var session := _stop("bench")
		session.run_state.set_car_wear(session.current_car_id, "rusty")
		if action == "fit":
			session.parts_held.append(RunParts.deal(913, session.car_stats(session.current_car_id))[0])
		if action in ["bank", "swap"]:
			session = _offer()
			session.send_it_ahead()
			_move_to(session, "bench")
		shell.call("show_run_bench")
		await _settle()
		match action:
			"repair":
				await _activate(_button("BenchRepair"))
				_expect(session.bench_action_done and session.run_state.get_car_wear(session.current_car_id) != "rusty", "bench REPAIR changes wear")
			"fit":
				await _activate(_button("BenchFit_0"))
				_expect(session.bench_action_done and session.parts_held.is_empty(), "bench FIT consumes held part")
			"bank":
				await _activate(_button("BenchBankHaul"))
				_expect(session.bench_action_done and session.boot_cars.is_empty(), "bench BANK clears boot")
			"swap":
				var before := session.current_car_id
				await _activate(_button("BenchSwap"))
				await _activate(_button("BenchSwapCar_0"))
				_expect(session.bench_action_done and session.current_car_id != before, "bench SWAP changes car")
			"back":
				await _activate(_button("ActionBack"))
				_expect(shell.get("_screen") == "run_board", "bench BACK")
	for index in 3:
		var session := _stop("parts_van")
		session.run_points = 100
		shell.call("show_run_parts_van")
		await _settle()
		var part: Dictionary = session.van_stock()[index]
		await _activate(_button("VanBuy_" + String(part["part"])))
		_expect(session.parts_held.size() > 0 and session.run_points == 100 - RunParts.cost(part), "van stock " + str(index) + " buys part")
	var ransom_session := _offer()
	var car := ransom_session.pending_offer
	ransom_session.race_it_now()
	ransom_session.impound_haul()
	_move_to(ransom_session, "parts_van")
	ransom_session.run_points = RunSession.HAUL_RANSOM_POINTS
	shell.call("show_run_parts_van")
	await _settle()
	await _activate(_button("VanRansom_" + car))
	_expect(ransom_session.impounded_cars.is_empty() and ransom_session.run_points == 0, "van RANSOM debits and releases impound")
	_stop("parts_van")
	shell.call("show_run_parts_van")
	await _settle()
	await _activate(_button("ActionBack"))
	_expect(shell.get("_screen") == "run_board", "van BACK")
	for item: String in ["tow", "nitro"]:
		var consumable_session := _stop("parts_van")
		consumable_session.run_points = 100
		shell.call("show_run_parts_van")
		await _settle()
		var stock := consumable_session.van_offer_consumables()
		var offer: Dictionary = stock[0] if item == "tow" else stock[1]
		var before: int = consumable_session.get(item + "_count")
		if item == "tow":
			await _focus(_button("VanBuy_" + item))
			await _capture("van")
		await _activate(_button("VanBuy_" + item))
		_expect(consumable_session.get(item + "_count") == before + int(offer["count"]) and consumable_session.run_points == 100 - int(offer["price"]) and consumable_session.resolved_nodes.has(consumable_session.current_node_id), "van " + item + " debits points, awards inventory and consumes visit")
		var saved: Dictionary = app.call("get_save_data")["current_run"]
		_expect(saved.get(item + "_count") == consumable_session.get(item + "_count"), "van " + item + " inventory persists")
	for action: String in ["open", "back"]:
		var session := _stop("lockup")
		shell.call("show_run_lockup")
		await _settle()
		await _activate(_button("LockupOpen" if action == "open" else "ActionBack"))
		_expect(session.lockup_used if action == "open" else shell.get("_screen") == "run_board", "lockup " + action)
	for action: String in ["pay", "tune", "back"]:
		var session := _stop("errand")
		session.run_state.set_car_wear(session.current_car_id, "rusty")
		var before := session.run_points
		shell.call("show_run_errand")
		await _settle()
		await _activate(_button({"pay": "ErrandPay", "tune": "ErrandTuneUp", "back": "ActionBack"}[action]))
		match action:
			"pay": _expect(session.run_points == before + RunSession.ERRAND_PAY_POINTS, "errand PAY awards points")
			"tune": _expect(session.run_state.get_car_wear(session.current_car_id) != "rusty", "errand TUNE-UP repairs")
			"back": _expect(shell.get("_screen") == "run_board", "errand BACK")
	_coverage.append("bench repair/fit/bank/swap/back; van all stock/ransom/tow/nitro/back; lockup open/back; errand pay/tune-up/back")


func _offers() -> void:
	for name: String in ["ActionTakeOffer", "ActionSendAhead", "ActionKeepCar", "ActionBack"]:
		var session := _offer()
		var won := session.pending_offer
		shell.call("show_run_offer")
		await _settle()
		if name == "ActionBack":
			await _key(KEY_ESCAPE)
		else:
			await _activate(_button(name))
		if name == "ActionBack":
			_expect(shell.get("_screen") == "title" and not session.pending_offer.is_empty(), "offer BACK preserves decision")
		else:
			_expect(session.pending_offer.is_empty(), "offer choice resolves " + name)
			_expect(won in session.boot_cars if name != "ActionKeepCar" else won not in session.boot_cars, "offer disposition " + name)
	_coverage.append("offer all three choices/BACK")


func _endings() -> void:
	for won: bool in [false, true]:
		for name: String in ["ActionViewGarage", "ActionNewRun", "ActionBack"]:
			var session: RunSession = app.call("start_run", 33333)
			session.completed = won
			session.failed = not won
			shell.call("show_run_board")
			await _settle()
			await _activate(_button(name))
			var expected: String = {"ActionViewGarage": "vehicle_select", "ActionNewRun": "run_board", "ActionBack": "title"}[name]
			_expect(shell.get("_screen") == expected, "night ending " + str(won) + " " + name)
			if name == "ActionNewRun":
				_expect(app.call("current_run_session") != session, "NEW RUN replaces ended session")
	_coverage.append("both night endings VIEW GARAGE/NEW RUN/BACK")


func _race() -> void:
	var session: RunSession = app.call("start_run", 33333)
	app.call("start_run_race", session.current_node_id)
	var race := preload("res://scenes/race/prototype_race.tscn").instantiate()
	root.add_child(race)
	shell.hide()
	# Scene fixtures avoid generated-track loading; all menu actions use input.
	await _settle()
	race.call("_set_paused", true)
	await _settle()
	await _activate(_text_button(race.get("_pause_menu_panel"), "RESUME"))
	_expect(not paused, "pause RESUME resumes race")
	race.call("_set_paused", true)
	await _settle()
	var return_button: Button
	for node: Node in (race.get("_pause_menu_panel") as Node).find_children("*", "Button", true, false):
		if (node as Button).text.begins_with("RETURN"):
			return_button = node as Button
	await _activate(return_button)
	_expect(not paused and app.call("get_current_race_session").is_empty(), "pause RETURN leaves race")
	race.queue_free()
	await _settle()
	session = app.call("start_run", 33333)
	app.call("start_run_race", session.current_node_id)
	race = preload("res://scenes/race/prototype_race.tscn").instantiate()
	root.add_child(race)
	shell.hide()
	await _settle()
	race.set("_results_finalized", true)
	race.set("_night_consequences", "+4 POINTS")
	var results: Array = []
	for index in 6:
		results.append({"position": index + 1, "driver_name": "Driver %d" % index, "vehicle_name": "Rustbug", "time": 42.0 + index, "finished": true, "dnf": false})
	race.call("_update_results", results)
	var panel := race.get("_results_panel") as Control
	panel.show()
	var continue_button := race.get("_continue_button") as Button
	continue_button.disabled = false
	(race.get("_retry_button") as Button).hide()
	await _settle()
	var label := race.get("_results_label") as Label
	_expect(not label.get_global_rect().intersects(continue_button.get_global_rect()), "six-car results text does not overlap CONTINUE")
	_expect(root.get_visible_rect().encloses(panel.get_global_rect()), "six-car results panel and consequences fit 1280x720")
	_expect(label.text.ends_with("RESULT SAVED") and not label.text.contains("CONTINUE"), "results prompt retains RESULT SAVED without repeating CONTINUE")
	await _focus(continue_button)
	await _capture("results")
	await _activate(continue_button)
	_expect(bool(race.get("_left_results")), "results CONTINUE leaves results")
	race.queue_free()
	await _settle()
	shell.show()
	_coverage.append("race pause RESUME/RETURN; six-car results layout and CONTINUE")


func _stop(kind: String) -> RunSession:
	for attempt in 12:
		var session: RunSession = app.call("start_run", 180600 + attempt * 37)
		if RUN_WALK.walk_to(app, session, kind):
			return session
	_expect(false, "fixture reaches " + kind)
	return null


func _offer() -> RunSession:
	var session := RunSession.create(33333)
	_move_to(session, "rival")
	session.resolve_rival(session.current_node_id, true)
	app.set("_current_run_session", session)
	app.set("current_race_session", {})
	app.call("persist_current_run")
	preload("res://scripts/progression/driver_directory.gd").install_opponents([session.pending_offer_driver])
	return session


func _move_to(session: RunSession, kind: String) -> void:
	for node: Dictionary in session.current_map.nodes.values():
		if node["type"] == kind:
			session.current_node_id = node["id"]
			session.run_state.row = node["row"]
			if kind == "bench":
				session.last_bench_visited = node["id"]
				session.bench_action_done = false
			return
	_expect(false, "fixture contains " + kind)


func _text_button(parent: Node, text: String) -> Button:
	for node: Node in parent.find_children("*", "Button", true, false):
		if (node as Button).is_visible_in_tree() and (node as Button).text == text:
			return node as Button
	return null


func _focus(control: Control) -> void:
	if not _expect(control != null and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE, "focus target exists and is focusable"):
		return
	control.grab_focus()
	await _settle()
	_expect(control.has_focus() and root.get_visible_rect().encloses(control.get_global_rect()), "focus is visible in viewport: " + control.name)


func _activate(control: Button) -> void:
	if not _expect(control != null and not control.disabled, "activation target exists and is enabled"):
		return
	await _focus(control)
	await _key(KEY_ENTER)


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await _settle()


func _button(node_name: String) -> Button:
	return shell.find_child(node_name, true, false) as Button


func _capture(screen: String) -> void:
	var directory := OS.get_environment("PC_QA_SHOT_DIR")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png(directory.path_join(screen + ".png")) == OK, "save " + screen + " evidence")


func _settle() -> void:
	for frame in 8:
		await process_frame


func _click(control: Control) -> void:
	if not _expect(control != null and control.is_visible_in_tree(), "click target exists and is visible"):
		return
	var position := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	await process_frame
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await _settle()


func _expect(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failed = true
		push_error("INTERACTION_QA_TEST FAIL: " + message)
	return condition
