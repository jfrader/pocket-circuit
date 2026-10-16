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
	var destination := String(sess.available_nodes()[0]["id"])
	_shell.call("_go_to_run_stop", destination, false)
	var contract: Dictionary = _app.get("current_race_session")
	_expect(contract.get("mode") == "chase_sprint" and contract.get("vehicle_id") == won and contract.get("event", {}).get("race_format") == "strip", "hot travel starts strip sprint instead of tween")
	_expect(contract.get("chaser", {}).get("vehicle_id") == sess.pending_chaser["chase_vehicle_id"], "sprint uses robbed driver's spare")
	_app.call("resolve_run_sprint", "RESCUED", {"terminal": false})
	_expect(sess.boot_cars.has(won) and sess.pending_chaser != null, "rescue keeps driving")
	_app.call("resolve_run_sprint", "ARRIVED", {"terminal": true})
	_expect(sess.boot_cars.is_empty() and sess.pending_chaser == null and sess.current_node_id == destination, "arrival banks and opens destination")
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
	sess.pending_offer_driver = {}
	_shell.call("show_run_offer")
	_expect(_button("ActionTakeOffer") == null and _button("ActionSendAhead") != null and _button("ActionKeepCar") != null, "ineligible hot choice hidden")
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
	if _failed:
		quit(1)
		return
	print("RUN_HAUL_UI_TEST PASS")
	quit(0)


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
