extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const CHECKPOINTS_PER_LAP := 8
const MAX_PHYSICS_FRAMES := 2400
const MAX_RECOVERIES_PER_LAP := 3
const MAX_LAP_SECONDS: Dictionary = {
	"sunday_drive": 38.0,
	"club_circuit": 34.0,
	"clockwork": 32.0,
}
const OBSTACLE_NAMES: Array[String] = ["MugA", "MugB", "CerealA", "CerealB", "Sponge", "Fork", "Ruler", "Apple", "Lime", "Cup", "Spoon"]
const THEME_SCENES: Dictionary = {
	&"kitchen": "res://scenes/tracks/kitchen_circuit.tscn",
	&"workshop": "res://scenes/tracks/workshop_workbench.tscn",
	&"office": "res://scenes/tracks/office_desk.tscn",
}

var _theme: StringName = &"kitchen"
var _room: StringName = &"classic"
var _seed := -1
var _direction: StringName = &"both"
var _difficulty := "club_circuit"


func _initialize() -> void:
	var env_theme := OS.get_environment("PC_THEME")
	if env_theme in [&"workshop", &"office", &"kitchen"]:
		_theme = StringName(env_theme)
	var env_room := OS.get_environment("PC_ROOM")
	if env_room in [&"classic", &"wide", &"tall", &"long", &"square", &"el"]:
		_room = StringName(env_room)
	var env_seed := OS.get_environment("PC_SEED")
	if env_seed.is_valid_int():
		_seed = int(env_seed)
	var env_direction := OS.get_environment("PC_DIRECTION")
	if env_direction in [&"forward", &"reverse", &"both"]:
		_direction = StringName(env_direction)
	var env_difficulty := OS.get_environment("PC_DIFFICULTY")
	if MAX_LAP_SECONDS.has(env_difficulty):
		_difficulty = env_difficulty
	call_deferred("_run_test")


func _run_test() -> void:
	print("THEME_AI_HARNESS track=%s difficulty=%s" % [_track_label(), _difficulty])
	if not await _verify_scene_contract():
		return
	if _direction != &"reverse" and not await _run_direction(false):
		return
	if _direction != &"forward" and not await _run_direction(true):
		return
	print("THEME_AI_HARNESS PASS %s" % _track_label())
	quit(0)


func _verify_scene_contract() -> bool:
	var override := OS.get_environment("PC_TRACK_SCENE")
	var packed: PackedScene
	if _seed >= 0:
		var built: Dictionary = TRACK_BUILDER.build_packed(_theme, _room, _seed)
		packed = built.get("scene") as PackedScene
	else:
		var scene_path := override if not override.is_empty() else String(THEME_SCENES[_theme])
		packed = load(scene_path) as PackedScene
	if not _expect(packed != null, "%s track scene should exist" % _track_label()):
		return false
	var track := packed.instantiate()
	root.add_child(track)
	var checkpoints: Array[Node2D] = []
	for child: Node in track.get_children():
		if child.is_in_group("track_checkpoints"):
			checkpoints.append(child as Node2D)
	if not _expect(checkpoints.size() >= 8, "%s should define a finish line and seven lap checkpoints" % _track_label()):
		return false
	for obstacle_name: String in OBSTACLE_NAMES:
		var obstacle := track.get_node_or_null(obstacle_name) as StaticBody2D
		if obstacle == null:
			continue
		for checkpoint: Node2D in checkpoints:
			if not _expect(obstacle.position.distance_to(checkpoint.position) >= 145.0, "%s obstacle %s should not block checkpoint %s (%.0f)" % [_track_label(), obstacle_name, checkpoint.name, obstacle.position.distance_to(checkpoint.position)]):
				return false
	var finish: Area2D
	for child: Node in track.get_children():
		if child is Area2D and bool(child.get("is_finish_line")):
			finish = child as Area2D
			break
	if not _expect(finish != null, "%s should define a finish-line checkpoint" % _track_label()):
		return false
	var shape := (finish.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	if not _expect(shape.size.x >= 272.0 or shape.size.y >= 272.0, "%s finish gate should span the corridor" % _track_label()):
		return false
	for container_name: String in ["GridForward", "GridReverse"]:
		if _seed < 0 and _theme == &"kitchen":
			continue
		var container := track.get_node_or_null(container_name) as Node2D
		if not _expect(container != null and container.get_child_count() == 4, "%s should place four %s spawn markers" % [_track_label(), container_name]):
			return false
	track.queue_free()
	await process_frame
	return true


func _run_direction(reverse: bool) -> bool:
	var direction_label := "reverse" if reverse else "forward"
	var prototype := PROTOTYPE_SCENE.instantiate()
	var event := {"theme": _theme, "reverse": reverse}
	if _seed >= 0:
		event.merge({"circuit": "generated", "room": _room, "seed": _seed})
	prototype.set("_session", {"event": event, "difficulty": _difficulty})
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
	var lap_times: Dictionary = {}
	var ai_vehicles: Array[Node2D] = []
	for racer: Node in get_nodes_in_group("race_vehicle"):
		if racer != player and _has_ai_controller(racer):
			ai_vehicles.append(racer as Node2D)
			checkpoint_counts[racer] = 0
	manager.racer_checkpoint_passed.connect(func(racer: Node2D, _checkpoint_index: int) -> void:
		if checkpoint_counts.has(racer):
			checkpoint_counts[racer] = int(checkpoint_counts[racer]) + 1
	)
	manager.racer_lap_completed.connect(func(racer: Node2D, lap: int) -> void:
		if lap == 1 and checkpoint_counts.has(racer) and not lap_times.has(racer):
			lap_times[racer] = float(manager.get_racer_state(racer).get("elapsed", manager.race_time))
	)

	var frame := 0
	while frame < MAX_PHYSICS_FRAMES and not _all_completed_lap(ai_vehicles, checkpoint_counts):
		await physics_frame
		frame += 1

	for racer: Node2D in ai_vehicles:
		var controller := _get_ai_controller(racer)
		var lap_time := float(lap_times.get(racer, INF))
		print(
			"AI_RACE_LAP %s %s difficulty=%s racer=%s lap_seconds=%.3f recoveries=%d"
			% [
				_track_label(),
				direction_label,
				controller.difficulty if controller else _difficulty,
				racer.name,
				lap_time,
				controller.recovery_count if controller else -1,
			]
		)
		print(
			"THEME_AI_STATE %s %s %s checkpoints=%d expected=%d position=%s speed=%.1f recoveries=%d"
			% [
				_track_label(),
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
			"%s %s %s should complete a legal lap (checkpoints=%d)" % [_track_label(), direction_label, racer.name, int(checkpoint_counts.get(racer, 0))]
		):
			return false
		var controller := _get_ai_controller(racer)
		if not _expect(
			controller != null and controller.recovery_count <= MAX_RECOVERIES_PER_LAP,
			"%s %s %s should not rely on repeated recovery (recoveries=%d)" % [_track_label(), direction_label, racer.name, controller.recovery_count if controller else -1]
		):
			return false
		var max_lap_seconds := float(MAX_LAP_SECONDS[_difficulty])
		if not _expect(
			float(lap_times.get(racer, INF)) <= max_lap_seconds,
			"%s %s %s should meet the %s pace floor (lap=%.3fs, max=%.1fs)"
			% [
				_track_label(),
				direction_label,
				racer.name,
				_difficulty,
				float(lap_times.get(racer, INF)),
				max_lap_seconds,
			]
		):
			return false
	print("THEME_AI_DIRECTION_PASS %s %s frames=%d" % [_track_label(), direction_label, frame])
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


func _track_label() -> String:
	return "%s/%s/%d" % [_theme, _room, _seed] if _seed >= 0 else String(_theme)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("THEME_AI_HARNESS FAIL: " + message)
	quit(1)
	return false
