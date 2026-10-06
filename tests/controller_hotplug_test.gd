extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must be present for hotplug test"):
		return

	# has_joypad must reflect the live Input state at boot (typically false in headless)
	var live := not Input.get_connected_joypads().is_empty()
	if not _expect(app.call("has_joypad") == live, "has_joypad() must reflect Input.get_connected_joypads()"):
		return

	# Track our signal
	var received: Array[bool] = []
	var sig_conn := func(connected: bool) -> void:
		received.append(connected)
	app.joypad_connection_changed.connect(sig_conn)

	# Pick a joypad-bound action (ui_accept has JoypadButton; driving like handbrake/accelerate also have)
	var test_action := &"ui_accept"

	# Try emit first for signal path (exercises connect in handler + our signal with live)
	Input.joy_connection_changed.emit(0, true)
	await process_frame
	var live_after_emit := not Input.get_connected_joypads().is_empty()
	if not _expect(received.size() > 0 and received[received.size() - 1] == live_after_emit, "signal must fire the live state on connect sim"):
		return

	# Simulate held via joypad event + action press (to survive poll in this env)
	var press := InputEventJoypadButton.new()
	press.device = 0
	press.button_index = 0
	press.pressed = true
	Input.parse_input_event(press)
	Input.action_press(test_action)
	await process_frame
	if not _expect(Input.is_action_pressed(test_action), "joypad InputEvent + press must make action held"):
		return

	# For release-on-disconnect, call handler directly (emit would emit live=true; direct exercises release path per "call handler if emit path limited")
	app.call("_on_joy_connection_changed", 0, false)
	await process_frame
	if not _expect(not Input.is_action_pressed(test_action), "held joypad-defined action must be released on disconnect handler (stuck-action core)"):
		return
	# signal during this will have emitted the live (true), which is consistent

	# re-sim connect via emit to exercise the signal again
	Input.joy_connection_changed.emit(0, true)
	await process_frame
	var live_after_reconnect := not Input.get_connected_joypads().is_empty()
	if not _expect(received[received.size() - 1] == live_after_reconnect, "signal must fire the live state on reconnect"):
		return

	# Clean up our signal listener (real disconnect happens in App._exit_tree on tree exit)
	app.joypad_connection_changed.disconnect(sig_conn)

	# Re-assert clean reflect after
	if not _expect(app.call("has_joypad") == not Input.get_connected_joypads().is_empty(), "final state must still reflect live"):
		return

	print("CONTROLLER_HOTPLUG_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	paused = false
	push_error("CONTROLLER_HOTPLUG_TEST FAIL: " + message)
	quit(1)
	return false
