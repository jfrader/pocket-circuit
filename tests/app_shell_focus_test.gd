extends SceneTree

const APP_SHELL_SCRIPT := preload("res://scripts/ui/app_shell.gd")

class TestApp extends Node:
	var save_read_only := false
	var save_data := {
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
		"completed_events": [
			"kitchen_crumb_rush", "kitchen_mug_run", "kitchen_clean_line",
			"workshop_screw_loose", "workshop_ruler_drop", "workshop_heavy_metal",
			"office_paper_trail", "office_keyboard_cut", "office_last_light",
		],
		"completed_acts": ["kitchen", "workshop", "office"],
		"unlocked_vehicles": ["rustbug", "pinbolt", "scrapjaw", "flicker"],
		"selected_vehicle": "pinbolt",
		"difficulty": "club_circuit",
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 0.8,
		"fullscreen": false,
		"reduced_camera_shake": false,
		"reduced_motion": false,
	}

	func is_save_read_only() -> bool:
		return save_read_only

	func has_championship_progress() -> bool:
		return true

	func get_save_data() -> Dictionary:
		return save_data

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
	if focus_owner == null or focus_owner.get("text") != "PLAY":
		push_error("APP_SHELL_FOCUS_TEST FAIL: returning to another screen should focus a live control")
		quit(1)
		return
	await _tap_action(&"ui_down")
	focus_owner = root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or focus_owner.get("text") != "NEW RUN":
		push_error("APP_SHELL_FOCUS_TEST FAIL: Down from the primary action should enter the first action row")
		quit(1)
		return
	await _tap_action(&"ui_down")
	focus_owner = root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or focus_owner.get("text") != "OPTIONS":
		push_error("APP_SHELL_FOCUS_TEST FAIL: Down should move between rows instead of snaking across siblings")
		quit(1)
		return
	shell.call("show_quick_race")
	await process_frame
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or focus_owner.name != "QuickRace_kitchen_crumb_rush":
		push_error("APP_SHELL_FOCUS_TEST FAIL: Quick Race should open a focused event picker")
		quit(1)
		return
	shell.call("go_back")
	await process_frame
	if String(shell.get("_screen")) != "title":
		push_error("APP_SHELL_FOCUS_TEST FAIL: Quick Race cancel should return to the title screen")
		quit(1)
		return
	var contextual_back := func() -> void:
		shell.call("show_map")
	shell.call("show_save_error", "Test save error", "Injected failure", func() -> void: pass, contextual_back)
	shell.call("go_back")
	await process_frame
	if String(shell.get("_screen")) != "map":
		push_error("APP_SHELL_FOCUS_TEST FAIL: save-error cancel should invoke its contextual back action")
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
	shell.call("show_map", {}, 3)
	await process_frame
	await process_frame
	for _step in 2:
		await _tap_action(&"ui_down")
	focus_owner = root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or not String(focus_owner.get("text")).begins_with("Last Light Grand Final"):
		push_error("APP_SHELL_FOCUS_TEST FAIL: act paging should focus the final act's first available event")
		quit(1)
		return
	shell.call("show_map", {}, 2)
	await process_frame
	await process_frame
	var previous_button: Button
	var next_button: Button
	var return_button: Button
	for node: Node in shell.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == "← PREVIOUS ACT":
			previous_button = button
		elif button.text == "NEXT ACT →":
			next_button = button
		elif button.text == "RETURN TO TITLE":
			return_button = button
	if (
		previous_button == null
		or next_button == null
		or return_button == null
		or previous_button.focus_neighbor_right != previous_button.get_path_to(next_button)
		or previous_button.focus_neighbor_bottom != previous_button.get_path_to(return_button)
		or next_button.focus_neighbor_bottom != next_button.get_path_to(return_button)
	):
		push_error("APP_SHELL_FOCUS_TEST FAIL: act pager should use horizontal focus and share the following vertical action")
		quit(1)
		return
	var scroll := shell.get("_scroll") as ScrollContainer
	if scroll == null or scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED or scroll.scroll_vertical != 0:
		push_error("APP_SHELL_FOCUS_TEST FAIL: release screens must not scroll")
		quit(1)
		return
	shell.call("show_briefing", "kitchen_crumb_rush")
	await process_frame
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or focus_owner.get("text") != "CHOOSE VEHICLE" or scroll.scroll_vertical != 0:
		push_error("APP_SHELL_FOCUS_TEST FAIL: briefing should focus its action without moving the page")
		quit(1)
		return
	for node: Node in shell.find_children("*", "Label", true, false):
		var label := node as Label
		if label and (label.text.contains("Inez rolls") or label.text.begins_with("Juniper:")):
			push_error("APP_SHELL_FOCUS_TEST FAIL: briefing should not render narrative filler")
			quit(1)
			return
	var fixed_screens: Array[Callable] = [
		func() -> void: shell.call("show_title"),
		func() -> void:
			app.save_read_only = true
			shell.call("show_title"),
		func() -> void:
			app.save_read_only = false
			shell.call("show_reset_confirmation"),
		func() -> void: shell.call("show_map", {}, 1),
		func() -> void:
			app.save_data["best_event_finishes"]["kitchen_crumb_rush"] = 0
			shell.call("show_map", {"points_gained": 10, "act_completed": true, "unlocked_vehicles": ["pinbolt"]}, 1),
		func() -> void: shell.call("show_map", {}, 2),
		func() -> void: shell.call("show_map", {}, 3),
		func() -> void: shell.call("show_quick_race", 1),
		func() -> void: shell.call("show_quick_race", 2),
		func() -> void: shell.call("show_quick_race", 3),
		func() -> void:
			app.save_data["completed_events"] = []
			shell.call("show_quick_race", 1),
		func() -> void: shell.call("show_briefing", "kitchen_crumb_rush"),
		func() -> void:
			app.save_data["best_event_finishes"]["kitchen_crumb_rush"] = 0
			shell.call("show_briefing", "kitchen_crumb_rush"),
		func() -> void: shell.call("show_vehicle_select", "kitchen_crumb_rush", false),
		func() -> void: shell.call("show_settings"),
		func() -> void: shell.call("show_credits"),
		func() -> void: shell.call("show_save_error", "Championship not saved", "The save file could not be written. Check available disk space and folder permissions.", func() -> void: pass, func() -> void: pass),
		func() -> void: shell.call("show_ending"),
	]
	for show_screen: Callable in fixed_screens:
		show_screen.call()
		await process_frame
		await process_frame
		var content := shell.get("_content") as VBoxContainer
		var footer := shell.get("_footer") as Label
		var viewport_bottom := root.get_viewport().get_visible_rect().end.y
		var content_bottom := content.get_global_rect().end.y if content else INF
		var scroll_bottom := scroll.get_global_rect().end.y
		var footer_bottom := footer.get_global_rect().end.y if footer else INF
		if (
			content == null
			or content.size.y > scroll.size.y + 1.0
			or content_bottom > scroll_bottom + 1.0
			or footer_bottom > viewport_bottom + 1.0
			or scroll.scroll_vertical != 0
		):
			push_error("APP_SHELL_FOCUS_TEST FAIL: %s must fit inside the fixed viewport (content=%.1f scroll=%.1f footer_bottom=%.1f viewport_bottom=%.1f)" % [String(shell.get("_screen")), content.size.y if content else -1.0, scroll.size.y, footer_bottom, viewport_bottom])
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
