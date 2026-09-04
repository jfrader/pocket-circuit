extends SceneTree

const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")


class TestCheckpoint extends Area2D:
	var checkpoint_index: int
	var is_finish_line: bool

	func _init(index: int, finish_line: bool, checkpoint_position: Vector2, checkpoint_rotation: float = 0.0) -> void:
		checkpoint_index = index
		is_finish_line = finish_line
		position = checkpoint_position
		rotation = checkpoint_rotation

	func get_recovery_transform() -> Transform2D:
		return Transform2D(rotation, position)


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var manager := RaceManager.new()
	var vehicle := VehicleController.new()
	var controller := AI_CONTROLLER_SCRIPT.new() as AIVehicleController
	var checkpoints: Array = [
		TestCheckpoint.new(0, true, Vector2(-700.0, 360.0), PI * 0.5),
		TestCheckpoint.new(1, false, Vector2(-220.0, 360.0)),
		TestCheckpoint.new(2, false, Vector2(440.0, 360.0)),
		TestCheckpoint.new(3, false, Vector2(735.0, 100.0), PI * 0.5),
		TestCheckpoint.new(4, false, Vector2(450.0, -365.0)),
		TestCheckpoint.new(5, false, Vector2(-130.0, -365.0)),
		TestCheckpoint.new(6, false, Vector2(-735.0, -150.0), PI * 0.5),
		TestCheckpoint.new(7, false, Vector2(-735.0, 170.0), PI * 0.5),
	]
	root.add_child(manager)
	root.add_child(vehicle)
	vehicle.add_child(controller)
	vehicle.set_physics_process(false)
	controller.set_physics_process(false)
	manager.configure_checkpoints(checkpoints)
	manager.register_racer(vehicle, "Test AI", "Rustbug")
	controller.configure(vehicle, manager, 0.0)
	if not _expect(is_equal_approx(vehicle.boost_amount, vehicle.stats.boost_capacity * 0.58), "Club Circuit should start with its difficulty-scaled legal boost reserve"):
		return
	controller.configure(
		vehicle,
		manager,
		0.0,
		"club_circuit",
		"juniper",
		{"corner_pace": 1.04, "brake_timing": 0.9, "overtake_aggression": 1.0}
	)
	if not _expect(controller.personality_id == "juniper" and float(controller.personality["corner_pace"]) > 1.0 and float(controller.personality["brake_timing"]) < 1.0, "Club Circuit should preserve a bounded, scaled driver personality"):
		return
	controller.configure(
		vehicle,
		manager,
		0.0,
		"sunday_drive",
		"juniper",
		{"corner_pace": 1.04, "brake_timing": 0.9}
	)
	if not _expect(float(controller.personality["corner_pace"]) < 1.02 and float(controller.personality["brake_timing"]) > 0.96, "Sunday Drive should narrow personality differences"):
		return
	controller.configure(vehicle, manager, 0.0)
	manager.prepare_race()
	manager.start_race()
	controller.set("_racing_line", PackedVector2Array([
		Vector2.ZERO,
		Vector2(100.0, 0.0),
		Vector2(100.0, 100.0),
		Vector2(0.0, 100.0),
	]))
	vehicle.global_position = Vector2.ZERO
	vehicle.speed = 0.0
	var forward_line_target := controller.call("_racing_line_target", Vector2.LEFT) as Vector2
	if not _expect(forward_line_target.x > 60.0 and absf(forward_line_target.y) < 0.01, "forward AI should keep the race direction even when its heading is reversed"):
		return
	manager.set_reverse_direction(true)
	var reverse_line_target := controller.call("_racing_line_target", Vector2.RIGHT) as Vector2
	if not _expect(reverse_line_target.y > 60.0 and absf(reverse_line_target.x) < 0.01, "reverse AI should follow the racing line in descending order"):
		return
	var directional_radius_line := PackedVector2Array()
	directional_radius_line.resize(37)
	for index in directional_radius_line.size():
		directional_radius_line[index] = Vector2(1000.0 + index * 10.0, 1000.0)
	directional_radius_line[0] = Vector2.ZERO
	directional_radius_line[9] = Vector2(90.0, 0.0)
	directional_radius_line[18] = Vector2(180.0, 0.0)
	directional_radius_line[19] = Vector2(-90.0, 90.0)
	directional_radius_line[28] = Vector2(0.0, 90.0)
	controller.set("_racing_line", directional_radius_line)
	var reverse_line_radius := float(controller.call("_racing_line_radius", Vector2.ZERO))
	manager.set_reverse_direction(false)
	var forward_line_radius := float(controller.call("_racing_line_radius", Vector2.ZERO))
	if not _expect(
		reverse_line_radius > forward_line_radius + 20.0,
		"corner speed planning should sample racing-line curvature in the active direction"
	):
		return
	controller.set("_racing_line", PackedVector2Array())
	var surface_zone := SurfaceZone.new()
	root.add_child(surface_zone)
	surface_zone.configure(
		&"test low grip",
		PackedVector2Array([
			Vector2(50.0, -50.0),
			Vector2(300.0, -50.0),
			Vector2(300.0, 50.0),
			Vector2(50.0, 50.0),
		]),
		0.45,
		0.7
	)
	var surface_plan := controller.call("_surface_anticipation", Vector2.RIGHT) as Dictionary
	if not _expect(float(surface_plan["risk"]) > 0.5 and float(surface_plan["speed_scale"]) < 0.9, "AI should anticipate and pre-slow for a low-grip surface"):
		return
	if not _expect(is_zero_approx(float(surface_plan["weight"])), "AI should not leave the racing line when a full-width surface has no safe alternate lane"):
		return
	vehicle.surface_grip_multiplier = 0.45
	var planned_grip := float(controller.call("_planned_surface_grip", surface_plan))
	if not _expect(is_equal_approx(planned_grip, 0.45), "AI should use replacement surface grip without squaring the current modifier"):
		return
	vehicle.surface_grip_multiplier = 1.0
	root.remove_child(surface_zone)
	surface_zone.free()

	var corner_guide := controller.call("_checkpoint_entry_guide_position", 3) as Vector2
	var raw_corner := Vector2(735.0, 360.0)
	if not _expect(
		is_equal_approx(corner_guide.x, raw_corner.x) and corner_guide.y > raw_corner.y + 10.0,
		"corner clearance should sit outside the incoming straight without extending its overshoot axis"
	):
		return
	var straight_guide: Variant = controller.call("_checkpoint_entry_guide_position", 2)
	if not _expect(straight_guide == null, "straight checkpoint segments should not add redundant guides"):
		return

	manager.report_checkpoint(checkpoints[1], vehicle)
	manager.report_checkpoint(checkpoints[2], vehicle)
	vehicle.global_position = Vector2(350.0, 360.0)
	vehicle.rotation = PI * 0.5
	vehicle.linear_velocity = Vector2.RIGHT * 520.0
	vehicle.speed = 520.0
	controller.call("_physics_process", 1.0 / 60.0)
	if not _expect(is_zero_approx(float(vehicle.get("_external_brake"))), "competitive AI should not brake at the old overly-early marker"):
		return
	vehicle.global_position = Vector2(430.0, 360.0)
	controller.call("_physics_process", 1.0 / 60.0)
	if not _expect(float(vehicle.get("_external_brake")) > 0.5, "AI should brake later and strongly before a sharp corner"):
		return
	if not _expect(not bool(vehicle.get("_external_handbrake")), "AI cornering should remain stable without handbrake spins"):
		return
	if not _expect(absf(float(vehicle.get("_external_steer"))) < 0.8, "steering should ramp instead of snapping to full lock"):
		return
	vehicle.set_external_power_multiplier(2.0)
	if not _expect(is_equal_approx(float(vehicle.get("_external_power_multiplier")), 1.15), "AI acceleration should be bounded at the legal 1.15x ceiling"):
		return

	var traffic_leader := VehicleController.new()
	traffic_leader.add_to_group("race_vehicle")
	traffic_leader.collision_layer = 1
	root.add_child(traffic_leader)
	manager.register_racer(traffic_leader, "Parked AI", "Rustbug")
	vehicle.global_position = Vector2.ZERO
	vehicle.rotation = 0.0
	vehicle.speed = 420.0
	traffic_leader.global_position = Vector2(0.0, -105.0)
	traffic_leader.speed = 180.0
	var pass_plan := controller.call(
		"_traffic_plan",
		1.0 / 60.0,
		Vector2.UP,
		Vector2(0.0, -220.0),
		1800.0
	) as Dictionary
	if not _expect(bool(pass_plan["passing"]), "a faster AI should choose a clear adjacent lane instead of joining a train"):
		return
	if not _expect(absf(float((pass_plan["target_position"] as Vector2).x)) >= 50.0, "a pass should create enough lateral separation to clear the slower car"):
		return
	if not _expect(controller.overtake_attempt_count == 1, "a new clear pass should be exposed for race telemetry"):
		return
	controller.set("_overtake_hold_remaining", 0.01)
	var expired_plan := controller.call(
		"_traffic_plan",
		0.02,
		Vector2.UP,
		Vector2(0.0, -220.0),
		1800.0
	) as Dictionary
	if not _expect(not bool(expired_plan["passing"]) and float(controller.get("_overtake_cooldown_remaining")) > 0.0, "a completed pass hold should cool down before another attempt"):
		return
	if not _expect(controller.overtake_attempt_count == 1, "hold expiry should not immediately count a duplicate pass attempt"):
		return

	var blocker := StaticBody2D.new()
	blocker.collision_layer = 2
	blocker.position = Vector2(0.0, -105.0)
	var blocker_shape := CollisionShape2D.new()
	var blocker_rectangle := RectangleShape2D.new()
	blocker_rectangle.size = Vector2(220.0, 42.0)
	blocker_shape.shape = blocker_rectangle
	blocker.add_child(blocker_shape)
	root.add_child(blocker)
	await physics_frame
	controller.call("_cancel_overtake")
	controller.set("_overtake_cooldown_remaining", 0.0)
	var blocked_plan := controller.call(
		"_traffic_plan",
		1.0 / 60.0,
		Vector2.UP,
		Vector2(0.0, -220.0),
		1800.0
	) as Dictionary
	if not _expect(not bool(blocked_plan["passing"]), "AI should reject both passing lanes when a static obstacle blocks the required travel"):
		return
	if not _expect(float(blocked_plan["speed_scale"]) >= 0.8, "a blocked pass should trail lightly instead of braking to the old train-forming pace"):
		return
	vehicle.speed = 20.0
	var low_speed_plan := controller.call("_obstacle_avoidance", Vector2.UP, Vector2.UP) as Dictionary
	if not _expect(float(low_speed_plan["weight"]) >= 0.68, "low-speed AI should still commit to steering away from a close obstacle"):
		return
	blocker.position = Vector2(0.0, -58.0)
	await physics_frame
	var contact_plan := controller.call("_obstacle_avoidance", Vector2.UP, Vector2.UP) as Dictionary
	if not _expect(bool(contact_plan["static_contact"]), "a near static collider should expose a contact-normal escape plan"):
		return
	for _step in 7:
		controller.call("_update_static_escape", 0.1, contact_plan, false)
	if not _expect(controller.static_escape_attempt_count == 1 and float(vehicle.get("_external_brake")) > 0.9, "sustained static contact should reverse before recovery"):
		return
	controller.set("_escape_time_remaining", 0.0)
	controller.set("_static_contact_time", 0.0)

	root.remove_child(blocker)
	blocker.free()
	await physics_frame
	traffic_leader.speed = 410.0
	controller.set("_overtake_cooldown_remaining", 0.0)
	var draft_plan := controller.call(
		"_traffic_plan",
		1.0 / 60.0,
		Vector2.UP,
		Vector2(0.0, -220.0),
		1800.0
	) as Dictionary
	if not _expect(bool(draft_plan["drafting"]), "an aligned close follower should enter the legal drafting window on a straight"):
		return
	vehicle.boost_amount = 10.0
	controller.call("_apply_drafting_recharge", 1.0, draft_plan, false)
	if not _expect(is_equal_approx(vehicle.boost_amount, 14.0), "drafting should recharge only the existing boost meter"):
		return
	manager.start_race()
	manager.report_checkpoint(checkpoints[1], vehicle)
	manager.report_checkpoint(checkpoints[2], vehicle)
	manager.laps_to_finish = 1
	for checkpoint_index in range(1, checkpoints.size()):
		if not _expect(manager.report_checkpoint(checkpoints[checkpoint_index], traffic_leader), "parked-racer fixture should advance through checkpoint %d (expected=%d)" % [checkpoint_index, manager.get_expected_checkpoint(traffic_leader)]):
			return
	if not _expect(manager.report_checkpoint(checkpoints[0], traffic_leader), "parked-racer fixture should complete at the finish gate"):
		return
	var finished_leader := controller.call("_nearest_vehicle_ahead", Vector2.UP) as Dictionary
	if not _expect(finished_leader.is_empty(), "finished and DNF racers should not remain stationary traffic targets"):
		return
	root.remove_child(traffic_leader)
	traffic_leader.free()

	controller.set("_racing_line", PackedVector2Array([
		Vector2(-100.0, -100.0),
		Vector2(100.0, -100.0),
		Vector2(100.0, 100.0),
		Vector2(-100.0, 100.0),
	]))
	controller.call("_reset_route_watchdog")
	controller.set("_last_recovery_time", Time.get_ticks_msec())
	controller.set("_overtake_hold_remaining", 1.0)
	controller.set("_overtake_offset", 52.0)
	vehicle.global_position = Vector2(700.0, 700.0)
	vehicle.speed = 300.0
	for _step in 14:
		controller.call("_update_route_watchdog", 0.1, manager.get_expected_checkpoint(vehicle))
	if not _expect(bool(controller.get("_recovering")) and controller.recovery_count == 1, "a severe off-route AI should recover at speed even during the normal cooldown"):
		return
	if not _expect(vehicle.global_position.distance_to(manager.get_last_recovery_transform(vehicle).origin) < 1.0, "off-route recovery should return the AI to its last legal gate"):
		return
	if not _expect(is_zero_approx(float(controller.get("_overtake_hold_remaining"))) and is_zero_approx(float(controller.get("_overtake_offset"))), "recovery should clear stale overtake hold and offset state"):
		return
	await create_timer(1.05).timeout

	manager.start_race()
	controller.set("_racing_line", PackedVector2Array())
	controller.set("_last_recovery_time", 0)
	vehicle.global_position = Vector2(430.0, 360.0)
	vehicle.rotation = PI * 0.5
	vehicle.speed = 60.0
	vehicle.linear_velocity = Vector2.ZERO
	controller.set("_guide_checkpoint_index", 3)
	controller.set("_guide_reached", true)
	controller.set("_stuck_target_key", "")
	controller.set("_best_checkpoint_distance", INF)
	controller.set("_stuck_time", 0.0)
	for _step in 8:
		controller.call("_physics_process", 0.5)
	if not _expect(bool(controller.get("_recovering")), "AI should recover after two seconds without route progress even if reported speed is nonzero"):
		return
	if not _expect(not bool(controller.get("_guide_reached")), "recovery should require the safe corner guide again"):
		return
	if not _expect(int(controller.get("_guide_checkpoint_index")) == -1, "recovery should reset the active route phase"):
		return

	root.remove_child(vehicle)
	root.remove_child(manager)
	vehicle.free()
	manager.free()
	for checkpoint: Node in checkpoints:
		checkpoint.free()
	print("AI_VEHICLE_CONTROLLER_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AI_VEHICLE_CONTROLLER_TEST FAIL: " + message)
	quit(1)
	return false
