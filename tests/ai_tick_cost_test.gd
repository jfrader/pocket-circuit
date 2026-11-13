extends SceneTree

const AI_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const BATCHES := 9
const TICKS_PER_BATCH := 256
const MAX_COST_RATIO := 0.70


class TestCheckpoint extends Area2D:
	var checkpoint_index: int
	var is_finish_line: bool

	func _init(index: int, checkpoint_position: Vector2) -> void:
		checkpoint_index = index
		is_finish_line = index == 0
		position = checkpoint_position

	func get_recovery_transform() -> Transform2D:
		return global_transform


# Pre-hoist horizon loop: same geometry, candidate order and envelope arithmetic,
# but predicts braking independently for every candidate, as before this change.
# The full callback inherits the eager-default fix, so its baseline conservatively
# excludes the saving from removing that redundant envelope evaluation.
class UnhoistedController extends AIVehicleController:
	func _racing_line_curvature_hazard() -> Dictionary:
		var count := _racing_line.size()
		var direction := -1 if race_manager.is_reverse_direction() else 1
		var index := _nearest_line_index(vehicle.global_position)
		var effective_max_speed := vehicle.get_effective_max_speed()
		var horizon := 900.0
		var walked := 0.0
		var hazard_radius := MAX_RACING_LINE_RADIUS
		var hazard_distance := INF
		var speed_limit := effective_max_speed
		for _step in count:
			if walked > horizon:
				break
			var radius := _radius_at_line_index(index)
			if radius > 0.0:
				var allowed := _v1_speed_envelope(radius, walked)
				if allowed < speed_limit:
					speed_limit = allowed
					hazard_distance = walked
					hazard_radius = radius
			if _open_route and (index + direction < 0 or index + direction >= count):
				break
			var next := (index + direction + count) % count
			walked += _racing_line[index].distance_to(_racing_line[next])
			index = next
		_hazard_result["radius"] = hazard_radius
		_hazard_result["distance"] = hazard_distance
		_hazard_result["speed_limit"] = speed_limit
		return _hazard_result

	func _v1_speed_envelope(radius: float, distance: float) -> float:
		var maximum := vehicle.get_effective_max_speed()
		if radius <= 0.0 or is_inf(distance):
			return maximum
		var grip := minf(vehicle.surface_grip_multiplier, _anticipated_grip)
		var lateral_accel := minf(vehicle.stats.front_grip, vehicle.stats.rear_grip) * grip * DYNAMICS.REFERENCE_GRAVITY * _tracking_grip_utilization
		var tuning := _difficulty_tuning()
		var margin := float(tuning["corner_margin"])
		var corner := minf(maximum, sqrt(lateral_accel * radius) * margin * float(personality["corner_pace"]))
		var rack := DYNAMICS.calculate_target_steer_angle(1.0, vehicle.stats.max_steer_angle_deg, corner, maximum, vehicle.stats.high_speed_steer_ratio, vehicle.stats.steer_fade_start_ratio)
		var minimum_radius := vehicle.stats.wheelbase / maxf(tan(rack), 0.001)
		corner *= minf(1.0, radius / minimum_radius)
		var reaction_seconds := float(tuning["reaction_seconds"])
		var braking_distance := maxf(0.0, distance - vehicle.speed * reaction_seconds * float(personality["brake_timing"]))
		var braking_accel := DYNAMICS.get_effective_brake_accel(vehicle.stats, grip, _brake_prediction, _brake_prediction_loads)
		return minf(maximum, sqrt(corner * corner + 2.0 * braking_accel * braking_distance))


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var manager := RaceManager.new()
	root.add_child(manager)
	var old := UnhoistedController.new()
	var current := AI_SCRIPT.new() as AIVehicleController
	var controllers: Array[AIVehicleController] = [old, current]
	var line := PackedVector2Array()
	for index in 240:
		var angle := TAU * float(index) / 240.0
		line.append(Vector2(cos(angle) * 700.0, sin(angle) * 450.0))
	for controller in controllers:
		var vehicle := VehicleController.new()
		root.add_child(vehicle)
		vehicle.add_child(controller)
		vehicle.set_physics_process(false)
		controller.set_physics_process(false)
		controller.configure(vehicle, manager, 0.0)
		controller.set("_racing_line", line)
		vehicle.global_position = line[0]
		vehicle.speed = 650.0
	# Adjacent calls deliberately change every input relevant to hoisted braking;
	# this also tests manual calls in one engine tick, not just frame invalidation.
	for reverse in [false, true]:
		manager.set_reverse_direction(reverse)
		for open_route in [false, true]:
			for sample in 24:
				for controller in controllers:
					controller.set("_open_route", open_route)
					controller.difficulty = ["sunday_drive", "club_circuit", "clockwork"][sample % 3]
					controller.personality["corner_pace"] = 0.96 + float(sample % 3) * 0.04
					controller.personality["brake_timing"] = 0.9 + float(sample % 3) * 0.1
					controller.set("_anticipated_grip", 0.35 + float(sample % 4) * 0.2)
					controller.set("_tracking_grip_utilization", 0.5 + float(sample % 3) * 0.15)
					controller.vehicle.surface_grip_multiplier = 0.4 + float(sample % 5) * 0.15
					controller.vehicle.surface_speed_multiplier = 0.6 + float(sample % 3) * 0.2
					controller.vehicle.speed = 100.0 + float(sample) * 30.0
					controller.vehicle.stats.brake_force = 2500.0 + float(sample) * 100.0
					controller.vehicle.stats.front_grip = 0.8 + float(sample % 4) * 0.1
					controller.vehicle.stats.rear_grip = 1.1 - float(sample % 4) * 0.1
					controller.vehicle.global_position = line[(sample * 9) % line.size()]
				var expected := old._racing_line_curvature_hazard()
				var actual := current._racing_line_curvature_hazard()
				if not _expect(expected == actual, "hoisted horizon must exactly match unhoisted results after state/direction/window changes"):
					return
	manager.set_reverse_direction(false)
	for controller in controllers:
		controller.configure(controller.vehicle, manager, 0.0)
		controller.set("_racing_line", line)
		controller.set("_open_route", false)
		controller.set("_anticipated_grip", 1.0)
		controller.set("_tracking_grip_utilization", AIVehicleController.CORNER_GRIP_UTILIZATION)
		controller.vehicle.global_position = line[0]
		controller.vehicle.speed = 650.0
		controller.vehicle.surface_grip_multiplier = 1.0
		controller.vehicle.surface_speed_multiplier = 1.0
	# Warm both sides; measure alternating batches in one process to reduce host
	# scheduling/order bias. This isolates the per-tick curvature callback, not FPS.
	_measure(old)
	_measure(current)
	var old_samples: Array[float] = []
	var new_samples: Array[float] = []
	for batch in BATCHES:
		if batch % 2 == 0:
			old_samples.append(_measure(old))
			new_samples.append(_measure(current))
		else:
			new_samples.append(_measure(current))
			old_samples.append(_measure(old))
	old_samples.sort()
	new_samples.sort()
	var old_usec := old_samples[BATCHES / 2]
	var new_usec := new_samples[BATCHES / 2]
	var ratio := new_usec / old_usec
	print("AI_TICK_COST curvature_callback old_usec=%.3f new_usec=%.3f ratio=%.3f batches=%d ticks_per_batch=%d" % [old_usec, new_usec, ratio, BATCHES, TICKS_PER_BATCH])
	if not _expect(ratio <= MAX_COST_RATIO, "per-tick curvature callback must cost <=70% of the unhoisted loop"):
		return
	var checkpoints: Array = []
	for index in 8:
		checkpoints.append(TestCheckpoint.new(index, line[index * 30]))
	manager.configure_checkpoints(checkpoints)
	for controller in controllers:
		manager.register_racer(controller.vehicle, "Test AI", "Rustbug")
	manager.prepare_race()
	manager.start_race()
	for controller in controllers:
		controller.set("_racing_line", line)
		controller.set("_reference_path", line)
		controller.call("_build_arc_tables")
	# Drive both controllers through the same fixed poses without advancing the
	# physics world. Compare the actual actuator targets, not race finish hashes.
	var targets := {}
	for sample in 120:
		var position_index := sample % 30
		var tangent := line[position_index].direction_to(line[position_index + 1])
		for controller in controllers:
			controller.vehicle.global_position = line[position_index]
			controller.vehicle.rotation = tangent.angle() + PI * 0.5
			controller.vehicle.speed = 250.0 + float(sample % 20) * 25.0
			controller.vehicle.linear_velocity = tangent * controller.vehicle.speed
			controller.vehicle.surface_grip_multiplier = 0.45 + float(sample % 4) * 0.15
			controller._physics_process(1.0 / 60.0)
		for target: String in ["_external_steer", "_external_brake", "_external_throttle", "_external_boost", "_external_handbrake"]:
			if not _expect(old.vehicle.get(target) == current.vehicle.get(target), "fixed inputs must produce identical %s at sample %d" % [target, sample]):
				return
		targets[Vector3(current.vehicle.get("_external_steer"), current.vehicle.get("_external_brake"), current.vehicle.get("_external_throttle"))] = true
	if not _expect(targets.size() > 1 and manager.is_running and not current.get("_recovering"), "callback fixture must exercise changing actuator targets without early-return/recovery"):
		return
	old_samples.clear()
	new_samples.clear()
	_measure_tick(old)
	_measure_tick(current)
	for batch in BATCHES:
		if batch % 2 == 0:
			old_samples.append(_measure_tick(old))
			new_samples.append(_measure_tick(current))
		else:
			new_samples.append(_measure_tick(current))
			old_samples.append(_measure_tick(old))
	old_samples.sort()
	new_samples.sort()
	old_usec = old_samples[BATCHES / 2]
	new_usec = new_samples[BATCHES / 2]
	print("AI_TICK_COST full_callback old_usec=%.3f new_usec=%.3f ratio=%.3f" % [old_usec, new_usec, new_usec / old_usec])
	if not _expect(new_usec / old_usec <= MAX_COST_RATIO, "full per-tick AI callback must cost <=70% of the unhoisted baseline"):
		return
	for controller in controllers:
		controller.vehicle.free()
	manager.free()
	for checkpoint: Node in checkpoints:
		checkpoint.free()
	print("AI_TICK_COST_TEST PASS")
	quit(0)


func _measure(controller: AIVehicleController) -> float:
	var started := Time.get_ticks_usec()
	for _tick in TICKS_PER_BATCH:
		controller._racing_line_curvature_hazard()
	return float(Time.get_ticks_usec() - started) / float(TICKS_PER_BATCH)


func _measure_tick(controller: AIVehicleController) -> float:
	var started := Time.get_ticks_usec()
	for _tick in TICKS_PER_BATCH:
		# Hold timer/recovery state fixed while exercising the complete callback.
		controller._physics_process(0.0)
	return float(Time.get_ticks_usec() - started) / float(TICKS_PER_BATCH)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AI_TICK_COST_TEST FAIL: " + message)
	quit(1)
	return false
