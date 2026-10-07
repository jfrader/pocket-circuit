extends SceneTree

const PROTOTYPE := preload("res://scenes/race/prototype_race.tscn")
const CATALOG := preload("res://data/championship/catalog.gd")
const CASES := [[&"kitchen", &"classic", 0]]
const MAX_FRAMES := 9000


class OscillatingRouteProbe extends AIVehicleController:
	var arc := 0.0

	func _active_route_sample(_expected_index: int) -> Dictionary:
		return {"arc": arc, "length": 1000.0, "distance": 0.0, "closed": true}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 1.0
	if not _check_planning():
		return
	if not _check_net_progress():
		return
	if not await _check_room_cuts():
		return
	for case: Array in CASES:
		var solo := await _race(case, 0)
		if solo.is_empty():
			return
		var field := await _race(case, 3)
		if field.is_empty():
			return
		var traffic_ratio := float(field["slowest"]) / float(solo["slowest"])
		print("AI_PACE_COMPARE %s/%s/%d solo=%.3f field_fastest=%.3f field_slowest=%.3f traffic_ratio=%.3f" % [case[0], case[1], case[2], solo["slowest"], field["fastest"], field["slowest"], traffic_ratio])
		if not _expect(traffic_ratio <= 1.35, "same-chassis traffic must not cause a large pace collapse"):
			return
	print("AI_PACE_TEST PASS solo_and_field")
	quit(0)


func _check_planning() -> bool:
	var car := VehicleController.new()
	car.stats = CATALOG.create_vehicle_stats("rustbug")
	var manager := RaceManager.new()
	var controller := AIVehicleController.new()
	controller.vehicle = car
	controller.race_manager = manager
	controller.call("_configure_personality", "baseline", {})
	var circle := PackedVector2Array()
	for i in 260:
		circle.append(Vector2.RIGHT.rotated(TAU * float(i) / 260.0) * 300.0)
	controller.set("_racing_line", circle)
	var measured_radius := float(controller.call("_radius_at_line_index", 0))
	car.speed = 500.0
	var near := float(controller.call("_v1_speed_envelope", 100.0, 0.0))
	var distant := float(controller.call("_v1_speed_envelope", 100.0, 700.0))
	var dry := float(controller.call("_v1_speed_envelope", 300.0, 0.0))
	car.surface_grip_multiplier = 0.45
	var wet := float(controller.call("_v1_speed_envelope", 300.0, 0.0))
	var maximum := car.get_effective_max_speed()
	var slick_straight := float(controller.call("_surface_driving_speed_scale", 1.0, 0.45, Vector2.UP))
	var slick_turn := float(controller.call("_surface_driving_speed_scale", 1.0, 0.45, Vector2.UP.rotated(0.2)))
	controller.free()
	manager.free()
	car.free()
	return (
		_expect(absf(measured_radius - 300.0) < 1.0, "circumradius must match the known circular route")
		and _expect(near < 500.0 and distant >= maximum * 0.99, "a distant corner allows acceleration while its apex requires braking")
		and _expect(wet < dry, "reduced tire grip still limits corner speed")
		and _expect(is_equal_approx(slick_straight, 1.0) and slick_turn < 1.0, "low grip limits turns, not an aligned straight")
	)


func _check_room_cuts() -> bool:
	var fixture := Node2D.new()
	root.add_child(fixture)
	var car := VehicleController.new()
	car.stats = CATALOG.create_vehicle_stats("rustbug")
	fixture.add_child(car)
	car.freeze = true
	var manager := RaceManager.new()
	fixture.add_child(manager)
	var gate := Node2D.new()
	gate.position = Vector2(0.0, -400.0)
	fixture.add_child(gate)
	var controller := AIVehicleController.new()
	car.add_child(controller)
	controller.set_physics_process(false)
	controller.vehicle = car
	controller.race_manager = manager
	controller.set("_allow_room_cuts", true)
	controller.set("_checkpoints_by_index", {1: gate})
	controller.set("_racing_line", PackedVector2Array([Vector2.ZERO, Vector2(200, 0), Vector2(200, -400), Vector2(0, -400)]))
	var blocker := StaticBody2D.new()
	blocker.collision_layer = 2
	blocker.position = Vector2(0.0, -200.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60.0, 60.0)
	shape.shape = rect
	blocker.add_child(shape)
	fixture.add_child(blocker)
	await physics_frame
	await physics_frame
	controller.call("_update_room_cut", 1, Vector2.UP)
	var rejects_wall := int(controller.get("_room_cut_checkpoint")) == -1
	fixture.remove_child(blocker)
	blocker.free()
	await physics_frame
	await physics_frame
	controller.call("_update_room_cut", 1, Vector2.UP)
	var accepts_clear := int(controller.get("_room_cut_checkpoint")) == 1
	controller.call("_update_room_cut", 2, Vector2.UP)
	var respects_next_gate := int(controller.get("_room_cut_checkpoint")) == -1
	root.remove_child(fixture)
	fixture.free()
	await physics_frame
	return _expect(rejects_wall and accepts_clear and respects_next_gate, "apron cuts require a clear car-width path to the currently required gate")


func _check_net_progress() -> bool:
	var controller := OscillatingRouteProbe.new()
	var vehicle := VehicleController.new()
	var manager := RaceManager.new()
	controller.vehicle = vehicle
	controller.race_manager = manager
	controller.call("_update_route_watchdog", 1.0 / 60.0, 1)
	for cycle in 10:
		controller.arc = 8.0
		controller.call("_update_route_watchdog", 1.0 / 60.0, 1)
		controller.arc = 0.0
		controller.call("_update_route_watchdog", 1.0 / 60.0, 1)
	var stalled := float(controller.get("_no_progress_time"))
	controller.free()
	vehicle.free()
	manager.free()
	return _expect(stalled >= 0.3, "reversing and re-covering the same distance must not reset the stall watchdog")


func _race(case: Array, opponents: int) -> Dictionary:
	var prototype := PROTOTYPE.instantiate()
	prototype.set("_session", {"event": {
		"theme": case[0], "circuit": "generated", "room": case[1], "seed": case[2],
		"laps": 3, "opponents": ["juniper", "milo", "tess"], "opponent_count": opponents,
	}, "difficulty": "club_circuit", "vehicle_id": "rustbug"})
	root.add_child(prototype)
	current_scene = prototype
	paused = false
	prototype.call("_set_paused", false)
	var manager := prototype.get_node("RaceManager") as RaceManager
	var racers: Array[VehicleController] = []
	var controllers: Array[AIVehicleController] = []
	for node: Node in get_nodes_in_group("race_vehicle"):
		if not prototype.is_ancestor_of(node):
			continue
		var car := node as VehicleController
		car.apply_stats(CATALOG.create_vehicle_stats("rustbug"))
		var controller: AIVehicleController
		for child: Node in car.get_children():
			if child is AIVehicleController:
				controller = child
		if controller == null:
			controller = AIVehicleController.new()
			car.add_child(controller)
		controller.configure(car, manager, 0.0, "club_circuit", "baseline", {})
		racers.append(car)
		controllers.append(controller)
	if not _expect(racers.size() == opponents + 1, "pace fixture must contain the complete requested field"):
		prototype.free()
		return {}
	# Deterministic settle: the old 6 x 0.1 s wall-clock timers covered 0.6 s of
	# simulated time, which is 36 physics frames here (60 frames per simulated
	# second). Stepping physics frames keeps the settle independent of rendered
	# frame rate.
	for _settle in 36:
		await physics_frame
	paused = false
	# Bounded condition wait: poll the manager's running state on physics frames
	# instead of wall-clock timers, with the old 30 x 0.1 s = 3.0 s budget
	# converted to 180 physics frames.
	for _wait in 180:
		if manager.is_running:
			break
		await physics_frame
	if not _expect(manager.is_running, "pace fixture must complete the real countdown"):
		prototype.free()
		return {}
	var frame := 0
	var peak_speed := 0.0
	var speed_sum := 0.0
	var samples := 0
	var braking_samples := 0
	while frame < MAX_FRAMES:
		await physics_frame
		frame += 1
		var complete := true
		for car: VehicleController in racers:
			complete = complete and manager.is_racer_finished(car)
			if not manager.is_racer_finished(car):
				peak_speed = maxf(peak_speed, car.speed)
				speed_sum += car.speed
				samples += 1
				if float(car.get("_external_brake")) > 0.1:
					braking_samples += 1
		if complete:
			break
	var times: Array[float] = []
	var valid := true
	valid = _expect(peak_speed >= racers[0].stats.max_speed * 0.85, "rivals must reach useful straight-line speed, not cruise at corner pace everywhere") and valid
	valid = _expect(speed_sum / maxf(samples, 1) >= racers[0].stats.max_speed * 0.55, "reference routes must not spend the race at a fraction of available pace") and valid
	for i in racers.size():
		var state := manager.get_racer_state(racers[i])
		print("AI_PACE_RACER theme=%s opponents=%d racer=%d finish=%.3f dnf=%s recoveries=%d" % [case[0], opponents, i, float(state.get("finish_time", INF)), bool(state.get("dnf", true)), controllers[i].recovery_count])
		valid = _expect(bool(state.get("finished", false)) and not bool(state.get("dnf", true)), "%s/%s/%d racer %d must finish without DNF at normal grace" % [case[0], case[1], case[2], i]) and valid
		valid = _expect(controllers[i].recovery_count <= 3, "pace improvements must not rely on repeated recovery") and valid
		times.append(float(state.get("finish_time", INF)))
	current_scene = null
	root.remove_child(prototype)
	prototype.free()
	await process_frame
	await physics_frame
	if not valid:
		return {}
	print("AI_PACE_SPEED theme=%s opponents=%d peak=%.1f mean=%.1f braking_fraction=%.3f" % [case[0], opponents, peak_speed, speed_sum / maxf(samples, 1), float(braking_samples) / maxf(samples, 1)])
	return {"fastest": times.min(), "slowest": times.max()}


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error("AI_PACE_TEST FAIL: " + message)
		quit(1)
	return ok
