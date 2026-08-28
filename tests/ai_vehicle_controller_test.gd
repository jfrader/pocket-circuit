extends SceneTree

const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")


class TestCheckpoint extends Area2D:
	var checkpoint_index: int
	var is_finish_line: bool

	func _init(index: int, finish_line: bool, checkpoint_position: Vector2, checkpoint_rotation: float = 0.0) -> void:
		checkpoint_index = index
		is_finish_line = finish_line
		position = checkpoint_position
		rotation = checkpoint_rotation

	func get_recovery_transform() -> Transform2D:
		return Transform2D(rotation, position)


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var manager := RaceManager.new()
	var vehicle := VehicleController.new()
	var controller := AI_CONTROLLER_SCRIPT.new() as AIVehicleController
	var checkpoints: Array = [
		TestCheckpoint.new(0, true, Vector2(-700.0, 360.0), PI * 0.5),
		TestCheckpoint.new(1, false, Vector2(-220.0, 360.0)),
		TestCheckpoint.new(2, false, Vector2(440.0, 360.0)),
		TestCheckpoint.new(3, false, Vector2(735.0, 100.0), PI * 0.5),
		TestCheckpoint.new(4, false, Vector2(450.0, -365.0)),
		TestCheckpoint.new(5, false, Vector2(-130.0, -365.0)),
		TestCheckpoint.new(6, false, Vector2(-735.0, -150.0), PI * 0.5),
		TestCheckpoint.new(7, false, Vector2(-735.0, 170.0), PI * 0.5),
	]
	root.add_child(manager)
	root.add_child(vehicle)
	vehicle.add_child(controller)
	vehicle.set_physics_process(false)
	controller.set_physics_process(false)
	manager.configure_checkpoints(checkpoints)
	manager.register_racer(vehicle, "Test AI", "Rustbug")
	controller.configure(vehicle, manager, 0.0)
	manager.prepare_race()
	manager.start_race()

	var corner_guide := controller.call("_checkpoint_entry_guide_position", 3) as Vector2
	var raw_corner := Vector2(735.0, 360.0)
	if not _expect(
		is_equal_approx(corner_guide.x, raw_corner.x) and corner_guide.y > raw_corner.y + 10.0,
		"corner clearance should sit outside the incoming straight without extending its overshoot axis"
	):
		return
	var straight_guide: Variant = controller.call("_checkpoint_entry_guide_position", 2)
	if not _expect(straight_guide == null, "straight checkpoint segments should not add redundant guides"):
		return

	manager.report_checkpoint(checkpoints[1], vehicle)
	manager.report_checkpoint(checkpoints[2], vehicle)
	vehicle.global_position = Vector2(350.0, 360.0)
	vehicle.rotation = PI * 0.5
	vehicle.linear_velocity = Vector2.RIGHT * 520.0
	vehicle.speed = 520.0
	controller.call("_physics_process", 1.0 / 60.0)
	if not _expect(float(vehicle.get("_external_brake")) > 0.0, "AI should brake before a sharp corner"):
		return
	if not _expect(not bool(vehicle.get("_external_handbrake")), "AI cornering should remain stable without handbrake spins"):
		return
	if not _expect(absf(float(vehicle.get("_external_steer"))) < 0.8, "steering should ramp instead of snapping to full lock"):
		return

	vehicle.speed = 60.0
	vehicle.linear_velocity = Vector2.ZERO
	controller.set("_guide_checkpoint_index", 3)
	controller.set("_guide_reached", true)
	for _step in 6:
		controller.call("_physics_process", 0.5)
	if not _expect(bool(controller.get("_recovering")), "AI should recover when it makes no positional progress even if reported speed is nonzero"):
		return
	if not _expect(not bool(controller.get("_guide_reached")), "recovery should require the safe corner guide again"):
		return
	if not _expect(int(controller.get("_guide_checkpoint_index")) == -1, "recovery should reset the active route phase"):
		return

	root.remove_child(vehicle)
	root.remove_child(manager)
	vehicle.free()
	manager.free()
	for checkpoint: Node in checkpoints:
		checkpoint.free()
	print("AI_VEHICLE_CONTROLLER_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AI_VEHICLE_CONTROLLER_TEST FAIL: " + message)
	quit(1)
	return false
