extends SceneTree

## GURI-1740f rival duel: `rival` node hands over via start_run_rival to the real
## race flow (1v1 rival_duel), report resolves via resolve_rival (win/loss), persist,
## route back to board, run not ended. Copy of idioms from run_race_outcome_test.

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

	# --- Win: a one-on-one duel that grants the rival's car ---
	var win_sess: RunSession = _run_to_rival(app)
	if not _expect(win_sess != null, "a rival must be reachable within a few runs"):
		return
	var rival_id := win_sess.current_node_id
	var owned_before: int = win_sess.owned_cars.size()
	if not _expect(bool(app.call("start_run_rival", rival_id)), "start_run_rival must accept the rival stop"):
		return
	var race_session: Dictionary = app.get("current_race_session")
	var ev: Dictionary = race_session.get("event", {}) as Dictionary
	if not _expect(String(race_session.get("mode", "")) == "run" and String(race_session.get("run_node_id", "")) == rival_id, "the duel must be a run race on the rival stop"):
		return
	if not _expect(String(ev.get("race_format", "")) == "rival_duel" and int(ev.get("opponent_count", 0)) == 1, "the duel must be rival_duel with one opponent"):
		return
	if not _expect(bool(app.call("report_race_result", 1, 30.0, [], false, {})), "reporting a duel win must succeed"):
		return
	if not _expect(win_sess.owned_cars.size() == owned_before + 1 and not win_sess.failed, "a win grants exactly one car"):
		return
	if not _expect(String((app.get("current_race_session") as Dictionary).get("post_race_destination", "")) == "run_board", "the duel routes back to the board"):
		return
	var path: String = String((app.get("_save_store") as Object).get("save_path"))
	var saved_run: Dictionary = SAVE_STORE.new(path).load_data().get("current_run", {}) as Dictionary
	if not _expect((saved_run.get("owned_cars", {}) as Dictionary).size() == win_sess.owned_cars.size(), "the save carries the won car"):
		return

	# --- Loss the points cover: costs points, not wear ---
	var loss_sess: RunSession = _run_to_rival(app)
	loss_sess.run_points = RunSession.RIVAL_LOSS_POINTS_COST + 2
	var wear_before: String = loss_sess.run_state.get_car_wear(loss_sess.current_car_id)
	app.call("start_run_rival", loss_sess.current_node_id)
	if not _expect(bool(app.call("report_race_result", 2, 35.0, [], false, {})), "reporting a duel loss must succeed"):
		return
	if not _expect(loss_sess.run_points == 2 and loss_sess.run_state.get_car_wear(loss_sess.current_car_id) == wear_before, "a covered loss costs exactly its points"):
		return
	if not _expect(not loss_sess.failed, "a lost duel does not end the run"):
		return
	saved_run = SAVE_STORE.new(path).load_data().get("current_run", {}) as Dictionary
	if not _expect(int(saved_run.get("run_points", -1)) == loss_sess.run_points, "the save carries the points after a loss"):
		return

	# --- Loss the points cannot cover: wears the car ---
	var short_sess: RunSession = _run_to_rival(app)
	short_sess.run_points = 0
	app.call("start_run_rival", short_sess.current_node_id)
	app.call("report_race_result", 2, 35.0, [], false, {})
	if not _expect(short_sess.run_state.get_car_wear(short_sess.current_car_id) != "clean", "an uncovered loss wears the car"):
		return

	app.call("abandon_run")
	if _failed:
		return
	print("RUN_RIVAL_OUTCOME_TEST PASS")
	quit(0)


## Starts runs until one walks onto an unraced rival stop.
func _run_to_rival(app: Object) -> RunSession:
	for attempt in 12:
		var sess: RunSession = app.call("start_run", 1740010 + attempt * 17) as RunSession
		if RUN_WALK.walk_to(app, sess, "rival"):
			return sess
	return null


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_RIVAL_OUTCOME_TEST FAIL: " + message)
	quit(1)
	return false
