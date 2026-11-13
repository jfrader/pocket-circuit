class_name PocketCircuitPlaythrough
extends SceneTree
## Run with a fresh XDG_DATA_HOME, rendered Compatibility backend and fixed FPS.
## PC_QA_OUT selects the evidence directory; PC_QA_SEED seeds route tie-breaks.
## PLAY randomizes its own night seed: journal the actual seed, never inject one.
## Import classes headlessly first, then use --main-loop PocketCircuitPlaythrough.
## Do not use --script: App intentionally suppresses race transitions in test mode.

const DIRECTOR := preload("res://tools/qa/qa_director.gd")
const CIRCUIT_CACHE := preload("res://scripts/race/circuit_cache.gd")
const DEFAULT_OUT := "/tmp/opencode/pocket-circuit-qa/play"
const WALL_BUDGET_MSEC := 840000
const STEP_TIMEOUT := 45.0
const PREWARM_DRAIN_TIMEOUT_MSEC := 180000
const RACE_TIMEOUT := 240.0
const UNSEEN_STOP_SCORE := 100.0
const ROUTE_STEP_COST := 1.0
var _out := DEFAULT_OUT
var _journal: FileAccess
var _app: Node
var _driver: Node
var _started := 0
var _sequence := 0
var _failed := false
var _visited: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _race_count := 0
var _mode := "autopilot"
var _haul_won := false
var _caught := false
var _lockup_seen := false
var _prewarm_drain_started := 0
var _prewarm_drained_msec := -1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_started = Time.get_ticks_msec()
	print("QA DISPLAY driver=", DisplayServer.get_name(), " adapter=", RenderingServer.get_video_adapter_name())
	if not OS.get_environment("PC_QA_MODE").is_empty():
		_mode = OS.get_environment("PC_QA_MODE")
	if not OS.get_environment("PC_QA_OUT").is_empty():
		_out = OS.get_environment("PC_QA_OUT")
	_rng.seed = int(OS.get_environment("PC_QA_SEED")) if not OS.get_environment("PC_QA_SEED").is_empty() else 2426
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("PLAYTHROUGH FAIL: cannot create evidence directory " + _out)
		quit(1)
		return
	_journal = FileAccess.open(_out.path_join("journal.jsonl"), FileAccess.WRITE)
	if _journal == null:
		push_error("PLAYTHROUGH FAIL: cannot write journal")
		quit(1)
		return
	if "--script" in OS.get_cmdline_args():
		_record("boot", "refuse test-mode launch", "", "Use --main-loop PocketCircuitPlaythrough: App suppresses races under --script")
		_journal.close()
		quit(1)
		return
	if current_scene == null:
		var boot := (load("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
		root.add_child(boot)
		current_scene = boot
	_driver = DIRECTOR.new()
	root.add_child(_driver)
	await _wait(1.0)
	_app = root.get_node_or_null("App")
	if _app == null:
		await _fail("App did not boot")
		return
	await _capture("boot", "boot.tscn", "Route policy seed %d; PLAY chooses an independent random night seed; fixed FPS does not make worker completion deterministic" % _rng.seed)
	if _mode not in ["autopilot", "coverage", "resume_a", "resume_b"]:
		await _fail("unknown PC_QA_MODE " + _mode)
		return
	if _mode == "coverage" and not await _title_extras():
		return
	if not await _press_text("PLAY"):
		return
	if not await _wait_screen_change("title"):
		return
	await _capture("first_board", "PLAY", "First-run board and route instructions")
	if _mode == "resume_b":
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("PC_QA_RESUME_FILE")))
		var actual := _night_identity()
		var matches: bool = expected is Dictionary and int(expected.get("seed", -1)) == int(actual.get("seed", -2)) and int(expected.get("act", -1)) == int(actual.get("act", -2)) and expected.get("node") == actual.get("node")
		if not await _expect(matches, "resume_same_night_seed_act_node", {"expected": expected, "actual": actual}):
			return
	if _mode == "coverage" and not await _board_extras():
		return
	var steps := 0
	while not _failed and steps < 100:
		steps += 1
		if not _within_budget():
			await _fail("wall-clock budget exceeded")
			return
		var screen := _screen()
		if screen == "run_board":
			if _board_travelling():
				if not await _wait_screen_change("run_board"):
					return
				continue
			if _mode in ["resume_a", "resume_b"] and _race_count == 1:
				await _finish_resume()
				return
			if _mode == "coverage" and _caught and _visited.has("ransom"):
				_record(screen, "lockup coverage", "visited" if _lockup_seen else "not-present on reachable selected route", "Optional lockup branch; no fabricated lockup")
				_finish("COVERAGE COMPLETE")
				return
			if _visible_text().contains("NIGHT OVER"):
				if _mode != "autopilot":
					await _fail("required coverage branch not reached before night ended: " + _mode)
					return
				if _race_count == 0:
					await _fail("night ended without an observed race outcome")
					return
				await _capture("night_over", "continue to night recap", "Night ended through normal gameplay; visited types: " + ", ".join(_visited.keys()))
				if not await _press_text("BACK"):
					return
				if not await _wait_screen_change("run_board"):
					return
				if _screen() != "title":
					await _fail("night recap BACK did not return to title")
					return
				await _capture("title_return", "BACK", "Completed title → night → night recap → title; races %d" % _race_count)
				_journal.close()
				print("PLAYTHROUGH COMPLETE: ", _out, " races=", _race_count, " visited=", _visited.keys())
				quit(0)
				return
			if not await _board():
				return
		elif screen == "run_driving_intro":
			await _capture("controls", "GO", "First-race controls are visible")
			if not await _press_name("DrivingReady") or not await _wait_screen_change(screen):
				return
		elif screen == "loading" or screen == "race":
			if not await _race():
				return
		elif screen == "transition":
			if not await _wait_screen_change(screen):
				return
		elif screen == "results":
			_race_count += 1
			var session: Dictionary = _app.call("get_current_race_session")
			var result: Dictionary = session.get("result", {})
			await _capture("results", "race finished", "Race %d: %s; resets %d; %s" % [_race_count, "DNF" if bool(result.get("dnf", false)) else "P%d" % int(result.get("position", 0)), int(_driver.get("reset_count")), "RESULT SAVED" if _visible_text().contains("RESULT SAVED") else "RESULT SAVED not visible"])
			if not _visible_text().contains("RESULT SAVED"):
				await _fail("results did not visibly confirm RESULT SAVED")
				return
			if not await _press_text("CONTINUE") or not await _wait_screen_change(screen):
				return
		elif screen == "run_offer":
			if _mode == "coverage" and _visible_text().contains("RACE IT NOW"):
				await _capture("haul_three_way_offer", "SCRIPTED duel win", "Expect RACE IT NOW / SEND IT AHEAD / SEND IT HOME; not an autopilot win")
				if not await _expect(_visible_text().contains("SEND IT AHEAD") and _visible_text().contains("SEND IT HOME"), "three_way_offer", {}):
					return
				_haul_won = true
				if not await _press_name("ActionTakeOffer") or not await _wait_screen_change(screen):
					return
				continue
			await _capture("offer", "open won-car offer", "Bank the offered car without adding a chase")
			if not await _press_name("ActionKeepCar") or not await _wait_screen_change(screen):
				return
		elif screen in ["run_bench", "run_parts_van", "run_lockup", "run_errand"]:
			if not await _stop(screen):
				return
		else:
			await _fail("unhandled screen " + screen)
			return
	if not _failed:
		await _fail("UI step budget exhausted")


func _board() -> bool:
	var night: RunSession = _app.call("current_run_session")
	if night == null:
		await _fail("board has no active night and no visible recap")
		return false
	var choices := night.available_nodes()
	if choices.is_empty():
		await _fail("board has no reachable stop")
		return false
	# Prefer unseen stop types and preserve future unseen choices on the route.
	var chosen: Dictionary = choices[_rng.randi_range(0, choices.size() - 1)]
	var memo := {}
	var best := _route_score(night, chosen, _visited.duplicate(), memo)
	for stop: Dictionary in choices:
		var score := _route_score(night, stop, _visited.duplicate(), memo)
		if score > best:
			best = score
			chosen = stop
	if _mode == "coverage":
		var target := "parts_van" if _caught else "rival" if not _haul_won else "lockup"
		var distance := INF
		for option: Dictionary in choices:
			var candidate := _distance_to(night, option, target)
			if candidate < distance:
				distance = candidate
				chosen = option
	var stop_id := String(chosen["id"])
	var kind := String(chosen["type"])
	var marker: Button = null
	for button: Button in _buttons():
		if String(button.get_meta("stop_id", "")) == stop_id:
			marker = button
			break
	if marker == null:
		await _fail("reachable stop has no visible marker " + stop_id)
		return false
	await _click(marker)
	await _capture("board_" + kind, "pick " + stop_id, "Night %d act %d; selected %s; reachable choices %s" % [night.run_seed, night.current_map.act, kind, JSON.stringify(choices)])
	if _screen() == "run_board":
		if not _board_travelling() and not await _press_name("RunGo"):
			return false
		if not await _wait_screen_change("run_board"):
			return false
	_visited[kind] = true
	return true


func _board_travelling() -> bool:
	var shell := _app.get("_shell") as Node
	return shell != null and bool(shell.get("_run_going"))


func _route_score(night: RunSession, stop: Dictionary, seen: Dictionary, memo: Dictionary) -> float:
	var seen_types := seen.keys()
	seen_types.sort()
	var key := String(stop["id"]) + "|" + ",".join(seen_types)
	if memo.has(key):
		return float(memo[key])
	var kind := String(stop["type"])
	var score := 0.0 if seen.has(kind) else UNSEEN_STOP_SCORE
	seen[kind] = true
	var children := night.current_map.get_children(String(stop["id"]))
	var future := 0.0 if children.is_empty() else -INF
	for child: Dictionary in children:
		future = maxf(future, _route_score(night, child, seen.duplicate(), memo))
	# Type coverage dominates the bounded ten-row map; a shorter path breaks
	# ties and avoids revisiting an empty, still-pending bench.
	score += future - ROUTE_STEP_COST
	memo[key] = score
	return score


func _stop(screen: String) -> bool:
	if screen == "run_lockup":
		_lockup_seen = true
	if _mode == "coverage" and _caught and screen == "run_parts_van":
		var ransom: Button = null
		for button: Button in _buttons():
			if String(button.name).begins_with("VanRansom_"):
				ransom = button
				break
		if not await _expect(ransom != null and not ransom.disabled, "van_ransom_available", {}):
			return false
		ransom.grab_focus()
		var ancestor := ransom.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				(ancestor as ScrollContainer).ensure_control_visible(ransom)
			ancestor = ancestor.get_parent()
		await _wait(0.5)
		var visible_rect := root.get_visible_rect()
		ancestor = ransom.get_parent()
		while ancestor is Control:
			if (ancestor as Control).clip_contents:
				visible_rect = visible_rect.intersection((ancestor as Control).get_global_rect())
			ancestor = ancestor.get_parent()
		var rect := ransom.get_global_rect()
		if not await _expect(visible_rect.encloses(rect), "van_ransom_visible_in_viewport", {"button_rect": str(rect), "unclipped_viewport": str(visible_rect)}):
			return false
		await _capture("van_ransom_before", "focus and scroll ransom into view", "Entire ransom control is inside its unclipped viewport; scripted haul/capture setup")
		var night: RunSession = _app.call("current_run_session")
		var vehicle_id := String(ransom.name).trim_prefix("VanRansom_")
		var points_before := night.run_points
		var current_before := night.current_car_id
		if not await _expect(night.impounded_cars.has(vehicle_id), "van_ransom_previously_impounded", {"vehicle_id": vehicle_id}):
			return false
		await _click(ransom)
		await _capture("van_ransom_after", "pay ransom via visible button", "Verify exact points debit and return to safe collection; ransom does not switch current car")
		var returned := false
		for car: Dictionary in night.collection_safe_cars():
			returned = returned or String(car["id"]) == vehicle_id
		if not await _expect(night.run_points == points_before - RunSession.HAUL_RANSOM_POINTS and not night.impounded_cars.has(vehicle_id) and returned and night.current_car_id == current_before, "van_ransom_paid_and_car_returned", {"vehicle_id": vehicle_id, "points_before": points_before, "points_after": night.run_points, "impounded": night.impounded_cars, "returned_to_safe_collection": returned, "current_car_before": current_before, "current_car_after": night.current_car_id}):
			return false
		_visited["ransom"] = true
		if _screen() == screen and not await _press_name("ActionBack"):
			return false
		return await _wait_screen_change(screen)
	var action: Button = null
	var prefixes: Dictionary = {"run_bench": ["BenchRepair", "BenchFit_", "BenchBankHaul"], "run_parts_van": ["VanBuy_"], "run_lockup": ["LockupOpen"], "run_errand": ["ErrandTuneUp", "ErrandPay"]}
	for prefix: String in prefixes[screen]:
		for button: Button in _buttons():
			if not button.disabled and String(button.name).begins_with(prefix):
				action = button
				break
		if action != null:
			break
	await _capture(screen, "visit stop", screen + (": no actions available" if action == null else ": available action " + action.text))
	if is_instance_valid(action) and _screen() == screen:
		var text := action.text
		await _click(action)
		await _capture(screen + "_action", text, "Visible outcome after stop action")
	if _screen() == screen:
		if not await _press_name("ActionBack"):
			return false
	return await _wait_screen_change(screen)


func _race() -> bool:
	var elapsed := 0.0
	var captured := false
	var watched: VehicleController = null
	var next_shot := 20.0
	var wear_beat := ""
	var towed := false
	while _screen() in ["loading", "race", "transition"] and elapsed < RACE_TIMEOUT and _within_budget():
		if _screen() == "race":
			var scene := current_scene
			var beat := String(scene.get("wear_out_beat"))
			if not beat.is_empty() and beat != wear_beat:
				wear_beat = beat
				towed = bool(scene.get("_wear_out_towed"))
				_driver.call("release_inputs")
				await _capture("wear_" + beat, "automatic wear-out sequence", "Race %d: %s; tow %s; this UI path returns to the board without a results panel" % [_race_count + 1, beat, str(towed)])
				if not is_instance_valid(scene) or current_scene != scene:
					await process_frame
					continue
			var manager := scene.get("race_manager") as RaceManager
			var player := scene.get("_player_vehicle") as VehicleController
			if manager != null and player != null and manager.is_running and watched != player:
				watched = player
				# AI's surface/traffic caches belong to one race, just like promo's
				# per-car driver. Never carry freed track nodes into the next race.
				_driver.set_physics_process(false)
				_driver.call("release_inputs")
				_driver.queue_free()
				_driver = DIRECTOR.new()
				root.add_child(_driver)
				_driver.call("watch", player, manager)
			if watched != null and not captured:
				var metrics: Dictionary = _app.get("loading_metrics")
				_record("race", "load phases", JSON.stringify(metrics), "App.loading_metrics; phase durations in milliseconds, not screenshot gaps")
				print("QA LOAD PHASES ", _mode, " ", JSON.stringify(metrics))
				print("QA DISK CACHE ", _mode, " hits=", CIRCUIT_CACHE.hits, " misses=", CIRCUIT_CACHE.misses)
				if _mode == "resume_b" and not await _expect(CIRCUIT_CACHE.hits > 0, "warm_process_disk_cache_hit", {"hits": CIRCUIT_CACHE.hits, "misses": CIRCUIT_CACHE.misses}):
					return false
				await _capture("race_go", "accelerate / steer / brake / drift / boost via input events", "Player control remains enabled; no AI assists or private recovery")
				captured = true
				if _mode == "coverage":
					return await _scripted_race(scene)
			if elapsed >= next_shot and is_instance_valid(player) and is_instance_valid(manager) and current_scene == scene:
				await _capture("race_progress", "autopilot inputs", "P%d; progress %.1f; race time %.1f; R recoveries %d" % [manager.get_racer_position(player), manager.get_racer_progress(player), manager.race_time, int(_driver.get("reset_count"))])
				next_shot += 30.0
		await process_frame
		elapsed += root.get_process_delta_time()
	_driver.call("release_inputs")
	if not wear_beat.is_empty() and _screen() == "run_board":
		_race_count += 1
		await _capture("tow_return" if towed else "wear_return", "automatic return to board", "Race %d ended through %s; no results panel is presented on this path" % [_race_count, "tow" if towed else "wear-out"])
		return true
	if _screen() != "results":
		await _fail("race/loading blocked without results after %.1f simulation seconds" % elapsed)
		return false
	await _wait(1.0)
	return true


func _expect(passed: bool, expectation: String, details: Dictionary) -> bool:
	_journal.store_line(JSON.stringify({"expectation": expectation, "passed": passed, "details": details, "mode": _mode}))
	_journal.flush()
	if not passed:
		await _fail("expectation failed: " + expectation + " " + JSON.stringify(details))
	return passed


func _finish(marker: String) -> void:
	_driver.call("release_inputs")
	_journal.close()
	print(marker, ": ", _out)
	quit(0)


func _night_identity() -> Dictionary:
	var night: RunSession = _app.call("current_run_session")
	return {} if night == null else {"seed": night.run_seed, "act": night.current_map.act, "node": night.current_node_id}


func _finish_resume() -> void:
	if not await _expect(not _night_identity().is_empty(), "resume_night_still_active", _night_identity()):
		return
	await _capture("resume_board", "one honest autopilot race completed", JSON.stringify(_night_identity()))
	if _mode == "resume_a":
		var file := FileAccess.open(OS.get_environment("PC_QA_RESUME_FILE"), FileAccess.WRITE)
		if file == null:
			await _fail("cannot write resume identity")
			return
		file.store_string(JSON.stringify(_night_identity()))
		file.close()
	if not await _press_name("ActionBack"):
		return
	if not await _expect(_screen() == "title", "resume_quit_to_title", {}):
		return
	await _capture("resume_title", "BACK then exit process", "Night retained; same XDG profile required on process B")
	var identity := _night_identity()
	_prewarm_drain_started = Time.get_ticks_msec()
	var running_at_title := bool(_app.get("_prewarm_running"))
	_prewarm_drained_msec = -1 if running_at_title else 0
	process_frame.connect(_observe_prewarm_drain)
	if not await _expect(_visible_text().contains("CONTINUE YOUR RUN"), "resume_continue_visible", {"prewarm_running": running_at_title}):
		return
	# PLAY is the title action; CONTINUE YOUR RUN is its saved-night status label.
	if not await _press_text("PLAY") or not await _wait_screen_change("title"):
		return
	if not await _expect(_screen() == "run_board" and _night_identity() == identity, "resume_title_interactive_same_night", {"expected": identity, "actual": _night_identity(), "prewarm_running_at_title": running_at_title, "prewarm_running_after_press": bool(_app.get("_prewarm_running"))}):
		return
	await _capture("resume_continue_board", "PLAY with CONTINUE YOUR RUN", "Title action resumes the same night without waiting for background preparation")
	if not await _press_name("ActionBack"):
		return
	var deadline := _prewarm_drain_started + PREWARM_DRAIN_TIMEOUT_MSEC
	while bool(_app.get("_prewarm_running")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_observe_prewarm_drain()
	process_frame.disconnect(_observe_prewarm_drain)
	var drain := {"elapsed_msec": _prewarm_drained_msec, "observation_window_msec": Time.get_ticks_msec() - _prewarm_drain_started, "bound_msec": PREWARM_DRAIN_TIMEOUT_MSEC, "running_at_title": running_at_title, "settled": not bool(_app.get("_prewarm_running"))}
	_record("title", "resume prewarm drain", JSON.stringify(drain), "Frame-observed wall-clock drain since first return to title; -1 means still pending at bound, 0 means already settled; a pending worker is not a frozen title")
	print("QA PREWARM DRAIN ", _mode, " ", JSON.stringify(drain))
	if not await _expect(_screen() == "title" and _visible_text().contains("CONTINUE YOUR RUN") and _night_identity() == identity, "resume_title_usable_night_retained", {"identity": _night_identity(), "drain": drain}):
		return
	_finish("RESUME " + _mode + " COMPLETE")


func _observe_prewarm_drain() -> void:
	if _prewarm_drained_msec < 0 and not bool(_app.get("_prewarm_running")):
		_prewarm_drained_msec = Time.get_ticks_msec() - _prewarm_drain_started


func _key_input(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await _wait(0.4)


func _title_extras() -> bool:
	if not await _press_text("QUICK RACE"):
		return false
	await _capture("quick_race_preview", "QUICK RACE", "Preview before selecting a car")
	var change: Button = null
	for button: Button in _buttons():
		if button.text.begins_with("CHANGE CAR"):
			change = button
	if not await _expect(change != null and _screen() == "quick_race", "quick_race_preview", {}):
		return false
	await _click(change)
	await _capture("garage_grid", "CHANGE CAR", "Quick Race garage; fresh profile stock roster, not a 45-car save")
	var first := root.gui_get_focus_owner()
	await _key_input(KEY_DOWN)
	await _key_input(KEY_RIGHT)
	await _capture("garage_focus_rows", "DOWN / RIGHT", "Focus crosses garage rows via player keyboard input")
	if not await _expect(_screen() == "vehicle_select" and root.gui_get_focus_owner() != first, "garage_focus_moved", {}):
		return false
	if not await _press_text("BACK"):
		return false
	if not await _expect(_screen() == "quick_race", "garage_back_preserves_quick_race", {}):
		return false
	if not await _press_text("BACK TO TITLE") or not await _press_text("QUICK STRIP"):
		return false
	await _capture("quick_strip_preview", "QUICK STRIP", "Strip preview; no exhibition race started")
	if not await _expect(_screen() == "quick_strip", "quick_strip_preview", {}):
		return false
	return await _press_text("BACK TO TITLE")


func _board_extras() -> bool:
	if not await _press_name("ActionHelp"):
		return false
	await _capture("board_help", "?", "Expect run instruction slip")
	if not await _expect(_visible_text().contains("SURVIVE THE NIGHT"), "board_help_open", {}):
		return false
	await _key_input(KEY_SHIFT)
	if not await _expect(not _visible_text().contains("SURVIVE THE NIGHT"), "board_help_dismissed", {}):
		return false
	var before := RunSession.serialize(_app.call("current_run_session"))
	if not await _press_name("ActionAbandon"):
		return false
	await _capture("abandon_confirm", "ABANDON RUN", "Confirm strip; do not abandon")
	if not await _press_name("ActionKeepDriving"):
		return false
	await _capture("keep_driving", "KEEP DRIVING", "Same live night after cancel")
	return await _expect(before == RunSession.serialize(_app.call("current_run_session")), "keep_driving_preserves_night", {})


func _distance_to(night: RunSession, stop: Dictionary, kind: String) -> float:
	if String(stop["type"]) == kind:
		return 0.0
	var result := INF
	for child: Dictionary in night.current_map.get_children(String(stop["id"])):
		result = minf(result, 1.0 + _distance_to(night, child, kind))
	return result


func _scripted_race(scene: Node) -> bool:
	_driver.set_physics_process(false)
	_driver.call("release_inputs")
	var session: Dictionary = _app.call("get_current_race_session")
	if String(session.get("mode", "")) == "chase_sprint":
		await _capture("chase_start", "SCRIPTED coverage, no autopilot claim", "First seconds of haul chase")
		await _wait(2.0)
		if current_scene != scene:
			await _fail("chase ended before capture")
			return false
		var controller := scene.get("_strip_controller") as Node
		if not await _expect(controller != null, "chase_controller_present", {}):
			return false
		await _capture("chase_capture_arc", "observe pursuit", "capture_fraction=" + str(controller.call("capture_fraction")) + "; arc is conditional on exposure")
		_record("race", "SCRIPTED force CAUGHT", "resolve_run_sprint(CAUGHT)", "Explicit coverage seam, not an earned gameplay outcome")
		_app.call("resolve_run_sprint", "CAUGHT", {})
		if not await _wait_screen_change("race"):
			return false
		_caught = true
		await _capture("haul_impounded", "SCRIPTED CAUGHT", "Impound note after forced chase outcome")
		return await _expect(_visible_text().contains("IMPOUNDED"), "haul_impounded", {})
	_record("race", "SCRIPTED report_race_result win", "position=1 time=30.0", "Test win seam; never counted as honest autopilot coverage")
	if not await _expect(bool(_app.call("report_race_result", 1, 30.0, [], false, {})), "scripted_result_saved", {}):
		return false
	_app.call("continue_after_race")
	return await _wait_screen_change("race")


func _screen() -> String:
	if _app == null:
		return "boot"
	if bool(_app.call("is_race_loading")):
		return "loading"
	if current_scene != null:
		var results := current_scene.find_child("ResultsPanel", true, false) as Control
		if results != null and results.is_visible_in_tree():
			return "results"
		if current_scene.get("race_manager") is RaceManager:
			return "race"
	var shell := _app.get("_shell") as Node
	return String(shell.get("_screen")) if shell != null and bool(shell.get("visible")) else "transition"


func _buttons() -> Array[Button]:
	var result: Array[Button] = []
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and not button.is_queued_for_deletion():
			result.append(button)
	return result


func _press_name(button_name: String) -> bool:
	for button: Button in _buttons():
		if String(button.name) == button_name and not button.disabled:
			await _click(button)
			return true
	await _fail("no enabled visible button " + button_name)
	return false


func _press_text(text: String) -> bool:
	for button: Button in _buttons():
		if button.text == text and not button.disabled:
			await _click(button)
			return true
	await _fail("no enabled visible button text " + text)
	return false


func _click(button: Button) -> void:
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled:
		await _fail("button disappeared or became unavailable before input")
		return
	var text := button.text
	var before := _screen()
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await _wait(1.0)
	_record(before, "click " + text, _visible_text(), "Observed screen after input: " + _screen())


func _wait_screen_change(before: String) -> bool:
	var elapsed := 0.0
	while _screen() == before and elapsed < STEP_TIMEOUT and _within_budget():
		await _wait(0.25)
		elapsed += 0.25
	if _screen() == before:
		await _fail("no transition seen from " + before)
		return false
	await _wait(0.75)
	return true


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _within_budget() -> bool:
	return Time.get_ticks_msec() - _started < WALL_BUDGET_MSEC


func _visible_text() -> String:
	var lines := PackedStringArray()
	for node: Node in root.find_children("*", "Control", true, false):
		if not (node as Control).is_visible_in_tree():
			continue
		if node is Label or node is Button or node is RichTextLabel:
			var text := String(node.get("text"))
			if not text.is_empty():
				lines.append(text)
	return "\n".join(lines)


func _capture(label: String, action: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	_sequence += 1
	var path := _out.path_join("%02d-%s.png" % [_sequence, label])
	var error := root.get_texture().get_image().save_png(path)
	_record(_screen(), action, _visible_text(), note, path if error == OK else "")
	if error != OK:
		_failed = true
		push_error("PLAYTHROUGH FAIL: screenshot write failed " + path)
		quit(1)


func _record(screen: String, action: String, outcome: String, note: String, screenshot := "") -> void:
	_journal.store_line(JSON.stringify({"timestamp": Time.get_datetime_string_from_system(true), "elapsed_msec": Time.get_ticks_msec() - _started, "physics_frame": Engine.get_physics_frames(), "screen": screen, "action": action, "visible_outcome": outcome, "player_lens_note": note, "screenshot": screenshot}))
	_journal.flush()
	print("QA ", screen, " | ", action, " | ", note)


func _fail(reason: String) -> void:
	_failed = true
	if is_instance_valid(_driver):
		_driver.call("release_inputs")
	await _capture("blocked", "stop", reason)
	push_error("PLAYTHROUGH FAIL: " + reason)
	_journal.close()
	quit(1)
