extends SceneTree

const BOOT_SCENE := preload("res://scenes/boot/boot.tscn")
const RACE_SCENE := preload("res://scenes/race/prototype_race.tscn")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return
	var boot := BOOT_SCENE.instantiate()
	root.add_child(boot)
	current_scene = boot
	await _wait_frames(3)
	var shell := app.get("_shell") as CanvasLayer
	if not _expect(shell != null and String(shell.get("_screen")) == "title", "boot should focus the controller-safe title screen"):
		return
	await _tap_joypad_button(0)
	if not _expect(String(shell.get("_screen")) == "map", "gamepad A should activate the focused New Championship button"):
		return
	await _tap_joypad_button(1)
	if not _expect(String(shell.get("_screen")) == "title", "gamepad B should navigate back from the championship map"):
		return
	await _tap_joypad_button(12)
	await _tap_joypad_button(12)
	await _tap_joypad_button(0)
	if not _expect(String(shell.get("_screen")) == "quick_race", "gamepad A should open Quick Race from the title screen"):
		return
	await _tap_joypad_button(0)
	if not _expect(String(shell.get("_screen")) == "vehicle_select" and bool(shell.get("_quick_race")), "gamepad A should accept the focused Quick Race circuit"):
		return
	await _tap_joypad_button(0)
	await _wait_frames(3)
	var race := current_scene
	var session: Dictionary = app.call("get_current_race_session")
	if not _expect(
			race != null
			and race.scene_file_path == RACE_SCENE.resource_path
			and String(session.get("mode", "")) == "quick"
			and String(session.get("event_id", "")) == "kitchen_crumb_rush",
			"accepting the focused Quick Race vehicle should load the race and keep the tree alive"
	):
		return
	await _tap_joypad_button(6)
	var pause_overlay := race.get("_pause_overlay") as Control
	if not _expect(paused and pause_overlay.visible, "gamepad Start should pause during the countdown"):
		return
	await _tap_joypad_button(12)
	await _tap_joypad_button(0)
	var settings_panel := race.get("_pause_settings_panel") as Control
	var menu_panel := race.get("_pause_menu_panel") as Control
	if not _expect(paused and settings_panel.visible and not menu_panel.visible, "pause Settings should open without resuming the race"):
		return
	await _tap_joypad_button(1)
	if not _expect(paused and not settings_panel.visible and menu_panel.visible, "gamepad B should return from race Settings to the pause menu"):
		return
	await _tap_joypad_button(1)
	if not _expect(not paused and not pause_overlay.visible, "gamepad B should resume from the pause menu"):
		return

	root.remove_child(race)
	race.free()
	current_scene = null
	print("CONTROLLER_FLOW_TEST PASS")
	quit(0)


func _tap_joypad_button(button_index: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _wait_frames(count: int) -> void:
	for frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	paused = false
	push_error("CONTROLLER_FLOW_TEST FAIL: " + message)
	quit(1)
	return false
