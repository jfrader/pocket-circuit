extends SceneTree

## GURI-1740 node-outcome slice: bench (repair XOR fit, plus continue at the
## final bench), parts van spends, the once-per-act lockup and the errand choice
## all resolve through the App seams, persist, and advance the act at the end.

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must exist"):
		return
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame

	# --- Bench: damage, repair, then refuse the fit (repair XOR fit) ---
	var bench_run: RunSession = app.call("start_run", 900001) as RunSession
	if not _expect(bench_run != null, "start_run must create a session"):
		return
	var bench_id := _walk_to_type(app, bench_run, "bench", 60)
	if not _expect(not bench_id.is_empty(), "a bench must be reachable (walk)"):
		return
	var car: String = bench_run.current_car_id
	bench_run.register_crash(0.6)
	if not _expect(bench_run.run_state.get_car_wear(car) == "dusty", "a medium crash must wear the car to dusty"):
		return
	if not _expect(bool(app.call("run_bench_repair", car)), "repair must succeed at the bench"):
		return
	if not _expect(bench_run.run_state.get_car_wear(car) == "clean", "repair must restore the car"):
		return
	if not _expect(not bool(app.call("run_bench_fit", "spare")), "fitting after repairing in the same visit must be refused"):
		return

	# --- Parts van: an exact spend, an overspend refusal, and the save follows ---
	var van_run: RunSession = app.call("start_run", 900002) as RunSession
	if not _expect(van_run != null, "start_run must create a session"):
		return
	var van_id := _walk_to_type(app, van_run, "parts_van", 60)
	if not _expect(not van_id.is_empty(), "a parts van must be reachable (walk)"):
		return
	var budget_before: int = van_run.run_budget
	if not _expect(bool(app.call("run_spend", 8)), "a spend inside the budget must succeed"):
		return
	if not _expect(van_run.run_budget == budget_before - 8, "the spend must debit exactly its cost"):
		return
	if not _expect(not bool(app.call("run_spend", 999999)), "an overspend must be refused"):
		return
	var live_store: Object = app.get("_save_store")
	var path := String(live_store.get("save_path"))
	var saved: Dictionary = SAVE_STORE.new(path).load_data()
	var saved_run: Dictionary = saved.get("current_run", {}) as Dictionary
	if not _expect(int(saved_run.get("run_budget", -1)) == van_run.run_budget, "the save must carry the spent budget"):
		return

	# --- Lockup: one free car, once per act ---
	# The lockup is scarce by design (6% quota), so try a few runs.
	var lock_run: RunSession = null
	var lock_id := ""
	for attempt in 6:
		lock_run = app.call("start_run", 900003 + attempt) as RunSession
		if lock_run == null:
			continue
		lock_id = _walk_to_type(app, lock_run, "lockup", 80)
		if not lock_id.is_empty():
			break
	if not _expect(not lock_id.is_empty(), "a lockup must be reachable within a few runs"):
		return
	var owned_before: int = lock_run.owned_cars.size()
	if not _expect(bool(app.call("run_open_lockup")), "opening the lockup must grant a car"):
		return
	if not _expect(lock_run.owned_cars.size() == owned_before + 1, "the lockup must add exactly one car"):
		return
	if not _expect(not bool(app.call("run_open_lockup")), "the lockup must be scarce (once per act)"):
		return

	# --- Errand: choice 0 pays cash ---
	var errand_run: RunSession = app.call("start_run", 900004) as RunSession
	if not _expect(errand_run != null, "start_run must create a session"):
		return
	var errand_id := _walk_to_type(app, errand_run, "errand", 60)
	if not _expect(not errand_id.is_empty(), "an errand must be reachable (walk)"):
		return
	var errand_budget: int = errand_run.run_budget
	if not _expect(bool(app.call("run_resolve_errand", 0)), "the errand choice must resolve"):
		return
	if not _expect(errand_run.run_budget == errand_budget + 12, "the cash errand must add its documented 12"):
		return

	# --- The act ends at the final bench: continue advances it ---
	var walk_run: RunSession = app.call("start_run", 900005) as RunSession
	if not _expect(walk_run != null, "start_run must create a session"):
		return
	var steps := 0
	while steps < 60 and not walk_run.current_map.is_last_row(int(walk_run.current_node().get("row", -1))):
		steps += 1
		var options: Array[Dictionary] = walk_run.available_nodes()
		if options.is_empty():
			break
		if not bool(app.call("enter_run_node", String(options[0].get("id", "")))):
			break
	if not _expect(walk_run.current_map.is_last_row(int(walk_run.current_node().get("row", -1))), "the walk must reach the final bench row"):
		return
	if not _expect(int(walk_run.current_map.act) == 1, "a fresh run starts in act 1"):
		return
	if not _expect(bool(app.call("run_bench_continue")), "continuing at the final bench must advance the act"):
		return
	if not _expect(int(walk_run.current_map.act) == 2, "the act must advance to 2"):
		return

	app.call("abandon_run")
	if _failed:
		return
	print("RUN_NODE_OUTCOMES_TEST PASS")
	quit(0)


## Walks greedily (position-only for every type) until `wanted` is an available
## child, then enters it. Returns the node id or "" when the budget runs out.
func _walk_to_type(app: Object, session: RunSession, wanted: String, budget: int) -> String:
	var steps := 0
	while steps < budget:
		steps += 1
		var options: Array[Dictionary] = session.available_nodes()
		for entry: Dictionary in options:
			var nid := String(entry.get("id", ""))
			var node: Dictionary = session.current_map.get_node(nid) as Dictionary
			if String(node.get("type", "")) == wanted:
				if bool(app.call("enter_run_node", nid)):
					return nid
				return ""
		if options.is_empty():
			return ""
		if not bool(app.call("enter_run_node", String(options[0].get("id", "")))):
			return ""
	return ""


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_NODE_OUTCOMES_TEST FAIL: " + message)
	quit(1)
	return false
