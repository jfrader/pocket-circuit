extends SceneTree

const BOOT_SCENE := preload("res://scenes/boot/boot.tscn")
const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE_SCRIPT := preload("res://scripts/persistence/save_store.gd")

class CountingSaveStore extends SaveStore:
	var save_count := 0
	var stored_data: Dictionary = {}
	var should_fail := false

	func _init() -> void:
		super("user://tests/pocket_circuit_championship_flow_test.json")

	func save_data(data: Dictionary) -> bool:
		save_count += 1
		if should_fail:
			last_save_error = "Injected save failure"
			return false
		stored_data = data.duplicate(true)
		return true


class TestShell extends CanvasLayer:
	var map_shown := false
	var ending_shown := false
	var save_error_shown := false
	var title_shown := false

	func show_map(_summary: Dictionary = {}) -> void:
		map_shown = true

	func show_ending() -> void:
		ending_shown = true

	func show_save_error(_title: String, _detail: String, _retry_action: Callable, _back_action: Callable) -> void:
		save_error_shown = true

	func show_title() -> void:
		title_shown = true


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
	store.should_fail = true
	app.call("confirm_new_championship")
	if not _expect(not bool(app.call("get_save_data")["championship_started"]) and shell.save_error_shown and not shell.map_shown and store.save_count == 1, "a failed New Championship save must preserve progress and show a blocking error"):
		return
	store.should_fail = false
	shell.save_error_shown = false
	app.call("confirm_new_championship")
	if not _expect(bool(app.call("get_save_data")["championship_started"]) and bool(app.call("get_save_data")["reduced_motion"]) and bool(app.call("get_save_data")["reduced_camera_shake"]) and store.save_count == 2, "confirming New Championship should preserve comfort settings and persist once"):
		return
	progress = app.call("get_save_data")
	progress["unlocked_vehicles"] = ["rustbug", "pinbolt"]
	app.set("_save_data", progress)
	store.should_fail = true
	shell.save_error_shown = false
	app.current_race_session.clear()
	app.call("start_race", "kitchen_crumb_rush", "pinbolt", false)
	if not _expect(String(app.call("get_save_data")["selected_vehicle"]) == "rustbug" and app.current_race_session.is_empty() and shell.save_error_shown and store.save_count == 3, "a failed vehicle-selection save must not start the championship race or change the selection"):
		return
	shell.save_error_shown = false
	if not _expect(not bool(app.call("update_setting", "difficulty", "clockwork")) and String(app.call("get_save_data")["difficulty"]) == "club_circuit" and shell.save_error_shown and store.save_count == 4, "a failed settings save must keep the previous value and report failure"):
		return

	app.current_race_session = _session("championship")
	if not _expect(not bool(app.call("report_race_result", 2, 12.0, [])), "a failed result save must report failure"):
		return
	progress = app.call("get_save_data")
	if not _expect(store.save_count == 5 and progress["best_event_finishes"].is_empty() and not bool(app.current_race_session["result_committed"]) and app.current_race_session.has("save_error"), "failed result persistence must not alter or commit progress"):
		return
	store.should_fail = false
	if not _expect(bool(app.call("report_race_result", 2, 12.0, [])), "retrying a failed result save should succeed"):
		return
	progress = app.call("get_save_data")
	if not _expect(store.save_count == 6 and int(progress["best_event_finishes"]["kitchen_crumb_rush"]) == 2 and bool(app.current_race_session["result_committed"]), "a successful retry should commit the result exactly once"):
		return
	app.call("report_race_result", 1, 10.0, [])
	if not _expect(store.save_count == 6 and int(app.call("get_save_data")["best_event_finishes"]["kitchen_crumb_rush"]) == 2, "a duplicate results signal must not save or alter progress"):
		return

	app.call("retry_race", false)
	if not _expect(not bool(app.current_race_session["result_committed"]) and not app.current_race_session.has("result") and not app.current_race_session.has("save_error"), "Retry should create a fresh uncommitted attempt"):
		return
	app.call("report_race_result", 4, 15.0, [])
	progress = app.call("get_save_data")
	if not _expect(store.save_count == 6 and int(progress["best_event_finishes"]["kitchen_crumb_rush"]) == 2, "a weaker retry should not rewrite unchanged progress"):
		return
	app.call("report_race_result", 1, 9.0, [])
	if not _expect(store.save_count == 6, "a duplicate retry result must remain idempotent"):
		return

	app.current_race_session = _session("quick")
	app.call("report_race_result", 1, 8.0, [])
	if not _expect(store.save_count == 6 and int(app.call("get_save_data")["best_event_finishes"]["kitchen_crumb_rush"]) == 2, "Quick Race must not save or mutate championship progress"):
		return

	app.current_race_session = _session("championship")
	app.call("report_race_result", 1, 7.0, [])
	var saves_before_continue := store.save_count
	app.call("continue_after_race", false)
	if not _expect(store.save_count == saves_before_continue and int(app.get("_last_result_summary")["points_gained"]) == 3, "Continue should only navigate with the latest committed summary"):
		return

	var pre_final := store.default_data()
	pre_final["championship_started"] = true
	for event_index in CATALOG.EVENTS.size() - 1:
		var event_id := String(CATALOG.EVENTS[event_index]["id"])
		pre_final = CATALOG.apply_event_result(pre_final, event_id, 1)["save"]
	app.set("_save_data", pre_final)
	app.current_race_session = _session("championship", "office_last_light")
	if not _expect(bool(app.call("report_race_result", 1, 40.0, [])), "the championship-winning result should persist"):
		return
	progress = app.call("get_save_data")
	if not _expect(CATALOG.is_ending_pending(progress) and not bool(progress["ending_seen"]) and String(app.current_race_session["post_race_destination"]) == "ending", "winning the championship should persist a pending, not pre-acknowledged, ending"):
		return

	app.set("_save_data", store.stored_data.duplicate(true))
	app.current_race_session.clear()
	var boot := BOOT_SCENE.instantiate()
	root.add_child(boot)
	current_scene = boot
	app.set("_last_scene", null)
	app.set("_destination", "title")
	app.call("_sync_current_scene")
	if not _expect(shell.ending_shown, "reloading before Continue should recover the pending ending"):
		return
	var saves_before_acknowledge := store.save_count
	if not _expect(bool(app.call("finish_ending", "map")), "leaving the ending should persist its acknowledgment"):
		return
	progress = app.call("get_save_data")
	if not _expect(bool(progress["ending_seen"]) and not CATALOG.is_ending_pending(progress) and store.save_count == saves_before_acknowledge + 1 and shell.map_shown, "ending acknowledgment should save exactly once before navigation"):
		return
	root.remove_child(boot)
	boot.free()
	current_scene = null

	app.current_race_session.clear()
	app.set("_shell", null)
	shell.free()
	store.remove_save()
	print("CHAMPIONSHIP_FLOW_TEST PASS")
	quit(0)


func _session(mode: String, event_id: String = "kitchen_crumb_rush") -> Dictionary:
	return {
		"mode": mode,
		"event_id": event_id,
		"event": CATALOG.get_event(event_id),
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
