extends SceneTree

const HAZARD_SCRIPT := preload("res://scripts/race/environmental_hazard.gd")
const VISUAL_ROLE := preload("res://scripts/race/generated_world_visual_role.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var hazard := HAZARD_SCRIPT.new() as EnvironmentalHazard
	hazard.configure(&"office", Vector2(20.0, 30.0), Vector2(220.0, 30.0), {
		"id": &"office_test_crossing",
		"seed": 663,
		"entry_distance": 80.0,
		"exit_distance": 100.0,
		"footprint_kind": &"rect",
		"footprint_size": Vector2(60.0, 36.0),
	})
	root.add_child(hazard)
	var hazard_sprite := hazard.get_node("MovingHazard/HazardSprite") as Sprite2D
	if not _expect(
		VISUAL_ROLE.read(hazard) == VISUAL_ROLE.MOVING_HAZARD
		and VISUAL_ROLE.read(hazard_sprite) == VISUAL_ROLE.MOVING_HAZARD
		and String(hazard_sprite.get_meta("asset_path", "")) == "res://assets/textures/imagine/hazard_office_cable.png",
		"office cable art should be owned by the telegraphed MOVING_HAZARD"
	):
		return
	if not _expect(hazard.get_state_name() == &"idle" and not hazard.get_node("WarningTelegraph").visible, "hazard should begin idle at its physical origin"):
		return
	var moving_visual := hazard.get_node("MovingHazard") as Node2D
	var collision := hazard.get_node("HazardCollision") as CollisionShape2D
	if not _expect(moving_visual.visible and moving_visual.position == hazard.entry_position and hazard.entry_position != hazard.start_position and collision.disabled, "idle hazard should wait visibly beyond the danger path with collision disabled"):
		return
	var bounds := hazard.get_motion_bounds()
	if not _expect(bounds.has_point(hazard.entry_position) and bounds.has_point(hazard.exit_position), "hazard motion bounds should include physical entry and exit"):
		return
	hazard.advance(hazard.idle_duration)
	var telegraph := hazard.get_node("WarningTelegraph") as Node2D
	var motion_path: PackedVector2Array = telegraph.get_meta("path", PackedVector2Array())
	if not _expect(
		hazard.get_state_name() == &"warning"
		and telegraph.visible
		and collision.disabled
		and telegraph.get_node_or_null("Origin") is Polygon2D
		and telegraph.get_node_or_null("DangerPath") is Line2D
		and telegraph.get_node_or_null("Timing") is Label
		and motion_path == PackedVector2Array([hazard.entry_position, hazard.start_position, hazard.end_position, hazard.exit_position])
		and hazard.get_meta("warning_path") == PackedVector2Array([hazard.entry_position, hazard.start_position])
		and hazard.get_meta("danger_path") == PackedVector2Array([hazard.start_position, hazard.end_position])
		and hazard.get_meta("exit_path") == PackedVector2Array([hazard.end_position, hazard.exit_position]),
		"warning should distinguish its physical approach, danger span, exit, and complete motion path"
	):
		return

	paused = true
	var elapsed_before_pause := float(hazard.get("_state_elapsed"))
	for _frame in 5:
		await process_frame
	if not _expect(is_equal_approx(float(hazard.get("_state_elapsed")), elapsed_before_pause), "an inherited hazard process must stop while the tree is paused"):
		return
	paused = false
	var warning_midpoint_prediction := hazard.get_prediction(hazard.warning_duration * 0.5)
	if not _expect(
		warning_midpoint_prediction["state"] == &"warning"
		and not bool(warning_midpoint_prediction["collision_active"])
		and warning_midpoint_prediction["position"].is_equal_approx(hazard.entry_position.lerp(hazard.start_position, 0.5))
		and is_equal_approx(hazard.get_time_until_danger(), hazard.warning_duration),
		"warning prediction should move from entry toward the danger-path start while collision remains disabled"
	):
		return
	hazard.advance(hazard.warning_duration * 0.5)
	if not _expect(moving_visual.position.is_equal_approx(warning_midpoint_prediction["position"]) and is_equal_approx(hazard.get_travel_progress(), 0.5) and collision.disabled and is_equal_approx(hazard.get_time_until_danger(), hazard.warning_duration * 0.5), "real warning motion and time-to-danger should match prediction"):
		return
	var midpoint_prediction: Dictionary = hazard.get_prediction(hazard.warning_duration * 0.5 + hazard.active_duration * 0.5)
	if not _expect(midpoint_prediction["state"] == &"active" and bool(midpoint_prediction["collision_active"]), "prediction should report the same dangerous state used by collision"):
		return
	hazard.advance(hazard.warning_duration * 0.5 + hazard.active_duration * 0.5)
	if not _expect(
		hazard.get_state_name() == &"active"
		and not telegraph.visible
		and hazard.is_collision_active()
		and not collision.disabled
		and moving_visual.position.is_equal_approx(midpoint_prediction["position"])
		and moving_visual.position.is_equal_approx(hazard.start_position.lerp(hazard.end_position, 0.5))
		and is_equal_approx(hazard.get_travel_progress(), 0.5),
		"AI prediction, real active motion, and collision timing should agree"
	):
		return
	hazard.advance(hazard.active_duration * 0.5)
	if not _expect(hazard.get_state_name() == &"exit" and moving_visual.position == hazard.end_position and hazard.is_collision_active() and not collision.disabled, "active travel should flow continuously into a collision-active physical exit phase"):
		return
	var exit_prediction: Dictionary = hazard.get_prediction(hazard.exit_duration * 0.5)
	hazard.advance(hazard.exit_duration * 0.5)
	if not _expect(moving_visual.position.is_equal_approx(exit_prediction["position"]) and moving_visual.position != hazard.exit_position and is_equal_approx(hazard.get_travel_progress(), 0.5), "exit prediction and progress should match visible motion before the hazard leaves"):
		return
	hazard.advance(hazard.exit_duration * 0.5)
	if not _expect(hazard.get_state_name() == &"cooldown" and moving_visual.position == hazard.exit_position and not moving_visual.visible and not hazard.is_collision_active() and collision.disabled, "hazard should disappear and disable collision only after physically reaching its exit"):
		return
	hazard.advance(hazard.cooldown_duration)
	if not _expect(hazard.get_state_name() == &"idle" and moving_visual.visible and moving_visual.position == hazard.entry_position, "cooldown should restart the complete deterministic lifecycle at the origin"):
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
