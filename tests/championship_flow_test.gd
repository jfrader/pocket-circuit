extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE_SCRIPT := preload("res://scripts/persistence/save_store.gd")

class CountingSaveStore extends SaveStore:
	var save_count := 0
	var stored_data: Dictionary = {}

	func _init() -> void:
		super("user://tests/pocket_circuit_championship_flow_test.json")

	func save_data(data: Dictionary) -> bool:
		save_count += 1
		stored_data = data.duplicate(true)
		return true


class TestShell extends CanvasLayer:
	var map_shown := false

	func show_map(_summary: Dictionary = {}) -> void:
		map_shown = true


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return
	var store := CountingSaveStore.new()
	var shell := TestShell.new()
	app.set("_save_store", store)
	app.set("_shell", shell)
	var progress := store.default_data()
	progress["reduced_camera_shake"] = true
	progress["reduced_motion"] = true
	app.set("_save_data", progress)
	app.call("confirm_new_championship")
	if not _expect(bool(app.call("get_save_data")["championship_started"]) and bool(app.call("get_save_data")["reduced_motion"]) and bool(app.call("get_save_data")["reduced_camera_shake"]) and store.save_count == 1, "confirming New Championship should preserve comfort settings and persist once"):
		return

	app.current_race_session = _session("championship")
	app.call("report_race_result", 2, 12.0, [])
	progress = app.call("get_save_data")
	if not _expect(store.save_count == 2 and int(progress["best_event_finishes"]["kitchen_crumb_rush"]) == 2, "a championship result should commit and save immediately"):
		return
	app.call("report_race_result", 1, 10.0, [])
	if not _expect(store.save_count == 2 and int(app.call("get_save_data")["best_event_finishes"]["kitchen_crumb_rush"]) == 2, "a duplicate results signal must not save or alter progress"):
		return

	app.call("retry_race", false)
	if not _expect(not bool(app.current_race_session["result_committed"]) and not app.current_race_session.has("result"), "Retry should create a fresh uncommitted attempt"):
		return
	app.call("report_race_result", 4, 15.0, [])
	progress = app.call("get_save_data")
	if not _expect(store.save_count == 3 and int(progress["best_event_finishes"]["kitchen_crumb_rush"]) == 2, "a weaker retry should save once without reducing the best"):
		return
	app.call("report_race_result", 1, 9.0, [])
	if not _expect(store.save_count == 3, "a duplicate retry result must remain idempotent"):
		return

	app.current_race_session = _session("quick")
	app.call("report_race_result", 1, 8.0, [])
	if not _expect(store.save_count == 3 and int(app.call("get_save_data")["best_event_finishes"]["kitchen_crumb_rush"]) == 2, "Quick Race must not save or mutate championship progress"):
		return

	app.current_race_session = _session("championship")
	app.call("report_race_result", 1, 7.0, [])
	var saves_before_continue := store.save_count
	app.call("continue_after_race", false)
	if not _expect(store.save_count == saves_before_continue and int(app.get("_last_result_summary")["points_gained"]) == 3, "Continue should only navigate with the latest committed summary"):
		return

	app.current_race_session.clear()
	app.set("_shell", null)
	shell.free()
	store.remove_save()
	print("CHAMPIONSHIP_FLOW_TEST PASS")
	quit(0)


func _session(mode: String) -> Dictionary:
	return {
		"mode": mode,
		"event_id": "kitchen_crumb_rush",
		"event": CATALOG.get_event("kitchen_crumb_rush"),
		"vehicle_id": "rustbug",
		"difficulty": "club_circuit",
		"result_committed": false,
	}


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("CHAMPIONSHIP_FLOW_TEST FAIL: " + message)
	quit(1)
	return false
