extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const VEHICLE_SCRIPT := preload("res://scripts/vehicle/vehicle_controller.gd")
const VEHICLE_IDS: Array[String] = ["rustbug", "pinbolt", "scrapjaw", "flicker"]
const PHYSICS_HZ := 60
const DELTA := 1.0 / float(PHYSICS_HZ)
const ACCEL_FRAMES := PHYSICS_HZ * 12
const SKIDPAD_WARMUP_FRAMES := PHYSICS_HZ
const SKIDPAD_SAMPLE_FRAMES := PHYSICS_HZ * 2
const DRIFT_WARMUP_FRAMES := 20
const DRIFT_SAMPLE_FRAMES := PHYSICS_HZ

var _world: Node2D


func _initialize() -> void:
	Engine.physics_ticks_per_second = PHYSICS_HZ
	call_deferred("_run_benchmark")


func _run_benchmark() -> void:
	_world = Node2D.new()
	_world.name = "VehiclePhysicsBenchmark"
	root.add_child(_world)
	current_scene = _world
	
	var surfaces := [1.0, 0.78, 0.58, 0.45]
	var versions := [0, 1]
	
	for vehicle_id: String in VEHICLE_IDS:
		for version in versions:
			for surf in surfaces:
				var stats := CATALOG.create_vehicle_stats(vehicle_id)
				stats.physics_model_version = version
				
				await _benchmark_acceleration(vehicle_id, stats, surf)
				await _benchmark_braking(vehicle_id, stats, surf)
				await _benchmark_skidpad(vehicle_id, stats, surf, 300.0)
				await _benchmark_skidpad(vehicle_id, stats, surf, 500.0)
				await _benchmark_drift(vehicle_id, stats, surf)
	
	_world.queue_free()
	await process_frame
	print("VEHICLE_PHYSICS_BENCHMARK PASS")
	quit(0)


func _spawn_vehicle(stats: VehicleStats, surf: float) -> RigidBody2D:
	var vehicle := VEHICLE_SCRIPT.new()
	vehicle.stats = stats
	vehicle.surface_speed_multiplier = surf
	vehicle.surface_grip_multiplier = surf
	vehicle.set_player_controlled(false)
	_world.add_child(vehicle)
	vehicle.rotation = 0.0
	vehicle.position = Vector2.ZERO
	vehicle.linear_velocity = Vector2.ZERO
	vehicle.angular_velocity = 0.0
	await physics_frame
	return vehicle


func _remove_vehicle(vehicle: RigidBody2D) -> void:
	vehicle.queue_free()
	await physics_frame


func _emit_row(vehicle_id: String, stats: VehicleStats, surf: float, scenario: String, metrics: Dictionary) -> void:
	for metric: String in metrics:
		var value = metrics[metric]
		var val_str = "%.3f" % float(value) if value is float else str(value)
		print("VEHICLE_DYNAMICS,%s,%d,%.2f,%s,%s,%s" % [vehicle_id, stats.physics_model_version, surf, scenario, metric, val_str])


func _benchmark_acceleration(vehicle_id: String, stats: VehicleStats, surf: float) -> void:
	var vehicle := await _spawn_vehicle(stats, surf)
	vehicle.set_external_controls(1.0, 0.0, 0.0)
	var zero_to_400 := -1.0
	var zero_to_95_percent := -1.0
	var eff_max: float = vehicle.get_effective_max_speed()
	var target_95: float = eff_max * 0.95
	for frame: int in ACCEL_FRAMES:
		await physics_frame
		var elapsed := float(frame + 1) * DELTA
		var forward_speed := vehicle.linear_velocity.dot(Vector2.UP)
		if zero_to_400 < 0.0 and forward_speed >= 400.0:
			zero_to_400 = elapsed
		if zero_to_95_percent < 0.0 and forward_speed >= target_95:
			zero_to_95_percent = elapsed
	
	vehicle.set_external_controls(0.0, 0.0, 0.0)
	
	_emit_row(vehicle_id, stats, surf, "launch", {
		"0->400": zero_to_400,
		"0->95%": zero_to_95_percent,
	})
	_emit_row(vehicle_id, stats, surf, "coast", {
		"top_speed": vehicle.linear_velocity.dot(Vector2.UP),
	})
	await _remove_vehicle(vehicle)


func _benchmark_braking(vehicle_id: String, stats: VehicleStats, surf: float) -> void:
	var vehicle := await _spawn_vehicle(stats, surf)
	vehicle.linear_velocity = Vector2.UP * 500.0
	vehicle.set_external_controls(0.0, 1.0, 0.0)
	var start_position := vehicle.position
	var stop_seconds := 0.0
	var stop_dist := -1.0
	for frame: int in PHYSICS_HZ * 5:
		await physics_frame
		stop_seconds = float(frame + 1) * DELTA
		if vehicle.linear_velocity.dot(Vector2.UP) <= 1.0:
			stop_dist = vehicle.position.distance_to(start_position)
			break
	_emit_row(vehicle_id, stats, surf, "brake", {
		"500->0": stop_dist if stop_dist >= 0 else vehicle.position.distance_to(start_position),
	})
	await _remove_vehicle(vehicle)


func _benchmark_skidpad(vehicle_id: String, stats: VehicleStats, surf: float, target_speed: float) -> void:
	var vehicle := await _spawn_vehicle(stats, surf)
	vehicle.linear_velocity = Vector2.UP * target_speed
	vehicle.set_external_controls(1.0, 0.0, 1.0)
	var min_radius := INF
	var total_lat_accel := 0.0
	var samples := 0
	for frame: int in SKIDPAD_WARMUP_FRAMES + SKIDPAD_SAMPLE_FRAMES:
		await physics_frame
		if frame >= SKIDPAD_WARMUP_FRAMES:
			var speed := vehicle.linear_velocity.length()
			var yaw_rate := absf(vehicle.angular_velocity)
			if yaw_rate > 0.01:
				min_radius = minf(min_radius, speed / yaw_rate)
				total_lat_accel += (speed * yaw_rate) / 980.0
				samples += 1
	var avg_g := total_lat_accel / float(maxi(1, samples))
	_emit_row(vehicle_id, stats, surf, "skidpad@%d" % int(target_speed), {
		"min_radius": min_radius if min_radius != INF else -1.0,
		"lat_g": avg_g,
	})
	await _remove_vehicle(vehicle)


func _benchmark_drift(vehicle_id: String, stats: VehicleStats, surf: float) -> void:
	var vehicle := await _spawn_vehicle(stats, surf)
	vehicle.linear_velocity = Vector2.UP * 450.0
	vehicle.set_external_controls(1.0, 0.0, 1.0, true)
	var max_slip := 0.0
	for frame: int in DRIFT_WARMUP_FRAMES + DRIFT_SAMPLE_FRAMES:
		await physics_frame
		if frame >= DRIFT_WARMUP_FRAMES:
			max_slip = maxf(max_slip, absf(vehicle.slip_angle))
	_emit_row(vehicle_id, stats, surf, "handbrake-drift", {
		"max_slip": max_slip,
	})
	
	vehicle.set_external_controls(1.0, 0.0, 0.0, false, true)
	if "boost_amount" in vehicle:
		vehicle.boost_amount = vehicle.get_boost_capacity()
	for frame: int in 10:
		await physics_frame
	
	var active = false
	if vehicle.has_method("is_boost_active"):
		active = vehicle.call("is_boost_active")
	
	_emit_row(vehicle_id, stats, surf, "boost", {
		"active": active,
	})
	
	await _remove_vehicle(vehicle)

