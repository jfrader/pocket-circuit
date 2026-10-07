extends SceneTree

## GURI-1741 (Run rewards and Quick Race as the garage): every car won in a
## night joins the garage once, win or lose, as a real vehicle with its own
## name, look and rolled physics; Quick Race offers it; the next night starts
## from the starter car; championship unlocks are untouched.

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
const CATALOG := preload("res://data/championship/catalog.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must exist"):
		return
	var path := String((app.get("_save_store") as Object).get("save_path"))

	var sess := _run_to_rival(app)
	if not _expect(sess != null, "a rival must be reachable within a few runs"):
		return
	RUN_WALK.settle(app, sess)
	var won: Array[Dictionary] = sess.won_cars()
	if not _expect(won.size() == 1, "beating the rival wins one car (got %d)" % won.size()):
		return
	var car_id := String(won[0]["id"])
	var live: Dictionary = CATALOG.get_vehicle(car_id)
	if not _expect(not live.is_empty() and not String(live["name"]).is_empty() and live.has("car_art"), "a won car resolves like a shipped car during the run"):
		return

	# Lose the night on the act rival: the car still goes to the garage.
	if not _expect(RUN_WALK.walk_to(app, sess, "act_rival"), "the run reaches the act rival"):
		return
	RUN_WALK.settle(app, sess, 2)
	if not _expect(app.call("current_run_session") == null, "a lost night clears the run"):
		return
	var saved: Dictionary = SAVE_STORE.new(path).load_data()
	var garage: Array = saved.get("garage_cars", [])
	if not _expect(garage.size() == 1 and String(garage[0]["id"]) == car_id, "the won car is in the saved garage exactly once"):
		return
	if not _expect((saved["current_run"] as Dictionary).is_empty(), "the saved run is cleared"):
		return
	if not _expect(not car_id in (saved["unlocked_vehicles"] as Array), "run cars never touch championship unlocks"):
		return

	var vehicle: Dictionary = CATALOG.get_vehicle(car_id)
	var base: Dictionary = CATALOG.base_vehicle_for_type(String(garage[0]["type"]))
	if not _expect(String(vehicle.get("name", "")) != String(base["name"]), "a won car has its own generated name"):
		return
	var rolled := CATALOG.create_vehicle_stats(car_id)
	var shipped := CATALOG.create_vehicle_stats(String(base["id"]))
	if not _expect(not is_equal_approx(rolled.max_speed, shipped.max_speed) or not is_equal_approx(rolled.engine_force, shipped.engine_force), "a won car drives on its roll, not on its base car"):
		return
	if not _expect(car_id in (app.call("quick_race_roster") as Array), "Quick Race offers the won car"):
		return

	# The next night starts from the starter car alone, and the garage keeps the car.
	var next: RunSession = app.call("start_run", 31337) as RunSession
	if not _expect(next.owned_cars.keys() == [RunSession.STARTER_CAR] and next.won_cars().is_empty(), "a new night starts with the starter car only"):
		return
	if not _expect(car_id in (app.call("quick_race_roster") as Array), "the garage outlives the next night"):
		return

	app.call("abandon_run")
	if _failed:
		return
	print("RUN_REWARDS_TEST PASS")
	quit(0)


func _run_to_rival(app: Object) -> RunSession:
	for attempt in 12:
		var sess: RunSession = app.call("start_run", 1741000 + attempt * 31) as RunSession
		if RUN_WALK.walk_to(app, sess, "rival"):
			return sess
	return null


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("RUN_REWARDS_TEST FAIL: " + message)
		quit(1)
	return condition
