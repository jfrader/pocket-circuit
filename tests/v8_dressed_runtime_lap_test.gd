extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const GENERATOR := preload("res://scripts/race/track_v8_development_generator.gd")
const MAX_PHYSICS_FRAMES := 5000
const MAX_RECOVERIES := 0

const CASES: Array[Dictionary] = [
	{"room": &"classic", "tier": "standard", "seed": 928, "reverse": false},
	{"room": &"classic", "tier": "standard", "seed": 928, "reverse": true},
	{"room": &"el", "tier": "compact", "seed": 1001, "reverse": false},
	{"room": &"el", "tier": "compact", "seed": 1001, "reverse": true},
]


func _initialize() -> void:
	Engine.time_scale = 1.0
	call_deferred("_run_test")


func _run_test() -> void:
	for test_case: Dictionary in CASES:
		if not await _run_case(test_case):
			return
	Engine.time_scale = 1.0
	print("V8_DRESSED_RUNTIME_LAP_TEST PASS cases=4")
	quit(0)


func _run_case(test_case: Dictionary) -> bool:
	var app := root.get_node_or_null("App")
	if app != null:
		app.current_race_session.clear()
	var generated := GENERATOR.generate_route(test_case["room"], StringName(test_case["tier"]), int(test_case["seed"]))
	if not _expect(bool(generated.get("ok", false)), "%s/%s runtime fixture should solve before scene assembly: %s" % [test_case["room"], test_case["tier"], generated.get("reason", "unknown")]):
		return false
	var room_seed := int(generated["identity"]["room_geometry_seed"])
	var rev: bool = bool(test_case.get("reverse", false))
	var identity := IDENTITIES.create_v8(&"kitchen", test_case["room"], int(test_case["seed"]), rev, 1, "", "", {}, test_case["tier"], -1, 1, room_seed)
	if not _expect(not identity.is_empty(), "%s/%s should create a PC2 identity" % [test_case["room"], test_case["tier"]]):
		return false
	var event := IDENTITIES.apply_to_event(identity, ["juniper", "milo", "tess"])
	event["laps"] = 1
	event["obstacles_enabled"] = true
	var prototype := PROTOTYPE_SCENE.instantiate()
	prototype.set("_session", {"mode": "quick", "event": event, "difficulty": "clockwork", "vehicle_id": "rustbug"})
	var manager := prototype.get_node("RaceManager") as RaceManager
	root.add_child(prototype)
	current_scene = prototype
	await process_frame
	await physics_frame
	var player := get_first_node_in_group("player_vehicle") as RigidBody2D
	if player:
		player.freeze = true
		player.collision_layer = 0
		player.collision_mask = 0
	var ai_racers: Array[Node2D] = []
	var ai_controllers: Array[AIVehicleController] = []
	for candidate: Node in get_nodes_in_group("race_vehicle"):
		if candidate == player:
			continue
		for child: Node in candidate.get_children():
			if child is AIVehicleController:
				ai_racers.append(candidate as Node2D)
				ai_controllers.append(child as AIVehicleController)
				break
	if not _expect(ai_racers.size() == 3 and ai_controllers.size() == 3, "%s/%s/%s should create a 4-car field (3 AI) for dressed lap" % [test_case["room"], test_case["tier"], "reverse" if rev else "forward"]):
		return false
	var track := prototype.get_node_or_null("Track") as Node2D
	if not _expect(track != null and bool(track.get_meta("generated_track", false)) and int(track.get_meta("generator_version", 0)) == 8 and StringName(track.get_meta("room_shape", &"")) == test_case["room"] and bool(track.get_meta("obstacles_enabled", false)), "%s/%s/%s should race assembled dressed v8 geometry with obstacles enabled" % [test_case["room"], test_case["tier"], "reverse" if rev else "forward"]):
		return false
	# Assembled world present: floor, island, walls, posts, gates, props
	if not _expect(track.has_node("Floor") and track.has_node("RoomSurface"), "%s/%s should have floor/room surface" % [test_case["room"], test_case["tier"]]):
		return false
	if not _expect(track.has_node("InnerBarrier") or track.has_node("IslandProp") or track.has_node("IslandMaterial"), "%s/%s should have island" % [test_case["room"], test_case["tier"]]):
		return false
	if not _expect(track.has_node("Wall0"), "%s/%s should have room walls" % [test_case["room"], test_case["tier"]]):
		return false
	if not _expect(track.has_node("GatePosts") and (track.get_node("GatePosts").get_child_count() >= 2), "%s/%s should have gate posts" % [test_case["room"], test_case["tier"]]):
		return false
	if not _expect(track.has_node("Checkpoint0Finish"), "%s/%s should have gates/checkpoints" % [test_case["room"], test_case["tier"]]):
		return false
	if not _expect(track.has_node("PermanentObstacles"), "%s/%s dressed should have obstacle props container" % [test_case["room"], test_case["tier"]]):
		return false
	# pre-drive blocked passage scan (static solids vs centerline + reserved lanes)
	var centerline: PackedVector2Array = generated.get("points", PackedVector2Array())
	var room_model: Dictionary = generated.get("room_model", {})
	var pre_blocked := _count_blocked_passages(track, centerline, room_model)
	if not _expect(pre_blocked == 0, "%s/%s/%s assembled world must have 0 blocked passages before run (got %d)" % [test_case["room"], test_case["tier"], "reverse" if rev else "forward", pre_blocked]):
		return false
	for _settle in 34:
		await physics_frame
	paused = false
	var started := Time.get_ticks_usec()
	var frames := 0
	var target_lap := 1
	while frames < MAX_PHYSICS_FRAMES:
		await physics_frame
		frames += 1
		var all_done := true
		for r: Node2D in ai_racers:
			if int(manager.get_racer_state(r).get("lap", 0)) < target_lap:
				all_done = false
				break
		if all_done:
			break
	var wall_ms := (Time.get_ticks_usec() - started) / 1000.0
	var total_recoveries := 0
	for ctrl: AIVehicleController in ai_controllers:
		total_recoveries += ctrl.recovery_count
	var loop_length := float(track.get_meta("loop_length", 0.0)) if track else 0.0
	var state0 := manager.get_racer_state(ai_racers[0]) if not ai_racers.is_empty() else {}
	print("V8_DRESSED_RUNTIME_LAP room=%s tier=%s seed=%d dir=%s room_seed=%d length=%.2f lap=%d expected_checkpoint=%d frames=%d lap_seconds=%.3f recoveries=%d blocked=%d wall_ms=%.2f" % [
		test_case["room"], test_case["tier"], int(test_case["seed"]), "reverse" if rev else "forward", int(identity["room_geometry_seed"]), loop_length, int(state0.get("lap", 0)), int(state0.get("expected_checkpoint", -1)), frames, float(state0.get("elapsed", manager.race_time)), total_recoveries, pre_blocked, wall_ms,
	])
	if not _expect(int(state0.get("lap", 0)) >= 1, "%s/%s/%s AI field should complete one ordered dressed lap within %d physics frames (lap=%d)" % [test_case["room"], test_case["tier"], "reverse" if rev else "forward", MAX_PHYSICS_FRAMES, int(state0.get("lap", 0))]):
		return false
	if not _expect(total_recoveries == MAX_RECOVERIES, "%s/%s/%s dressed runtime lap should need 0 recoveries (got %d)" % [test_case["room"], test_case["tier"], "reverse" if rev else "forward", total_recoveries]):
		return false
	# final post-run scan (should still be 0)
	var post_blocked := _count_blocked_passages(track, centerline, room_model)
	if not _expect(post_blocked == 0, "%s/%s/%s post-run should still have 0 blocked (got %d)" % [test_case["room"], test_case["tier"], "reverse" if rev else "forward", post_blocked]):
		return false
	current_scene = null
	root.remove_child(prototype)
	prototype.free()
	if app != null:
		app.current_race_session.clear()
	await process_frame
	await physics_frame
	return true


func _count_blocked_passages(track: Node2D, centerline: PackedVector2Array, room_model: Dictionary) -> int:
	if not is_instance_valid(track) or centerline.is_empty():
		return 0
	var probes := centerline.duplicate()
	for psg: Dictionary in room_model.get("reserved_passages", []) as Array:
		probes.append_array(psg.get("lane_centers", PackedVector2Array()) as PackedVector2Array)
	var shape := CircleShape2D.new()
	shape.radius = 125.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	var excluded: Array[RID] = []
	for racer: Node in get_nodes_in_group("race_vehicle"):
		if racer is CollisionObject2D:
			excluded.append((racer as CollisionObject2D).get_rid())
	query.exclude = excluded
	var space := track.get_world_2d().direct_space_state
	var blocked := 0
	for probe: Vector2 in probes:
		query.transform = Transform2D(0.0, probe)
		var hits := space.intersect_shape(query, 1)
		if not hits.is_empty():
			blocked += 1
	return blocked


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	Engine.time_scale = 1.0
	push_error("V8_DRESSED_RUNTIME_LAP_TEST FAIL: " + message)
	quit(1)
	return false
