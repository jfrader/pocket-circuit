extends SceneTree

const RESET_MANAGER_SCRIPT := preload("res://scripts/race/reset_manager.gd")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")

class TestRaceManager extends Node:
	var is_running := false
	var finished := false

	func is_racer_finished(_vehicle: Node2D) -> bool:
		return finished

	func get_last_recovery_transform() -> Transform2D:
		return Transform2D(0.0, Vector2(24.0, 36.0))


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var reset_manager := RESET_MANAGER_SCRIPT.new()
	var vehicle := RigidBody2D.new()
	var race_manager := TestRaceManager.new()
	vehicle.add_to_group("player_vehicle")
	race_manager.add_to_group("race_manager")
	root.add_child(vehicle)
	root.add_child(race_manager)
	root.add_child(reset_manager)
	reset_manager.set("_vehicle", vehicle)
	reset_manager.set("_race_manager", race_manager)
	reset_manager.valid_polygon = PackedVector2Array([Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)])
	reset_manager.invalid_polygon = PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)])
	if not _expect(reset_manager.is_position_valid(Vector2(60, 0)) and not reset_manager.is_position_valid(Vector2.ZERO), "recovery bounds should allow the room apron while rejecting the raised island interior"):
		return
	if not _expect(not bool(reset_manager.call("_can_recover")), "recovery should be disabled while the race is stopped"):
		return
	race_manager.is_running = true
	if not _expect(bool(reset_manager.call("_can_recover")), "an active unfinished racer should be recoverable"):
		return
	race_manager.finished = true
	if not _expect(not bool(reset_manager.call("_can_recover")), "recovery should be disabled after the player finishes"):
		return

	race_manager.finished = false
	vehicle.collision_layer = 5
	vehicle.collision_mask = 7
	reset_manager.ghost_duration = 0.05
	reset_manager.call("recover_vehicle")
	paused = true
	await create_timer(0.08, true).timeout
	if not _expect(bool(reset_manager.get("_recovering")) and vehicle.collision_layer == 0 and vehicle.collision_mask == 0, "recovery ghost time must not expire while paused"):
		return
	paused = false
	await create_timer(0.08).timeout
	if not _expect(not bool(reset_manager.get("_recovering")) and vehicle.collision_layer == 5 and vehicle.collision_mask == 7, "recovery should restore collisions after unpaused ghost time"):
		return

	var ai_controller := AI_CONTROLLER_SCRIPT.new()
	var ai_vehicle := VehicleController.new()
	var ai_race_manager := RaceManager.new()
	ai_controller.set_physics_process(false)
	ai_vehicle.set_physics_process(false)
	root.add_child(ai_vehicle)
	root.add_child(ai_race_manager)
	root.add_child(ai_controller)
	ai_controller.set("vehicle", ai_vehicle)
	ai_controller.set("race_manager", ai_race_manager)
	ai_vehicle.collision_layer = 9
	ai_vehicle.collision_mask = 11
	ai_controller.call("_recover_vehicle")
	paused = true
	await create_timer(1.1, true).timeout
	if not _expect(bool(ai_controller.get("_recovering")) and ai_vehicle.collision_layer == 0 and ai_vehicle.collision_mask == 0, "AI recovery ghost time must not expire while paused"):
		return
	paused = false
	await create_timer(1.1).timeout
	if not _expect(not bool(ai_controller.get("_recovering")) and ai_vehicle.collision_layer == 9 and ai_vehicle.collision_mask == 11, "AI recovery should restore collisions after unpaused ghost time"):
		return

	root.remove_child(reset_manager)
	root.remove_child(vehicle)
	root.remove_child(race_manager)
	root.remove_child(ai_controller)
	root.remove_child(ai_vehicle)
	root.remove_child(ai_race_manager)
	reset_manager.free()
	vehicle.free()
	race_manager.free()
	ai_controller.free()
	ai_vehicle.free()
	ai_race_manager.free()
	print("RESET_MANAGER_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("RESET_MANAGER_TEST FAIL: " + message)
	quit(1)
	return false
