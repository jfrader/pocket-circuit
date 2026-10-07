extends SceneTree

## GURI-1740 persistence slice: the active run survives a save/reload like a
## fresh boot, and abandoning it clears the field.

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_SESSION := preload("res://scripts/progression/run_session.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must exist"):
		return
	var sess: RunSession = app.call("start_run", 4242) as RunSession
	if not _expect(sess != null, "start_run must create a session"):
		return
	if not _expect(app.call("current_run_session") == sess, "the app must expose the active run"):
		return
	# Resolve one node so the persisted state is mid-run, not just the opening.
	var options: Array[Dictionary] = sess.available_nodes()
	if not _expect(options.size() > 0, "the opening node must have children"):
		return
	if not _expect(sess.enter_node(String(options[0].get("id", ""))), "entering the first node must succeed"):
		return
	app.call("persist_current_run")

	# Reload from disk exactly like a fresh boot would.
	var live_store: Object = app.get("_save_store")
	var path := String(live_store.get("save_path"))
	var reloaded := SAVE_STORE.new(path)
	var data: Dictionary = reloaded.load_data()
	var resumed: RunSession = RUN_SESSION.deserialize(data.get("current_run", {}) as Dictionary)
	if not _expect(resumed != null and resumed.run_seed == sess.run_seed, "the run seed must survive the roundtrip"):
		return
	if not _expect(resumed.current_node_id == sess.current_node_id, "the current node must survive the roundtrip (got %s want %s)" % [resumed.current_node_id, sess.current_node_id]):
		return
	if not _expect(resumed.run_budget == sess.run_budget and resumed.run_points == sess.run_points, "budget and points must survive"):
		return
	if not _expect(resumed.owned_cars.size() == sess.owned_cars.size(), "owned cars must survive"):
		return
	if not _expect(resumed.run_state.get_car_wear(resumed.current_car_id) == sess.run_state.get_car_wear(sess.current_car_id), "wear must survive"):
		return

	# Abandoning clears the run from the live session and from the save.
	app.call("abandon_run")
	if not _expect(app.call("current_run_session") == null, "abandon_run must clear the live session"):
		return
	var after: Dictionary = SAVE_STORE.new(path).load_data()
	var run_after: Variant = after.get("current_run", {})
	if not _expect(run_after is Dictionary and (run_after as Dictionary).is_empty(), "abandon_run must clear the saved run"):
		return

	if _failed:
		return
	print("RUN_PERSISTENCE_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_PERSISTENCE_TEST FAIL: " + message)
	quit(1)
	return false
