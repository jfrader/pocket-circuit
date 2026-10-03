extends SceneTree

const SHELL := preload("res://scripts/ui/app_shell.gd")
const FIXTURE := preload("res://tests/app_shell_focus_test.gd")
const ROSTER := preload("res://scripts/progression/driver_roster.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const RIVAL_EVENTS := [
	{"id": "kitchen_clean_line", "slot": 0},
	{"id": "workshop_heavy_metal", "slot": 1},
	{"id": "office_last_light", "slot": 0},
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := FIXTURE.TestApp.new()
	var shell := SHELL.new()
	root.add_child(app)
	root.add_child(shell)
	shell.configure(app)
	for height in [720, 800]:
		root.content_scale_size = Vector2i(1280, height)
		root.size = Vector2i(1280, height)
		await process_frame
		await process_frame
		for screen in ["title", "garage", "quick_race", "settings", "briefing"]:
			match screen:
				"title": shell.show_title()
				"garage": shell.show_vehicle_select("kitchen_crumb_rush")
				"quick_race": shell.show_quick_race()
				"settings": shell.show_settings()
				"briefing": shell.show_briefing("kitchen_crumb_rush")
			await process_frame
			await process_frame
			if not _expect(root.get_visible_rect().size == Vector2(1280, height), "the test must exercise the requested logical viewport"):
				return
			var stage := shell.get("_stage") as Control
			if stage.is_visible_in_tree() and not _expect(root.get_visible_rect().encloses(stage.get_global_rect()), "%s illustration must remain entirely visible at %dp" % [screen, height]):
				return
			if screen != "settings":
				var primary_text := "REPLAY EVENT" if screen == "briefing" else "PLAY"
				var primary := _button(shell, primary_text)
				if not _expect(primary != null and not primary.disabled, "%s must expose an enabled primary race action without additional selections at %dp" % [screen, height]):
					return
			for node: Node in shell.find_children("*", "Button", true, false):
				var button := node as Button
				if not button.is_visible_in_tree():
					continue
				if not _expect(root.get_visible_rect().encloses(button.get_global_rect()), "%s must remain entirely visible at %dp" % [button.text, height]):
					return
	shell.show_vehicle_select("kitchen_crumb_rush")
	await process_frame
	await process_frame
	await _tap(&"ui_right")
	if not _expect(String(shell.get("_current_vehicle_select_id")) == "scrapjaw", "moving keyboard focus to a car should select the displayed car"):
		return
	await _tap(&"ui_down")
	if not _expect(root.gui_get_focus_owner() == _button(shell, "PLAY"), "Down from a car should reach the primary action, not force a trip through Back"):
		return
	var rustbug := shell.find_child("Vehicle_rustbug", true, false) as Button
	rustbug.mouse_entered.emit()
	if not _expect(String(shell.get("_current_vehicle_select_id")) == "scrapjaw", "mouse hover must not silently replace the selected car"):
		return
	_button(shell, "PLAY").pressed.emit()
	if not _expect(app.launched_vehicle == "scrapjaw", "Play must launch the car that the garage displays as selected"):
		return
	shell.show_quick_race()
	var seed_before: int = shell.get("_quick_race_seed")
	shell.show_vehicle_select("", true)
	await process_frame
	await process_frame
	var flicker := shell.find_child("Vehicle_flicker", true, false) as Button
	flicker.grab_focus()
	_button(shell, "NEXT: TRACK").pressed.emit()
	await process_frame
	await process_frame
	if not _expect(String(shell.get("_screen")) == "quick_race" and int(shell.get("_quick_race_seed")) == seed_before, "Next should return to Quick Race without changing the chosen circuit"):
		return
	_button(shell, "REROLL").pressed.emit()
	await process_frame
	if not _expect(String(shell.get("_stage").get("vehicle_id")) == "flicker", "reroll must keep the preview car aligned with the selected and launched car"):
		return
	_button(shell, "PLAY").pressed.emit()
	if not _expect(app.launched_vehicle == "flicker", "Quick Race should use the car chosen in the garage"):
		return
	app.save_data["unlocked_vehicles"] = ["rustbug"]
	shell.show_vehicle_select("kitchen_crumb_rush")
	await process_frame
	await process_frame
	if not _expect(String(shell.get("_current_vehicle_select_id")) == "rustbug", "a stale locked selection should fall back to the available car"):
		return
	if not _expect((shell.find_child("Vehicle_pinbolt", true, false) as Button).disabled, "locked cars must not be selectable"):
		return
	shell.queue_free()
	app.queue_free()
	await process_frame
	var real_app := root.get_node("App")
	var real_shell := SHELL.new()
	root.add_child(real_shell)
	real_shell.configure(real_app)
	for seed_value in [123, 424242]:
		var progress: Dictionary = real_app.call("get_save_data")
		var roster := ROSTER.create(seed_value, CATALOG.championship_vehicle_ids(), 3)
		progress["driver_roster"] = roster
		real_app.set("_save_data", progress)
		real_app.call("_install_active_roster")
		for rival_event: Dictionary in RIVAL_EVENTS:
			real_shell.show_briefing(String(rival_event["id"]))
			var opponent: Dictionary = roster["opponents"][int(rival_event["slot"])]
			if not _expect(String(real_shell.get("_stage").get("driver_id")) == String(opponent["id"]), "each briefing should show the generated driver assigned to its event"):
				return
			var named_rival := false
			for label: Label in real_shell.find_children("*", "Label", true, false):
				named_rival = named_rival or label.text.contains(String(opponent["name"]))
			if not _expect(named_rival, "the lead-rival text and portrait should agree"):
				return
		real_shell.show_ending()
		if not _expect(String(real_shell.get("_stage").get("secondary_driver_id")) == String(roster["opponents"][0]["id"]), "the ending should show the generated final rival, not the former cast"):
			return
		if not _expect(real_app.call("get_save_data") == progress, "presenting a saved roster must not rewrite progress"):
			return
	real_shell.queue_free()
	await process_frame
	print("CHAMPIONSHIP_PRESENTATION_TEST PASS visible_actions_720p_800p_selected_car_and_back_flow_generated_rivals")
	quit(0)


func _button(shell: Node, text: String) -> Button:
	for node: Node in shell.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and button.text == text:
			return button
	return null


func _tap(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("CHAMPIONSHIP_PRESENTATION_TEST FAIL: " + message)
	quit(1)
	return false
