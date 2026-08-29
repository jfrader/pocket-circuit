extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const CHECKPOINTS_PER_LAP := 8
const MAX_PHYSICS_FRAMES := 2400
const MAX_RECOVERIES_PER_LAP := 2
const THEMES: Array[StringName] = [&"kitchen", &"workshop", &"office"]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	Engine.time_scale = 1.0
	for theme: StringName in THEMES:
		if not await _run_direction(theme, false):
			return
		if not await _run_direction(theme, true):
			return
	Engine.time_scale = 1.0
	print("AI_RACE_SMOKE_TEST PASS all_themes")
	quit(0)


func _run_direction(theme: StringName, reverse: bool) -> bool:
	var direction_label := "reverse" if reverse else "forward"
	var prototype := PROTOTYPE_SCENE.instantiate()
	prototype.set("_session", {"event": {"theme": theme, "reverse": reverse}})
	var manager := prototype.get_node("RaceManager") as RaceManager
	manager.set_reverse_direction(reverse)
	root.add_child(prototype)
	current_scene = prototype
	var player := get_first_node_in_group("player_vehicle") as RigidBody2D
	if player:
		player.freeze = true
		player.collision_layer = 0
		player.collision_mask = 0

	for settle in 6:
		await create_timer(0.1).timeout
	paused = false

	var checkpoint_counts: Dictionary = {}
	var ai_vehicles: Array[Node2D] = []
	for racer: Node in get_nodes_in_group("race_vehicle"):
		if racer != player and _has_ai_controller(racer):
			ai_vehicles.append(racer as Node2D)
			checkpoint_counts[racer] = 0
	manager.racer_checkpoint_passed.connect(func(racer: Node2D, _checkpoint_index: int) -> void:
		if checkpoint_counts.has(racer):
			checkpoint_counts[racer] = int(checkpoint_counts[racer]) + 1
	)

	var frame := 0
	while frame < MAX_PHYSICS_FRAMES and not _all_completed_lap(ai_vehicles, checkpoint_counts):
		await physics_frame
		frame += 1

	if not _expect(ai_vehicles.size() == 3, "%s %s prototype should create a full three-opponent field" % [theme, direction_label]):
		return false
	for racer: Node2D in ai_vehicles:
		var controller := _get_ai_controller(racer)
		print(
			"AI_RACE_STATE %s %s %s checkpoints=%d expected=%d position=%s speed=%.1f recoveries=%d recovering=%s stuck=%.2f"
			% [
				theme,
				direction_label,
				racer.name,
				int(checkpoint_counts.get(racer, 0)),
				manager.get_expected_checkpoint(racer),
				str(racer.global_position.round()),
				float(racer.get("speed")),
				controller.recovery_count if controller else -1,
				str(controller.get("_recovering")) if controller else "missing",
				float(controller.get("_stuck_time")) if controller else -1.0,
			]
		)
	for racer: Node2D in ai_vehicles:
		if not _expect(
			int(checkpoint_counts.get(racer, 0)) >= CHECKPOINTS_PER_LAP,
			"%s %s %s should complete a legal lap (checkpoints=%d)" % [theme, direction_label, racer.name, int(checkpoint_counts.get(racer, 0))]
		):
			return false
		var controller := _get_ai_controller(racer)
		if not _expect(
			controller != null and controller.recovery_count <= MAX_RECOVERIES_PER_LAP,
			"%s %s %s should not rely on repeated recovery (recoveries=%d)" % [theme, direction_label, racer.name, controller.recovery_count if controller else -1]
		):
			return false
	print("AI_RACE_DIRECTION_PASS %s %s frames=%d checkpoints=%s" % [theme, direction_label, frame, str(checkpoint_counts.values())])
	current_scene = null
	prototype.queue_free()
	await process_frame
	return true


func _all_completed_lap(ai_vehicles: Array[Node2D], checkpoint_counts: Dictionary) -> bool:
	if ai_vehicles.is_empty():
		return false
	for racer: Node2D in ai_vehicles:
		if int(checkpoint_counts.get(racer, 0)) < CHECKPOINTS_PER_LAP:
			return false
	return true


func _has_ai_controller(racer: Node) -> bool:
	return _get_ai_controller(racer) != null


func _get_ai_controller(racer: Node) -> AIVehicleController:
	for child: Node in racer.get_children():
		if child is AIVehicleController:
			return child as AIVehicleController
	return null


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	Engine.time_scale = 1.0
	push_error("AI_RACE_SMOKE_TEST FAIL: " + message)
	quit(1)
	return false
