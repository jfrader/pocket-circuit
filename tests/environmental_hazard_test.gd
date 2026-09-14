extends SceneTree

const HAZARD_SCRIPT := preload("res://scripts/race/environmental_hazard.gd")
const VISUAL_ROLE := preload("res://scripts/race/generated_world_visual_role.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not await _test_rolling_kitchen():
		return
	if not _test_static_office():
		return
	print("ENVIRONMENTAL_HAZARD_TEST PASS")
	quit(0)


func _test_rolling_kitchen() -> bool:
	var hazard := HAZARD_SCRIPT.new() as EnvironmentalHazard
	hazard.configure(&"kitchen", Vector2(20.0, 30.0), Vector2(220.0, 30.0), {
		"id": &"kitchen_test_crossing",
		"seed": 663,
		"motion": &"rolling",
		"entry_distance": 80.0,
		"exit_distance": 100.0,
		"footprint_kind": &"circle",
		"footprint_size": Vector2(60.0, 60.0),
	})
	root.add_child(hazard)
	var hazard_sprite := hazard.get_node("MovingHazard/HazardSprite") as Sprite2D
	if not _expect(
		VISUAL_ROLE.read(hazard) == VISUAL_ROLE.MOVING_HAZARD
		and VISUAL_ROLE.read(hazard_sprite) == VISUAL_ROLE.MOVING_HAZARD
		and String(hazard_sprite.get_meta("asset_path", "")) == "res://assets/textures/imagine/hazard_kitchen_apple.png"
		and hazard.get_node_or_null("WarningTelegraph") == null,
		"kitchen apple should roll as a MOVING_HAZARD without a telegraph overlay"
	):
		return false
	if not _expect(hazard.get_state_name() == &"idle" and not hazard.is_static(), "rolling hazard should begin idle at its physical origin"):
		return false
	var moving_visual := hazard.get_node("MovingHazard") as Node2D
	var collision := hazard.get_node("HazardCollision") as CollisionShape2D
	if not _expect(moving_visual.visible and moving_visual.position == hazard.entry_position and hazard.entry_position != hazard.start_position and collision.disabled, "idle hazard should wait visibly beyond the danger path with collision disabled"):
		return false
	hazard.advance(hazard.idle_duration)
	if not _expect(
		hazard.get_state_name() == &"warning"
		and collision.disabled
		and is_equal_approx(hazard_sprite.rotation, 0.0)
		and hazard.get_meta("danger_path") == PackedVector2Array([hazard.start_position, hazard.end_position]),
		"warning is the object approaching — no overlay, collision still off"
	):
		return false

	paused = true
	var elapsed_before_pause := float(hazard.get("_state_elapsed"))
	for _frame in 5:
		await process_frame
	if not _expect(is_equal_approx(float(hazard.get("_state_elapsed")), elapsed_before_pause), "an inherited hazard process must stop while the tree is paused"):
		return false
	paused = false
	var warning_midpoint_prediction := hazard.get_prediction(hazard.warning_duration * 0.5)
	if not _expect(
		warning_midpoint_prediction["state"] == &"warning"
		and not bool(warning_midpoint_prediction["collision_active"])
		and warning_midpoint_prediction["position"].is_equal_approx(hazard.entry_position.lerp(hazard.start_position, 0.5))
		and is_equal_approx(hazard.get_time_until_danger(), hazard.warning_duration),
		"warning prediction should move from entry toward the danger-path start while collision remains disabled"
	):
		return false
	hazard.advance(hazard.warning_duration * 0.5)
	if not _expect(moving_visual.position.is_equal_approx(warning_midpoint_prediction["position"]) and is_equal_approx(hazard.get_travel_progress(), 0.5) and collision.disabled, "real warning motion should match prediction"):
		return false
	var midpoint_prediction: Dictionary = hazard.get_prediction(hazard.warning_duration * 0.5 + hazard.active_duration * 0.5)
	if not _expect(midpoint_prediction["state"] == &"active" and bool(midpoint_prediction["collision_active"]), "prediction should report the same dangerous state used by collision"):
		return false
	hazard.advance(hazard.warning_duration * 0.5 + hazard.active_duration * 0.5)
	var expected_roll := (hazard.entry_position.distance_to(hazard.start_position) + hazard.start_position.distance_to(hazard.end_position) * 0.5) / 30.0
	if not _expect(
		hazard.get_state_name() == &"active"
		and hazard.is_collision_active()
		and not collision.disabled
		and moving_visual.position.is_equal_approx(midpoint_prediction["position"])
		and is_equal_approx(hazard.get_travel_progress(), 0.5)
		and absf(hazard_sprite.rotation - expected_roll) < 0.05,
		"the apple should be on the danger path, colliding, and rolled by traveled distance"
	):
		return false
	hazard.advance(hazard.active_duration * 0.5)
	if not _expect(hazard.get_state_name() == &"exit" and moving_visual.position == hazard.end_position and hazard.is_collision_active() and not collision.disabled, "active travel should flow continuously into a collision-active physical exit phase"):
		return false
	var exit_prediction: Dictionary = hazard.get_prediction(hazard.exit_duration * 0.5)
	hazard.advance(hazard.exit_duration * 0.5)
	if not _expect(moving_visual.position.is_equal_approx(exit_prediction["position"]) and moving_visual.position != hazard.exit_position and is_equal_approx(hazard.get_travel_progress(), 0.5), "exit prediction and progress should match visible motion before the hazard leaves"):
		return false
	hazard.advance(hazard.exit_duration * 0.5)
	if not _expect(hazard.get_state_name() == &"cooldown" and moving_visual.position == hazard.exit_position and not moving_visual.visible and not hazard.is_collision_active() and collision.disabled, "hazard should disappear and disable collision only after physically reaching its exit"):
		return false
	hazard.advance(hazard.cooldown_duration)
	if not _expect(hazard.get_state_name() == &"idle" and moving_visual.visible and moving_visual.position == hazard.entry_position, "cooldown should restart the complete deterministic lifecycle at the origin"):
		return false
	hazard.queue_free()
	return true


func _test_static_office() -> bool:
	var rest := Vector2(80.0, 40.0)
	var hazard := HAZARD_SCRIPT.new() as EnvironmentalHazard
	hazard.configure(&"office", rest, Vector2(280.0, 40.0), {
		"id": &"office_test_coil",
		"seed": 664,
		"motion": &"static",
		"footprint_kind": &"rect",
		"footprint_size": Vector2(60.0, 36.0),
	})
	root.add_child(hazard)
	var hazard_sprite := hazard.get_node("MovingHazard/HazardSprite") as Sprite2D
	var collision := hazard.get_node("HazardCollision") as CollisionShape2D
	if not _expect(
		hazard.is_static()
		and hazard.get_state_name() == &"active"
		and hazard.is_collision_active()
		and not collision.disabled
		and hazard.start_position == rest
		and hazard.end_position == rest
		and hazard.get_node("MovingHazard").position == rest
		and is_equal_approx(hazard_sprite.rotation, 0.0)
		and hazard.get_node_or_null("WarningTelegraph") == null
		and String(hazard_sprite.get_meta("asset_path", "")) == "res://assets/textures/imagine/hazard_office_cable.png",
		"office coiled cable should sit still, collide, and never grow a telegraph"
	):
		return false
	var before: Vector2 = (hazard.get_node("MovingHazard") as Node2D).position
	var prediction: Dictionary = hazard.get_prediction(4.0)
	hazard.advance(4.0)
	if not _expect(
		hazard.get_node("MovingHazard").position == before
		and bool(prediction["collision_active"])
		and prediction["position"] == rest
		and is_equal_approx(hazard.get_time_until_danger(), 0.0),
		"static cable prediction and motion must stay on the rest pose"
	):
		return false
	hazard.queue_free()
	return true


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	paused = false
	push_error("ENVIRONMENTAL_HAZARD_TEST FAIL: " + message)
	quit(1)
	return false
