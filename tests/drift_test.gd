extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const CATALOG := preload("res://data/championship/catalog.gd")
const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const PHYSICS_HZ := 60
const DELTA := 1.0 / float(PHYSICS_HZ)

var _world: Node2D
var _failed := 0
var _passed := 0
var _spawn_index := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = PHYSICS_HZ
	call_deferred("_run_test")


func _run_test() -> void:
	var requested_version := OS.get_environment("PC_PHYSICS_MODEL_VERSION")
	if requested_version != "1":
		await _run_v0_smoke_test()
	if requested_version != "0":
		_world = Node2D.new()
		root.add_child(_world)
		current_scene = _world
		await _test_entry_gates_and_axle_slip()
		await _test_counter_steer_and_scrub()
		await _test_controlled_exit_awards_once()
		await _test_invalid_exits_award_nothing()
		await _test_reward_identity_and_recovery()
		_world.queue_free()
		await process_frame
	if _failed > 0:
		push_error("DRIFT_TEST: %d PASSED, %d FAILED" % [_passed, _failed])
		quit(1)
	else:
		print("DRIFT_TEST: %d PASSED, 0 FAILED" % _passed)
		print("DRIFT_TEST PASS")
		quit(0)


func _run_v0_smoke_test() -> void:
	var prototype := PROTOTYPE_SCENE.instantiate()
	root.add_child(prototype)
	current_scene = prototype
	for _settle in 6:
		await create_timer(0.1).timeout
	paused = false
	for _frame in 5:
		await physics_frame
	var vehicle := get_first_node_in_group("player_vehicle") as RigidBody2D
	var manager := get_first_node_in_group("race_manager") as RaceManager
	_check("v0 player exists", vehicle != null)
	_check("v0 race manager exists", manager != null)
	if vehicle != null and manager != null:
		var timeout := 300
		while not manager.is_running and timeout > 0:
			await physics_frame
			timeout -= 1
		Input.action_press("accelerate")
		for _frame in 90:
			await physics_frame
		Input.action_press("handbrake")
		Input.action_press("steer_right")
		var drift_seen := false
		var max_slip := 0.0
		for _frame in 60:
			await physics_frame
			drift_seen = drift_seen or bool(vehicle.get("is_drifting"))
			max_slip = maxf(max_slip, absf(float(vehicle.get("slip_angle"))))
		_check("v0 drift enters", drift_seen)
		_check("v0 drift develops slip", max_slip > 5.0)
	Input.action_release("accelerate")
	Input.action_release("handbrake")
	Input.action_release("steer_right")
	current_scene = null
	prototype.queue_free()
	for _frame in 3:
		await process_frame


func _test_entry_gates_and_axle_slip() -> void:
	var vehicle := await _spawn_vehicle("rustbug")
	_set_entry_fixture(vehicle, 200.0, 1.0, true, -10.0)
	vehicle.call("_v1_update_drift", DELTA, 200.0)
	_check("v1 valid entry", vehicle.is_drifting)
	_check("rear slip exceeds front on entry", absf(vehicle._rear_slip_angle) > absf(vehicle._front_slip_angle))

	vehicle.reset_dynamics_state()
	_set_entry_fixture(vehicle, 200.0, 1.0, false, -10.0)
	vehicle.call("_v1_update_drift", DELTA, 200.0)
	_check("entry requires handbrake", not vehicle.is_drifting)

	vehicle.reset_dynamics_state()
	_set_entry_fixture(vehicle, 200.0, vehicle.stats.drift_entry_steer - 0.01, true, -10.0)
	vehicle.call("_v1_update_drift", DELTA, 200.0)
	_check("entry requires steering threshold", not vehicle.is_drifting)

	vehicle.reset_dynamics_state()
	_set_entry_fixture(vehicle, vehicle.stats.drift_min_speed - 1.0, 1.0, true, -10.0)
	vehicle.call("_v1_update_drift", DELTA, vehicle.speed)
	_check("entry requires minimum speed", not vehicle.is_drifting)

	vehicle.reset_dynamics_state()
	_set_entry_fixture(vehicle, 200.0, 1.0, true, 10.0)
	vehicle.call("_v1_update_drift", DELTA, 200.0)
	_check("entry requires growing rear slip direction", not vehicle.is_drifting)
	await _remove_vehicle(vehicle)


func _test_counter_steer_and_scrub() -> void:
	var vehicle := await _spawn_vehicle("flicker")
	vehicle.linear_velocity = Vector2.UP * 450.0
	vehicle.set_external_controls(1.0, 0.0, 1.0, true)
	var entered := false
	for _frame in 45:
		await physics_frame
		if vehicle.is_drifting:
			entered = true
			break
	_check("physical drift entry", entered)
	for _frame in 18:
		await physics_frame
	var pre_counter_slip := absf(vehicle.slip_angle)
	vehicle.set_external_controls(1.0, 0.0, -1.0, true)
	var final_slip := INF
	for _frame in 36:
		await physics_frame
		if _frame >= 12:
			final_slip = minf(final_slip, absf(vehicle.slip_angle))
	print("DRIFT_COUNTER_STEER vehicle=flicker before=%.3f after=%.3f" % [pre_counter_slip, final_slip])
	_check("counter-steer reduces slip within 0.6s", final_slip < pre_counter_slip)
	await _remove_vehicle(vehicle)

	var scrub_vehicle := await _spawn_vehicle("rustbug")
	scrub_vehicle.linear_velocity = Vector2.UP * 350.0
	_force_active_drift(scrub_vehicle)
	scrub_vehicle._throttle_input = 0.0
	scrub_vehicle._external_throttle = 0.0
	var speed_before := scrub_vehicle.linear_velocity.length()
	for _frame in 24:
		await physics_frame
	_check("unboosted drift loses speed", scrub_vehicle.linear_velocity.length() < speed_before)
	await _remove_vehicle(scrub_vehicle)


func _test_controlled_exit_awards_once() -> void:
	var vehicle := await _spawn_vehicle("rustbug")
	_force_active_drift(vehicle)
	for _frame in 24:
		vehicle.call("_v1_update_drift", DELTA, 200.0)
	var before := vehicle.boost_amount
	vehicle._handbrake_input = false
	vehicle._rear_slip_angle = 0.0
	for _frame in 13:
		vehicle.call("_v1_update_drift", DELTA, 200.0)
	var awarded := vehicle.boost_amount - before
	_check("qualified controlled exit ends drift", not vehicle.is_drifting)
	_check("qualified controlled exit awards boost", awarded > 0.0)
	var after_first_exit := vehicle.boost_amount
	for _frame in 30:
		vehicle.call("_v1_update_drift", DELTA, 200.0)
	_check("controlled exit awards exactly once", is_equal_approx(vehicle.boost_amount, after_first_exit))
	await _remove_vehicle(vehicle)


func _test_invalid_exits_award_nothing() -> void:
	var quick_tap := await _spawn_vehicle("rustbug")
	_force_active_drift(quick_tap)
	for _frame in 10:
		quick_tap.call("_v1_update_drift", DELTA, 200.0)
	var quick_before := quick_tap.boost_amount
	quick_tap._handbrake_input = false
	quick_tap._rear_slip_angle = 0.0
	for _frame in 13:
		quick_tap.call("_v1_update_drift", DELTA, 200.0)
	_check("handbrake tap awards nothing", is_equal_approx(quick_tap.boost_amount, quick_before))
	await _remove_vehicle(quick_tap)

	var spin := await _spawn_vehicle("rustbug")
	_force_active_drift(spin)
	spin._drift_qualified_time = 0.5
	var spin_before := spin.boost_amount
	spin._rear_slip_angle = deg_to_rad(70.0)
	spin.call("_v1_update_drift", DELTA, -1.0)
	_check("spin awards nothing", is_equal_approx(spin.boost_amount, spin_before))
	await _remove_vehicle(spin)

	var wall := await _spawn_vehicle("rustbug")
	_force_active_drift(wall)
	wall._drift_qualified_time = 0.5
	var wall_before := wall.boost_amount
	wall._drift_collision_cancel = true
	wall.call("_v1_update_drift", DELTA, 200.0)
	_check("wall collision awards nothing", is_equal_approx(wall.boost_amount, wall_before))
	await _remove_vehicle(wall)

	var speed_loss := await _spawn_vehicle("rustbug")
	_force_active_drift(speed_loss)
	speed_loss._drift_qualified_time = 0.5
	var loss_before := speed_loss.boost_amount
	speed_loss.speed = speed_loss._drift_entry_speed * 0.79
	speed_loss.call("_v1_update_drift", DELTA, speed_loss.speed)
	_check("speed-loss exits drift", not speed_loss.is_drifting)
	_check("speed-loss awards nothing", is_equal_approx(speed_loss.boost_amount, loss_before))
	await _remove_vehicle(speed_loss)


func _test_reward_identity_and_recovery() -> void:
	var pinbolt_reward := await _qualified_reward("pinbolt", 0.5)
	var flicker_reward := await _qualified_reward("flicker", 0.5)
	_check("Flicker reward exceeds Pinbolt for equal duration", flicker_reward > pinbolt_reward)

	var vehicle := await _spawn_vehicle("rustbug")
	_force_active_drift(vehicle)
	vehicle._rack_angle = 0.3
	vehicle._drift_qualified_time = 0.5
	var before := vehicle.boost_amount
	vehicle.reset_dynamics_state()
	_check("recovery clears drift", not vehicle.is_drifting)
	_check("recovery clears steering rack", is_zero_approx(vehicle._rack_angle))
	_check("recovery clears axle slip", is_zero_approx(vehicle._front_slip_angle) and is_zero_approx(vehicle._rear_slip_angle))
	_check("recovery awards nothing", is_equal_approx(vehicle.boost_amount, before))
	await _remove_vehicle(vehicle)


func _qualified_reward(vehicle_id: String, seconds: float) -> float:
	var vehicle := await _spawn_vehicle(vehicle_id)
	_force_active_drift(vehicle)
	var before := vehicle.boost_amount
	for _frame in int(ceil(seconds * PHYSICS_HZ)):
		vehicle.call("_v1_update_drift", DELTA, 200.0)
	vehicle._handbrake_input = false
	vehicle._rear_slip_angle = 0.0
	for _frame in 13:
		vehicle.call("_v1_update_drift", DELTA, 200.0)
	var reward := vehicle.boost_amount - before
	await _remove_vehicle(vehicle)
	return reward


func _force_active_drift(vehicle: VehicleController) -> void:
	vehicle.reset_dynamics_state()
	vehicle._drift_state = VehicleController.DriftState.ACTIVE
	vehicle.is_drifting = true
	vehicle._drift_entry_speed = 150.0
	vehicle.speed = 200.0
	vehicle._throttle_input = 1.0
	vehicle._handbrake_input = true
	vehicle._steer_input = 1.0
	vehicle._rear_slip_angle = deg_to_rad(vehicle.stats.drift_optimal_slip_deg)


func _set_entry_fixture(vehicle: VehicleController, fixture_speed: float, steer: float, handbrake: bool, rear_slip_deg: float) -> void:
	vehicle.speed = fixture_speed
	vehicle._steer_input = steer
	vehicle._handbrake_input = handbrake
	vehicle._front_slip_angle = deg_to_rad(3.0)
	vehicle._rear_slip_angle = deg_to_rad(rear_slip_deg)


func _spawn_vehicle(vehicle_id: String) -> VehicleController:
	var stats := CATALOG.create_vehicle_stats(vehicle_id)
	stats.physics_model_version = 1
	var vehicle := VEHICLE_SCENE.instantiate() as VehicleController
	vehicle.apply_stats(stats)
	vehicle.set_player_controlled(false)
	_spawn_index += 1
	vehicle.position = Vector2(float(_spawn_index) * 300.0, 0.0)
	_world.add_child(vehicle)
	await physics_frame
	vehicle.linear_velocity = Vector2.ZERO
	vehicle.angular_velocity = 0.0
	return vehicle


func _remove_vehicle(vehicle: VehicleController) -> void:
	vehicle.queue_free()
	await physics_frame


func _check(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("DRIFT_TEST FAIL [%s]" % name)
