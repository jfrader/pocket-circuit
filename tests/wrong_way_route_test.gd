extends SceneTree

const RACE_MANAGER_SCRIPT := preload("res://scripts/race/race_manager.gd")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")


class TestCheckpoint extends Area2D:
	var checkpoint_index: int
	var is_finish_line: bool

	func _init(index: int, finish_line: bool, checkpoint_position: Vector2) -> void:
		checkpoint_index = index
		is_finish_line = finish_line
		position = checkpoint_position

	func get_recovery_transform() -> Transform2D:
		return Transform2D(0.0, position)


var _created: Array = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _test_forward_away_from_gate():
		return
	if not _test_backward_on_section():
		return
	if not _test_reverse_tangent():
		return
	if not _test_parallel_legs():
		return
	if not _test_recovery_notification():
		return
	_cleanup()
	print("WRONG_WAY_ROUTE_TEST PASS")
	quit(0)


# ── Fixture lifecycle: every node/checkpoint is tracked and freed once. ──
func _remember(node: Node) -> Node:
	_created.append(node)
	return node


func _manager() -> RaceManager:
	return _remember(RACE_MANAGER_SCRIPT.new()) as RaceManager


func _checkpoint(index: int, finish_line: bool, position: Vector2) -> TestCheckpoint:
	return _remember(TestCheckpoint.new(index, finish_line, position)) as TestCheckpoint


func _cleanup() -> void:
	for index in range(_created.size() - 1, -1, -1):
		var node := _created[index] as Node
		if is_instance_valid(node):
			node.free()
	_created.clear()


# ── Route: an overshoot that reproduces the endurance U/long-sweep shape ──
# The route runs +x from the start (0,0) out to (2000,0) before curving down and
# back left to the next gate at (1000,500). A car on the +x leg is moving AWAY
# from the gate's direct chord while still travelling forward on the route.
func _overshoot_route() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, 0),
		Vector2(500, 0),
		Vector2(1000, 0),
		Vector2(1500, 0),
		Vector2(2000, 0),
		Vector2(2000, 300),
		Vector2(1500, 500),
		Vector2(1000, 500),
		Vector2(500, 500),
		Vector2(0, 500),
		Vector2(0, 250),
	])


func _overshoot_manager() -> RaceManager:
	var manager := _manager()
	var checkpoints: Array = [
		_checkpoint(0, true, Vector2(0, 0)),
		_checkpoint(1, false, Vector2(1000, 500)),
	]
	manager.configure_checkpoints(checkpoints)
	manager.configure_route_reference(_overshoot_route())
	return manager


func _test_forward_away_from_gate() -> bool:
	var manager := _overshoot_manager()
	# The gate (1000,500) lies down-left of the car; the direct chord points
	# backward, but the route tangent points forward (+x).
	var position := Vector2(1500, 0)
	var tangent := manager.get_route_forward_direction(position, 0, 1)
	var chord := position.direction_to(Vector2(1000, 500))
	if not _expect(tangent.length_squared() > 0.001, "route reference should resolve a tangent on the overshoot leg"):
		return false
	if not _expect(tangent.dot(Vector2(1, 0)) > 0.99, "forward tangent on the +x leg should point +x"):
		return false
	if not _expect(chord.dot(Vector2(1, 0)) < -0.4, "the direct gate chord should point backward here (proving the tangent is a different reference)"):
		return false
	# Integration: a forward-moving car must not be flagged wrong way.
	var racer := _registered_racer(manager, position, Vector2(500, 0))
	var wrong_way := _advance_and_read_wrong_way(manager, racer, 0.7)
	if not _expect(not wrong_way, "forward motion on a curved section must not flag wrong way"):
		return false
	return true


func _test_backward_on_section() -> bool:
	var manager := _overshoot_manager()
	var racer := _registered_racer(manager, Vector2(1500, 0), Vector2(-500, 0))
	var wrong_way := _advance_and_read_wrong_way(manager, racer, 0.7)
	if not _expect(wrong_way, "backward motion on that same section must flag wrong way"):
		return false
	return true


func _test_reverse_tangent() -> bool:
	var manager := _manager()
	var checkpoints: Array = [
		_checkpoint(0, true, Vector2(0, 0)),
		_checkpoint(1, false, Vector2(1000, 0)),
		_checkpoint(2, false, Vector2(1000, 500)),
	]
	manager.configure_checkpoints(checkpoints)
	manager.configure_route_reference(PackedVector2Array([
		Vector2(0, 0),
		Vector2(1000, 0),
		Vector2(1000, 500),
		Vector2(0, 500),
	]))
	manager.set_reverse_direction(true)
	# Reverse section cp2 -> cp1 travels up the right leg (x=1000). The route
	# tangent there is +y (down), so the race-direction tangent must be -y (up).
	var tangent := manager.get_route_forward_direction(Vector2(1000, 250), 2, 1)
	if not _expect(tangent.length_squared() > 0.001, "reverse route reference should resolve a tangent"):
		return false
	if not _expect(tangent.dot(Vector2(0, -1)) > 0.99, "reverse race-direction tangent must negate the forward route tangent"):
		return false
	return true


func _test_parallel_legs() -> bool:
	var manager := _manager()
	var checkpoints: Array = [
		_checkpoint(0, true, Vector2(0, 0)),
		_checkpoint(1, false, Vector2(1000, 0)),
		_checkpoint(2, false, Vector2(0, 300)),
	]
	manager.configure_checkpoints(checkpoints)
	manager.configure_route_reference(PackedVector2Array([
		Vector2(0, 0),
		Vector2(500, 0),
		Vector2(1000, 0),
		Vector2(1000, 150),
		Vector2(1000, 300),
		Vector2(500, 300),
		Vector2(0, 300),
		Vector2(0, 150),
	]))
	# The car sits midway between leg A (y=0, arc ~500) and leg B (y=300,
	# arc ~1800), slightly closer to leg B. The active section finish->cp1
	# constrains the search to leg A, so the tangent must point +x, not the
	# opposite leg's -x.
	var tangent := manager.get_route_forward_direction(Vector2(500, 150), 0, 1)
	if not _expect(tangent.length_squared() > 0.001, "parallel-leg section should resolve a tangent"):
		return false
	if not _expect(tangent.dot(Vector2(1, 0)) > 0.99, "section constraint must keep the tangent on the active leg (+x), not the parallel return leg (-x)"):
		return false
	return true


func _test_recovery_notification() -> bool:
	var manager := _manager()
	var checkpoints: Array = [
		_checkpoint(0, true, Vector2(0, 0)),
		_checkpoint(1, false, Vector2(100, 0)),
	]
	manager.configure_checkpoints(checkpoints)
	var racer := _remember(VehicleController.new()) as VehicleController
	manager.register_racer(racer, "Driver", "Rustbug", true)
	var emitted := [0]
	manager.racer_recovered.connect(func(_r: Node2D) -> void: emitted[0] += 1)
	manager.report_recovery(racer)
	if not _expect(emitted[0] == 1, "report_recovery should emit racer_recovered once"):
		return false
	# The AI controller re-anchors its route watchdog on an external recovery.
	var controller := _remember(AI_CONTROLLER_SCRIPT.new()) as AIVehicleController
	controller.set("vehicle", racer)
	controller.set("race_manager", manager)
	controller.set("_route_progress_accumulator", -970.0)
	controller.set("_watchdog_target_key", "4:-1")
	controller.call("_on_external_recovery", racer)
	if not _expect(float(controller.get("_route_progress_accumulator")) == 0.0, "external recovery should reset the route progress accumulator"):
		return false
	if not _expect(str(controller.get("_watchdog_target_key")) == "", "external recovery should re-anchor the watchdog target key"):
		return false
	return true


func _registered_racer(manager: RaceManager, position: Vector2, velocity: Vector2) -> RigidBody2D:
	var racer := _remember(RigidBody2D.new()) as RigidBody2D
	racer.position = position
	manager.register_racer(racer, "Driver", "Rustbug", true)
	manager.prepare_race()
	manager.start_race()
	racer.linear_velocity = velocity
	return racer


func _advance_and_read_wrong_way(manager: RaceManager, racer: RigidBody2D, delta: float) -> bool:
	manager.advance_race_time(delta)
	return manager.is_racer_wrong_way(racer)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("WRONG_WAY_ROUTE_TEST FAIL: " + message)
	quit(1)
	return false
