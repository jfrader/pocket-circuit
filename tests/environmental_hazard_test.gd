extends SceneTree

const HAZARD_SCRIPT := preload("res://scripts/race/environmental_hazard.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var hazard := HAZARD_SCRIPT.new() as EnvironmentalHazard
	hazard.configure(&"office", Vector2(20.0, 30.0), Vector2(220.0, 30.0))
	root.add_child(hazard)
	if not _expect(hazard.get_state_name() == &"warning" and hazard.get_node("WarningTelegraph").visible, "hazard should begin with a visible warning phase"):
		return
	var bounds := hazard.get_motion_bounds()
	if not _expect(bounds.has_point(hazard.start_position) and bounds.has_point(hazard.end_position), "hazard motion bounds should include its complete deterministic path"):
		return

	paused = true
	var elapsed_before_pause := float(hazard.get("_state_elapsed"))
	for _frame in 5:
		await process_frame
	if not _expect(is_equal_approx(float(hazard.get("_state_elapsed")), elapsed_before_pause), "an inherited hazard process must stop while the tree is paused"):
		return
	paused = false
	hazard.advance(hazard.warning_duration)
	if not _expect(hazard.get_state_name() == &"active" and not hazard.get_node("WarningTelegraph").visible, "warning completion should enter the racing line only after the telegraph"):
		return
	hazard.advance(hazard.active_duration * 0.5)
	var moving_visual := hazard.get_node("MovingHazard") as Node2D
	if not _expect(bounds.has_point(moving_visual.position) and is_equal_approx(hazard.get_travel_progress(), 0.5), "active hazard travel should remain bounded and deterministic"):
		return
	hazard.advance(hazard.active_duration * 0.5)
	if not _expect(hazard.get_state_name() == &"cooldown" and not moving_visual.visible, "hazard should leave the racing line for cooldown"):
		return

	print("ENVIRONMENTAL_HAZARD_TEST PASS")
	hazard.queue_free()
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	paused = false
	push_error("ENVIRONMENTAL_HAZARD_TEST FAIL: " + message)
	quit(1)
	return false
