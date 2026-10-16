extends SceneTree

const PRESENTER := preload("res://scripts/race/prototype_race.gd")
const CATALOG := preload("res://data/championship/catalog.gd")

var _failed := false
var _presenter: Node2D


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var app := root.get_node("App")
	var shell := app.get("_shell") as CanvasLayer
	_presenter = PRESENTER.new()

	var win: RunSession = app.call("start_run", 33333)
	_expect(_report_copy(app, win, 1) == "+6 POINTS", "opening win reports its exact payout")
	_expect(String(_presenter.call("_night_result_consequences", _presenter.call("_night_result_snapshot", win), win, {})) == "NIGHT UNCHANGED", "no changes are not invented")

	var lost: RunSession = app.call("start_run", 33333)
	lost.run_points = 16
	_move_to(lost, "rival")
	_expect(_report_copy(app, lost, 2) == "RIVAL LOSS: -10 POINTS", "funded rival loss reports the actual charge")
	var broke: RunSession = app.call("start_run", 33333)
	_move_to(broke, "rival")
	_expect(_report_copy(app, broke, 2) == "RIVAL LOSS: -0 POINTS · WEAR: CLEAN -> DUSTY", "unfunded loss reports no invented debit and actual wear")

	var duel: RunSession = app.call("start_run", 33333)
	_move_to(duel, "rival")
	var duel_copy := _report_copy(app, duel, 1)
	var won_car := String(duel.pending_offer)
	var car_name := String(CATALOG.get_vehicle(won_car)["name"]).to_upper()
	_expect(duel_copy == "+6 POINTS · WON: %s - DECIDE AT THE BOARD" % car_name, "rival win names the real offered car")
	_expect(duel.send_it_home(), "fixture banks the duel car")
	_move_to(duel, "act_rival")
	var act_copy := _report_copy(app, duel, 1)
	var nbsp := String.chr(0xA0)
	_expect(act_copy.begins_with("+6 POINTS · WON: ") and act_copy.ends_with(" - DECIDE AT THE BOARD · ACT%s2%sUNLOCKED" % [nbsp, nbsp]), "act victory names its car and unlocked act")

	var defeat: RunSession = app.call("start_run", 33333)
	_move_to(defeat, "act_rival")
	_report_copy(app, defeat, 2)
	shell.call("show_run_board")
	_expect(_label(shell, "NightVerdict") == "DEFEATED BY THE ACT RIVAL", "resolved act rival defeat has its own verdict")
	_expect(_label(shell, "HaulSummary") == "NO HAUL", "empty haul has no zero-count segments")
	_expect(shell.find_child("ActionNewRun", true, false) != null and shell.find_child("ActionBack", true, false) != null, "terminal actions retain their names")

	var worn: RunSession = app.call("start_run", 33333)
	for crash in 8:
		worn.register_crash(1.0)
	app.call("persist_current_run")
	shell.call("show_run_board")
	_expect(_label(shell, "NightVerdict") == "THE CAR GAVE OUT", "wear failure names the car")

	var abandoned: RunSession = app.call("start_run", 33333)
	_move_to(abandoned, "act_rival")
	app.call("abandon_run")
	shell.call("show_run_board")
	_expect(_label(shell, "NightVerdict") == "YOU LEFT THE NIGHT", "abandoning an unresolved act rival is not a defeat")

	var haul: RunSession = app.call("start_run", 33333)
	var banked := haul._add_car("banked", RunSession.CAR_ORIGIN_LOCKUP, ["compact"])
	var impounded := haul._add_car("impounded", RunSession.CAR_ORIGIN_LOCKUP, ["compact"])
	var dropped := haul._add_car("lost", RunSession.CAR_ORIGIN_LOCKUP, ["compact"])
	haul.boot_cars[impounded] = {}
	haul.impound_haul()
	haul.boot_cars[dropped] = {}
	app.call("abandon_run")
	shell.call("show_run_board")
	_expect(_label(shell, "HaulSummary") == "BANKED: 1 CAR - IMPOUNDED: 1 CAR - LOST: 1 CAR", "haul counts are disjoint and omit the starter")
	_expect(_label(shell, "HaulRecap_" + banked).begins_with("BANKED · "), "banked car retains its named recap")
	_expect(_label(shell, "HaulRecap_" + impounded).begins_with("IMPOUNDED · "), "impounded car is not mislabeled lost")
	_expect(_label(shell, "HaulRecap_" + dropped).begins_with("LOST · "), "unbanked car is lost")

	var complete: RunSession = app.call("start_run", 33333)
	complete._advance_to_act(RunSession.FINAL_ACT)
	_move_to(complete, "act_rival")
	var final_copy := _report_copy(app, complete, 1)
	_expect(final_copy.begins_with("+6 POINTS · WON: ") and final_copy.ends_with(" - BANKED"), "final win never offers a decision the ended night cannot take")
	shell.call("show_run_board")
	_expect(_label(shell, "NightVerdict") == "ALL ACT RIVALS DEFEATED", "completed flag gives a victory verdict")
	_expect(_label(shell, "HaulSummary") == "BANKED: 1 CAR", "final rival reward is banked")
	var repeated: RunSession = app.call("start_run", 33333)
	repeated._advance_to_act(RunSession.FINAL_ACT)
	_move_to(repeated, "act_rival")
	var reward: Dictionary = repeated._win_car(repeated.current_node_id, RunSession.CAR_ORIGIN_RIVAL, ProceduralCarGenerator.SUPPORTED_TYPES)
	_expect(repeated.send_it_home(), "fixture already owns the final rival car")
	var repeat_copy := _report_copy(app, repeated, 1)
	_expect(repeat_copy == "+6 POINTS · WON: %s - BANKED" % String(CATALOG.get_vehicle(String(reward["id"]))["name"]).to_upper(), "winning the same final car again still reports its real award")
	_presenter.free()
	if _failed:
		quit(1)
		return
	print("RUN_NIGHT_CONSEQUENCES_TEST PASS")
	quit(0)


func _report_copy(app: Node, sess: RunSession, position: int) -> String:
	var before: Dictionary = _presenter.call("_night_result_snapshot", sess)
	var method := "start_run_rival" if String(sess.current_node()["type"]) == "rival" else "start_run_race"
	_expect(bool(app.call(method, sess.current_node_id)), "scripted race starts")
	_expect(bool(app.call("report_race_result", position, 42.0, [], false, {})), "scripted result commits")
	var race: Dictionary = app.call("get_current_race_session")
	return String(_presenter.call("_night_result_consequences", before, sess, race["result"]))


func _move_to(sess: RunSession, kind: String) -> void:
	for node: Dictionary in sess.current_map.nodes.values():
		if String(node["type"]) == kind:
			sess.current_node_id = String(node["id"])
			sess.run_state.row = int(node["row"])
			return
	_expect(false, "fixture stop exists: " + kind)


func _label(shell: Node, name: String) -> String:
	var label := shell.find_child(name, true, false) as Label
	_expect(label != null, "label exists: " + name)
	return label.text if label != null else ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("RUN_NIGHT_CONSEQUENCES_TEST FAIL: " + message)
