extends SceneTree

const APP_PATH := "/root/App"
const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE_SCRIPT := preload("res://scripts/persistence/save_store.gd")
const TEST_PATH := "user://tests/pocket_circuit_race_result_persistence_test.json"


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var store := SAVE_STORE_SCRIPT.new(TEST_PATH) as SaveStore
	store.remove_save()
	var app := root.get_node_or_null(APP_PATH)
	if not _expect(app != null, "App autoload must exist"):
		return
	app.set("_save_store", store)
	var data := store.default_data()
	app.set("_save_data", data)

	# Use championship session + report_race_result seam (smallest real App result path; avoids _begin_race_transition + scene load for speed)
	var event_id := "kitchen_crumb_rush"
	var session: Dictionary = {
		"mode": "championship",
		"event_id": event_id,
		"event": CATALOG.get_event(event_id),
		"vehicle_id": "rustbug",
		"difficulty": "club_circuit",
		"result_committed": false,
	}
	app.current_race_session = session
	var results: Array = [
		{"position": 1, "driver_name": "Juniper", "vehicle_name": "Pinbolt", "time": 46.1, "finished": true, "dnf": false},
		{"position": 2, "driver_name": "Rae", "vehicle_name": "Rustbug", "time": 46.5, "finished": true, "dnf": false},
	]
	var committed: bool = app.call("report_race_result", 2, 46.5, results, false, {})
	if not _expect(committed, "first result report must succeed"):
		return
	var loaded: Dictionary = store.load_data()
	if not _expect(int(loaded.get("best_event_finishes", {}).get(event_id, 0)) == 2, "2nd place must record best finish 2"):
		return
	if not _expect(int(loaded.get("best_event_points", {}).get(event_id, 0)) == 7, "2nd place must record 7 points"):
		return
	if not _expect((loaded.get("completed_events", []) as Array) == [event_id], "event must be marked completed"):
		return
	if not _expect((loaded.get("completed_acts", []) as Array).is_empty(), "non-finale must not complete act"):
		return
	if not _expect((loaded.get("unlocked_vehicles", []) as Array) == ["rustbug"], "no new unlock on non-finale"):
		return

	# Better result on same event must improve best and keep the improvement
	app.current_race_session = session.duplicate(true)
	app.current_race_session["result_committed"] = false
	var better: Array = [
		{"position": 1, "driver_name": "Rae", "vehicle_name": "Rustbug", "time": 40.2, "finished": true, "dnf": false},
		{"position": 2, "driver_name": "Juniper", "vehicle_name": "Pinbolt", "time": 41.0, "finished": true, "dnf": false},
	]
	committed = app.call("report_race_result", 1, 40.2, better, false, {})
	if not _expect(committed, "better result must commit"):
		return
	loaded = store.load_data()
	if not _expect(int(loaded.get("best_event_finishes", {}).get(event_id, 99)) == 1, "better must update best finish to 1"):
		return
	if not _expect(int(loaded.get("best_event_points", {}).get(event_id, 0)) == 10, "1st must set 10 points"):
		return

	# Worse result after must keep the prior best (accumulate correctly)
	app.current_race_session = session.duplicate(true)
	app.current_race_session["result_committed"] = false
	var worse: Array = [
		{"position": 1, "driver_name": "Juniper", "vehicle_name": "Pinbolt", "time": 39.0, "finished": true, "dnf": false},
		{"position": 2, "driver_name": "Opp", "vehicle_name": "Pinbolt", "time": 40.0, "finished": true, "dnf": false},
		{"position": 3, "driver_name": "Rae", "vehicle_name": "Rustbug", "time": 50.0, "finished": true, "dnf": false},
	]
	committed = app.call("report_race_result", 3, 50.0, worse, false, {})
	if not _expect(committed, "worse result must still commit without regress"):
		return
	loaded = store.load_data()
	if not _expect(int(loaded.get("best_event_finishes", {}).get(event_id, 99)) == 1, "worse must retain best finish 1"):
		return
	if not _expect(int(loaded.get("best_event_points", {}).get(event_id, 0)) == 10, "worse must retain best points 10"):
		return

	# Finale win via disk-reload seam: act complete + vehicle unlock.
	# Prep the act gate points (20 total) so the finale is legally reachable in real flow; report path itself does not gate.
	var pre_finale := store.load_data().duplicate(true)
	pre_finale["best_event_finishes"] = {"kitchen_crumb_rush": 1, "kitchen_mug_run": 1}
	pre_finale["best_event_points"] = {"kitchen_crumb_rush": 10, "kitchen_mug_run": 10}
	pre_finale["completed_events"] = ["kitchen_crumb_rush", "kitchen_mug_run"]
	pre_finale["completed_acts"] = []
	pre_finale["unlocked_vehicles"] = ["rustbug"]
	app.set("_save_data", pre_finale)
	if not store.save_data(pre_finale):
		push_error("prep save failed")
		quit(1)
		return

	var finale_id := "kitchen_clean_line"
	var finale_session: Dictionary = {
		"mode": "championship",
		"event_id": finale_id,
		"event": CATALOG.get_event(finale_id),
		"vehicle_id": "rustbug",
		"difficulty": "club_circuit",
		"result_committed": false,
	}
	app.current_race_session = finale_session
	var win_res: Array = [
		{"position": 1, "driver_name": "Rae", "vehicle_name": "Rustbug", "time": 55.0, "finished": true, "dnf": false},
		{"position": 2, "driver_name": "Juniper", "vehicle_name": "Pinbolt", "time": 58.0, "finished": true, "dnf": false},
	]
	committed = app.call("report_race_result", 1, 55.0, win_res, false, {})
	if not _expect(committed, "finale win report must succeed"):
		return
	# Fresh store instance forces disk reload
	var disk_store := SAVE_STORE_SCRIPT.new(TEST_PATH) as SaveStore
	var disk: Dictionary = disk_store.load_data()
	if not _expect("kitchen" in (disk.get("completed_acts", []) as Array), "finale 1st must complete the act"):
		return
	if not _expect("pinbolt" in (disk.get("unlocked_vehicles", []) as Array), "finale 1st must unlock act vehicle"):
		return
	if not _expect(int(disk.get("best_event_finishes", {}).get(finale_id, 0)) == 1, "finale must record finish 1"):
		return
	if not _expect(int(disk.get("best_event_points", {}).get(finale_id, 0)) == 10, "finale must record 10 points"):
		return

	store.remove_save()
	print("RACE_RESULT_PERSISTENCE_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	var s := SAVE_STORE_SCRIPT.new(TEST_PATH) as SaveStore
	s.remove_save()
	push_error("RACE_RESULT_PERSISTENCE_TEST FAIL: " + message)
	quit(1)
	return false
