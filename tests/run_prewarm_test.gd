extends SceneTree

## GURI-1846 (Prewarm the run board's next race circuits): the board's race
## stops are prepared ahead of their race, one job at a time, each circuit once,
## under the same cache key the race then loads.

const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const RACE_PREPARATION := preload("res://scripts/race/race_preparation.gd")
## Generous: a cold prepare builds a full generated circuit off the main thread.
const PREWARM_DEADLINE_MSEC := 120000

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must exist"):
		return
	TRACK_BUILDER.clear_generated_cache()
	var sess: RunSession = app.call("start_run", 61616) as RunSession
	var opening := sess.current_node_id

	app.call("prewarm_run_stops")
	app.call("prewarm_run_stops")
	var queued: Dictionary = app.get("_prewarm_keys")
	var jobs: Array = app.get("_prewarm_queue")
	if not _expect(queued.size() == 1 and jobs.size() == 1, "the opening race is queued once, however often the board asks (jobs %d)" % jobs.size()):
		return
	if not _expect(bool(app.call("start_run_race", opening)), "the opening race starts"):
		return
	var event: Dictionary = (app.get("current_race_session") as Dictionary).get("event", {})
	var key: String = TRACK_BUILDER.generated_circuit_cache_key(event)
	if not _expect(queued.has(key), "the board warms the exact circuit the race loads"):
		return
	if not _expect(await _wait_cached(key), "the opening circuit is prepared before its race"):
		return

	if not _expect(await _wait_idle(app), "the queue runs dry once its jobs finish"):
		return
	if not _expect((app.get("_prewarm_keys") as Dictionary).is_empty(), "a finished job leaves nothing marked as queued"):
		return

	# Stand on a settled stop whose children include more than one race-type
	# stop (siblings never share a type, so a race beside a rival): every
	# race-type stop the board offers is warmed.
	var fork := _fork_stop(sess)
	if not _expect(not fork.is_empty(), "the act has a stop offering a race and a rival"):
		return
	sess.current_node_id = fork
	sess.resolved_nodes[fork] = true
	var race_stops: Array[String] = []
	for stop: Dictionary in sess.available_nodes():
		if String(stop["type"]) in RunSession.RACE_NODE_TYPES:
			race_stops.append(String(stop["id"]))
	if not _expect(race_stops.size() > 1, "the seed offers several race stops past the opening (got %d)" % race_stops.size()):
		return
	app.call("prewarm_run_stops")
	if not _expect((app.get("_prewarm_keys") as Dictionary).size() == race_stops.size(), "each race-type stop on offer is queued (%d)" % race_stops.size()):
		return
	# Jobs run one at a time: never more than one preparation node alive.
	var most_at_once := 0
	for frame in 120:
		var alive := 0
		for child: Node in app.get_children():
			if child.get_script() == RACE_PREPARATION:
				alive += 1
		most_at_once = maxi(most_at_once, alive)
		await process_frame
	if not _expect(most_at_once == 1, "prewarm jobs run one at a time (saw %d at once)" % most_at_once):
		return
	app.call("_drop_queued_prewarms")
	if not _expect((app.get("_prewarm_queue") as Array).is_empty(), "a race starting to load drops the queued prewarms"):
		return
	if not _expect(await _wait_idle(app), "the running job finishes after the queue is dropped"):
		return

	app.call("abandon_run")
	TRACK_BUILDER.clear_generated_cache()
	if _failed:
		return
	print("RUN_PREWARM_TEST PASS")
	quit(0)


func _wait_cached(key: String) -> bool:
	var deadline := Time.get_ticks_msec() + PREWARM_DEADLINE_MSEC
	while Time.get_ticks_msec() < deadline:
		if not TRACK_BUILDER.cached_prepared(key).is_empty():
			return true
		await process_frame
	return false


## The first stop of the act whose children hold more than one race-type stop.
func _fork_stop(sess: RunSession) -> String:
	for stop_id: String in sess.current_map.nodes:
		var count := 0
		for child: Dictionary in sess.current_map.get_children(stop_id):
			if String(child["type"]) in RunSession.RACE_NODE_TYPES:
				count += 1
		if count > 1:
			return stop_id
	return ""


## Waits for the queue to finish; false if it is still running at the deadline.
func _wait_idle(app: Object) -> bool:
	var deadline := Time.get_ticks_msec() + PREWARM_DEADLINE_MSEC
	while bool(app.get("_prewarm_running")) and Time.get_ticks_msec() < deadline:
		await process_frame
	return not bool(app.get("_prewarm_running"))


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("RUN_PREWARM_TEST FAIL: " + message)
		quit(1)
	return condition
