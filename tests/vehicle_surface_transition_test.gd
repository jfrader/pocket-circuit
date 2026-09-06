extends SceneTree

## Surface-transition regression test using real RigidBody2D + VehicleController.
## Verifies the bounded surface-transition fix (GURI-557):
##   1. Entering a slow+low-grip zone never truncates velocity instantaneously.
##   2. Surface-target deceleration is finite and never exceeds the vehicle's
##      own friction-circle braking capacity.
##   3. Pure grip loss reduces tire forces, not sustained speed (no braking).
##   4. Slow material still reduces sustained speed toward its surface target.
##   5. Exiting a slow zone restores normal acceleration.
##   6. Boost entry does not truncate and stays within the dry boost ceiling.
## Thresholds are derived from physical braking capacity, not fit to failures.

const CATALOG := preload("res://data/championship/catalog.gd")
const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const PHYSICS_HZ := 60
const DELTA := 1.0 / float(PHYSICS_HZ)

var _world: Node2D
var _passed := 0
var _failed := 0
var _vehicle_id := "rustbug"


func _initialize() -> void:
	Engine.physics_ticks_per_second = PHYSICS_HZ
	Engine.time_scale = 1.0
	call_deferred("_run")


func _run() -> void:
	_world = Node2D.new()
	_world.name = "SurfaceTransitionWorld"
	root.add_child(_world)
	current_scene = _world

	for vehicle_id in ["rustbug", "pinbolt", "scrapjaw", "flicker"]:
		_vehicle_id = vehicle_id
		print("SURFACE_TRANSITION_CAR %s" % _vehicle_id)
		await _test_entry_no_truncation()
		await _test_bounded_deceleration()
		await _test_pure_grip_no_brake()
		await _test_slow_reduces_sustained()
		await _test_exit_restores_acceleration()
		await _test_boost_entry_bounded()

	_world.queue_free()
	await process_frame

	if _failed > 0:
		push_error("SURFACE_TRANSITION_TEST: %d passed, %d failed" % [_passed, _failed])
		quit(1)
	else:
		print("SURFACE_TRANSITION_TEST: %d passed, 0 failed" % _passed)
		print("SURFACE_TRANSITION_TEST PASS")
		quit(0)


func _spawn() -> VehicleController:
	var stats := CATALOG.create_vehicle_stats(_vehicle_id)
	stats.physics_model_version = 1
	var v := VEHICLE_SCENE.instantiate() as VehicleController
	v.apply_stats(stats)
	v.set_player_controlled(false)
	v.reset_dynamics_state()
	var vfx := v.get_node_or_null("VFX")
	if vfx:
		vfx.queue_free()
	_world.add_child(v)
	v.rotation = 0.0
	v.position = Vector2.ZERO
	v.linear_velocity = Vector2.ZERO
	v.angular_velocity = 0.0
	await physics_frame
	return v


func _remove(v: VehicleController) -> void:
	v.queue_free()
	await physics_frame


func _fwd(v: VehicleController) -> float:
	return v.linear_velocity.dot(Vector2.UP)


## Dry braking capacity expressed as a per-tick speed change (the physical bound
## the surface overspeed resistance must never exceed).
func _brake_per_tick(v: VehicleController) -> float:
	return VehicleDynamics.get_effective_brake_accel(v.stats, 1.0) * DELTA


func _check(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("SURFACE_TRANSITION_FAIL [%s: %s]" % [_vehicle_id, name])


func _test_entry_no_truncation() -> void:
	var v := await _spawn()
	v.linear_velocity = Vector2.UP * 600.0
	await physics_frame
	var pre := _fwd(v)
	v.apply_surface_modifier(101, &"bad zone", 0.45, 0.7)
	await physics_frame
	var post := _fwd(v)
	var drop := pre - post
	var eff_max := v.get_effective_max_speed()
	print("TRANSITION,entry,pre=%.2f,post=%.2f,drop=%.2f,eff_max=%.2f" % [pre, post, drop, eff_max])
	# Momentum must carry through: no instantaneous snap below the surface target.
	_check("entry_no_truncation (post > eff_max)", post > eff_max)
	# The one-tick drop must not exceed the vehicle's own braking capacity.
	_check("entry_drop_within_brake_capacity (%.2f <= %.2f)" % [drop, _brake_per_tick(v)], drop <= _brake_per_tick(v) + 0.001)
	await _remove(v)


func _test_bounded_deceleration() -> void:
	var v := await _spawn()
	v.linear_velocity = Vector2.UP * 600.0
	await physics_frame
	v.apply_surface_modifier(102, &"bad zone", 0.45, 0.7)
	var prev := _fwd(v)
	var max_drop := 0.0
	var brake_tick := _brake_per_tick(v)
	for i in 60:
		await physics_frame
		var cur := _fwd(v)
		max_drop = maxf(max_drop, prev - cur)
		prev = cur
	print("TRANSITION,bounded,max_one_tick_drop=%.2f,brake_per_tick=%.2f" % [max_drop, brake_tick])
	# Deceleration is finite and bounded across the whole entry transient.
	_check("bounded_deceleration (%.2f <= %.2f)" % [max_drop, brake_tick], max_drop <= brake_tick + 0.001)
	# Surface grip must still change (tire forces reduced, not removed).
	_check("grip_applied", is_equal_approx(v.surface_grip_multiplier, 0.45))
	_check("effective_grip_reduced",
		v.get_effective_grip() < VehicleDynamics.get_effective_grip(v.stats, 1.0))
	await _remove(v)


func _test_pure_grip_no_brake() -> void:
	var v := await _spawn()
	v.linear_velocity = Vector2.UP * 600.0
	await physics_frame
	v.apply_surface_modifier(103, &"slick", 0.45, 1.0)
	v.set_external_controls(1.0, 0.0, 0.0)
	# Hold throttle long enough to reach sustained speed.
	var sustained := 0.0
	for i in 180:
		await physics_frame
		sustained = _fwd(v)
	var dry_max := v.stats.max_speed
	print("TRANSITION,pure_grip,sustained=%.2f,dry_max=%.2f" % [sustained, dry_max])
	# Pure grip loss must NOT reduce sustained top speed (only tire forces).
	_check("pure_grip_sustains_dry_speed (%.2f > %.2f)" % [sustained, dry_max * 0.92], sustained > dry_max * 0.92)
	await _remove(v)


func _test_slow_reduces_sustained() -> void:
	var v := await _spawn()
	v.apply_surface_modifier(104, &"bad zone", 0.45, 0.7)
	v.set_external_controls(1.0, 0.0, 0.0)
	var sustained := 0.0
	for i in 240:
		await physics_frame
		sustained = _fwd(v)
	var eff_max := v.get_effective_max_speed()
	var dry_max := v.stats.max_speed
	print("TRANSITION,slow_sustained,sustained=%.2f,eff_max=%.2f,dry_max=%.2f" % [sustained, eff_max, dry_max])
	# Slow material reduces sustained speed to the surface target (below dry max)…
	_check("slow_reduces_sustained (%.2f < %.2f)" % [sustained, dry_max * 0.85], sustained < dry_max * 0.85)
	# …without collapsing far below the target.
	_check("slow_sustains_near_target (%.2f > %.2f)" % [sustained, eff_max * 0.8], sustained > eff_max * 0.8)
	await _remove(v)


func _test_exit_restores_acceleration() -> void:
	var v := await _spawn()
	v.linear_velocity = Vector2.UP * 600.0
	await physics_frame
	v.apply_surface_modifier(105, &"bad zone", 0.45, 0.7)
	v.set_external_controls(1.0, 0.0, 0.0)
	# Settle into the slow zone.
	for i in 120:
		await physics_frame
	var in_zone := _fwd(v)
	v.clear_surface_modifier(105)
	# Re-accelerate on dry.
	var after := 0.0
	for i in 120:
		await physics_frame
		after = _fwd(v)
	var dry_max := v.stats.max_speed
	print("TRANSITION,exit,in_zone=%.2f,after=%.2f,dry_max=%.2f" % [in_zone, after, dry_max])
	# Exit restores normal acceleration back toward the dry top speed.
	_check("exit_restores_acceleration (%.2f > %.2f)" % [after, in_zone], after > in_zone)
	_check("exit_recovers_toward_dry (%.2f > %.2f)" % [after, dry_max * 0.8], after > dry_max * 0.8)
	await _remove(v)


func _test_boost_entry_bounded() -> void:
	var v := await _spawn()
	v.boost_amount = 100.0
	v.linear_velocity = Vector2.UP * 600.0
	await physics_frame
	v.set_external_controls(1.0, 0.0, 0.0, false, true)
	await physics_frame
	var pre := _fwd(v)
	var brake_tick := _brake_per_tick(v)
	v.apply_surface_modifier(106, &"bad zone", 0.45, 0.7)
	await physics_frame
	var post := _fwd(v)
	var drop := pre - post
	var boost_cap := v.stats.max_speed * 1.2
	print("TRANSITION,boost_entry,pre=%.2f,post=%.2f,drop=%.2f,boost_cap=%.2f" % [pre, post, drop, boost_cap])
	# Boost entry must not truncate velocity.
	_check("boost_entry_bounded (%.2f <= %.2f)" % [drop, brake_tick], drop <= brake_tick + 0.001)
	# Speed must remain within the dry boost ceiling (no overshoot).
	_check("boost_within_cap (%.2f <= %.2f)" % [post, boost_cap], post <= boost_cap + 0.001)
	await _remove(v)
