extends SceneTree

## GURI-1827 (Offer won cars to drive during the run): a duel win sends the
## board to the car offer, drawn against the current car; taking it puts the
## won car on the grid for the next race, keeping it does not.

const RUN_WALK := preload("res://tests/support/run_walk.gd")
const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var shell := app.get("_shell") as CanvasLayer
	var sess := _run_to_rival(app)
	if not _expect(sess != null, "a rival is reachable"):
		return
	var starter: String = sess.current_car_id
	RUN_WALK.settle(app, sess)
	var won := sess.pending_offer
	if not _expect(not won.is_empty(), "a duel win opens an offer"):
		return

	shell.call("show_run_board")
	await process_frame
	var offer := shell.find_child("RunOffer", true, false)
	var shape := shell.find_child("OfferShape", true, false) as CarShapeView
	if not _expect(offer != null and shape != null and shell.find_child("RunBoard", true, false) == null, "the board gives way to the offer"):
		return
	if not _expect(shape.compare_shape.size() == CarProfile.AXES.size() and shape.label.begins_with("VS "), "the offer draws the won car against the current one"):
		return
	(shell.find_child("ActionTakeOffer", true, false) as Button).pressed.emit()
	await process_frame
	if not _expect(sess.current_car_id == won and shell.find_child("RunBoard", true, false) != null, "taking the offer drives the won car and returns to the board"):
		return
	var next_race := _first_race(sess)
	if not _expect(not next_race.is_empty() and bool(app.call("start_run_race", next_race)), "the next race starts"):
		return
	if not _expect(String((app.get("current_race_session") as Dictionary).get("vehicle_id", "")) == won, "the next race is driven in the won car"):
		return
	if not _expect(String(CATALOG_SCRIPT.get_vehicle(won).get("name", "")) != "" and not CATALOG_SCRIPT.get_vehicle(starter).is_empty(), "the won car and the starter are real vehicles"):
		return

	# Keep: ESC leaves the offer open, a reloaded run shows it again, KEEP closes
	# it and the save says so.
	var keep_run := _run_to_rival(app)
	if not _expect(keep_run != null, "a second rival is reachable"):
		return
	var kept: String = keep_run.current_car_id
	RUN_WALK.settle(app, keep_run)
	shell.call("show_run_board")
	await process_frame
	shell.call("go_back")
	await process_frame
	if not _expect(not keep_run.pending_offer.is_empty(), "leaving the offer screen leaves the offer open"):
		return
	var path := String((app.get("_save_store") as Object).get("save_path"))
	var reloaded := RunSession.deserialize(SAVE_STORE.new(path).load_data().get("current_run", {}) as Dictionary)
	if not _expect(reloaded != null and reloaded.pending_offer == keep_run.pending_offer, "the open offer is in the save"):
		return
	app.set("_current_run_session", reloaded)
	shell.call("show_run_board")
	await process_frame
	var keep_button := shell.find_child("ActionKeepCar", true, false) as Button
	if not _expect(keep_button != null, "a reloaded run shows the open offer again"):
		return
	keep_button.pressed.emit()
	await process_frame
	var saved_run: Dictionary = SAVE_STORE.new(path).load_data().get("current_run", {}) as Dictionary
	if not _expect(reloaded.current_car_id == kept and String(saved_run.get("pending_offer", "x")).is_empty() and String(saved_run.get("current_car_id", "")) == kept, "KEEP keeps the car and the save records it"):
		return

	app.call("abandon_run")
	if _failed:
		return
	print("RUN_OFFER_TEST PASS")
	quit(0)


const CATALOG_SCRIPT := preload("res://data/championship/catalog.gd")


func _run_to_rival(app: Object) -> RunSession:
	for attempt in 12:
		var sess: RunSession = app.call("start_run", 1827000 + attempt * 31) as RunSession
		if RUN_WALK.walk_to(app, sess, "rival"):
			return sess
	return null


func _first_race(sess: RunSession) -> String:
	for stop: Dictionary in sess.available_nodes():
		if String(stop["type"]) in ["race", "act_rival"]:
			return String(stop["id"])
	return ""


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("RUN_OFFER_TEST FAIL: " + message)
		quit(1)
	return condition
