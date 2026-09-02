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
	var manager := RACE_MANAGER_SCRIPT.new() as RaceManager
	manager.laps_to_finish = 1
	manager.finish_grace_seconds = 0.5
	var checkpoints: Array = [
		TestCheckpoint.new(0, true, Vector2(0.0, 0.0)),
		TestCheckpoint.new(1, false, Vector2(100.0, 0.0)),
		TestCheckpoint.new(2, false, Vector2(200.0, 0.0)),
	]
	manager.configure_checkpoints(checkpoints)
	var racers: Array[Node2D] = []
	for index in 4:
		var racer := Node2D.new()
		racers.append(racer)
		manager.register_racer(racer, "Driver %d" % index, "Rustbug", index == 0)
	var emitted_results: Array = []
	manager.results_ready.connect(func(results: Array) -> void: emitted_results.append(results))
	manager.prepare_race()
	manager.start_race()

	manager.report_checkpoint(checkpoints[1], racers[1])
	manager.report_checkpoint(checkpoints[2], racers[1])
	manager.report_checkpoint(checkpoints[1], racers[2])
	for checkpoint: Area2D in [checkpoints[1], checkpoints[2], checkpoints[0]]:
		manager.report_checkpoint(checkpoint, racers[0])
	var player_position := manager.get_racer_position(racers[0])
	manager.advance_race_time(0.49)
	if not _expect(emitted_results.is_empty() and manager.is_running, "the field should receive the full grace period"):
		return
	manager.advance_race_time(0.02)
	if not _expect(emitted_results.size() == 1 and not manager.is_running, "grace expiry should finalize results exactly once"):
		return
	var results: Array = emitted_results[0]
	if not _expect(player_position == 1 and int(results[0]["position"]) == 1 and not bool(results[0]["dnf"]), "grace finalization must preserve the player's finish position"):
		return
	if not _expect(results[1]["vehicle"] == racers[1] and results[2]["vehicle"] == racers[2] and results[3]["vehicle"] == racers[3], "DNFs should retain current legal checkpoint ranking"):
		return
	if not _expect(bool(results[1]["dnf"]) and bool(results[2]["dnf"]) and bool(results[3]["dnf"]), "every unfinished racer should be marked DNF"):
		return
	manager.finalize_remaining_racers_as_dnf()
	if not _expect(emitted_results.size() == 1, "manual finalization should be idempotent"):
		return
	manager.free()
	for racer: Node2D in racers:
		racer.free()

	manager = RACE_MANAGER_SCRIPT.new() as RaceManager
	manager.laps_to_finish = 1
	manager.finish_grace_seconds = 0.5
	manager.configure_checkpoints(checkpoints)
	racers.clear()
	for index in 4:
		var racer := Node2D.new()
		racers.append(racer)
		manager.register_racer(racer, "AI-first Driver %d" % index, "Rustbug", index == 0)
	emitted_results.clear()
	manager.results_ready.connect(func(ai_first_results: Array) -> void: emitted_results.append(ai_first_results))
	manager.prepare_race()
	manager.start_race()
	manager.report_checkpoint(checkpoints[1], racers[0])
	manager.report_checkpoint(checkpoints[2], racers[0])
	manager.report_checkpoint(checkpoints[1], racers[2])
	for checkpoint: Area2D in [checkpoints[1], checkpoints[2], checkpoints[0]]:
		manager.report_checkpoint(checkpoint, racers[1])
	manager.advance_race_time(0.49)
	if not _expect(emitted_results.is_empty(), "an AI first finish should start the full grace period"):
		return
	manager.advance_race_time(0.02)
	if not _expect(emitted_results.size() == 1 and not manager.is_running, "AI-first grace expiry should finish the race"):
		return
	results = emitted_results[0]
	if not _expect(results[0]["vehicle"] == racers[1] and not bool(results[0]["dnf"]), "the AI first finisher should remain the winner"):
		return
	if not _expect(results[1]["vehicle"] == racers[0] and bool(results[1]["dnf"]), "the unfinished player should be finalized as DNF in legal order"):
		return
	if not _expect(results[2]["vehicle"] == racers[2] and results[3]["vehicle"] == racers[3], "AI-first DNFs should preserve current legal ranking"):
		return

	print("RACE_GRACE_TEST PASS")
	manager.free()
	for checkpoint: Node in checkpoints:
		checkpoint.free()
	for racer: Node2D in racers:
		racer.free()
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("RACE_GRACE_TEST FAIL: " + message)
	quit(1)
	return false
