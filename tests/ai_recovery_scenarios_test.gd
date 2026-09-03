extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const MAX_SCENARIO_FRAMES := 3600


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	Engine.time_scale = 1.0
	if not await _run_giant_jam_scenario():
		return
	if not await _run_parked_car_scenario():
		return
	print("AI_RECOVERY_SCENARIOS_TEST PASS")
	quit(0)


func _run_giant_jam_scenario() -> bool:
	var prototype := PROTOTYPE_SCENE.instantiate()
	prototype.set("_session", {
		"event": {
			"theme": &"workshop",
			"circuit": "generated",
			"room": &"wide",
			"seed": 1,
			"reverse": false,
			"laps": 1,
		},
		"difficulty": "club_circuit",
	})
	var manager := prototype.get_node("RaceManager") as RaceManager
	manager.finish_grace_seconds = 60.0
	root.add_child(prototype)
	current_scene = prototype
	if not await _wait_for_race(manager):
		return _expect(false, "giant-jam scenario should finish its countdown")

	var player := get_first_node_in_group("player_vehicle") as RigidBody2D
	if player:
		player.freeze = true
		player.collision_layer = 0
		player.collision_mask = 0
	var racers := _ai_racers(player)
	if not _expect(racers.size() == 3, "giant-jam scenario should create three AI rivals"):
		return false
	var target := racers[1] as VehicleController
	var controller := _get_ai_controller(target)
	var track := prototype.get_node("Track") as Node2D
	var giants := track.get_node_or_null("GeneratedMoments/GiantLandmarks")
	if not _expect(controller != null and giants != null and giants.get_child_count() > 0, "giant-jam scenario needs an AI controller and generated giant"):
		return false
	var giant := giants.get_child(0) as Node2D
	var collisions := giant.find_children("*", "CollisionShape2D", true, false)
	if not _expect(not collisions.is_empty(), "generated giant should expose its physical collision shape"):
		return false
	var collision := collisions[0] as CollisionShape2D
	var racing_line := track.get_node("RacingLine") as Line2D
	var nearest_line_point := _nearest_line_point(giant.global_position, racing_line, track)
	var outward := giant.global_position.direction_to(nearest_line_point)
	var support := _collision_support_point(collision, outward)
	var jam_position := support + outward * 26.0
	var jam_rotation := Vector2.UP.angle_to(-outward)
	# Hold the fixture against the giant long enough to model a sustained jam,
	# rather than letting the initial physics impulse resolve it as a normal bump.
	var jam_frame := 0
	while jam_frame < 90 and controller.static_escape_attempt_count == 0:
		target.global_position = jam_position
		target.rotation = jam_rotation
		target.linear_velocity = -outward * 35.0
		await physics_frame
		jam_frame += 1

	var frame := 0
	while frame < MAX_SCENARIO_FRAMES and not manager.is_racer_finished(target):
		await physics_frame
		frame += 1
	var state := manager.get_racer_state(target)
	if not _expect(bool(state.get("finished", false)) and not bool(state.get("dnf", true)), "AI pressed against a giant should escape or recover and finish"):
		return false
	if not _expect(controller.static_escape_attempt_count + controller.recovery_count >= 1, "giant contact should exercise static escape or recovery"):
		return false
	print("AI_GIANT_JAM_PASS frames=%d escapes=%d recoveries=%d" % [frame, controller.static_escape_attempt_count, controller.recovery_count])
	await _free_prototype(prototype)
	return true


func _run_parked_car_scenario() -> bool:
	var prototype := PROTOTYPE_SCENE.instantiate()
	prototype.set("_session", {
		"event": {
			"theme": &"kitchen",
			"circuit": "generated",
			"room": &"classic",
			"seed": 0,
			"reverse": false,
			"laps": 1,
			"opponents": ["juniper", "milo"],
			"opponent_count": 2,
		},
		"difficulty": "club_circuit",
	})
	var manager := prototype.get_node("RaceManager") as RaceManager
	manager.finish_grace_seconds = 60.0
	root.add_child(prototype)
	current_scene = prototype
	if not await _wait_for_race(manager):
		return _expect(false, "parked-car scenario should finish its countdown")

	var player := get_first_node_in_group("player_vehicle") as RigidBody2D
	if player:
		player.freeze = true
		player.collision_layer = 0
		player.collision_mask = 0
	var racers := _ai_racers(player)
	if not _expect(racers.size() == 2, "parked-car scenario should create two AI rivals"):
		return false
	var parked := racers[0] as VehicleController
	var trailing := racers[1] as VehicleController
	var parked_controller := _get_ai_controller(parked)
	var trailing_controller := _get_ai_controller(trailing)
	if not _expect(_finish_racer_at_gates(manager, parked), "parked-car fixture should legally finish the lead AI"):
		return false
	var ghost_wait := 0
	while parked.collision_layer != 0 and ghost_wait < 120:
		await physics_frame
		ghost_wait += 1
	if not _expect(parked.collision_layer == 0 and parked.collision_mask == 0, "finished AI should ghost instead of becoming a parked obstacle"):
		return false

	var line: PackedVector2Array = trailing_controller.get("_racing_line")
	var nearest_index := int(trailing_controller.call("_nearest_line_index", trailing.global_position))
	var parked_index := posmod(nearest_index + 6, line.size())
	parked.global_position = line[parked_index]
	parked.rotation = Vector2.UP.angle_to(line[parked_index].direction_to(line[(parked_index + 1) % line.size()]))
	var ahead := trailing_controller.call("_nearest_vehicle_ahead", Vector2.UP.rotated(trailing.rotation)) as Dictionary
	if not _expect(ahead.is_empty() or ahead.get("vehicle") != parked, "finished AI should be excluded from traffic planning"):
		return false

	var frame := 0
	while frame < MAX_SCENARIO_FRAMES and not manager.is_racer_finished(trailing):
		await physics_frame
		frame += 1
	var state := manager.get_racer_state(trailing)
	if not _expect(bool(state.get("finished", false)) and not bool(state.get("dnf", true)), "trailing AI should pass through a parked finisher and finish"):
		return false
	print("AI_PARKED_CAR_PASS frames=%d recoveries=%d" % [frame, trailing_controller.recovery_count])
	parked_controller = null
	await _free_prototype(prototype)
	return true


func _wait_for_race(manager: RaceManager) -> bool:
	for _settle in 6:
		await create_timer(0.1).timeout
	paused = false
	var waits := 0
	while not manager.is_running and waits < 30:
		await create_timer(0.1).timeout
		waits += 1
	return manager.is_running


func _ai_racers(player: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node: Node in get_nodes_in_group("race_vehicle"):
		if node != player and _get_ai_controller(node) != null:
			result.append(node as Node2D)
	return result


func _finish_racer_at_gates(manager: RaceManager, racer: Node2D) -> bool:
	for _gate in manager.get_checkpoint_count() + 1:
		if manager.is_racer_finished(racer):
			return true
		var expected := manager.get_expected_checkpoint(racer)
		var checkpoint: Area2D
		for candidate: Node in manager.get_ordered_checkpoints():
			if int(candidate.get("checkpoint_index")) == expected:
				checkpoint = candidate as Area2D
				break
		if checkpoint == null or not manager.report_checkpoint(checkpoint, racer):
			return false
	return manager.is_racer_finished(racer)


func _nearest_line_point(position: Vector2, line: Line2D, track: Node2D) -> Vector2:
	var best := track.to_global(line.points[0])
	var best_distance := INF
	for point: Vector2 in line.points:
		var world_point := track.to_global(point)
		var distance := position.distance_squared_to(world_point)
		if distance < best_distance:
			best_distance = distance
			best = world_point
	return best


func _collision_support_point(collision: CollisionShape2D, direction: Vector2) -> Vector2:
	var points: Array[Vector2] = []
	if collision.shape is CircleShape2D:
		return collision.global_position + direction * (collision.shape as CircleShape2D).radius
	if collision.shape is RectangleShape2D:
		var half := (collision.shape as RectangleShape2D).size * 0.5
		points.assign([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])
	elif collision.shape is ConvexPolygonShape2D:
		for point: Vector2 in (collision.shape as ConvexPolygonShape2D).points:
			points.append(point)
	elif collision.shape is CapsuleShape2D:
		var capsule := collision.shape as CapsuleShape2D
		var half_height := capsule.height * 0.5
		points.assign([
			Vector2(-capsule.radius, -half_height),
			Vector2(capsule.radius, -half_height),
			Vector2(capsule.radius, half_height),
			Vector2(-capsule.radius, half_height),
		])
	var support := collision.global_position
	var best_projection := -INF
	for point: Vector2 in points:
		var world_point := collision.to_global(point)
		var projection := world_point.dot(direction)
		if projection > best_projection:
			best_projection = projection
			support = world_point
	return support


func _get_ai_controller(racer: Node) -> AIVehicleController:
	for child: Node in racer.get_children():
		if child is AIVehicleController:
			return child as AIVehicleController
	return null


func _free_prototype(prototype: Node) -> void:
	current_scene = null
	prototype.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	Engine.time_scale = 1.0
	push_error("AI_RECOVERY_SCENARIOS_TEST FAIL: " + message)
	quit(1)
	return false
