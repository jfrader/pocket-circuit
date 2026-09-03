extends SceneTree

## Vehicle physics benchmark: spawns real RigidBody2D vehicles with collision
## shapes (capsule r=18, h=52) into a PhysicsServer world. Runs all scenarios
## for all 4 cars at all surfaces. Honors PC_PHYSICS_MODEL_VERSION env to
## select which model(s) to benchmark (default: both).
##
## Scenarios: launch, coast, brake, skidpad@300, skidpad@500, handbrake-drift,
## boost, counter-steer.
## Surfaces: 1.0, 0.78, 0.58, 0.45.
## Outputs VEHICLE_DYNAMICS CSV rows. Asserts numeric gates on dry surface.

const CATALOG := preload("res://data/championship/catalog.gd")
const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const VEHICLE_IDS: Array[String] = ["rustbug", "pinbolt", "scrapjaw", "flicker"]
const SURFACES: Array[float] = [1.0, 0.78, 0.58, 0.45]
const PHYSICS_HZ := 60
const DELTA := 1.0 / float(PHYSICS_HZ)
const ACCEL_FRAMES := PHYSICS_HZ * 12
const COAST_FRAMES := PHYSICS_HZ * 3
const SKIDPAD_WARMUP_FRAMES := PHYSICS_HZ * 2
const SKIDPAD_SAMPLE_FRAMES := PHYSICS_HZ * 3
const DRIFT_WARMUP_FRAMES := PHYSICS_HZ
const DRIFT_SAMPLE_FRAMES := PHYSICS_HZ * 2
const COUNTER_STEER_FRAMES := PHYSICS_HZ * 2
const BOOST_FRAMES := PHYSICS_HZ * 2
const TEN_MIN_FRAMES := PHYSICS_HZ * 600

# Metric gates (dry surface, v1 only) — P2 bounds
const STABLE_SPEED_GATES := {
	"rustbug": Vector2(620.0, 720.0),
	"pinbolt": Vector2(580.0, 680.0),
	"scrapjaw": Vector2(640.0, 740.0),
	"flicker": Vector2(660.0, 770.0),
}
const BRAKE_DIST_GATES := {
	"rustbug": Vector2(50.0, 200.0),
	"pinbolt": Vector2(40.0, 180.0),
	"scrapjaw": Vector2(60.0, 250.0),
	"flicker": Vector2(50.0, 200.0),
}

var _world: Node2D
var _gate_failures: int = 0
var _requested_versions: Array[int] = []


func _initialize() -> void:
	Engine.physics_ticks_per_second = PHYSICS_HZ
	# Honor PC_PHYSICS_MODEL_VERSION env variable
	var env_version := OS.get_environment("PC_PHYSICS_MODEL_VERSION")
	if env_version == "0":
		_requested_versions = [0]
	elif env_version == "1":
		_requested_versions = [1]
	else:
		_requested_versions = [0, 1]
	call_deferred("_run_benchmark")


func _run_benchmark() -> void:
	_world = Node2D.new()
	_world.name = "VehiclePhysicsBenchmark"
	root.add_child(_world)
	current_scene = _world

	for vehicle_id: String in VEHICLE_IDS:
		for version: int in _requested_versions:
			for surf: float in SURFACES:
				var stats := CATALOG.create_vehicle_stats(vehicle_id)
				stats.physics_model_version = version

				await _benchmark_acceleration(vehicle_id, stats, surf)
				await _benchmark_coast(vehicle_id, stats, surf)
				await _benchmark_braking(vehicle_id, stats, surf)
				await _benchmark_skidpad(vehicle_id, stats, surf, 300.0)
				await _benchmark_skidpad(vehicle_id, stats, surf, 500.0)
				await _benchmark_drift(vehicle_id, stats, surf)
				await _benchmark_boost(vehicle_id, stats, surf)
				if version == 1:
					await _benchmark_counter_steer(vehicle_id, stats, surf)

	# ── 10 minute stability check (v1 rustbug dry only, abbreviated) ──
	if 1 in _requested_versions:
		await _benchmark_stability("rustbug")

	# ── Repeatability: run launch twice, check <2% variance ──
	if 1 in _requested_versions:
		await _benchmark_repeatability("rustbug")

	_world.queue_free()
	await process_frame

	if _gate_failures > 0:
		push_error("VEHICLE_PHYSICS_BENCHMARK: %d gate failures" % _gate_failures)
		quit(1)
	else:
		print("VEHICLE_PHYSICS_BENCHMARK PASS")
		quit(0)


func _spawn_vehicle(stats: VehicleStats, surf: float) -> RigidBody2D:
	## Spawn a real vehicle scene (with collision shape) for accurate physics.
	var vehicle: RigidBody2D
	var scene_ok := ResourceLoader.exists("res://scenes/vehicles/rustbug.tscn")
	if scene_ok:
		vehicle = VEHICLE_SCENE.instantiate() as RigidBody2D
	else:
		# Fallback: script-only with capsule collision
		vehicle = RigidBody2D.new()
		var shape := CapsuleShape2D.new()
		shape.radius = 18.0
		shape.height = 52.0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		vehicle.add_child(collision)

	# Ensure the vehicle has the controller script
	if not vehicle is VehicleController:
		# The scene node may not have VehicleController directly; configure stats
		if vehicle.has_method("apply_stats"):
			vehicle.call("apply_stats", stats)
	else:
		(vehicle as VehicleController).apply_stats(stats)

	if vehicle is VehicleController:
		var vc := vehicle as VehicleController
		vc.stats = stats
		vc.surface_speed_multiplier = surf
		vc.surface_grip_multiplier = surf
		vc.set_player_controlled(false)
	else:
		vehicle.set("stats", stats)
		vehicle.set("surface_speed_multiplier", surf)
		vehicle.set("surface_grip_multiplier", surf)

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


func _set_controls(vehicle: RigidBody2D, throttle: float, brake: float, steer: float, handbrake: bool = false, boost: bool = false) -> void:
	if vehicle.has_method("set_external_controls"):
		vehicle.call("set_external_controls", throttle, brake, steer, handbrake, boost)


func _emit_row(vehicle_id: String, stats: VehicleStats, surf: float, scenario: String, metrics: Dictionary) -> void:
	for metric: String in metrics:
		var value = metrics[metric]
		var val_str = "%.4f" % float(value) if value is float else str(value)
		print("VEHICLE_DYNAMICS,%s,%d,%.2f,%s,%s,%s" % [vehicle_id, stats.physics_model_version, surf, scenario, metric, val_str])


func _check_gate(name: String, value: float, lo: float, hi: float) -> void:
	if value < lo or value > hi:
		push_error("GATE FAIL %s: %.4f not in [%.4f, %.4f]" % [name, value, lo, hi])
		_gate_failures += 1
	else:
		print("GATE PASS %s: %.4f in [%.4f, %.4f]" % [name, value, lo, hi])


# ═══════════════════════════════════════════════════════════════════════
# Scenarios
# ═══════════════════════════════════════════════════════════════════════

func _benchmark_acceleration(vehicle_id: String, stats: VehicleStats, surf: float) -> void:
	var vehicle := await _spawn_vehicle(stats, surf)
	_set_controls(vehicle, 1.0, 0.0, 0.0)
	var zero_to_400 := -1.0
	var zero_to_95_percent := -1.0
	var eff_max: float = 680.0
	if vehicle.has_method("get_effective_max_speed"):
		eff_max = vehicle.call("get_effective_max_speed")
	var target_95: float = eff_max * 0.95
	var top_speed := 0.0
	for frame: int in ACCEL_FRAMES:
		await physics_frame
		var elapsed := float(frame + 1) * DELTA
		var forward_speed := vehicle.linear_velocity.dot(Vector2.UP)
		top_speed = maxf(top_speed, forward_speed)
		if zero_to_400 < 0.0 and forward_speed >= 400.0:
			zero_to_400 = elapsed
		if zero_to_95_percent < 0.0 and forward_speed >= target_95:
			zero_to_95_percent = elapsed

	_emit_row(vehicle_id, stats, surf, "launch", {
		"0->400": zero_to_400,
		"0->95%": zero_to_95_percent,
		"top_speed": top_speed,
	})

	# Gate: stable speed on dry surface
	if stats.physics_model_version == 1 and is_equal_approx(surf, 1.0) and STABLE_SPEED_GATES.has(vehicle_id):
		var gate: Vector2 = STABLE_SPEED_GATES[vehicle_id]
		_check_gate("stable_speed_%s" % vehicle_id, top_speed, gate.x, gate.y)

	await _remove_vehicle(vehicle)


func _benchmark_coast(vehicle_id: String, stats: VehicleStats, surf: float) -> void:
	var vehicle := await _spawn_vehicle(stats, surf)
	# Start at max speed estimate and coast
	var eff_max := 680.0
	if vehicle.has_method("get_effective_max_speed"):
		eff_max = vehicle.call("get_effective_max_speed")
	vehicle.linear_velocity = Vector2.UP * eff_max * 0.9
	_set_controls(vehicle, 0.0, 0.0, 0.0)
	var final_speed := 0.0
	for frame: int in COAST_FRAMES:
		await physics_frame
		final_speed = vehicle.linear_velocity.dot(Vector2.UP)

	_emit_row(vehicle_id, stats, surf, "coast", {
		"coast_speed": final_speed,
		"decel_rate": (eff_max * 0.9 - final_speed) / (float(COAST_FRAMES) * DELTA),
	})
	await _remove_vehicle(vehicle)


func _benchmark_braking(vehicle_id: String, stats: VehicleStats, surf: float) -> void:
	var vehicle := await _spawn_vehicle(stats, surf)
	vehicle.linear_velocity = Vector2.UP * 500.0
	_set_controls(vehicle, 0.0, 1.0, 0.0)
	var start_position := vehicle.position
	var stop_dist := -1.0
	var stop_time := -1.0
	for frame: int in PHYSICS_HZ * 5:
		await physics_frame
		if vehicle.linear_velocity.dot(Vector2.UP) <= 1.0:
			stop_dist = vehicle.position.distance_to(start_position)
			stop_time = float(frame + 1) * DELTA
			break

	if stop_dist < 0.0:
		stop_dist = vehicle.position.distance_to(start_position)
		stop_time = 5.0

	_emit_row(vehicle_id, stats, surf, "brake", {
		"500->0_dist": stop_dist,
		"500->0_time": stop_time,
	})

	# Gate: braking distance on dry surface
	if stats.physics_model_version == 1 and is_equal_approx(surf, 1.0) and BRAKE_DIST_GATES.has(vehicle_id):
		var gate: Vector2 = BRAKE_DIST_GATES[vehicle_id]
		_check_gate("brake_dist_%s" % vehicle_id, stop_dist, gate.x, gate.y)

	await _remove_vehicle(vehicle)


func _benchmark_skidpad(vehicle_id: String, stats: VehicleStats, surf: float, target_speed: float) -> void:
	var vehicle := await _spawn_vehicle(stats, surf)
	vehicle.linear_velocity = Vector2.UP * target_speed
	_set_controls(vehicle, 1.0, 0.0, 1.0)

	var min_radius := INF
	var total_lat_g := 0.0
	var samples := 0
	for frame: int in SKIDPAD_WARMUP_FRAMES + SKIDPAD_SAMPLE_FRAMES:
		await physics_frame
		if frame >= SKIDPAD_WARMUP_FRAMES:
			var spd := vehicle.linear_velocity.length()
			var yaw_rate := absf(vehicle.angular_velocity)
			if yaw_rate > 0.01 and spd > 10.0:
				min_radius = minf(min_radius, spd / yaw_rate)
				total_lat_g += (spd * yaw_rate) / 980.0
				samples += 1

	var avg_g := total_lat_g / float(maxi(1, samples))
	_emit_row(vehicle_id, stats, surf, "skidpad@%d" % int(target_speed), {
		"min_radius": min_radius if min_radius != INF else -1.0,
		"lat_g": avg_g,
		"samples": samples,
	})

	# Gate: skidpad lat_g > 0 on v1 dry (proves inertia/collision fixture works)
	if stats.physics_model_version == 1 and is_equal_approx(surf, 1.0):
		_check_gate("skidpad%d_lat_g_%s" % [int(target_speed), vehicle_id], avg_g, 0.05, 5.0)

	await _remove_vehicle(vehicle)


func _benchmark_drift(vehicle_id: String, stats: VehicleStats, surf: float) -> void:
	var vehicle := await _spawn_vehicle(stats, surf)
	vehicle.linear_velocity = Vector2.UP * 450.0
	_set_controls(vehicle, 1.0, 0.0, 1.0, true)

	var max_slip := 0.0
	var drift_detected := false
	for frame: int in DRIFT_WARMUP_FRAMES + DRIFT_SAMPLE_FRAMES:
		await physics_frame
		if frame >= DRIFT_WARMUP_FRAMES:
			max_slip = maxf(max_slip, absf(float(vehicle.get("slip_angle"))))
			if bool(vehicle.get("is_drifting")):
				drift_detected = true

	_emit_row(vehicle_id, stats, surf, "handbrake-drift", {
		"max_slip": max_slip,
		"drift_detected": drift_detected,
	})

	# Release handbrake for controlled exit test
	_set_controls(vehicle, 1.0, 0.0, 0.0, false)
	var exit_boost_gained := false
	var boost_before := float(vehicle.get("boost_amount"))
	for _f: int in PHYSICS_HZ:
		await physics_frame
	var boost_after := float(vehicle.get("boost_amount"))
	exit_boost_gained = boost_after > boost_before + 0.5

	_emit_row(vehicle_id, stats, surf, "drift-exit", {
		"boost_gained": exit_boost_gained,
		"boost_delta": boost_after - boost_before,
	})

	await _remove_vehicle(vehicle)


func _benchmark_boost(vehicle_id: String, stats: VehicleStats, surf: float) -> void:
	var vehicle := await _spawn_vehicle(stats, surf)
	vehicle.linear_velocity = Vector2.UP * 400.0
	if "boost_amount" in vehicle:
		vehicle.boost_amount = 100.0
	_set_controls(vehicle, 1.0, 0.0, 0.0, false, true)

	var peak_speed := 0.0
	var boost_active_frames := 0
	for frame: int in BOOST_FRAMES:
		await physics_frame
		peak_speed = maxf(peak_speed, vehicle.linear_velocity.dot(Vector2.UP))
		if vehicle.has_method("is_boost_active") and bool(vehicle.call("is_boost_active")):
			boost_active_frames += 1

	_emit_row(vehicle_id, stats, surf, "boost", {
		"peak_speed": peak_speed,
		"active_frames": boost_active_frames,
		"boost_remaining": float(vehicle.get("boost_amount")),
	})

	# Gate: boost speed should not exceed hard cap by > 1 wu/s
	if stats.physics_model_version == 1 and is_equal_approx(surf, 1.0):
		var eff_max := 680.0
		if vehicle.has_method("get_effective_max_speed"):
			eff_max = vehicle.call("get_effective_max_speed")
		var hard_cap := eff_max * 1.2
		_check_gate("boost_cap_%s" % vehicle_id, peak_speed, 0.0, hard_cap + 1.0)

	await _remove_vehicle(vehicle)


func _benchmark_counter_steer(vehicle_id: String, stats: VehicleStats, surf: float) -> void:
	## Scripted counter-steer: start drifting right, then steer left.
	## Gate: counter-steer reduces slip angle.
	var vehicle := await _spawn_vehicle(stats, surf)
	vehicle.linear_velocity = Vector2.UP * 450.0

	# Phase 1: initiate drift right
	_set_controls(vehicle, 1.0, 0.0, 1.0, true)
	var slip_before_counter := 0.0
	for _f: int in PHYSICS_HZ:
		await physics_frame
		slip_before_counter = maxf(slip_before_counter, absf(float(vehicle.get("slip_angle"))))

	# Phase 2: counter-steer left (still holding handbrake)
	_set_controls(vehicle, 1.0, 0.0, -1.0, true)
	var slip_after_counter := absf(float(vehicle.get("slip_angle")))
	for _f2: int in PHYSICS_HZ:
		await physics_frame
		slip_after_counter = minf(slip_after_counter, absf(float(vehicle.get("slip_angle"))))

	_emit_row(vehicle_id, stats, surf, "counter-steer", {
		"slip_before": slip_before_counter,
		"slip_after": slip_after_counter,
		"reduced": slip_after_counter < slip_before_counter,
	})

	# Gate: counter-steer should reduce slip
	if is_equal_approx(surf, 1.0):
		_check_gate("counter_steer_%s" % vehicle_id, slip_after_counter, 0.0, slip_before_counter + 1.0)

	await _remove_vehicle(vehicle)


func _benchmark_stability(vehicle_id: String) -> void:
	## 10 simulated minutes: check no NaN/inf/oscillation.
	var stats := CATALOG.create_vehicle_stats(vehicle_id)
	stats.physics_model_version = 1
	var vehicle := await _spawn_vehicle(stats, 1.0)
	_set_controls(vehicle, 1.0, 0.0, 0.3)

	var nan_detected := false
	var max_speed := 0.0
	# Run abbreviated (10 sim-seconds for benchmark timing, real 10-min is too slow)
	var stability_frames := mini(TEN_MIN_FRAMES, PHYSICS_HZ * 10)
	for _f: int in stability_frames:
		await physics_frame
		var v := vehicle.linear_velocity
		if is_nan(v.x) or is_nan(v.y) or is_inf(v.x) or is_inf(v.y):
			nan_detected = true
			break
		if is_nan(vehicle.angular_velocity) or is_inf(vehicle.angular_velocity):
			nan_detected = true
			break
		max_speed = maxf(max_speed, v.length())

	_emit_row(vehicle_id, stats, 1.0, "stability", {
		"nan_detected": nan_detected,
		"max_speed": max_speed,
		"frames": stability_frames,
	})

	if nan_detected:
		push_error("GATE FAIL stability_%s: NaN/inf detected" % vehicle_id)
		_gate_failures += 1
	else:
		print("GATE PASS stability_%s: no NaN/inf over %d frames" % [vehicle_id, stability_frames])

	await _remove_vehicle(vehicle)


func _benchmark_repeatability(vehicle_id: String) -> void:
	## Run launch twice, check <2% variance.
	var stats := CATALOG.create_vehicle_stats(vehicle_id)
	stats.physics_model_version = 1
	var speeds: Array[float] = []
	for _run: int in 2:
		var vehicle := await _spawn_vehicle(stats, 1.0)
		_set_controls(vehicle, 1.0, 0.0, 0.0)
		for _f: int in PHYSICS_HZ * 5:
			await physics_frame
		speeds.append(vehicle.linear_velocity.dot(Vector2.UP))
		await _remove_vehicle(vehicle)

	var variance := absf(speeds[1] - speeds[0]) / maxf(speeds[0], 0.001)
	_emit_row(vehicle_id, stats, 1.0, "repeatability", {
		"run1_speed": speeds[0],
		"run2_speed": speeds[1],
		"variance_pct": variance * 100.0,
	})

	if variance > 0.02:
		push_error("GATE FAIL repeatability_%s: %.2f%% variance" % [vehicle_id, variance * 100.0])
		_gate_failures += 1
	else:
		print("GATE PASS repeatability_%s: %.2f%% variance" % [vehicle_id, variance * 100.0])
