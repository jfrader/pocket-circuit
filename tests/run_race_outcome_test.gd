extends SceneTree

## GURI-1740d race-outcome slice: a `race` node hands over to the real race flow
## and the reported result resolves back into the run (points, wear, persist,
## and the route back to the board).

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")

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
