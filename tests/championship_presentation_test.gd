extends SceneTree

const SHELL := preload("res://scripts/ui/app_shell.gd")
const FIXTURE := preload("res://tests/app_shell_focus_test.gd")


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
		for screen in ["title", "garage", "quick_race", "briefing"]:
			match screen:
				"title": shell.show_title()
				"garage": shell.show_vehicle_select("kitchen_crumb_rush")
				"quick_race": shell.show_quick_race()
				"briefing": shell.show_briefing("kitchen_crumb_rush")
			await process_frame
			await process_frame
			if not _expect(root.get_visible_rect().size == Vector2(1280, height), "the test must exercise the requested logical viewport"):
				return
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
	print("CHAMPIONSHIP_PRESENTATION_TEST PASS visible_actions_720p_800p_selected_car_and_back_flow")
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
