extends SceneTree

const RESET_MANAGER_SCRIPT := preload("res://scripts/race/reset_manager.gd")

class TestRaceManager extends Node:
	var is_running := false
	var finished := false

	func is_racer_finished(_vehicle: Node2D) -> bool:
		return finished


func _initialize() -> void:
	var reset_manager := RESET_MANAGER_SCRIPT.new()
	var vehicle := RigidBody2D.new()
	var race_manager := TestRaceManager.new()
	reset_manager.set("_vehicle", vehicle)
	reset_manager.set("_race_manager", race_manager)
	if not _expect(not bool(reset_manager.call("_can_recover")), "recovery should be disabled while the race is stopped"):
		return
	race_manager.is_running = true
	if not _expect(bool(reset_manager.call("_can_recover")), "an active unfinished racer should be recoverable"):
		return
	race_manager.finished = true
	if not _expect(not bool(reset_manager.call("_can_recover")), "recovery should be disabled after the player finishes"):
		return
	reset_manager.free()
	vehicle.free()
	race_manager.free()
	print("RESET_MANAGER_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("RESET_MANAGER_TEST FAIL: " + message)
	quit(1)
	return false
