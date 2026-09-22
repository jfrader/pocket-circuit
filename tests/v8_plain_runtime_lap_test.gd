extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const GENERATOR := preload("res://scripts/race/track_v8_development_generator.gd")
const MAX_PHYSICS_FRAMES := 3000
const MAX_RECOVERIES := 3

const CASES: Array[Dictionary] = [
	{"room": &"classic", "tier": "standard", "seed": 928},
	{"room": &"el", "tier": "compact", "seed": 1001},
]


func _initialize() -> void:
	Engine.time_scale = 1.0
	call_deferred("_run_test")


func _run_test() -> void:
	for test_case: Dictionary in CASES:
		if not await _run_case(test_case):
			return
	Engine.time_scale = 1.0
	print("V8_PLAIN_RUNTIME_LAP_TEST PASS cases=2")
	quit(0)


func _run_case(test_case: Dictionary) -> bool:
	var app := root.get_node_or_null("App")
	if app != null:
		app.current_race_session.clear()
	var generated := GENERATOR.generate_route(test_case["room"], StringName(test_case["tier"]), int(test_case["seed"]))
	if not _expect(bool(generated.get("ok", false)), "%s/%s runtime fixture should solve before scene assembly: %s" % [test_case["room"], test_case["tier"], generated.get("reason", "unknown")]):
		return false
	var room_seed := int(generated["identity"]["room_geometry_seed"])
	var identity := IDENTITIES.create_v8(&"kitchen", test_case["room"], int(test_case["seed"]), false, 1, "", "", {}, test_case["tier"], -1, 1, room_seed)
	if not _expect(not identity.is_empty(), "%s/%s should create a PC2 identity" % [test_case["room"], test_case["tier"]]):
		return false
	var event := IDENTITIES.apply_to_event(identity, ["juniper"])
	event["laps"] = 1
	event["obstacles_enabled"] = false
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
	var racer: Node2D
	var controller: AIVehicleController
	for candidate: Node in get_nodes_in_group("race_vehicle"):
		if candidate == player:
			continue
		for child: Node in candidate.get_children():
			if child is AIVehicleController:
				racer = candidate as Node2D
				controller = child as AIVehicleController
				break
	if not _expect(racer != null and controller != null, "%s/%s should create one runtime AI vehicle" % [test_case["room"], test_case["tier"]]):
		return false
	for _settle in 34:
		await physics_frame
	paused = false
	var started := Time.get_ticks_usec()
	var frames := 0
	while frames < MAX_PHYSICS_FRAMES and int(manager.get_racer_state(racer).get("lap", 0)) < 1:
		await physics_frame
		frames += 1
	var wall_ms := (Time.get_ticks_usec() - started) / 1000.0
	var state := manager.get_racer_state(racer)
	var track := prototype.get_node_or_null("Track") as Node2D
	var loop_length := float(track.get_meta("loop_length", 0.0)) if track else 0.0
	if not _expect(track != null and bool(track.get_meta("generated_track", false)) and int(track.get_meta("generator_version", 0)) == 8 and StringName(track.get_meta("room_shape", &"")) == test_case["room"] and loop_length > 0.0, "%s/%s should race the assembled v8 geometry rather than the embedded authored track" % [test_case["room"], test_case["tier"]]):
		return false
	print("V8_RUNTIME_LAP room=%s tier=%s seed=%d room_seed=%d length=%.2f lap=%d expected_checkpoint=%d frames=%d lap_seconds=%.3f recoveries=%d wall_ms=%.2f" % [
		test_case["room"], test_case["tier"], int(test_case["seed"]), int(identity["room_geometry_seed"]), loop_length, int(state.get("lap", 0)), int(state.get("expected_checkpoint", -1)), frames, float(state.get("elapsed", manager.race_time)), controller.recovery_count, wall_ms,
	])
	if not _expect(int(state.get("lap", 0)) >= 1, "%s/%s AI should complete one ordered runtime lap within %d physics frames (lap=%d)" % [test_case["room"], test_case["tier"], MAX_PHYSICS_FRAMES, int(state.get("lap", 0))]):
		return false
	if not _expect(controller.recovery_count <= MAX_RECOVERIES, "%s/%s runtime lap should need at most %d recoveries (got %d)" % [test_case["room"], test_case["tier"], MAX_RECOVERIES, controller.recovery_count]):
		return false
	current_scene = null
	root.remove_child(prototype)
	prototype.free()
	if app != null:
		app.current_race_session.clear()
	await process_frame
	await physics_frame
	return true


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	Engine.time_scale = 1.0
	push_error("V8_PLAIN_RUNTIME_LAP_TEST FAIL: " + message)
	quit(1)
	return false
