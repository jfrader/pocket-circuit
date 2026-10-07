extends SceneTree

## Run session rules: a race-type stop is raced before moving on, points are the
## only currency, the act rival closes each act, and wear can end the run.

const RUN_SESSION := preload("res://scripts/progression/run_session.gd")
const RUN_STATE := preload("res://scripts/progression/run_state.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for check: Callable in [_check_opening, _check_full_run, _check_act_rival_loss, _check_wear_failure, _check_bench_and_van, _check_rival_loss, _check_errand, _check_determinism_and_save]:
		check.call()
		if _failed:
			return
	print("RUN_SESSION_TEST PASS")
	quit(0)


func _check_opening() -> void:
	var sess = RUN_SESSION.create(424242)
	if not _expect(sess != null and sess.run_seed == 424242 and sess.run_points == RUN_SESSION.INITIAL_POINTS, "a run starts on its seed with the starting points"):
		return
	if not _expect(sess.current_car_id == "rustbug" and sess.run_state.get_car_wear("rustbug") == "clean", "a run starts in a clean rustbug"):
		return
	var start: Dictionary = sess.current_node()
	if not _expect(String(start.get("type", "")) == "race" and sess.is_race_pending(), "the run opens on an unraced race"):
		return
	var avail: Array[Dictionary] = sess.available_nodes()
	if not _expect(avail.size() == 1 and String(avail[0]["id"]) == String(start["id"]), "the only stop on offer is the opening race itself"):
		return
	var child_id := String(sess.current_map.get_children(String(start["id"]))[0]["id"])
	if not _expect(not sess.enter_node(child_id), "the run cannot move past an unraced race"):
		return
	var out: Dictionary = sess.resolve_race(String(start["id"]), 1, 4)
	if not _expect(int(out.get("points_gained", -1)) == 6 and sess.run_points == 6, "a win pays 6 points"):
		return
	if not _expect(sess.resolve_race(String(start["id"]), 1, 4).has("error") and sess.run_points == 6, "a race pays once"):
		return
	if not _expect(not sess.is_race_pending() and sess.available_nodes().size() >= 1 and sess.enter_node(child_id), "after racing, the children open"):
		return


func _check_full_run() -> void:
	var sess = RUN_SESSION.create(98765)
	var acts_seen: Array[int] = []
	var guard := 0
	while not sess.is_complete() and not sess.is_failed() and guard < 200:
		guard += 1
		if not acts_seen.has(sess.current_map.act):
			acts_seen.append(sess.current_map.act)
		_resolve_current(sess, true)
		if sess.is_complete() or sess.is_failed():
			break
		var avail: Array[Dictionary] = sess.available_nodes()
		if not _expect(not avail.is_empty(), "every unfinished stop offers a way on (act %d, %s)" % [sess.current_map.act, sess.current_node_id]):
			return
		if not sess.is_race_pending():
			if not _expect(sess.enter_node(String(avail[0]["id"])), "an offered stop can be entered"):
				return
	if not _expect(sess.is_complete() and not sess.is_failed(), "beating three act rivals completes the run (failed=%s, act=%d)" % [str(sess.is_failed()), sess.current_map.act]):
		return
	if not _expect(acts_seen == [1, 2, 3], "the run climbs acts 1, 2 and 3 in order (got %s)" % str(acts_seen)):
		return
	if not _expect(sess.available_nodes().is_empty(), "a finished run offers nothing"):
		return


func _check_act_rival_loss() -> void:
	var sess = RUN_SESSION.create(5150)
	_walk_to_act_rival(sess)
	if not _expect(String(sess.current_node().get("type", "")) == "act_rival", "every route reaches the act rival"):
		return
	var out: Dictionary = sess.resolve_race(sess.current_node_id, 2, 4)
	if not _expect(bool(out.get("run_failed", false)) and sess.is_failed() and not sess.is_complete(), "losing to the act rival ends the run"):
		return


func _check_wear_failure() -> void:
	var sess = RUN_SESSION.create(777)
	for i: int in range(RUN_STATE.WEAR_LEVELS.size()):
		sess.register_crash(0.8)
	if not _expect(sess.is_failed() and not sess.is_complete(), "repeated crashes wear the car out and end the run"):
		return


func _check_bench_and_van() -> void:
	var sess = RUN_SESSION.create(11111)
	if not _expect(_walk_to(sess, "bench"), "a route reaches a bench"):
		return
	var car: String = sess.current_car_id
	if not _expect(sess.bench_repair(car), "repair at the bench"):
		return
	if not _expect(not sess.bench_fit(car, "spare") and not sess.bench_repair(car), "one bench action per visit"):
		return
	var van = RUN_SESSION.create(22222)
	if not _expect(_walk_to(van, "parts_van"), "a route reaches a parts van"):
		return
	var cheapest: int = RUN_SESSION.VAN_PART_COSTS.values().min()
	if not _expect(cheapest <= int(RUN_SESSION.RUN_POINTS_BY_FINISH[1]), "one race win buys the cheapest part"):
		return
	van.run_points = 20
	if not _expect(not van.spend(9999) and van.run_points == 20, "overspending is refused"):
		return
	if not _expect(van.spend(15) and van.run_points == 5, "a purchase spends exactly its points"):
		return
	if not _expect(not van.spend(1), "the van sells once per visit"):
		return


func _check_rival_loss() -> void:
	var sess = RUN_SESSION.create(33333)
	if not _expect(_walk_to(sess, "rival"), "a route reaches a rival"):
		return
	sess.run_points = RUN_SESSION.RIVAL_LOSS_POINTS_COST + 3
	var wear_before: String = sess.run_state.get_car_wear(sess.current_car_id)
	var out: Dictionary = sess.resolve_rival(sess.current_node_id, false)
	if not _expect(int(out.get("cost", 0)) == RUN_SESSION.RIVAL_LOSS_POINTS_COST and sess.run_points == 3 and not bool(out.get("wear_advanced", true)), "a covered rival loss costs points only"):
		return
	if not _expect(sess.run_state.get_car_wear(sess.current_car_id) == wear_before, "a covered loss leaves the car alone"):
		return
	var short = RUN_SESSION.create(33333)
	_walk_to(short, "rival")
	short.run_points = 0
	var short_out: Dictionary = short.resolve_rival(short.current_node_id, false)
	if not _expect(bool(short_out.get("wear_advanced", false)) and short.run_state.get_car_wear(short.current_car_id) != "clean", "a loss the points cannot cover wears the car"):
		return
	var win = RUN_SESSION.create(33333)
	_walk_to(win, "rival")
	var owned_before: int = win.owned_cars.size()
	var win_out: Dictionary = win.resolve_rival(win.current_node_id, true)
	if not _expect(win_out.has("car") and win.owned_cars.size() == owned_before + 1, "beating a rival wins its car"):
		return


func _check_errand() -> void:
	var pay = RUN_SESSION.create(44444)
	if not _expect(_walk_to(pay, "errand"), "a route reaches an errand"):
		return
	var before: int = pay.run_points
	var out: Dictionary = pay.resolve_errand(0)
	if not _expect(String(out.get("effect", "")) == "points" and pay.run_points == before + RUN_SESSION.ERRAND_PAY_POINTS, "the pay adds its points"):
		return
	if not _expect(pay.resolve_errand(1).has("error"), "an errand is settled once"):
		return
	var tune = RUN_SESSION.create(44444)
	_walk_to(tune, "errand")
	tune.run_state.set_car_wear(tune.current_car_id, "rusty")
	var tune_out: Dictionary = tune.resolve_errand(1)
	if not _expect(String(tune_out.get("effect", "")) == "restore" and tune.run_state.get_car_wear(tune.current_car_id) == "dusty", "the tune-up steps wear back one level"):
		return


func _check_determinism_and_save() -> void:
	var a = RUN_SESSION.create(55555)
	var b = RUN_SESSION.create(55555)
	for s in [a, b]:
		_resolve_current(s, true)
		s.enter_node(String(s.available_nodes()[0]["id"]))
		_resolve_current(s, false)
	if not _expect(RUN_SESSION.serialize(a) == RUN_SESSION.serialize(b), "same seed and choices give the same run"):
		return
	var snap: Dictionary = RUN_SESSION.serialize(a)
	var restored = RUN_SESSION.deserialize(snap)
	if not _expect(restored != null and RUN_SESSION.serialize(restored) == snap, "a run survives a save round trip unchanged"):
		return
	var broken_state := snap.duplicate(true)
	broken_state["run_state"] = {"schema_version": 9999}
	if not _expect(RUN_SESSION.deserialize(broken_state) == null, "an unreadable run state rejects the whole run"):
		return
	var broken_map := snap.duplicate(true)
	broken_map["current_map"] = {}
	if not _expect(RUN_SESSION.deserialize(broken_map) == null, "an unreadable map rejects the whole run"):
		return
	var old := snap.duplicate(true)
	old["schema_version"] = RUN_SESSION.SCHEMA_VERSION - 1
	if not _expect(RUN_SESSION.deserialize(old) == null, "a run from older rules is not restored"):
		return


## Settles the current stop: races finish first (or last when losing), rivals
## win or lose, other stops take their first action.
func _resolve_current(sess, win: bool) -> void:
	var node: Dictionary = sess.current_node()
	var id := String(node.get("id", ""))
	match String(node.get("type", "")):
		"race", "act_rival":
			sess.resolve_race(id, 1 if win else 4, 4)
		"rival":
			sess.resolve_rival(id, win)
		"bench":
			sess.bench_repair(sess.current_car_id)
		"parts_van":
			sess.spend(RUN_SESSION.RIVAL_LOSS_POINTS_COST)
		"lockup":
			sess.open_lockup()
		"errand":
			sess.resolve_errand(0)


## Walks the first offered route, settling each stop, until the current stop is
## of the wanted type. Returns false when the act rival comes first.
func _walk_to(sess, wanted: String) -> bool:
	for step: int in range(40):
		if String(sess.current_node().get("type", "")) == wanted:
			return true
		_resolve_current(sess, true)
		var next := _first_of_type(sess, wanted)
		if next.is_empty():
			return false
		sess.enter_node(next)
	return false


func _first_of_type(sess, wanted: String) -> String:
	var avail: Array[Dictionary] = sess.available_nodes()
	for entry: Dictionary in avail:
		if String(entry["type"]) == wanted:
			return String(entry["id"])
	return "" if avail.is_empty() else String(avail[0]["id"])


func _walk_to_act_rival(sess) -> void:
	_walk_to(sess, "act_rival")


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		print("FAIL: ", message)
		quit(1)
	return condition
