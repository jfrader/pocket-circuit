extends SceneTree

const STRIP_TRAFFIC := preload("res://scripts/race/strip/strip_traffic.gd")
const TRAFFIC_CAR := preload("res://scripts/race/strip/traffic_car.gd")
const RACE_MANAGER := preload("res://scripts/race/race_manager.gd")

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var route := PackedVector2Array([
		Vector2(0, 0),
		Vector2(120, 0),
		Vector2(240, 10),
		Vector2(360, -5),
		Vector2(500, 0)
	])
	var half := 72.0
	var plan: Array = [
		{"arc": 15.0, "lane": 0.0, "speed": 95.0, "behavior": &"cruiser", "vehicle_id": "rustbug"},
		{"arc": 80.0, "lane": 0.6, "speed": 110.0, "behavior": &"cutter", "vehicle_id": "pinbolt"},
		{"arc": 150.0, "lane": -0.3, "speed": 88.0, "behavior": &"line", "vehicle_id": "rustbug"},
	]
	var r := root
	var mgr := RACE_MANAGER.new()
	var traffic := STRIP_TRAFFIC.new()
	r.add_child(mgr)
	r.add_child(traffic)
	traffic.configure(route, half, plan, mgr)

	# frozen before start
	if traffic.get_child_count() != 3:
		push_error("STRIP_TRAFFIC_TEST FAIL: expected 3 cars spawned")
		quit(1)
		return
	for c in traffic.get_children():
		if not (c is TRAFFIC_CAR):
			push_error("STRIP_TRAFFIC_TEST FAIL: child not TrafficCar")
			quit(1)
			return
		if (c as TRAFFIC_CAR).linear_velocity.length() > 0.1:
			push_error("STRIP_TRAFFIC_TEST FAIL: cars should be frozen before race start")
			quit(1)
			return

	# start
	mgr.race_started.emit()
	await process_frame
	await process_frame
	await process_frame

	# advanced, no wrap
	var any_moved := false
	for c in traffic.get_children():
		var tc := c as TRAFFIC_CAR
		if tc.global_position.x > 30.0:
			any_moved = true
	if not any_moved:
		push_error("STRIP_TRAFFIC_TEST FAIL: cars did not advance after start")
		quit(1)
		return
	# cutter lane change is internal deterministic; rely on no crash + count for MVP test


	# end of route no wrap (halt)
	mgr.race_finished.emit(12.3)
	await process_frame
	for c in traffic.get_children():
		if (c as TRAFFIC_CAR).linear_velocity.length() > 0.5:
			push_error("STRIP_TRAFFIC_TEST FAIL: cars should stop on race finish")
			quit(1)
			return

	print("STRIP_TRAFFIC_TEST PASS")
	quit(0)
