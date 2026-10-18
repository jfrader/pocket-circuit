extends SceneTree

const SESSION := preload("res://scripts/progression/run_session.gd")
var _failed := false
var _app: Node
var _shell: CanvasLayer


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	_app = root.get_node("App")
	_shell = _app.get("_shell")
	var sess := _offer()
	_shell.call("show_run_offer")
	_expect(_button("ActionTakeOffer").text == "RACE IT NOW", "hot offer action")
	_expect(_button("ActionSendAhead").text == "SEND IT AHEAD · %d POINTS" % sess.pending_offer_points, "exact ahead price")
	_expect(_button("ActionKeepCar").text == "SEND IT HOME", "home action")
	for copy: String in ["The driver you took it from chases you on the next sprint", "Spend this win's points, nobody chases you", "In your collection next night, keep your points"]:
		_expect(_has_copy(copy), "literal offer copy: " + copy)
	_expect(_shell.find_child("OfferDriver", true, false) != null, "robbed driver's portrait and name")
	var won := sess.pending_offer
	_button("ActionTakeOffer").pressed.emit()
	_expect(sess.pending_chaser != null and sess.boot_cars.has(won), "hot button invokes domain")
	_expect(_has_copy("HAULING %s - CHASED ON THE NEXT CONNECTOR" % str(preload("res://scripts/ui/run_ui.gd").car_name(won)).to_upper()), "board names the carried car and pending chaser")
	await process_frame
	await process_frame
	var legend := _shell.find_child("RunLegend", true, false) as Control
	_expect(legend != null and legend.get_global_rect().end.y <= root.get_visible_rect().end.y + 1.0, "pending chase status must not push the board legend below the viewport")
	var destination := String(sess.available_nodes()[0]["id"])
	var board := _shell.get("_run_board") as Control
	var status_labels := board.get_node("RunStateLabels") as Control
	for marker: Node in board.get_children():
		if marker is Button:
			_expect(not status_labels.get_global_rect().intersects((marker as Button).get_global_rect()), "pending state must not cover a route marker")
	var token := board.get_node("CarToken") as Control
	var token_position := token.position
	_shell.call("_go_to_run_stop", destination, false)
	var contract: Dictionary = _app.get("current_race_session")
	_expect(contract.get("mode") == "chase_sprint" and contract.get("vehicle_id") == won and contract.get("event", {}).get("race_format") == "strip", "hot edge starts strip sprint immediately instead of waiting for travel")
	_expect(not bool(board.get("_travelling")) and token.position == token_position, "hot sprint is the connector, without a map travel tween")
	_expect(contract.get("chaser", {}).get("vehicle_id") == sess.pending_chaser["chase_vehicle_id"], "sprint uses robbed driver's spare")
	_app.call("resolve_run_sprint", "RESCUED", {"terminal": false})
	_expect(sess.boot_cars.has(won) and sess.pending_chaser != null, "rescue keeps driving")
	_app.call("resolve_run_sprint", "ARRIVED", {"terminal": true})
	_expect(sess.boot_cars.is_empty() and sess.pending_chaser == null and sess.current_node_id == destination, "arrival banks and opens destination")
	_shell.call("show_run_board")
	_expect(_shell.find_child("RunHaulStatus", true, false) == null, "haul status disappears when the chase resolves")
	sess = _offer()
	won = sess.pending_offer
	_app.call("run_race_it_now")
	_shell.call("show_run_board")
	destination = String(sess.available_nodes()[0]["id"])
	_shell.call("_go_to_run_stop", destination, false)
	_app.call("resolve_run_sprint", "CAUGHT", {"terminal": true})
	_expect(sess.impounded_cars.has(won) and sess.boot_cars.is_empty() and _shell.get("_screen") == "run_board", "capture impounds and returns board")
	_expect(_shell.find_child("HaulNote", true, false) != null, "capture has impound note")
	_move_to(sess, "parts_van")
	sess.run_points = SESSION.HAUL_RANSOM_POINTS
	_shell.call("show_run_parts_van")
	var ransom := _button("VanRansom_" + won)
	_expect(ransom != null and str(SESSION.HAUL_RANSOM_POINTS) in ransom.text, "van displays ransom price")
	ransom.pressed.emit()
	_expect(sess.impounded_cars.is_empty() and sess.run_points == 0 and sess.resolved_nodes.has(sess.current_node_id), "ransom debits points and consumes visit")
	_shell.call("show_run_parts_van")
	_expect(_shell.find_children("VanRansom_*", "Button", true, false).is_empty(), "no ransom without impound")
	sess = _offer()
	var original_rosters := sess.node_opponents.duplicate(true)
	for act: Dictionary in sess.node_opponents.values():
		for roster: Dictionary in act.values():
			for opponent: Dictionary in roster["opponents"]:
				opponent["vehicle_id"] = sess.pending_offer_driver["vehicle_id"]
	_shell.call("show_run_offer")
	var hot := _button("ActionTakeOffer")
	_expect(hot != null and hot.visible and hot.text == "RACE IT NOW" and hot.disabled, "ineligible hot choice remains visible and disabled")
	_expect(_has_copy("NO SPARE CAR FOR THE CHASE"), "ineligible hot choice explains the missing spare")
	_expect(not sess.can_race_hot(sess.pending_offer) and not bool(_app.call("run_race_it_now")), "disabled hot choice cannot bypass the domain rule")
	_expect(_button("ActionSendAhead") != null and _button("ActionKeepCar") != null, "eligible choices remain available")
	sess.node_opponents = original_rosters
	_app.call("run_send_it_ahead")
	_move_to(sess, "bench")
	_shell.call("show_run_bench")
	_expect(_button("BenchBankHaul") != null, "bank action appears with boot")
	_button("BenchBankHaul").pressed.emit()
	_expect(sess.boot_cars.is_empty() and sess.bench_action_done and not sess.bench_repair(sess.current_car_id), "bank uses bench's one action")
	_shell.call("show_run_bench")
	_expect(_button("BenchBankHaul") == null, "no bank action without boot")
	sess = _offer()
	won = sess.pending_offer
	_app.call("run_race_it_now")
	_shell.call("show_run_board")
	_shell.call("_go_to_run_stop", String(sess.available_nodes()[0]["id"]), false)
	_app.call("abandon_race")
	_expect(sess.impounded_cars.has(won) and _shell.get("_screen") == "run_board", "pause abandon impounds")
	sess = _offer()
	won = sess.pending_offer
	_app.call("run_send_it_ahead")
	_app.call("abandon_run")
	_expect(won not in _app.call("garage_car_ids"), "night-end excludes unbanked boot car")
	_shell.call("show_run_board")
	_expect(_has_copy("LOST · " + str(preload("res://scripts/ui/run_ui.gd").car_name(won)).to_upper()), "terminal recap itemizes lost car")
	var boss := SESSION.create(33333)
	_move_to(boss, "act_rival")
	var boss_result := boss.resolve_race(boss.current_node_id, 1, 4)
	_app.set("_current_run_session", boss)
	_app.set("current_race_session", {})
	_app.call("persist_current_run")
	preload("res://scripts/progression/driver_directory.gd").install_opponents([boss.pending_offer_driver])
	_shell.call("show_run_board")
	_expect(boss_result.get("act_advanced", false) and boss.current_map.act == 2, "act-rival win still advances the act")
	_expect(_shell.get("_screen") == "run_offer" and _button("ActionTakeOffer") != null and _button("ActionSendAhead") != null and _button("ActionKeepCar") != null, "act-rival win opens the normal three-way offer after advancing")
	_expect(not _button("ActionTakeOffer").disabled, "eligible act-rival hot choice is enabled")
	_test_tow_status()
	if _failed:
		quit(1)
		return
	print("RUN_HAUL_UI_TEST PASS")
	quit(0)


func _test_tow_status() -> void:
	var sess := SESSION.create(33333)
	sess.resolve_race(sess.current_node_id, 1, 6)
	sess.add_tow()
	sess.run_state.set_car_wear(sess.current_car_id, "dented")
	sess.register_crash(1.0)
	_app.set("_current_run_session", sess)
	_shell.call("show_run_board")
	_expect(sess.towed_to_bench and _has_copy("TOWED - THE NEXT BENCH VISIT IS SPENT"), "board explains the pending tow's bench cost")
	for parent: Dictionary in sess.current_map.nodes.values():
		for child: Dictionary in sess.current_map.get_children(parent["id"]):
			if child["type"] == "bench":
				sess.current_node_id = parent["id"]
				sess.resolved_nodes[parent["id"]] = true
				_expect(sess.enter_node(child["id"]) and sess.bench_action_done, "entering the next bench spends the tow visit")
				_shell.call("show_run_board")
				_expect(not sess.towed_to_bench and _shell.find_child("RunTowStatus", true, false) == null, "tow status disappears once the bench visit is spent")
				return
	_expect(false, "tow fixture has a reachable bench")


func _offer() -> RunSession:
	var sess := SESSION.create(33333)
	_move_to(sess, "rival")
	sess.resolve_rival(sess.current_node_id, true)
	_app.set("_current_run_session", sess)
	_app.set("current_race_session", {})
	_app.call("persist_current_run")
	preload("res://scripts/progression/driver_directory.gd").install_opponents([sess.pending_offer_driver])
	return sess


func _move_to(sess: RunSession, kind: String) -> void:
	for node: Dictionary in sess.current_map.nodes.values():
		if node["type"] == kind:
			sess.current_node_id = node["id"]
			sess.run_state.row = node["row"]
			if kind == "bench":
				sess.last_bench_visited = node["id"]
				sess.bench_action_done = false
			return
	_expect(false, "fixture stop exists: " + kind)


func _button(node_name: String) -> Button:
	return _shell.find_child(node_name, true, false) as Button


func _has_copy(copy: String) -> bool:
	for label: Node in _shell.find_children("*", "Label", true, false):
		if label.text == copy:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("RUN_HAUL_UI_TEST FAIL: " + message)
