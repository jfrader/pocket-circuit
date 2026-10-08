extends SceneTree

## GURI-1846 (Prewarm the run board's next race circuits): the board's race
## stops are prepared ahead of their race, one job at a time, each circuit once,
## under the same cache key the race then loads.

const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
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

	await _wait_idle(app)
	if not _expect((app.get("_prewarm_keys") as Dictionary).is_empty(), "a finished job leaves nothing marked as queued"):
		return

	# Past the opening race the board offers its children: every race-type one is warmed.
	RUN_WALK.settle(app, sess)
	var race_stops: Array[String] = []
	for stop: Dictionary in sess.available_nodes():
		if String(stop["type"]) in RunSession.RACE_NODE_TYPES:
			race_stops.append(String(stop["id"]))
	app.call("prewarm_run_stops")
	if not _expect((app.get("_prewarm_keys") as Dictionary).size() == race_stops.size(), "each race-type stop on offer is queued (%d)" % race_stops.size()):
		return
	app.call("_drop_queued_prewarms")
	if not _expect((app.get("_prewarm_queue") as Array).is_empty(), "a race starting to load drops the queued prewarms"):
		return
	await _wait_idle(app)

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


## Lets a running job finish before teardown, so no thread outlives the test.
func _wait_idle(app: Object) -> void:
	var deadline := Time.get_ticks_msec() + PREWARM_DEADLINE_MSEC
	while bool(app.get("_prewarm_running")) and Time.get_ticks_msec() < deadline:
		await process_frame


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("RUN_PREWARM_TEST FAIL: " + message)
		quit(1)
	return condition
