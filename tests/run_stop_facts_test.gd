extends SceneTree

const RUN_UI := preload("res://scripts/ui/run_ui.gd")
const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const SAVE_PATH := "user://tests/run_stop_facts_test.json"

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must exist"):
		return
	app.set("_save_store", SAVE_STORE.new(SAVE_PATH))
	var session := RunSession.create(1806)
	if not _expect(_fact("race", "FIELD", session) == "6 cars" and _fact("act_rival", "FIELD", session) == "6 cars, hardest drivers" and _fact("rival", "FIELD", session) == "one on one, contact", "field facts match six-car races and two-car duels"):
		return
	var costs := _fact("race", "COSTS", session)
	var prefix := "wear at finish "
	var suffix := "+ or DNF"
	if not _expect(costs.begins_with(prefix) and costs.ends_with(suffix), "race cost must name a finish threshold and DNF"):
		return
	var threshold_text := costs.trim_prefix(prefix).trim_suffix(suffix)
	if not _expect(threshold_text.is_valid_int(), "displayed finish threshold must be a number"):
		return
	var threshold := threshold_text.to_int()
	var clean := RunState.WEAR_LEVELS[0]
	var advanced := RunState.advance_wear(clean, App.RUN_CRASH_SEVERITY)
	if not _expect(advanced != clean, "race penalty must actually advance wear"):
		return
	for dnf: bool in [false, true]:
		for position: int in RunSession.RUN_POINTS_BY_FINISH:
			session = RunSession.create(1806)
			app.set("_current_run_session", session)
			app.call("_commit_run_result", session.current_node_id, position, dnf, RunSession.RUN_POINTS_BY_FINISH.size())
			var expected := advanced if dnf or position >= threshold else clean
			if not _expect(session.resolved_nodes.has(session.current_node_id), "race outcome must be applied"):
				return
			if not _expect(session.run_state.get_car_wear(session.current_car_id) == expected, "displayed race cost must match finish %d, DNF %s" % [position, dnf]):
				return
	var repair := _fact("bench", "REPAIR", session)
	if not _expect(_fact("rival", "LOSE", session) == "%d points; pay what you have, plus wear if short" % RunSession.RIVAL_LOSS_POINTS_COST, "duel fact names the full charge and partial-payment wear"):
		return
	for points: int in [0, RunSession.RIVAL_LOSS_POINTS_COST - 1, RunSession.RIVAL_LOSS_POINTS_COST]:
		var duel := RunSession.create(33333)
		for node: Dictionary in duel.current_map.nodes.values():
			if String(node["type"]) == "rival":
				duel.current_node_id = String(node["id"])
				break
		duel.run_points = points
		var outcome := duel.resolve_rival(duel.current_node_id, false)
		if not _expect(not outcome.has("error") and duel.run_points == maxi(0, points - RunSession.RIVAL_LOSS_POINTS_COST), "duel loss takes all available points up to its charge"):
			return
		var expected_wear := RunState.advance_wear(clean, RunSession.RIVAL_LOSS_SEVERITY) if points < RunSession.RIVAL_LOSS_POINTS_COST else clean
		if not _expect(duel.run_state.get_car_wear(duel.current_car_id) == expected_wear, "duel loss adds wear only when the full charge cannot be paid"):
			return
	for wear: String in RunState.WEAR_LEVELS:
		var restored := RunState.restore_at_bench(wear)
		if not _expect(restored == clean and repair == "restore to " + restored, "bench fact must match full repair from " + wear):
			return
	if _failed:
		return
	print("RUN_STOP_FACTS_TEST PASS")
	quit(0)


func _fact(kind: String, key: String, session: RunSession) -> String:
	for row: Array in RUN_UI.stop_facts(kind, session, {}):
		if String(row[0]) == key:
			return String(row[1])
	return ""


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_STOP_FACTS_TEST FAIL: " + message)
	quit(1)
	return false
