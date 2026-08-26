extends SceneTree

const RACE_MANAGER_SCRIPT := preload("res://scripts/race/race_manager.gd")

class TestCheckpoint extends Area2D:
	var checkpoint_index: int
	var is_finish_line: bool
	var recovery_rotation: float
	var recovery_offset := 20.0

	func _init(index: int, finish_line: bool) -> void:
		checkpoint_index = index
		is_finish_line = finish_line
		position = Vector2(float(index) * 100.0, float(index % 2) * 40.0)
		recovery_rotation = float(index) * 0.1

	func get_recovery_transform() -> Transform2D:
		var forward := Vector2.UP.rotated(recovery_rotation)
		return Transform2D(recovery_rotation, position + forward * recovery_offset)


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var manager := RACE_MANAGER_SCRIPT.new() as RaceManager
	manager.laps_to_finish = 1
	manager.set_reverse_direction(true)
	var checkpoints: Array = []
	for index in 8:
		checkpoints.append(TestCheckpoint.new(index, index == 0))
	manager.configure_checkpoints(checkpoints)
	var order: Array[int] = []
	for checkpoint: Node in manager.get_ordered_checkpoints():
		order.append(int(checkpoint.get("checkpoint_index")))
	if not _expect(order == [0, 7, 6, 5, 4, 3, 2, 1], "reverse order should be finish, then checkpoints 7 through 1"):
		return
	if not _expect(manager.direction == &"reverse" and manager.is_reverse_direction(), "race manager should expose reverse direction"):
		return

	var racer := Node2D.new()
	manager.register_racer(racer, "Reverse Driver", "Rustbug", true)
	manager.prepare_race()
	manager.start_race()
	if not _expect(manager.get_expected_checkpoint(racer) == 7, "a reverse race should target checkpoint 7 first"):
		return
	var checkpoint_seven := checkpoints[7] as TestCheckpoint
	if not _expect(manager.report_checkpoint(checkpoint_seven, racer), "checkpoint 7 should be legal first in reverse"):
		return
	var recovery := manager.get_last_recovery_transform(racer)
	var expected_rotation := wrapf(checkpoint_seven.recovery_rotation + PI, -PI, PI)
	var original_offset := Vector2.UP.rotated(checkpoint_seven.recovery_rotation) * checkpoint_seven.recovery_offset
	if not _expect(absf(angle_difference(recovery.get_rotation(), expected_rotation)) < 0.0001, "reverse recovery should rotate the vehicle by 180 degrees"):
		return
	if not _expect(recovery.origin.is_equal_approx(checkpoint_seven.position - original_offset), "reverse recovery should mirror the forward checkpoint offset"):
		return
	for index in range(6, 0, -1):
		if not _expect(manager.report_checkpoint(checkpoints[index], racer), "reverse checkpoint sequence should descend deterministically"):
			return
	if not _expect(manager.report_checkpoint(checkpoints[0], racer), "finish should complete the reverse lap"):
		return
	if not _expect(manager.is_racer_finished(racer) and manager.lap_count == 1, "reverse finish should complete the race normally"):
		return

	print("REVERSE_RACE_TEST PASS")
	manager.free()
	racer.free()
	for checkpoint: Node in checkpoints:
		checkpoint.free()
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("REVERSE_RACE_TEST FAIL: " + message)
	quit(1)
	return false
