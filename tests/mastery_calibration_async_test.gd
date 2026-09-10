extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")

class CalibrationStore extends SaveStore:
	var save_count := 0
	var stored_data: Dictionary = {}
	var should_fail := false

	func _init() -> void:
		super("user://tests/pocket_circuit_mastery_calibration_async_test.json")

	func save_data(data: Dictionary) -> bool:
		save_count += 1
		if should_fail:
			last_save_error = "Injected calibration save failure"
			return false
		stored_data = data.duplicate(true)
		return true


class CalibrationShell extends CanvasLayer:
	var refreshed_events: Array[String] = []

	func refresh_mastery_calibration(event_id: String) -> void:
		refreshed_events.append(event_id)


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return
	var store := CalibrationStore.new()
	var shell := CalibrationShell.new()
	var progress := store.default_data()
	progress["championship_started"] = true
	progress = CATALOG.apply_event_result(progress, "kitchen_crumb_rush", 1)["save"]
	app.set("_save_store", store)
	app.set("_save_data", progress)
	app.set("_shell", shell)
	store.should_fail = true

	var initial: Dictionary = app.call("get_mastery_state", "kitchen_crumb_rush", "rustbug")
	if not _expect(bool(initial.get("calibrating", false)) and not bool(initial.get("available", false)) and (initial.get("targets", {}) as Dictionary).is_empty(), "a migrated completed event should return CALIBRATING immediately instead of preparing synchronously"):
		return
	var deadline := Time.get_ticks_msec() + 15000
	var failed: Dictionary = initial
	while bool(failed.get("calibrating", false)) and Time.get_ticks_msec() < deadline:
		await process_frame
		failed = app.call("get_mastery_state", "kitchen_crumb_rush", "rustbug")
	if not _expect(bool(failed.get("calibration_failed", false)) and not bool(failed.get("available", false)) and store.save_count == 1 and store.stored_data.is_empty() and (app.call("get_save_data")["mastery_circuit_metrics"] as Dictionary).is_empty(), "failed async persistence must leave saved state unchanged and must not expose unsaved targets"):
		return

	store.should_fail = false
	app.call("retry_mastery_calibration", "kitchen_crumb_rush")
	var ready: Dictionary = failed
	deadline = Time.get_ticks_msec() + 15000
	while not bool(ready.get("available", false)) and Time.get_ticks_msec() < deadline:
		await process_frame
		ready = app.call("get_mastery_state", "kitchen_crumb_rush", "rustbug")
	if not _expect(bool(ready.get("available", false)) and not bool(ready.get("calibrating", true)) and not (ready.get("targets", {}) as Dictionary).is_empty(), "background data preparation should automatically make mastery targets available"):
		return
	if not _expect(store.save_count == 2 and not (store.stored_data.get("mastery_circuit_metrics", {}) as Dictionary).is_empty() and shell.refreshed_events == ["kitchen_crumb_rush", "kitchen_crumb_rush"], "retrying calibration should persist successfully and refresh failed then ready UI states"):
		return

	app.set("_shell", null)
	shell.free()
	store.remove_save()
	print("MASTERY_CALIBRATION_ASYNC_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("MASTERY_CALIBRATION_ASYNC_TEST FAIL: " + message)
	quit(1)
	return false