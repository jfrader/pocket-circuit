extends SceneTree

const PHYSICS_HZ := 60
const VEHICLE_SCENE := "res://scenes/vehicles/rustbug.tscn"
const RUSTBUG_STATS := "res://data/vehicles/rustbug.tres"


func _initialize() -> void:
	Engine.physics_ticks_per_second = PHYSICS_HZ
	Engine.time_scale = 1.0
	call_deferred("_run")


func _run() -> void:
	if not await _test_not_soap():
		return
	if not await _test_low_speed_turns():
		return
	if not await _test_high_speed_oversteer_without_handbrake():
		return
	if not await _test_counter_steer_saves():
		return
	if not await _test_handbrake_stronger():
		return
	print("VEHICLE_ARCADE_TEST PASS")
	quit(0)


func _spawn(stats: VehicleStats) -> VehicleController:
	var vehicle := load(VEHICLE_SCENE).instantiate() as VehicleController
	vehicle.stats = stats
	vehicle.surface_speed_multiplier = 1.0
	vehicle.surface_grip_multiplier = 1.0
	vehicle.set_player_controlled(false)
	vehicle.reset_dynamics_state()
	var vfx := vehicle.get_node_or_null("VFX")
	if vfx:
		vfx.queue_free()
	root.add_child(vehicle)
	vehicle.global_position = Vector2.ZERO
	vehicle.rotation = 0.0
	vehicle.linear_velocity = Vector2.ZERO
	vehicle.angular_velocity = 0.0
	return vehicle


func _slip_ratio(vehicle: VehicleController) -> float:
	var forward := Vector2.UP.rotated(vehicle.rotation)
	var speed := maxf(vehicle.linear_velocity.length(), 1.0)
	var lat := absf(vehicle.linear_velocity.dot(forward.orthogonal()))
	return lat / speed


func _test_not_soap() -> bool:
	var stats: VehicleStats = load(RUSTBUG_STATS).duplicate()
	stats.physics_model_version = 2
	var vehicle := _spawn(stats)
	vehicle.linear_velocity = Vector2.UP * 280.0
	await physics_frame
	vehicle.set_external_controls(0.7, 0.0, 0.0, false, false)
	for _i in 20:
		await physics_frame
	var straight := _slip_ratio(vehicle)
	vehicle.set_external_controls(0.55, 0.0, 1.0, false, false)
	for _i in 30:
		await physics_frame
	var turning := _slip_ratio(vehicle)
	vehicle.queue_free()
	return _expect(
		straight < 0.06 and turning < 0.18,
		"car must track its heading (straight slip %.3f turn slip %.3f) — soap fails this" % [straight, turning]
	)


func _test_low_speed_turns() -> bool:
	var stats: VehicleStats = load(RUSTBUG_STATS).duplicate()
	stats.physics_model_version = 2
	var vehicle := _spawn(stats)
	vehicle.linear_velocity = Vector2.UP * 140.0
	await physics_frame
	vehicle.set_external_controls(0.4, 0.0, 1.0, false, false)
	var start := vehicle.rotation
	for _i in 45:
		await physics_frame
	var turned := absf(angle_difference(start, vehicle.rotation))
	vehicle.queue_free()
	return _expect(turned > 0.35, "low-speed full steer should turn tightly (got %.2f rad)" % turned)


func _test_high_speed_oversteer_without_handbrake() -> bool:
	var stats: VehicleStats = load(RUSTBUG_STATS).duplicate()
	stats.physics_model_version = 2
	var vehicle := _spawn(stats)
	var cruise := stats.max_speed * 0.85
	vehicle.linear_velocity = Vector2.UP * cruise
	await physics_frame
	vehicle.set_external_controls(1.0, 0.0, 1.0, false, false)
	var yaw0 := absf(vehicle.angular_velocity)
	for _i in 40:
		await physics_frame
	var yaw1 := absf(vehicle.angular_velocity)
	var heading := absf(vehicle.rotation)
	vehicle.queue_free()
	return _expect(
		yaw1 > yaw0 + 0.4 and heading > 0.12,
		"throttle+steer at speed without handbrake should grow yaw (yaw %.2f heading %.2f)" % [yaw1, heading]
	)


func _test_counter_steer_saves() -> bool:
	var stats: VehicleStats = load(RUSTBUG_STATS).duplicate()
	stats.physics_model_version = 2
	var vehicle := _spawn(stats)
	vehicle.linear_velocity = Vector2.UP * stats.max_speed * 0.85
	vehicle.angular_velocity = 2.2
	await physics_frame
	vehicle.set_external_controls(0.35, 0.0, -1.0, false, false)
	var yaw0 := absf(vehicle.angular_velocity)
	for _i in 8:
		await physics_frame
	var yaw1 := absf(vehicle.angular_velocity)
	vehicle.queue_free()
	return _expect(yaw1 < yaw0, "counter-steer should cut yaw in the first beats (%.2f -> %.2f)" % [yaw0, yaw1])


func _test_handbrake_stronger() -> bool:
	var stats: VehicleStats = load(RUSTBUG_STATS).duplicate()
	stats.physics_model_version = 2
	var a := _spawn(stats)
	var b := _spawn(stats)
	var cruise := stats.max_speed * 0.8
	a.linear_velocity = Vector2.UP * cruise
	b.linear_velocity = Vector2.UP * cruise
	await physics_frame
	a.set_external_controls(0.8, 0.0, 1.0, false, false)
	b.set_external_controls(0.8, 0.0, 1.0, true, false)
	for _i in 25:
		await physics_frame
	var yaw_throttle := absf(a.angular_velocity)
	var yaw_hb := absf(b.angular_velocity)
	a.queue_free()
	b.queue_free()
	return _expect(
		yaw_throttle > 1.2 and yaw_hb > 1.2,
		"throttle-only and handbrake should both rotate hard (throttle %.2f hb %.2f)" % [yaw_throttle, yaw_hb]
	)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("VEHICLE_ARCADE_TEST FAIL: " + message)
	quit(1)
	return false
