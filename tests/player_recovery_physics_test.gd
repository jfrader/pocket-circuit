extends SceneTree

const RESET_SCRIPT := preload("res://scripts/race/reset_manager.gd")
const CHECKPOINT_SCRIPT := preload("res://scripts/race/checkpoint.gd")
const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")


class RecoveryRace extends Node:
	var is_running := true
	var finished := false
	var anchor := Transform2D.IDENTITY
	var recoveries := 0
	var gates := 0
	var racers: Array[Node2D] = []

	func get_last_recovery_transform() -> Transform2D:
		return anchor

	func is_racer_finished(_vehicle: Node2D) -> bool:
		return finished

	func report_recovery(_vehicle: Node2D) -> void:
		recoveries += 1

	func report_checkpoint(_checkpoint: Area2D, _vehicle: Node2D) -> void:
		gates += 1

	func get_rankings() -> Array[Node2D]:
		return racers


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for reverse in [false, true]:
		if not await _run_case(reverse):
			quit(1)
			return
	print("PLAYER_RECOVERY_PHYSICS_TEST PASS held_throttle_world_collision_and_gates")
	quit(0)


func _run_case(reverse: bool) -> bool:
	var world := Node2D.new()
	root.add_child(world)
	var manager := RecoveryRace.new()
	manager.add_to_group("race_manager")
	world.add_child(manager)
	var heading := PI if reverse else 0.0
	manager.anchor = Transform2D(heading, Vector2(0, 200).rotated(heading))
	var vehicle := VEHICLE_SCENE.instantiate() as VehicleController
	vehicle.position = Vector2(0, 400).rotated(heading)
	vehicle.rotation = heading
	world.add_child(vehicle)
	manager.racers.append(vehicle)
	var wall := StaticBody2D.new()
	wall.collision_layer = 2
	wall.position = Vector2(0, -80).rotated(heading)
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(800, 20)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	world.add_child(wall)
	var checkpoint := CHECKPOINT_SCRIPT.new() as Area2D
	checkpoint.collision_layer = 0
	checkpoint.collision_mask = 1
	checkpoint.position = Vector2(0, 120).rotated(heading)
	var sensor := CollisionShape2D.new()
	var sensor_shape := RectangleShape2D.new()
	sensor_shape.size = Vector2(300, 20)
	sensor.shape = sensor_shape
	checkpoint.add_child(sensor)
	world.add_child(checkpoint)
	var reset := RESET_SCRIPT.new()
	reset.valid_bounds = Rect2(-1500, -1500, 3000, 3000)
	var island := PackedVector2Array([
		Vector2(-400, -1000), Vector2(400, -1000), Vector2(400, -80), Vector2(-400, -80),
	])
	for index in island.size():
		island[index] = island[index].rotated(heading)
	reset.invalid_polygon = island
	world.add_child(reset)
	await physics_frame
	await physics_frame
	Input.action_press("accelerate")
	reset.recover_vehicle()
	var entered_island := false
	var farthest_travel := 0.0
	for frame in 132:
		await physics_frame
		entered_island = entered_island or not reset.is_position_valid(vehicle.position)
		farthest_travel = maxf(farthest_travel, vehicle.position.distance_to(manager.anchor.origin))
	Input.action_release("accelerate")
	print("PLAYER_RECOVERY_CASE reverse=%s recoveries=%d illegal=%s gates=%d travel=%.1f" % [reverse, manager.recoveries, entered_island, manager.gates, farthest_travel])
	var passed := manager.recoveries == 1 and not entered_island and manager.gates == 1 and farthest_travel > 50.0
	if not passed:
		push_error("PLAYER_RECOVERY_PHYSICS_TEST FAIL: held throttle must preserve world collision and gate detection, without a second reset")
	world.queue_free()
	await process_frame
	return passed
