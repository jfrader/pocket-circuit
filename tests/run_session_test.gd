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
	var starter: Dictionary = sess.car_record(sess.current_car_id)
	if not _expect(String(starter.get("won_from", "")) == RUN_SESSION.CAR_ORIGIN_START and String(starter["type"]) in RUN_SESSION.STARTER_TYPES and sess.run_state.get_car_wear(sess.current_car_id) == "clean", "a night is dealt a clean starter car of a starter type"):
		return
	if not _expect(sess.won_cars().is_empty() and sess.pending_offer.is_empty(), "the starter is not a won car and nothing is offered yet"):
		return
	var starter_looks := {}
	for night in 12:
		var other = RUN_SESSION.create(424242 + night * 977)
		starter_looks["%s|%d" % [other.car_record(other.current_car_id)["type"], other.car_record(other.current_car_id)["seed"]]] = true
	if not _expect(starter_looks.size() == 12, "different nights deal different starter cars"):
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
		sess.decline_offer()
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
	sess.parts_held.append(RunParts.deal(1)[0])
	if not _expect(not sess.bench_fit(car, 0) and not sess.bench_repair(car) and sess.parts_held.size() == 1, "one bench action per visit"):
		return
	if not _expect(sess.open_lockup().is_empty() and sess.lockup_used == false, "a lockup opens only at a lockup"):
		return
	var van = RUN_SESSION.create(22222)
	if not _expect(_walk_to(van, "parts_van"), "a route reaches a parts van"):
		return
	var cheapest: int = RunParts.UPSIDES.values().map(func(part: Dictionary) -> int: return int(part["cost"])).min()
	if not _expect(cheapest <= int(RUN_SESSION.RUN_POINTS_BY_FINISH[1]), "one race win buys the cheapest part"):
		return
	var stock: Array[Dictionary] = van.van_stock()
	if not _expect(stock.size() == RunParts.VAN_STOCK, "the van stocks its rolled parts"):
		return
	var unstocked := ""
	for part_id: String in RunParts.UPSIDES:
		if not stock.any(func(part: Dictionary) -> bool: return part["part"] == part_id):
			unstocked = part_id
	van.run_points = 20
	if not _expect(not van.buy_part(unstocked) and not van.buy_part("rocket") and van.run_points == 20, "the van sells only what it stocks"):
		return
	var part: Dictionary = stock[0]
	van.run_points = RunParts.cost(part) - 1
	if not _expect(not van.buy_part(String(part["part"])) and van.run_points == RunParts.cost(part) - 1, "a part above the points is refused"):
		return
	van.run_points = 20
	if not _expect(van.buy_part(String(part["part"])) and van.run_points == 20 - RunParts.cost(part) and van.parts_held == [part], "a purchase spends exactly its price and the part is held"):
		return
	if not _expect(not van.buy_part(String(stock[1]["part"])), "the van sells once per visit"):
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
	var starter_id: String = win.current_car_id
	var win_out: Dictionary = win.resolve_rival(win.current_node_id, true)
	if not _expect(win_out.has("car") and win.owned_cars.size() == owned_before + 1, "beating a rival wins its car"):
		return
	var won_id := String(win_out["car"]["id"])
	if not _expect(win.pending_offer == won_id and win.current_car_id == starter_id, "a won car is offered, not forced"):
		return
	var next_stop := String(win.current_map.get_children(win.current_node_id)[0]["id"])
	if not _expect(not win.enter_node(next_stop), "the run does not move on while a won car waits for an answer"):
		return
	var offered_snap: Dictionary = RUN_SESSION.serialize(win)
	var stale := offered_snap.duplicate(true)
	stale["schema_version"] = RUN_SESSION.SCHEMA_VERSION - 1
	var salvaged: Array[Dictionary] = RUN_SESSION.salvage_won_cars(stale)
	if not _expect(RUN_SESSION.deserialize(stale) == null and salvaged.size() == win.won_cars().size() and salvaged[salvaged.size() - 1]["id"] == won_id, "a run that cannot be restored still hands over every car it won"):
		return
	var self_offer := offered_snap.duplicate(true)
	self_offer["pending_offer"] = win.current_car_id
	if not _expect(RUN_SESSION.deserialize(self_offer).pending_offer.is_empty(), "a stored offer of the car already driven is dropped"):
		return
	if not _expect(RUN_SESSION.deserialize(offered_snap).pending_offer == won_id, "an open offer survives a save"):
		return
	win.run_state.set_car_wear(starter_id, "rusty")
	if not _expect(win.take_offer() and win.current_car_id == won_id and win.pending_offer.is_empty(), "taking the offer drives the won car"):
		return
	if not _expect(win.run_state.get_car_wear(won_id) == "clean" and win.run_state.get_car_wear(starter_id) == "rusty", "the won car starts clean and the car left behind keeps its wear"):
		return
	if not _expect(not win.take_offer() and not win.decline_offer(), "an offer closes once"):
		return
	var keep = RUN_SESSION.create(33333)
	_walk_to(keep, "rival")
	var kept_id: String = keep.current_car_id
	var won_before: int = keep.won_cars().size()
	keep.resolve_rival(keep.current_node_id, true)
	if not _expect(keep.decline_offer() and keep.current_car_id == kept_id and keep.won_cars().size() == won_before + 1, "declining keeps the current car and the won one stays won"):
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
	var junk_owned := snap.duplicate(true)
	var junk_cars: Dictionary = (snap["owned_cars"] as Dictionary).duplicate(true)
	junk_cars["car-x"] = "compact"
	junk_cars["car-y"] = {"type": "suv", "won_from": "rival", "seed": 3, "act": 1}
	junk_owned["owned_cars"] = junk_cars
	var cleaned = RUN_SESSION.deserialize(junk_owned)
	if not _expect(cleaned != null and cleaned.owned_cars.keys() == (snap["owned_cars"] as Dictionary).keys(), "unreadable owned cars are dropped on load"):
		return
	var carless := snap.duplicate(true)
	carless["owned_cars"] = {}
	if not _expect(RUN_SESSION.deserialize(carless) == null, "a run without the car it drives is rejected"):
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
			sess.buy_part(String(sess.van_stock()[0]["part"]))
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
		sess.decline_offer()
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
