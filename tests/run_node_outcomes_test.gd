extends SceneTree

## Node outcomes through the App seams: bench (repair XOR fit), parts van
## purchases from points, the once-per-act lockup, the errand choice, and the
## act rival closing the act. Each persists.

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")

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
	if not _expect(bench_run != null and RUN_WALK.walk_to(app, bench_run, "bench"), "a bench must be reachable"):
		return
	var car: String = bench_run.current_car_id
	bench_run.run_state.set_car_wear(car, "dusty")
	if not _expect(bool(app.call("run_bench_repair", car)), "repair must succeed at the bench"):
		return
	if not _expect(bench_run.run_state.get_car_wear(car) == "clean", "repair must restore the car"):
		return
	bench_run.parts_held.append(RunParts.deal(3)[0])
	if not _expect(not bool(app.call("run_bench_fit", 0)) and bench_run.parts_held.size() == 1, "fitting after repairing in the same visit must be refused"):
		return

	# --- Parts van: an exact spend of points, an overspend refusal, and the save follows ---
	var van_run: RunSession = app.call("start_run", 900002) as RunSession
	if not _expect(van_run != null and RUN_WALK.walk_to(app, van_run, "parts_van"), "a parts van must be reachable"):
		return
	var part: Dictionary = van_run.van_stock()[0]
	van_run.run_points = RunParts.cost(part) - 1
	if not _expect(not bool(app.call("run_buy_part", String(part["part"]))), "a part above the points must be refused"):
		return
	van_run.run_points = 20
	if not _expect(bool(app.call("run_buy_part", String(part["part"]))), "a part inside the points must sell"):
		return
	if not _expect(van_run.run_points == 20 - RunParts.cost(part), "the purchase must debit exactly its listed price"):
		return
	var live_store: Object = app.get("_save_store")
	var saved: Dictionary = SAVE_STORE.new(String(live_store.get("save_path"))).load_data()
	if not _expect(int((saved.get("current_run", {}) as Dictionary).get("run_points", -1)) == van_run.run_points, "the save must carry the spent points"):
		return

	# --- Lockup: one free car, once per act ---
	# The lockup is scarce by design, so try a few runs.
	var lock_run: RunSession = null
	for attempt in 8:
		lock_run = app.call("start_run", 900003 + attempt * 101) as RunSession
		if RUN_WALK.walk_to(app, lock_run, "lockup"):
			break
		lock_run = null
	if not _expect(lock_run != null, "a lockup must be reachable within a few runs"):
		return
	var owned_before: int = lock_run.owned_cars.size()
	if not _expect(bool(app.call("run_open_lockup")), "opening the lockup must grant a car"):
		return
	if not _expect(lock_run.owned_cars.size() == owned_before + 1, "the lockup must add exactly one car"):
		return
	if not _expect(not bool(app.call("run_open_lockup")), "the lockup must be scarce (once per act)"):
		return

	# --- Errand: the pay adds points; the tune-up steps wear back ---
	var errand_run: RunSession = app.call("start_run", 900004) as RunSession
	if not _expect(errand_run != null and RUN_WALK.walk_to(app, errand_run, "errand"), "an errand must be reachable"):
		return
	var errand_points: int = errand_run.run_points
	if not _expect(bool(app.call("run_resolve_errand", 0)), "the pay must resolve"):
		return
	if not _expect(errand_run.run_points == errand_points + RunSession.ERRAND_PAY_POINTS, "the pay must add its points"):
		return
	var tune_run: RunSession = app.call("start_run", 900004) as RunSession
	RUN_WALK.walk_to(app, tune_run, "errand")
	tune_run.run_state.set_car_wear(tune_run.current_car_id, "rusty")
	if not _expect(bool(app.call("run_resolve_errand", 1)) and tune_run.run_state.get_car_wear(tune_run.current_car_id) == "dusty", "the tune-up must step wear back one level"):
		return

	# --- The act ends on the act rival: beating it opens the next act ---
	var walk_run: RunSession = app.call("start_run", 900005) as RunSession
	if not _expect(walk_run != null and RUN_WALK.walk_to(app, walk_run, "act_rival"), "every route must reach the act rival"):
		return
	if not _expect(int(walk_run.current_map.act) == 1, "a fresh run starts in act 1"):
		return
	RUN_WALK.settle(app, walk_run)
	if not _expect(int(walk_run.current_map.act) == 2 and walk_run.is_race_pending(), "beating the act rival must open act 2 on its opening race"):
		return

	app.call("abandon_run")
	if _failed:
		return
	print("RUN_NODE_OUTCOMES_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_NODE_OUTCOMES_TEST FAIL: " + message)
	quit(1)
	return false
