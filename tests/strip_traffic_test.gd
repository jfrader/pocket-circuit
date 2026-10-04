extends SceneTree

const STRIP_TRAFFIC := preload("res://scripts/race/strip/strip_traffic.gd")
const TRAFFIC_CAR := preload("res://scripts/race/strip/traffic_car.gd")
const RACE_MANAGER := preload("res://scripts/race/race_manager.gd")
const ROUTE := preload("res://scripts/race/strip_route.gd")
const LAYOUT := preload("res://scripts/race/strip_layout.gd")
const CATALOG := preload("res://scripts/race/track_builder_catalog.gd")
const SAMPLER := preload("res://scripts/race/strip/strip_route_sampler.gd")
const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const FIXED_FPS := 60

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
		if Vector2.UP.rotated(c.rotation).dot(Vector2.RIGHT) < 0.95:
			push_error("STRIP_TRAFFIC_TEST FAIL: civilian sprite must face its travel direction")
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

	traffic.free()
	mgr.free()
	await _pathing_test()


func _pathing_test() -> void:
	var generated := ROUTE.generate(42, LAYOUT.runner_room(CATALOG.ROOM_SHAPES[&"classic"], "compact"))
	var route := PackedVector2Array()
	var distance := 0.0
	for point: Vector2 in generated["centerline"]:
		if not route.is_empty():
			distance += route[-1].distance_to(point)
		route.append(point)
		if distance > 9000.0:
			break
	var sampler := SAMPLER.new()
	sampler.configure(route)
	var manager := RACE_MANAGER.new()
	root.add_child(manager)
	var traffic := STRIP_TRAFFIC.new()
	root.add_child(traffic)
	var plan: Array = [
		{"arc": 100.0, "lane": -0.35, "speed": 225.0, "behavior": &"cruiser"},
		{"arc": 270.0, "lane": -0.35, "speed": 210.0, "behavior": &"truck"},
		{"arc": 600.0, "lane": 0.35, "speed": 220.0, "behavior": &"cutter"},
		{"arc": 850.0, "lane": -0.35, "speed": 220.0, "behavior": &"swerve"},
		{"arc": 1150.0, "lane": 0.25, "speed": 225.0, "behavior": &"line"},
		{"arc": 1600.0, "lane": -0.40, "speed": 225.0, "behavior": &"cutter"},
		{"arc": 1600.0, "lane": 0.40, "speed": 225.0, "behavior": &"cutter"},
	]
	traffic.configure(route, 125.0, plan, manager)
	var cars := traffic.get_children()
	var obstacle_sample: Dictionary = sampler.sample(2200.0)
	var obstacle := StaticBody2D.new()
	obstacle.collision_layer = 16
	obstacle.position = obstacle_sample["pos"] + obstacle_sample["perp"] * -45.0
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	obstacle.add_child(collision)
	root.add_child(obstacle)
	var parked_sample: Dictionary = sampler.sample(4500.0)
	var parked_racer := StaticBody2D.new()
	parked_racer.collision_layer = 1
	parked_racer.position = parked_sample["pos"]
	parked_racer.rotation = (parked_sample["dir"] as Vector2).angle() + PI * 0.5
	var parked_shape := CapsuleShape2D.new()
	parked_shape.radius = 18.0
	parked_shape.height = 52.0
	var parked_collision := CollisionShape2D.new()
	parked_collision.shape = parked_shape
	parked_racer.add_child(parked_collision)
	root.add_child(parked_racer)
	manager.race_started.emit()
	var minimum_gap := INF
	var maximum_lane_error := 0.0
	var recovered_error := INF
	var stuck_ticks := 0
	for tick in FIXED_FPS * 65:
		await physics_frame
		if tick == FIXED_FPS * 4:
			var bumped := cars[2] as TrafficCar
			var sample: Dictionary = sampler.sample(bumped._arc)
			bumped.apply_central_impulse((sample["perp"] as Vector2) * 300.0)
		for candidate in cars:
			if not is_instance_valid(candidate):
				continue
			var car := candidate as TrafficCar
			var projected: Dictionary = sampler.project(car.global_position)
			if absf(float(projected["arc"]) - car._arc) > 15.0:
				_fail("Traffic progress ran ahead of its physical body")
				return
			var sample: Dictionary = sampler.sample(car._arc)
			var lateral := (car.global_position - (sample["pos"] as Vector2)).dot(sample["perp"])
			var error := absf(lateral - car._lane * 125.0)
			if tick > FIXED_FPS * 9 and car == cars[2]:
				recovered_error = minf(recovered_error, error)
			if tick > FIXED_FPS * 10:
				maximum_lane_error = maxf(maximum_lane_error, absf(lateral))
			if tick > FIXED_FPS * 3 and car.linear_velocity.length() < 8.0:
				stuck_ticks += 1
			if car.global_position.distance_to(obstacle.position) < 24.0 + car._body_width * 0.5 - 3.0:
				_fail("Traffic penetrated solid scenery")
				return
		for first in cars.size():
			if not is_instance_valid(cars[first]):
				continue
			for second in range(first + 1, cars.size()):
				if not is_instance_valid(cars[second]):
					continue
				var a := cars[first] as TrafficCar
				var b := cars[second] as TrafficCar
				var a_axis := Vector2.UP.rotated(a.rotation) * (a._body_length - a._body_width) * 0.5
				var b_axis := Vector2.UP.rotated(b.rotation) * (b._body_length - b._body_width) * 0.5
				var closest := Geometry2D.get_closest_points_between_segments(a.position - a_axis, a.position + a_axis, b.position - b_axis, b.position + b_axis)
				var gap := closest[0].distance_to(closest[1]) - (a._body_width + b._body_width) * 0.5
				minimum_gap = minf(minimum_gap, gap)
				if gap < -3.0:
					_fail("Traffic stacked/overlapped: %.2f wu" % gap)
					return
	if recovered_error > 12.0 or maximum_lane_error > 108.0 or stuck_ticks > FIXED_FPS * 3 or traffic.get_child_count() != 0:
		for car in traffic.get_children():
			print("TRAFFIC_SURVIVOR behavior=%s arc=%.1f lane=%.2f speed=%.1f position=%s" % [car._behavior, car._arc, car._lane, car.linear_velocity.length(), car.position])
		_fail("Pathing/recovery/end failed: recovery=%.1f lateral=%.1f stuck=%d remaining=%d" % [recovered_error, maximum_lane_error, stuck_ticks, traffic.get_child_count()])
		return
	traffic.free()
	manager.free()
	obstacle.free()
	parked_racer.free()
	if not await _world_traffic_test():
		return
	print("STRIP_TRAFFIC_TEST PASS physical_65s min_gap=%.2f recovered_lane_error=%.2f max_lateral=%.2f stuck_ticks=%d remaining=0" % [minimum_gap, recovered_error, maximum_lane_error, stuck_ticks])
	quit(0)


func _world_traffic_test() -> bool:
	for theme in [&"kitchen", &"workshop", &"office"]:
		var prepared := BUILDER.prepare_layout(theme, &"classic", 42, {"route_shape": "strip"})
		var track := BUILDER.create_layout_root(prepared)
		root.add_child(track)
		await BUILDER.assemble_runtime(track, prepared, Callable())
		var manager := RACE_MANAGER.new()
		root.add_child(manager)
		var traffic := STRIP_TRAFFIC.new()
		track.add_child(traffic)
		traffic.configure(prepared["centerline"], prepared["strip_half_width"], prepared["traffic_plan"], manager)
		manager.race_started.emit()
		var stalled := {}
		var worst_stall := 0
		for tick in FIXED_FPS * 30:
			await physics_frame
			for car: TrafficCar in traffic.get_children():
				var id := car.get_instance_id()
				stalled[id] = int(stalled.get(id, 0)) + 1 if tick > FIXED_FPS * 3 and car.linear_velocity.length() < 8.0 else 0
				worst_stall = maxi(worst_stall, int(stalled[id]))
		var minimum_progress := INF
		for car: TrafficCar in traffic.get_children():
			minimum_progress = minf(minimum_progress, car._arc - car._spawn_arc)
		if minimum_progress < 3500.0 or worst_stall > FIXED_FPS * 3:
			_fail("World traffic stalled in %s: min_progress=%.1f worst_stall=%d" % [theme, minimum_progress, worst_stall])
			return false
		print("STRIP_TRAFFIC_WORLD %s seed=42 30s min_progress=%.1f worst_stall_ticks=%d" % [theme, minimum_progress, worst_stall])
		track.free()
		manager.free()
	return true


func _fail(message: String) -> void:
	push_error("STRIP_TRAFFIC_TEST FAIL: " + message)
	quit(1)
