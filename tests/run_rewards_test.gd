extends SceneTree

## GURI-1741 (Run rewards and Quick Race as the garage): every car won in a
## night joins the garage once, win or lose, as a real vehicle with its own
## name, look and rolled physics; Quick Race offers it; the next night starts
## from the starter car; championship unlocks are untouched.

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
const CATALOG := preload("res://data/championship/catalog.gd")

## A store whose every write fails, for the nights that cannot be saved.
class FailingSaveStore extends SaveStore:
	func _init(path: String) -> void:
		super(path)

	func save_data(_data: Dictionary) -> bool:
		last_save_error = "Injected run save failure"
		return false

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

	# NEW RUN over a night that won a car ends that night first: the car is kept.
	var swapped := _run_to_rival(app)
	if not _expect(swapped != null, "a second rival is reachable"):
		return
	RUN_WALK.settle(app, swapped)
	if not _expect(not swapped.won_cars().is_empty(), "the second duel wins a car"):
		return
	var swapped_car := String(swapped.won_cars()[0]["id"])
	app.call("start_new_run")
	if not _expect(swapped_car in (app.call("garage_car_ids") as Array), "starting a new run keeps the cars the old one won"):
		return

	# A night that ends while the save cannot be written keeps its cars until it can.
	var blocked := _run_to_rival(app)
	if not _expect(blocked != null, "a third rival is reachable"):
		return
	RUN_WALK.settle(app, blocked)
	if not _expect(not blocked.won_cars().is_empty(), "the third duel wins a car"):
		return
	var blocked_car := String(blocked.won_cars()[0]["id"])
	var store: Object = app.get("_save_store")
	app.set("_save_store", FailingSaveStore.new(path))
	app.call("abandon_run")
	if not _expect(app.call("current_run_session") == blocked and not String(app.get("last_run_error")).is_empty(), "an ended night that failed to save is held, and says so"):
		return
	if not _expect(not blocked_car in (SAVE_STORE.new(path).load_data()["garage_cars"] as Array).map(func(car: Dictionary) -> String: return String(car["id"])), "nothing reaches disk while the save is blocked"):
		return
	if not _expect(app.call("start_new_run") == null and app.call("current_run_session") == blocked, "a new run never replaces a night that is not saved yet"):
		return
	var shell := app.get("_shell") as CanvasLayer
	shell.call("show_run_board")
	await process_frame
	var save_again := shell.find_child("ActionSaveAgain", true, false) as Button
	if not _expect(save_again != null and _has_label(shell, "NIGHT OVER"), "the board says the night is over and offers to save it"):
		return
	app.set("_save_store", store)
	save_again.pressed.emit()
	await process_frame
	if not _expect(app.call("current_run_session") == null and blocked_car in (app.call("garage_car_ids") as Array), "saving again lands the held night with its car"):
		return

	# A new championship resets the championship, not the garage.
	var before: Array = app.call("garage_car_ids")
	var running: RunSession = app.call("start_run", 4040) as RunSession
	app.call("confirm_new_championship")
	if not _expect(app.call("garage_car_ids") == before, "a new championship keeps every won car"):
		return
	var kept_run: Dictionary = SAVE_STORE.new(path).load_data()["current_run"]
	if not _expect(int(kept_run.get("run_seed", 0)) == running.run_seed, "a new championship keeps the run in progress"):
		return

	app.call("abandon_run")
	if _failed:
		return
	print("RUN_REWARDS_TEST PASS")
	quit(0)


## Each call walks fresh seeds, so every car it wins has its own id.
var _next_seed := 1741000


func _run_to_rival(app: Object) -> RunSession:
	for attempt in 12:
		_next_seed += 31
		var sess: RunSession = app.call("start_run", _next_seed) as RunSession
		if RUN_WALK.walk_to(app, sess, "rival"):
			return sess
	return null


func _has_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _has_label(child, text):
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("RUN_REWARDS_TEST FAIL: " + message)
		quit(1)
	return condition
