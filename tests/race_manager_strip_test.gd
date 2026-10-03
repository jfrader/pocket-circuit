extends SceneTree

const MANAGER := preload("res://scripts/race/race_manager.gd")

class Gate extends Area2D:
	var checkpoint_index: int
	var is_finish_line := false
	func _init(index: int) -> void:
		checkpoint_index = index
		is_finish_line = index == 7
		position = Vector2(index * 300.0, 0.0)
	func get_recovery_transform() -> Transform2D:
		return Transform2D(0.0, position)


func _initialize() -> void:
	var manager := MANAGER.new() as RaceManager
	var gates: Array = []
	for index in 8:
		gates.append(Gate.new(index))
	manager.configure_checkpoints(gates)
	manager.configure_strip_route(2, 7)
	if int(manager.get_ordered_checkpoints()[0].get("checkpoint_index")) != 0:
		_fail("Strip checkpoints must be sorted from start to finish")
		return
	manager.configure_route_reference(PackedVector2Array([Vector2(0, 0), Vector2(300, 0), Vector2(600, 0), Vector2(600, 300)]), true)
	if absf(float(manager.get("_route_length")) - 900.0) > 0.01:
		_fail("Open reference must not close the endpoints")
		return
	var player := Node2D.new()
	var chaser := Node2D.new()
	manager.register_racer(player, "Player", "Car", true)
	manager.register_racer(chaser, "Chaser", "Car")
	var wins := [0]
	manager.race_finished.connect(func(_time: float) -> void: wins[0] += 1)
	manager.prepare_race()
	manager.start_race()
	manager.finalize_remaining_racers_as_dnf()
	if not manager.is_running or bool(manager.get_racer_state(player).get("dnf")) or bool(manager.get_racer_state(chaser).get("dnf")):
		_fail("Strip must not finalize other racers as DNF")
		return
	if manager.get_expected_checkpoint(player) != 2 or manager.report_checkpoint(gates[7], player) or manager.report_checkpoint(gates[0], player):
		_fail("Expected gate or skipped finish")
		return
	for index in range(2, 7):
		if not manager.report_checkpoint(gates[index], player) or not manager.report_checkpoint(gates[index], chaser):
			_fail("Ordered gates")
			return
	if manager.report_checkpoint(gates[7], chaser) or manager.is_racer_finished(chaser) or manager.get_expected_checkpoint(chaser) != 7:
		_fail("Chaser finished")
		return
	if not manager.report_checkpoint(gates[7], player) or wins[0] != 1 or manager.lap_count != 0 or manager.is_running or manager.report_checkpoint(gates[0], player):
		_fail("Player finish/lap wrap")
		return
	print("RACE_MANAGER_STRIP_TEST PASS")
	manager.free()
	player.free()
	chaser.free()
	for gate: Node in gates:
		gate.free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
