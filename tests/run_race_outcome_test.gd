extends SceneTree

## GURI-1740d race-outcome slice: a `race` node hands over to the real race flow
## and the reported result resolves back into the run (points, wear, persist,
## and the route back to the board).

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const GENERATED_CIRCUITS := preload("res://scripts/race/generated_circuit_identity.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
## Generous: the scene builds a generated circuit before its countdown.
const RACE_SCENE_FRAME_LIMIT := 3000

var _failed := false

class FailingSaveStore extends SaveStore:
	func _init(path: String) -> void:
		super(path)

	func save_data(_data: Dictionary) -> bool:
		last_save_error = "Injected run result save failure"
		return false


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

	# A failed result save is not a committed result; retry saves the same outcome.
	var blocked: RunSession = app.call("start_run", 94949) as RunSession
	var blocked_node := blocked.current_node_id
	app.call("start_run_race", blocked_node)
	app.call("race_started")
	app.set("_save_store", FailingSaveStore.new(path))
	if not _expect(not bool(app.call("report_race_result", 3, 42.0, [], false, {})), "an unsaved run result reports failure"):
		return
	var pending: Dictionary = app.get("current_race_session")
	if not _expect(not bool(pending.get("result_committed", false)) and not String(pending.get("save_error", "")).is_empty(), "an unsaved result retains its save error"):
		return
	var applied := RunSession.serialize(blocked)
	if not _expect(not bool(app.call("report_race_result", 1, 1.0, [], false, {})) and RunSession.serialize(blocked) == applied, "repeated failed saves cannot award points or wear twice"):
		return
	app.set("_save_store", live_store)
	if not _expect(bool(app.call("report_race_result", 1, 1.0, [], false, {})) and RunSession.serialize(blocked) == applied, "retry saves the originally resolved outcome once"):
		return
	var committed: Dictionary = app.get("current_race_session")
	if not _expect(bool(committed.get("result_committed", false)) and not committed.has("save_error") and int((committed.get("result", {}) as Dictionary).get("position", 0)) == 3, "successful retry clears the warning without replacing the result"):
		return
	var retried := RunSession.deserialize(SAVE_STORE.new(path).load_data()["current_run"])
	if not _expect(retried != null and retried.run_points == blocked.run_points and retried.resolved_nodes.has(blocked_node) and retried.race_in_flight.is_empty() and retried.run_state.get_car_wear(retried.current_car_id) == blocked.run_state.get_car_wear(blocked.current_car_id), "the retried result reaches disk"):
		return
	var countdown_run: RunSession = app.call("start_run", 95959) as RunSession
	app.call("start_run_race", countdown_run.current_node_id)
	app.set("_save_store", FailingSaveStore.new(path))
	if not _expect(app.call("race_started") == false and countdown_run.race_in_flight.is_empty(), "a failed countdown write does not start an unrecorded race"):
		return
	app.set("_save_store", live_store)
	if not _expect(bool(app.call("race_started")), "the countdown can retry after storage recovers"):
		return

	# Every stop races its own circuit, in the act's room, and keeps it.
	var tour: RunSession = app.call("start_run", 74747) as RunSession
	var first_stop := tour.current_node_id
	var first := _run_circuit(app, first_stop)
	if not _expect(String(first.get("theme", "")) == "kitchen", "act 1 races in the kitchen"):
		return
	var tour_reloaded := RunSession.deserialize(RunSession.serialize(tour))
	app.set("_current_run_session", tour_reloaded)
	if not _expect(String(_run_circuit(app, first_stop).get("fingerprint", "")) == String(first["fingerprint"]), "a stop keeps its circuit after the run is saved and loaded"):
		return
	app.set("_current_run_session", tour)
	# Across a run's stops the draw varies the room and the direction independently.
	var rooms := {}
	var directions := {}
	var combos := {}
	for stop: String in tour.current_map.nodes:
		var draw := GENERATED_CIRCUITS.create(&"kitchen", GENERATED_CIRCUITS.room_for_route_seed(tour.circuit_seed(stop)), tour.circuit_seed(stop), tour.circuit_reversed(stop), 1)
		rooms[String(draw["room"])] = true
		directions[bool(draw["reverse"])] = true
		combos["%s|%s" % [draw["room"], draw["reverse"]]] = true
	if not _expect(rooms.size() > 2 and directions.size() == 2 and combos.size() > rooms.size(), "stops draw several rooms, both directions, and a room is not tied to one direction (rooms %d, combos %d)" % [rooms.size(), combos.size()]):
		return
	RUN_WALK.settle(app, tour)
	if not _expect(RUN_WALK.walk_to(app, tour, "race"), "a second race is reachable in act 1"):
		return
	var second := _run_circuit(app, tour.current_node_id)
	if not _expect(String(second["fingerprint"]) != String(first["fingerprint"]), "a different stop races a different circuit"):
		return
	if not _expect(RUN_WALK.walk_to(app, tour, "act_rival"), "the act rival is reachable"):
		return
	RUN_WALK.settle(app, tour)
	var act_two := _run_circuit(app, tour.current_node_id)
	if not _expect(tour.current_map.act == 2 and String(act_two.get("theme", "")) == "workshop", "act 2 races in the workshop"):
		return
	var duel_run: RunSession = null
	for attempt in 12:
		duel_run = app.call("start_run", 85858 + attempt * 29) as RunSession
		if RUN_WALK.walk_to(app, duel_run, "rival"):
			break
		duel_run = null
	if not _expect(duel_run != null and bool(app.call("start_run_rival", duel_run.current_node_id)), "a rival duel is reachable and starts"):
		return
	var duel_event: Dictionary = (app.get("current_race_session") as Dictionary).get("event", {})
	if not _expect(String(duel_event.get("race_format", "")) == "rival_duel" and int(duel_event.get("opponent_count", 0)) == 1 and duel_event.has("generated_circuit_identity"), "a duel stays one on one on its generated circuit"):
		return
	app.set("_save_store", FailingSaveStore.new(path))
	if not _expect(not bool(app.call("report_race_result", 1, 2.0, [], false, {})), "an unsaved rival reward reports failure"):
		return
	var duel_applied := RunSession.serialize(duel_run)
	app.set("_save_store", live_store)
	if not _expect(bool(app.call("report_race_result", 1, 2.0, [], false, {})) and RunSession.serialize(duel_run) == duel_applied and duel_run.won_cars().size() == 1, "retrying a rival reward does not deal another car"):
		return
	duel_run = app.call("start_run", 74747) as RunSession
	if not _expect(RUN_WALK.walk_to(app, duel_run, "act_rival"), "the next run reaches the act rival"):
		return
	var next_act := duel_run.current_map.act + 1
	app.call("start_run_race", duel_run.current_node_id)
	app.set("_save_store", FailingSaveStore.new(path))
	if not _expect(not bool(app.call("report_race_result", 1, 2.0, [], false, {})), "an unsaved act advance reports failure"):
		return
	var advanced := RunSession.serialize(duel_run)
	app.set("_save_store", live_store)
	var advance_saved: bool = app.call("report_race_result", 1, 2.0, [], false, {})
	if not _expect(advance_saved and RunSession.serialize(duel_run) == advanced and duel_run.current_map.act == next_act, "retry saves an advanced act without resolving its opening race"):
		return
	if not _expect(RUN_WALK.walk_to(app, duel_run, "act_rival"), "the advanced run reaches its next act rival"):
		return
	app.call("start_run_race", duel_run.current_node_id)
	app.set("_save_store", FailingSaveStore.new(path))
	if not _expect(not bool(app.call("report_race_result", 2, 2.0, [], false, {})) and duel_run.is_failed(), "an unsaved terminal result reports failure and retains its ended run"):
		return
	app.set("_save_store", live_store)
	if not _expect(bool(app.call("report_race_result", 2, 2.0, [], false, {})) and app.call("current_run_session") == null, "retry saves the terminal result and releases the active run"):
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
	race.set("_results_finalized", true)
	race.set("_save_error", "Injected display failure")
	var continue_action := race.get("_continue_button") as Button
	continue_action.disabled = true
	race.call("_update_results", [])
	var result_copy := (race.get("_results_label") as Label).text.to_upper()
	if not _expect(result_copy.contains("RETRY SAVE") and not result_copy.contains("CONTINUE"), "unsaved results must not offer a disabled continue action"):
		return
	continue_action.disabled = false
	race.call("_update_results", [])
	if not _expect((race.get("_results_label") as Label).text.to_upper().contains("CONTINUE"), "unsaved results may name continue when it is enabled"):
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
	app.set("_save_store", FailingSaveStore.new(path))
	app.call("_settle_race_in_flight")
	if not _expect(reloaded.resolved_nodes.has(reloaded.current_node_id) and reloaded.race_in_flight.is_empty(), "a race interrupted by a closed game resolves on boot"):
		return
	var recovered := RunSession.serialize(reloaded)
	app.call("_settle_race_in_flight")
	if not _expect(RunSession.serialize(reloaded) == recovered and not String(app.get("run_save_error")).is_empty(), "failed recovery saves retain the resolved outcome without a second penalty"):
		return
	app.set("_save_store", live_store)
	app.call("persist_current_run")
	var recovered_disk := RunSession.deserialize(SAVE_STORE.new(path).load_data()["current_run"])
	if not _expect(recovered_disk != null and recovered_disk.resolved_nodes.has(reloaded.current_node_id) and recovered_disk.race_in_flight.is_empty(), "SAVE AGAIN persists a recovered DNF without racing it again"):
		return

	app.call("abandon_run")
	if _failed:
		return
	print("RUN_RACE_OUTCOME_TEST PASS")
	quit(0)


## Starts the stop's race (test mode: no scene change) and returns its circuit.
func _run_circuit(app: Object, stop_id: String) -> Dictionary:
	if not _expect(bool(app.call("start_run_race", stop_id)), "the run race at %s starts" % stop_id):
		return {}
	var event: Dictionary = (app.get("current_race_session") as Dictionary).get("event", {})
	return event.get("generated_circuit_identity", {})


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_RACE_OUTCOME_TEST FAIL: " + message)
	quit(1)
	return false
