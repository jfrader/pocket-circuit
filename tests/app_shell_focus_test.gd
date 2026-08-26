extends SceneTree

const APP_SHELL_SCRIPT := preload("res://scripts/ui/app_shell.gd")

class TestApp extends Node:
	func is_save_read_only() -> bool:
		return false

	func has_championship_progress() -> bool:
		return false

	func get_save_data() -> Dictionary:
		return {
			"best_event_finishes": {
				"kitchen_crumb_rush": 1,
				"kitchen_mug_run": 1,
				"kitchen_clean_line": 1,
				"workshop_screw_loose": 1,
				"workshop_ruler_drop": 1,
				"workshop_heavy_metal": 1,
				"office_paper_trail": 1,
				"office_keyboard_cut": 1,
				"office_last_light": 1,
			},
			"best_event_points": {
				"kitchen_crumb_rush": 10,
				"kitchen_mug_run": 10,
				"kitchen_clean_line": 10,
				"workshop_screw_loose": 10,
				"workshop_ruler_drop": 10,
				"workshop_heavy_metal": 10,
				"office_paper_trail": 10,
				"office_keyboard_cut": 10,
				"office_last_light": 10,
			},
			"completed_acts": ["kitchen", "workshop", "office"],
			"unlocked_vehicles": ["rustbug", "pinbolt", "scrapjaw", "flicker"],
			"selected_vehicle": "pinbolt",
		}

	func start_race(_event_id: String, _vehicle_id: String, _quick_race: bool) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := TestApp.new()
	var shell := APP_SHELL_SCRIPT.new() as CanvasLayer
	root.add_child(app)
	root.add_child(shell)
	shell.call("configure", app)
	shell.call("show_vehicle_select", "kitchen_crumb_rush", false)
	await process_frame
	await process_frame
	var focus_owner := root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or focus_owner.name != "Vehicle_pinbolt":
		push_error("APP_SHELL_FOCUS_TEST FAIL: persisted selected vehicle should receive focus")
		quit(1)
		return
	shell.call("show_title")
	await process_frame
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or focus_owner.get("text") != "NEW CHAMPIONSHIP":
		push_error("APP_SHELL_FOCUS_TEST FAIL: returning to another screen should focus a live control")
		quit(1)
		return
	shell.call("_clear_content")
	shell.call("_add_section", "ACT 1", "REWARDS AND ACCESS NEVER CHANGE")
	await process_frame
	var metadata_label: Label
	for node: Node in shell.find_children("*", "Label", true, false):
		var label := node as Label
		if label and label.text == "REWARDS AND ACCESS NEVER CHANGE":
			metadata_label = label
			break
	if metadata_label == null or metadata_label.custom_minimum_size.x < 320.0 or metadata_label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		push_error("APP_SHELL_FOCUS_TEST FAIL: section metadata should retain a readable horizontal column")
		quit(1)
		return
	shell.call("show_map")
	await process_frame
	await process_frame
	for _step in 8:
		await _tap_action(&"ui_down")
	focus_owner = root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or not String(focus_owner.get("text")).begins_with("Last Light Grand Final"):
		push_error("APP_SHELL_FOCUS_TEST FAIL: keyboard focus should reach every completed championship event")
		quit(1)
		return
	var scroll := shell.get("_scroll") as ScrollContainer
	if scroll == null or scroll.scroll_vertical <= 0:
		push_error("APP_SHELL_FOCUS_TEST FAIL: keyboard focus should scroll off-screen events into view")
		quit(1)
		return
	shell.call("show_map")
	await process_frame
	await process_frame
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or not String(focus_owner.get("text")).begins_with("Crumb Rush") or scroll.scroll_vertical > 0:
		push_error("APP_SHELL_FOCUS_TEST FAIL: rebuilding the map should reveal its newly focused first event (focus=%s, scroll=%d)" % [focus_owner.get("text") if focus_owner else "none", scroll.scroll_vertical])
		quit(1)
		return
	root.remove_child(shell)
	root.remove_child(app)
	shell.free()
	app.free()
	print("APP_SHELL_FOCUS_TEST PASS")
	quit(0)


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
