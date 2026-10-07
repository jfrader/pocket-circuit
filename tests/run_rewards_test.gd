extends SceneTree

## GURI-1741: run rewards one-way into Quick Race garage (unlocked_vehicles).
## Every run-owned car (dedup) written on end (win or fail); run cleared.
## Second run always starts from starter set.
## Uses real App + _expect + marker, per run_persistence_test idiom.
## Walk reuses structure from run node/race outcome tests (enter + report for races).

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_SESSION := preload("res://scripts/progression/run_session.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must exist"):
		return

	var live_store: Object = app.get("_save_store")
	var path: String = String(live_store.get("save_path"))

	# --- WIN CASE: walk to act-3 final bench, resolve bench action to complete ---
	var sess: RunSession = app.call("start_new_run") as RunSession
	if not _expect(sess != null, "start_new_run must create a session"):
		return
	var pre_owned_win: Dictionary = sess.owned_cars.duplicate(true)
	if not _walk_to_act3_final_bench_and_resolve(app, sess):
		_expect(false, "the walk must reach the act-3 final bench")
		return
	# resolve final bench action to trigger is_complete (see RunSession._maybe_complete_on_final_bench)
	var ckey: String = sess.current_car_id
	if not _expect(sess.bench_repair(ckey), "final bench repair must succeed and mark completed"):
		return
	app.call("persist_current_run")
	if not _expect(app.call("current_run_session") == null, "win must clear current_run_session"):
		return
	var saved_win: Dictionary = SAVE_STORE.new(path).load_data()
	var unlocked_win: Array = saved_win.get("unlocked_vehicles", []) as Array
	for k: Variant in pre_owned_win.keys():
		var vid: String = String(k)
		var count: int = 0
		for u: Variant in unlocked_win:
			if String(u) == vid:
				count += 1
		if not _expect(count == 1, "win: owned car " + vid + " must appear exactly once (got " + str(count) + ")"):
			return
	var run_after_win: Dictionary = saved_win.get("current_run", {}) as Dictionary
	if not _expect(run_after_win.is_empty(), "win must clear current_run from save"):
		return

	# second run still starts with starter set only
	var sess2: RunSession = app.call("start_new_run") as RunSession
	if not _expect(sess2 != null, "second start_new_run after win"):
		return
	var owned2: Dictionary = sess2.owned_cars
	if not _expect(owned2.size() == 1 and owned2.has("rustbug"), "second run must start with starter set (only rustbug), got " + str(owned2.keys())):
		return
	app.call("abandon_run")

	# --- FAILURE CASE: wear car via register_crash until failed ---
	var sessf: RunSession = app.call("start_new_run") as RunSession
	if not _expect(sessf != null, "start_new_run for failure case"):
		return
	var pre_owned_fail: Dictionary = sessf.owned_cars.duplicate(true)
	var crashes: int = 0
	while not sessf.is_failed() and crashes < 30:
		sessf.register_crash(0.6)
		crashes += 1
	if not _expect(sessf.is_failed(), "register_crash must produce is_failed"):
		return
	app.call("persist_current_run")
	if not _expect(app.call("current_run_session") == null, "failure must clear current_run_session"):
		return
	var saved_fail: Dictionary = SAVE_STORE.new(path).load_data()
	var unlocked_fail: Array = saved_fail.get("unlocked_vehicles", []) as Array
	for k2: Variant in pre_owned_fail.keys():
		var vid2: String = String(k2)
		var count2: int = 0
		for u2: Variant in unlocked_fail:
			if String(u2) == vid2:
				count2 += 1
		if not _expect(count2 == 1, "fail: owned car " + vid2 + " must appear exactly once (got " + str(count2) + ")"):
			return
	var run_after_fail: Dictionary = saved_fail.get("current_run", {}) as Dictionary
	if not _expect(run_after_fail.is_empty(), "fail must clear current_run from save"):
		return

	# still can start another with starter
	var sess3: RunSession = app.call("start_new_run") as RunSession
	if not _expect(sess3 != null, "start after failure"):
		return
	if not _expect(sess3.owned_cars.has("rustbug") and sess3.owned_cars.size() == 1, "post-fail run starts with starter"):
		return
	app.call("abandon_run")

	if _failed:
		return
	print("RUN_REWARDS_TEST PASS")
	quit(0)


func _walk_to_act3_final_bench_and_resolve(app: Node, sess: RunSession) -> bool:
	# Advance by entering nodes; resolve races with pos=1 (wins rivals to advance acts),
	# resolve other nodes (rival/errand/lockup/bench non-final) then persist to progress.
	# Stop when positioned on act-3 final bench (before its resolve).
	var steps: int = 0
	var max_steps: int = 300
	var last_id: String = ""
	var same_id: int = 0
	while steps < max_steps:
		steps += 1
		if sess.current_map == null:
			return false
		if sess.current_node_id == last_id:
			same_id += 1
			if same_id > 6:
				return false
		else:
			same_id = 0
			last_id = sess.current_node_id
		var curr: Dictionary = sess.current_node()
		var ctype: String = String(curr.get("type", ""))
		var act: int = 0
		if sess.current_map != null:
			act = sess.current_map.act
		var row: int = int(sess.run_state.row) if sess.run_state != null else 0
		var is_final_bench: bool = (act == 3 and sess.current_map.is_last_row(row) and ctype == "bench")
		if is_final_bench:
			return true
		var options: Array[Dictionary] = sess.available_nodes()
		if options.is_empty():
			return false
		# Prefer race/act_rival to drive progress and act advances
		var chosen: String = ""
		var ntype: String = ""
		for entry: Dictionary in options:
			var nid: String = String(entry.get("id", ""))
			var nd: Dictionary = sess.current_map.get_node(nid) as Dictionary
			var nt: String = String(nd.get("type", ""))
			if nt == "act_rival" or nt == "race":
				chosen = nid
				ntype = nt
				break
			if chosen.is_empty():
				chosen = nid
				ntype = nt
		if chosen.is_empty():
			chosen = String(options[0].get("id", ""))
			var nd0: Dictionary = sess.current_map.get_node(chosen) as Dictionary
			ntype = String(nd0.get("type", ""))
		if ntype == "race" or ntype == "act_rival":
			var started: bool = bool(app.call("start_run_race", chosen))
			if not started:
				if not bool(app.call("enter_run_node", chosen)):
					return false
			# win the race (pos 1) to score, qualify, advance acts on rivals
			if not bool(app.call("report_race_result", 1, 25.0, [], false, {})):
				return false
			app.call("persist_current_run")
			continue
		# non-race: enter
		if not bool(app.call("enter_run_node", chosen)):
			return false
		app.call("persist_current_run")
		# resolve if action node (after enter)
		var after_t: String = String(sess.current_node().get("type", ""))
		var ccar: String = sess.current_car_id
		if after_t == "bench":
			# resolve non-final benches to allow leaving them
			if not (act == 3 and sess.current_map.is_last_row(int(sess.run_state.row))):
				sess.bench_repair(ccar)
				app.call("persist_current_run")
		elif after_t == "rival":
			sess.resolve_rival(chosen, true)
			app.call("persist_current_run")
		elif after_t == "errand":
			sess.resolve_errand(0)
			app.call("persist_current_run")
		elif after_t == "lockup":
			sess.open_lockup()
			app.call("persist_current_run")
		elif after_t == "parts_van":
			sess.spend(5)
			app.call("persist_current_run")
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_REWARDS_TEST FAIL: " + message)
	quit(1)
	return false
