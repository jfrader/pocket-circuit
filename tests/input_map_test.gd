extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _expect(_has_joypad_button(&"ui_accept", 0), "ui_accept must include the primary gamepad face button"):
		return
	if not _expect(_has_joypad_button(&"ui_cancel", 1), "ui_cancel must include the secondary gamepad face button"):
		return
	if not _expect(_has_joypad_button(&"pause", 6), "pause must include the gamepad Start button"):
		return
	if not _expect(not _has_joypad_button(&"pause", 1), "the in-race boost button must not also pause an active race"):
		return
	print("INPUT_MAP_TEST PASS")
	quit(0)


func _has_joypad_button(action: StringName, button_index: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button_index:
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("INPUT_MAP_TEST FAIL: " + message)
	quit(1)
	return false
