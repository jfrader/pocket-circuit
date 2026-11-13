extends SceneTree

const TRANSITION := preload("res://scripts/ui/night_transition.gd")
const RACE := preload("res://scripts/race/prototype_race.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node("App")
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var shell: CanvasLayer = app.get("_shell")
	app.set("_test_mode", false)
	shell.call("show_settings")
	if not _expect(shell.get("_screen") == "settings", "logical screen changes synchronously"):
		return
	await process_frame
	var overlay: CanvasLayer = shell.get("_night_transition")
	if not _expect(overlay != null and overlay.visible, "real mode presents the transition"):
		return
	var focused := root.gui_get_focus_owner()
	if not _expect(focused != null and shell.is_ancestor_of(focused), "destination retains focus"):
		return
	if not _expect(_ignores_input(overlay), "the entire overlay is input-transparent"):
		return
	await create_timer(TRANSITION.SWEEP_SECONDS + 0.1).timeout
	if not _expect(not overlay.visible and root.gui_get_focus_owner() == focused, "transition ends without taking focus"):
		return
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	Input.parse_input_event(back)
	await process_frame
	back.pressed = false
	Input.parse_input_event(back)
	await process_frame
	if not _expect(shell.get("_screen") == "title", "controller input still navigates after the visual beat"):
		return
	shell.call("show_credits")
	await process_frame
	if not _expect(overlay.visible, "subsequent screen changes replay the visual beat"):
		return
	app.set("_test_mode", true)
	shell.call("show_settings")
	await process_frame
	if not _expect(not overlay.visible, "test mode cancels an active transition instantly"):
		return
	app.set("_test_mode", false)
	app.set("reduced_motion", true)
	overlay.call("play", "THE BENCH", false, true)
	var band: Control = overlay.get("_band")
	var resting_position := band.position
	await process_frame
	if not _expect(band.position == resting_position, "reduced motion has no sweep"):
		return
	await create_timer(TRANSITION.FADE_SECONDS + 0.05).timeout
	if not _expect(not overlay.visible, "reduced-motion crossfade ends on its own"):
		return
	var panel := PanelContainer.new()
	panel.size = Vector2(620, 300)
	panel.hide()
	root.add_child(panel)
	# Exercise the actual results entry point without starting a race simulation.
	var race := Node2D.new()
	root.add_child(race)
	race.set_script(RACE)
	race.set("_results_panel", panel)
	app.set("_test_mode", true)
	race.call("_present_results_panel")
	if not _expect(panel.visible and panel.scale == Vector2.ONE and panel.modulate.a == 1.0, "test results enter instantly"):
		return
	race.free()
	panel.hide()
	var entrance := TRANSITION.results_entrance(panel, false, false)
	if not _expect(entrance != null and panel.visible and panel.scale == TRANSITION.RESULTS_STAMP_SCALE, "results have a stamp entrance"):
		return
	if not _expect(panel.modulate.a >= 0.94, "results backing is readable from the first stamp frame"):
		return
	await create_timer(TRANSITION.RESULTS_SECONDS + 0.1).timeout
	if not _expect(panel.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(panel.modulate.a, 1.0), "results settle at their original bounds"):
		return
	panel.hide()
	TRANSITION.results_entrance(panel, false, true)
	if not _expect(panel.scale == Vector2.ONE, "reduced-motion results do not stamp"):
		return
	await create_timer(TRANSITION.FADE_SECONDS + 0.05).timeout
	panel.free()
	app.set("reduced_motion", false)
	app.set("_test_mode", true)
	print("TRANSITION_TEST PASS")
	quit(0)


func _ignores_input(node: Node) -> bool:
	if node is Control and (node.mouse_filter != Control.MOUSE_FILTER_IGNORE or node.focus_mode != Control.FOCUS_NONE):
		return false
	for child in node.get_children():
		if not _ignores_input(child):
			return false
	return true


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	root.get_node("App").set("_test_mode", true)
	push_error("TRANSITION_TEST FAIL: " + message)
	quit(1)
	return false
