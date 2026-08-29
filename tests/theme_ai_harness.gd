extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const CHECKPOINTS_PER_LAP := 8
const MAX_PHYSICS_FRAMES := 2400
const MAX_RECOVERIES_PER_LAP := 2
const OBSTACLE_NAMES: Array[String] = ["MugA", "MugB", "CerealA", "CerealB", "Sponge", "Fork", "Ruler", "Apple", "Lime", "Cup", "Spoon"]
const THEME_SCENES: Dictionary = {
	&"kitchen": "res://scenes/tracks/kitchen_graybox.tscn",
	&"workshop": "res://scenes/tracks/workshop_workbench.tscn",
	&"office": "res://scenes/tracks/office_desk.tscn",
}

var _theme: StringName = &"kitchen"


func _initialize() -> void:
	var env_theme := OS.get_environment("PC_THEME")
	if env_theme in [&"workshop", &"office", &"kitchen"]:
		_theme = StringName(env_theme)
	call_deferred("_run_test")


func _run_test() -> void:
	print("THEME_AI_HARNESS theme=%s" % _theme)
	if not await _verify_scene_contract():
		return
	if not await _run_direction(false):
		return
	if not await _run_direction(true):
		return
	print("THEME_AI_HARNESS PASS %s" % _theme)
	quit(0)


func _verify_scene_contract() -> bool:
	var packed := load(String(THEME_SCENES[_theme])) as PackedScene
	if not _expect(packed != null, "%s track scene should exist" % _theme):
		return false
	var track := packed.instantiate()
	root.add_child(track)
	var checkpoints: Array[Node2D] = []
	for child: Node in track.get_children():
		if child.is_in_group("track_checkpoints"):
			checkpoints.append(child as Node2D)
	if not _expect(checkpoints.size() >= 8, "%s should define a finish line and seven lap checkpoints" % _theme):
		return false
	for obstacle_name: String in OBSTACLE_NAMES:
		var obstacle := track.get_node_or_null(obstacle_name) as StaticBody2D
		if obstacle == null:
			continue
		for checkpoint: Node2D in checkpoints:
			if not _expect(obstacle.position.distance_to(checkpoint.position) >= 145.0, "%s obstacle %s should not block checkpoint %s (%.0f)" % [_theme, obstacle_name, checkpoint.name, obstacle.position.distance_to(checkpoint.position)]):
				return false
	var finish: Area2D
	for child: Node in track.get_children():
		if child is Area2D and bool(child.get("is_finish_line")):
			finish = child as Area2D
			break
	if not _expect(finish != null, "%s should define a finish-line checkpoint" % _theme):
		return false
	var shape := (finish.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	if not _expect(shape.size.x >= 272.0 or shape.size.y >= 272.0, "%s finish gate should span the corridor" % _theme):
		return false
	for container_name: String in ["GridForward", "GridReverse"]:
		var container := track.get_node_or_null(container_name) as Node2D
		if not _expect(container != null and container.get_child_count() == 4, "%s should place four %s spawn markers" % [_theme, container_name]):
			return false
	track.queue_free()
	await process_frame
	return true


func _run_direction(reverse: bool) -> bool:
	var direction_label := "reverse" if reverse else "forward"
	var prototype := PROTOTYPE_SCENE.instantiate()
	prototype.set("_session", {"event": {"theme": _theme, "reverse": reverse}})
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

	for racer: Node2D in ai_vehicles:
		var controller := _get_ai_controller(racer)
		print(
			"THEME_AI_STATE %s %s %s checkpoints=%d expected=%d position=%s speed=%.1f recoveries=%d"
			% [
				_theme,
				direction_label,
				racer.name,
				int(checkpoint_counts.get(racer, 0)),
				manager.get_expected_checkpoint(racer),
				str(racer.global_position.round()),
				float(racer.get("speed")),
				controller.recovery_count if controller else -1,
			]
		)
	for racer: Node2D in ai_vehicles:
		if not _expect(
			int(checkpoint_counts.get(racer, 0)) >= CHECKPOINTS_PER_LAP,
			"%s %s %s should complete a legal lap (checkpoints=%d)" % [_theme, direction_label, racer.name, int(checkpoint_counts.get(racer, 0))]
		):
			return false
		var controller := _get_ai_controller(racer)
		if not _expect(
			controller != null and controller.recovery_count <= MAX_RECOVERIES_PER_LAP,
			"%s %s %s should not rely on repeated recovery (recoveries=%d)" % [_theme, direction_label, racer.name, controller.recovery_count if controller else -1]
		):
			return false
	print("THEME_AI_DIRECTION_PASS %s %s frames=%d" % [_theme, direction_label, frame])
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
	push_error("THEME_AI_HARNESS FAIL: " + message)
	quit(1)
	return false
