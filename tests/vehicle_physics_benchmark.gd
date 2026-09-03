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
	for vehicle_id: String in VEHICLE_IDS:
		var stats := CATALOG.create_vehicle_stats(vehicle_id)
		_apply_requested_model_version(stats)
		await _benchmark_acceleration(vehicle_id, stats)
		await _benchmark_braking(vehicle_id, stats)
		await _benchmark_skidpad(vehicle_id, stats)
		await _benchmark_drift(vehicle_id, stats)
	_world.queue_free()
	await process_frame
	print("VEHICLE_PHYSICS_BENCHMARK PASS")
	quit(0)


func _benchmark_acceleration(vehicle_id: String, stats: VehicleStats) -> void:
	var vehicle := await _spawn_vehicle(stats)
	vehicle.set_external_controls(1.0, 0.0, 0.0)
	var zero_to_400 := -1.0
	var zero_to_95_percent := -1.0
	var target_95 := stats.max_speed * 0.95
	for frame: int in ACCEL_FRAMES:
		await physics_frame
		var elapsed := float(frame + 1) * DELTA
		var forward_speed := vehicle.linear_velocity.dot(Vector2.UP)
		if zero_to_400 < 0.0 and forward_speed >= 400.0:
			zero_to_400 = elapsed
		if zero_to_95_percent < 0.0 and forward_speed >= target_95:
			zero_to_95_percent = elapsed
	_emit_row(vehicle_id, stats, "straight_accel", {
		"stable_speed_wu_s": vehicle.linear_velocity.dot(Vector2.UP),
		"zero_to_400_s": zero_to_400,
		"zero_to_95_percent_s": zero_to_95_percent,
	})
	await _remove_vehicle(vehicle)


func _benchmark_braking(vehicle_id: String, stats: VehicleStats) -> void:
	var vehicle := await _spawn_vehicle(stats)
	vehicle.linear_velocity = Vector2.UP * 500.0
	vehicle.set_external_controls(0.0, 1.0, 0.0)
	var start_position := vehicle.position
	var stop_seconds := 0.0
	for frame: int in PHYSICS_HZ * 5:
		await physics_frame
		stop_seconds = float(frame + 1) * DELTA
		if vehicle.linear_velocity.dot(Vector2.UP) <= 0.0:
			break
	_emit_row(vehicle_id, stats, "brake_500_to_0", {
		"distance_wu": vehicle.position.distance_to(start_position),
		"stop_seconds": stop_seconds,
	})
	await _remove_vehicle(vehicle)


func _benchmark_skidpad(vehicle_id: String, stats: VehicleStats) -> void:
	var vehicle := await _spawn_vehicle(stats)
	vehicle.linear_velocity = Vector2.UP * 300.0
	vehicle.set_external_controls(1.0, 0.0, 1.0)
	for _frame: int in SKIDPAD_WARMUP_FRAMES:
		await physics_frame
	var radius_sum := 0.0
	var lateral_g_sum := 0.0
	var slip_sum := 0.0
	var samples := 0
	var previous_velocity := vehicle.linear_velocity
	for _frame: int in SKIDPAD_SAMPLE_FRAMES:
		await physics_frame
		var velocity := vehicle.linear_velocity
		var path_yaw_rate := absf(previous_velocity.angle_to(velocity)) / DELTA
		if velocity.length() > 1.0 and path_yaw_rate > 0.001:
			radius_sum += velocity.length() / path_yaw_rate
			lateral_g_sum += velocity.length() * path_yaw_rate / 980.0
			slip_sum += absf(vehicle.slip_angle)
			samples += 1
		previous_velocity = velocity
	_emit_row(vehicle_id, stats, "skidpad_300", {
		"lateral_g_eq": lateral_g_sum / maxf(float(samples), 1.0),
		"radius_wu": radius_sum / maxf(float(samples), 1.0),
		"slip_deg": slip_sum / maxf(float(samples), 1.0),
	})
	await _remove_vehicle(vehicle)


func _benchmark_drift(vehicle_id: String, stats: VehicleStats) -> void:
	var vehicle := await _spawn_vehicle(stats)
	vehicle.linear_velocity = Vector2.UP * 300.0
	vehicle.set_external_controls(1.0, 0.0, 1.0, true)
	var slip_sum := 0.0
	var max_slip := 0.0
	var samples := 0
	for frame: int in DRIFT_WARMUP_FRAMES + DRIFT_SAMPLE_FRAMES:
		await physics_frame
		if frame < DRIFT_WARMUP_FRAMES or not vehicle.is_drifting:
			continue
		var absolute_slip := absf(vehicle.slip_angle)
		slip_sum += absolute_slip
		max_slip = maxf(max_slip, absolute_slip)
		samples += 1
	_emit_row(vehicle_id, stats, "handbrake_drift", {
		"max_slip_deg": max_slip,
		"slip_deg": slip_sum / maxf(float(samples), 1.0),
	})
	await _remove_vehicle(vehicle)


func _spawn_vehicle(stats: VehicleStats) -> VehicleController:
	var vehicle := VEHICLE_SCRIPT.new() as VehicleController
	vehicle.name = "BenchmarkVehicle"
	vehicle.control_mode = VehicleController.ControlMode.EXTERNAL
	vehicle.stats = stats
	vehicle.collision_layer = 0
	vehicle.collision_mask = 0
	vehicle.can_sleep = false
	_world.add_child(vehicle)
	await physics_frame
	vehicle.position = Vector2.ZERO
	vehicle.rotation = 0.0
	vehicle.linear_velocity = Vector2.ZERO
	vehicle.angular_velocity = 0.0
	return vehicle


func _remove_vehicle(vehicle: VehicleController) -> void:
	vehicle.queue_free()
	await physics_frame


func _emit_row(vehicle_id: String, stats: VehicleStats, scenario: String, metrics: Dictionary) -> void:
	var row := {
		"vehicle_id": vehicle_id,
		"physics_model_version": _model_version(stats),
		"scenario": scenario,
		"metrics": _rounded_metrics(metrics),
	}
	print("VEHICLE_DYNAMICS " + JSON.stringify(row))


func _rounded_metrics(metrics: Dictionary) -> Dictionary:
	var rounded := {}
	for key: String in metrics:
		rounded[key] = snappedf(float(metrics[key]), 0.0001)
	return rounded


func _apply_requested_model_version(stats: VehicleStats) -> void:
	var requested := OS.get_environment("PC_PHYSICS_MODEL_VERSION")
	if requested.is_empty() or not _has_property(stats, &"physics_model_version"):
		return
	stats.set("physics_model_version", clampi(requested.to_int(), 0, 1))


func _model_version(stats: VehicleStats) -> int:
	if _has_property(stats, &"physics_model_version"):
		return int(stats.get("physics_model_version"))
	return 0


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false
