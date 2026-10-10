extends SceneTree

## GURI-1827 (Offer won cars to drive during the run): a duel win sends the
## board to the car offer, drawn against the current car; taking it puts the
## won car on the grid for the next race, keeping it does not.

const RUN_WALK := preload("res://tests/support/run_walk.gd")

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
	if not _expect(String(CATALOG_SCRIPT.get_vehicle(won).get("name", "")) != "" and starter != won, "the won car is a real vehicle"):
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
