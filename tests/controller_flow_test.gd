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

	root.remove_child(boot)
	boot.free()
	current_scene = null
	var race := RACE_SCENE.instantiate()
	root.add_child(race)
	current_scene = race
	await _wait_frames(3)
	await _tap_joypad_button(6)
	var pause_overlay := race.get("_pause_overlay") as Control
	if not _expect(paused and pause_overlay.visible, "gamepad Start should pause during the countdown"):
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
