extends SceneTree

const RACE_MANAGER_SCRIPT := preload("res://scripts/race/race_manager.gd")

class TestCheckpoint extends Area2D:
	var checkpoint_index: int
	var is_finish_line: bool

	func _init(index: int, finish_line: bool, checkpoint_position: Vector2) -> void:
		checkpoint_index = index
		is_finish_line = finish_line
		position = checkpoint_position

	func get_recovery_transform() -> Transform2D:
		return Transform2D(0.0, position)


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _check_finish_sensor_required():
		return
	var manager := RACE_MANAGER_SCRIPT.new() as RaceManager
	manager.laps_to_finish = 2
	var checkpoints: Array = [
		TestCheckpoint.new(0, true, Vector2(0.0, 0.0)),
		TestCheckpoint.new(1, false, Vector2(100.0, 0.0)),
		TestCheckpoint.new(2, false, Vector2(200.0, 0.0)),
	]
	manager.configure_checkpoints(checkpoints)

	var racers: Array[Node2D] = []
	for index in 4:
		var racer := Node2D.new()
		racer.position = Vector2(float(index) * -10.0, 0.0)
		racers.append(racer)
		manager.register_racer(racer, "Driver %d" % (index + 1), "Rustbug", index == 0)
	var results_emitted := [0]
	manager.results_ready.connect(func(_results: Array) -> void: results_emitted[0] += 1)
	manager.prepare_race()
	manager.start_race()

	if not _expect(manager.get_expected_checkpoint(racers[0]) == 1, "race should begin at checkpoint 1"):
		return
	if not _expect(not manager.report_checkpoint(checkpoints[2], racers[0]), "out-of-order checkpoint should be rejected"):
		return
	if not _expect(manager.is_racer_wrong_way(racers[0]), "out-of-order checkpoint should mark wrong way"):
		return
	manager.report_recovery(racers[0])
	if not _expect(not manager.is_racer_wrong_way(racers[0]), "recovery should clear stale wrong-way state"):
		return
	if not _pass_lap(manager, checkpoints, racers[0]):
		return
	if not _expect(manager.lap_count == 1 and manager.current_checkpoint_index == 1, "player compatibility state should track lap and next gate"):
		return
	if not _pass_lap(manager, checkpoints, racers[1]):
		return

	manager.advance_race_time(2.0)
	if not _pass_lap(manager, checkpoints, racers[1]):
		return
	if not _expect(manager.is_racer_finished(racers[1]) and manager.get_racer_position(racers[1]) == 1, "first finisher should hold first place"):
		return

	manager.advance_race_time(1.0)
	if not _pass_lap(manager, checkpoints, racers[0]):
		return
	if not _expect(manager.is_racer_finished(racers[0]) and manager.get_racer_position(racers[0]) == 2, "second finisher should retain finish order"):
		return

	if not _expect(manager.report_checkpoint(checkpoints[1], racers[2]), "third racer should pass checkpoint 1"):
		return
	if not _expect(manager.report_checkpoint(checkpoints[2], racers[2]), "third racer should pass checkpoint 2"):
		return
	if not _expect(manager.report_checkpoint(checkpoints[1], racers[3]), "fourth racer should pass checkpoint 1"):
		return
	var rankings := manager.refresh_rankings()
	if not _expect(rankings == [racers[1], racers[0], racers[2], racers[3]], "ranking should sort finishers first, then legal checkpoint progress"):
		return

	if not _expect(manager.report_checkpoint(checkpoints[0], racers[2]), "third racer should complete lap 1"):
		return
	if not _pass_lap(manager, checkpoints, racers[2]):
		return
	if not _expect(manager.report_checkpoint(checkpoints[2], racers[3]), "fourth racer should pass checkpoint 2"):
		return
	if not _expect(manager.report_checkpoint(checkpoints[0], racers[3]), "fourth racer should complete lap 1"):
		return
	if not _pass_lap(manager, checkpoints, racers[3]):
		return
	if not _expect(results_emitted[0] == 1 and not manager.is_running, "results should emit once after every racer finishes"):
		return
	var results := manager.get_results()
	if not _expect(results.size() == 4 and int(results[0]["position"]) == 1 and String(results[0]["driver_name"]) == "Driver 2", "results should preserve finish order and identity"):
		return

	print("RACE_MANAGER_TEST PASS")
	manager.free()
	for checkpoint: Node in checkpoints:
		checkpoint.free()
	for racer: Node2D in racers:
		racer.free()
	quit(0)


func _pass_lap(manager: RaceManager, checkpoints: Array, racer: Node2D) -> bool:
	for checkpoint: Area2D in [checkpoints[1], checkpoints[2], checkpoints[0]]:
		if not _expect(manager.report_checkpoint(checkpoint, racer), "legal checkpoint sequence should be accepted"):
			return false
	return true


func _check_finish_sensor_required() -> bool:
	var manager := RACE_MANAGER_SCRIPT.new() as RaceManager
	manager.laps_to_finish = 1
	var checkpoints: Array = [
		TestCheckpoint.new(0, true, Vector2(0.0, 0.0)),
		TestCheckpoint.new(1, false, Vector2(100.0, 0.0)),
		TestCheckpoint.new(2, false, Vector2(200.0, 0.0)),
	]
	manager.configure_checkpoints(checkpoints)
	var racer := Node2D.new()
	manager.register_racer(racer, "Apron Cutter", "Rustbug", true)
	manager.prepare_race()
	manager.start_race()
	if not _expect(manager.report_checkpoint(checkpoints[1], racer) and manager.report_checkpoint(checkpoints[2], racer), "ordered gates before the finish should be accepted"):
		return false
	if not _expect(not manager.report_checkpoint(checkpoints[1], racer), "cutting from the finish vicinity directly to the next gate must not substitute for crossing the finish sensor"):
		return false
	if not _expect(manager.lap_count == 0 and manager.get_expected_checkpoint(racer) == 0 and not manager.is_racer_finished(racer), "a skipped finish sensor must count no lap and preserve the expected finish gate"):
		return false
	if not _expect(manager.report_checkpoint(checkpoints[0], racer) and manager.lap_count == 1, "crossing the expected finish after every ordered gate should complete the legal lap"):
		return false
	manager.free()
	racer.free()
	for checkpoint: Node in checkpoints:
		checkpoint.free()
	return true


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("RACE_MANAGER_TEST FAIL: " + message)
	quit(1)
	return false
