extends SceneTree

## GURI-1740d race-outcome slice: a `race` node hands over to the real race flow
## and the reported result resolves back into the run (points, wear, persist,
## and the route back to the board).

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
## Generous: the scene builds a generated circuit before its countdown.
const RACE_SCENE_FRAME_LIMIT := 3000

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
	var sess: RunSession = app.call("start_new_run") as RunSession
	if not _expect(sess != null, "start_new_run must create a session"):
		return

	# Walk position-only until a race node becomes available (bounded).
	var race_id := ""
	var steps := 0
	while race_id.is_empty() and steps < 40:
		steps += 1
		var options: Array[Dictionary] = sess.available_nodes()
		if options.is_empty():
			break
		for entry: Dictionary in options:
			var nid := String(entry.get("id", ""))
			var node: Dictionary = sess.current_map.get_node(nid) as Dictionary
			var ntype := String(node.get("type", ""))
			if ntype == "race":
				race_id = nid
				break
		if not race_id.is_empty():
			break
		if not bool(app.call("enter_run_node", String(options[0].get("id", "")))):
			break
	if not _expect(not race_id.is_empty(), "a race node must become available within the walk (steps=%d)" % steps):
		return

	if not _expect(bool(app.call("start_run_race", race_id)), "start_run_race must accept an available race node"):
		return
	if not _expect(String(sess.current_node_id) == race_id, "the race node must be entered"):
		return
	var race_session: Dictionary = app.get("current_race_session")
	if not _expect(String(race_session.get("mode", "")) == "run", "the race session must be a run race"):
		return
	if not _expect(String(race_session.get("run_node_id", "")) == race_id, "the race session must carry the run node"):
		return

	# Drive the real report seam: third place scores points and wears the car.
	var points_before: int = sess.run_points
	var wear_before: String = sess.run_state.get_car_wear(sess.current_car_id)
	if not _expect(bool(app.call("report_race_result", 3, 42.0, [], false, {})), "reporting a run race result must succeed"):
		return
	if not _expect(sess.run_points > points_before, "the finish position must score run points"):
		return
	if not _expect(sess.run_state.get_car_wear(sess.current_car_id) != wear_before, "a bad finish must wear the car"):
		return
	if not _expect(not sess.failed, "a bad finish on a plain race node must not end the run"):
		return
	var after: Dictionary = app.get("current_race_session")
	if not _expect(String(after.get("post_race_destination", "")) == "run_board", "the run race must route back to the board"):
		return

	# The save follows the resolved run.
	var live_store: Object = app.get("_save_store")
	var path := String(live_store.get("save_path"))
	var saved: Dictionary = SAVE_STORE.new(path).load_data()
	var saved_run: Dictionary = saved.get("current_run", {}) as Dictionary
	if not _expect(int(saved_run.get("run_points", -1)) == sess.run_points, "the save must carry the awarded points"):
		return

	# A started run race is marked in the save, cannot be restarted or retried,
	# and quitting it is a did-not-finish that resolves the stop for good.
	var quit_run: RunSession = app.call("start_run", 52525) as RunSession
	var opening := quit_run.current_node_id
	# A loading screen that fails and is backed out of costs nothing.
	app.call("start_run_race", opening)
	app.set("_transitioning_to_race", true)
	app.call("fail_race_loading", "test: the circuit did not build")
	app.call("_cancel_race_loading")
	for frame in 3:
		await process_frame
	if not _expect(quit_run.is_race_pending() and quit_run.race_in_flight.is_empty(), "a race that never left its loading screen is still there to race"):
		return

	# The race scene itself marks the race when its countdown begins.
	app.call("start_run_race", opening)
	var race := (load(RACE_SCENE) as PackedScene).instantiate()
	root.add_child(race)
	var waited := 0
	while quit_run.race_in_flight.is_empty() and waited < RACE_SCENE_FRAME_LIMIT:
		waited += 1
		await process_frame
	if not _expect(String(quit_run.race_in_flight.get("node", "")) == opening, "the race scene's countdown marks the run race as running"):
		return
	race.queue_free()
	await process_frame
	quit_run.race_in_flight = {}
	if not _expect(bool(app.call("start_run_race", opening)), "the opening race starts"):
		return
	app.call("race_started")
	if not _expect(not quit_run.race_in_flight.is_empty(), "a started race is marked"):
		return
	var on_disk: Dictionary = SAVE_STORE.new(path).load_data().get("current_run", {}) as Dictionary
	if not _expect(String((on_disk.get("race_in_flight", {}) as Dictionary).get("node", "")) == opening, "a started race is in the save before it is driven"):
		return
	if not _expect(not bool(app.call("can_retry_race")), "a run race offers no restart or retry"):
		return
	app.call("retry_race", false)
	if not _expect(quit_run.race_in_flight.get("node", "") == opening and not quit_run.resolved_nodes.has(opening), "retry does nothing in a run"):
		return
	app.call("abandon_race")
	for frame in 3:
		await process_frame
	if not _expect(quit_run.resolved_nodes.has(opening) and quit_run.race_in_flight.is_empty(), "quitting a run race resolves it"):
		return
	if not _expect(quit_run.run_points == 0 and quit_run.run_state.get_car_wear(quit_run.current_car_id) != "clean", "a quit race scores nothing and wears the car"):
		return
	if not _expect(not bool(app.call("start_run_race", opening)), "a quit race cannot be started again"):
		return

	# A race left running when the game closed resolves the same way on boot.
	var closed: RunSession = app.call("start_run", 63636) as RunSession
	app.call("start_run_race", closed.current_node_id)
	app.call("race_started")
	var reloaded := RunSession.deserialize(SAVE_STORE.new(path).load_data().get("current_run", {}) as Dictionary)
	app.set("_current_run_session", reloaded)
	app.call("_settle_race_in_flight")
	if not _expect(reloaded.resolved_nodes.has(reloaded.current_node_id) and reloaded.race_in_flight.is_empty(), "a race interrupted by a closed game resolves on boot"):
		return

	app.call("abandon_run")
	if _failed:
		return
	print("RUN_RACE_OUTCOME_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_RACE_OUTCOME_TEST FAIL: " + message)
	quit(1)
	return false
