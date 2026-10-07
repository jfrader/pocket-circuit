extends SceneTree

const APP_SHELL_SCRIPT := preload("res://scripts/ui/app_shell.gd")


class TestApp extends Node:
	var sfx_calls: Array = []
	var mastery_calibrating := false
	var save_data := {
		"best_event_finishes": {},
		"best_event_points": {},
		"completed_events": [],
		"completed_acts": [],
		"unlocked_vehicles": ["rustbug"],
		"selected_vehicle": "rustbug",
		"difficulty": "club_circuit",
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 0.8,
		"engine_volume": 0.8,
		"tyre_volume": 0.8,
		"fullscreen": false,
		"reduced_camera_shake": false,
		"reduced_motion": false,
	}

	func is_save_read_only() -> bool:
		return false

	func get_save_recovery_message() -> String:
		return ""

	func has_championship_progress() -> bool:
		return true

	func current_run_session() -> RunSession:
		return null

	func quick_race_roster() -> Array[String]:
		return preload("res://data/championship/catalog.gd").quick_race_vehicle_ids()

	func get_save_data() -> Dictionary:
		return save_data

	func get_championship_event(event_id: String) -> Dictionary:
		return get_tree().root.get_node("App").call("get_championship_event", event_id)

	func get_mastery_state(_event_id: String, _vehicle_id: String = "") -> Dictionary:
		if mastery_calibrating:
			return {"available": false, "calibrating": true, "record": {}, "targets": {}}
		return {
			"available": true,
			"calibrating": false,
			"record": {"best_lap": 39.0, "best_race": 82.0, "medal": "gold"},
			"targets": {"gold": 92.0, "silver": 104.0, "bronze": 118.0},
		}

	func play_sfx(sound_name: StringName, volume_scale: float = 1.0) -> void:
		sfx_calls.append([sound_name, volume_scale])


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := TestApp.new()
	var shell := APP_SHELL_SCRIPT.new() as CanvasLayer
	root.add_child(app)
	root.add_child(shell)
	shell.call("configure", app)

	# A fresh save unlocks only the first event; locked stops must stay
	# unreachable and skipped by the road's focus chain.
	shell.call("show_map")
	await process_frame
	await process_frame
	var crumb := shell.find_child("Stop_kitchen_crumb_rush", true, false) as Button
	var mug := shell.find_child("Stop_kitchen_mug_run", true, false) as Button
	if crumb == null or mug == null or not mug.disabled:
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: a fresh save should render locked stops disabled")
		quit(1)
		return
	var focus_owner := root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or focus_owner.name != "Stop_kitchen_crumb_rush":
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: a fresh save should focus its single unlocked stop")
		quit(1)
		return
	await _tap_action(&"ui_down")
	focus_owner = root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or focus_owner.name != "ReturnToTitle":
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: locked stops must be skipped when moving down the road")
		quit(1)
		return

	# Result summaries must surface unlocks and mastery outcomes on the route
	# board notice, not just points.
	shell.call("show_map", {"points_gained": 10, "act_completed": true, "unlocked_vehicles": ["pinbolt"]}, 1)
	await process_frame
	await process_frame
	if not _notice_contains(shell, "PINBOLT UNLOCKED") or not _notice_contains(shell, "ACT WON"):
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: a championship result should announce its unlock and act win")
		quit(1)
		return
	shell.call("show_map", {"mastery": true, "mastery_dnf": true}, 1)
	await process_frame
	await process_frame
	if not _notice_contains(shell, "DID NOT FINISH"):
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: a mastery DNF should be announced on the map")
		quit(1)
		return
	shell.call("show_map", {"mastery": true, "mastery_record": {"medal": "gold", "best_lap": 39.0, "best_race": 82.0}, "ghost_saved": true}, 1)
	await process_frame
	await process_frame
	if not _notice_contains(shell, "TIME TRIAL GOLD") or not _notice_contains(shell, "GHOST SAVED"):
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: a saved mastery record should be announced on the map")
		quit(1)
		return

	# Async calibration finishing while on the map must refresh the stop label.
	app.save_data["best_event_finishes"]["kitchen_crumb_rush"] = 1
	app.save_data["best_event_points"]["kitchen_crumb_rush"] = 10
	app.save_data["completed_events"] = ["kitchen_crumb_rush"]
	app.mastery_calibrating = true
	shell.call("show_map", {}, 1)
	await process_frame
	await process_frame
	crumb = shell.find_child("Stop_kitchen_crumb_rush", true, false) as Button
	if crumb == null or not String(crumb.text).contains("CALIBRATING"):
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: a calibrating completed stop should expose its calibration state")
		quit(1)
		return
	app.mastery_calibrating = false
	shell.call("refresh_mastery_calibration", "kitchen_crumb_rush")
	await process_frame
	if String(crumb.text).contains("CALIBRATING") or not String(crumb.text).contains("MASTERY GOLD"):
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: completed calibration should refresh the map stop status")
		quit(1)
		return

	# Route board buttons must route through the shared UI audio.
	app.save_data = {
		"best_event_finishes": {},
		"best_event_points": {},
		"completed_events": [],
		"completed_acts": [],
		"unlocked_vehicles": ["rustbug"],
		"selected_vehicle": "rustbug",
		"difficulty": "club_circuit",
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 0.8,
		"engine_volume": 0.8,
		"tyre_volume": 0.8,
		"fullscreen": false,
		"reduced_camera_shake": false,
		"reduced_motion": false,
	}
	app.sfx_calls.clear()
	shell.call("show_map")
	await process_frame
	await process_frame
	crumb = shell.find_child("Stop_kitchen_crumb_rush", true, false) as Button
	if crumb == null:
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: fresh map should expose the first stop for audio coverage")
		quit(1)
		return
	if not _sfx_called(app, "ui_move", 0.62):
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: focusing a route stop should play the shared move cue")
		quit(1)
		return
	crumb.pressed.emit()
	if not _sfx_called(app, "ui_confirm", 0.78):
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: choosing a route stop should play the shared confirm cue")
		quit(1)
		return
	if shell.get("_screen") != "briefing" or shell.get("_event_id") != "kitchen_crumb_rush":
		push_error("ROUTE_BOARD_REGRESSION_TEST FAIL: choosing a route stop should open its event briefing")
		quit(1)
		return

	root.remove_child(shell)
	root.remove_child(app)
	shell.free()
	app.free()
	print("ROUTE_BOARD_REGRESSION_TEST PASS")
	quit(0)


func _notice_contains(shell: CanvasLayer, fragment: String) -> bool:
	var route := shell.get("_route") as Control
	return route != null and String(route.get("_notice")).contains(fragment)


func _sfx_called(app: TestApp, sound: String, volume: float) -> bool:
	for call in app.sfx_calls:
		if String(call[0]) == sound and is_equal_approx(float(call[1]), volume):
			return true
	return false


func _tap_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
