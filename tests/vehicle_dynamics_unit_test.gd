extends SceneTree

## Comprehensive unit tests for VehicleDynamics pure-math helpers.
## Covers: torque curve, drag, rolling, braking distance, corner speed,
## tire lateral force (linear + post-peak + falloff), load split, friction
## circle, steering rack, slip angles, progressive stiffness, soft cap,
## AI queries, and 60Hz simulation agreement within 8%.

const CATALOG := preload("res://data/championship/catalog.gd")
const EPSILON := 0.001
const VEHICLE_IDS: Array[String] = ["rustbug", "pinbolt", "scrapjaw", "flicker"]

var _failed := 0


func _init() -> void:
	print("Running VehicleDynamics Unit Tests...")
	var passed := 0

	# ── Torque curve ──
	passed += _assert_near("launch_torque",
		VehicleDynamics.get_engine_torque_curve(0.0, 100.0, 1.2, 0.3, 0.5, 2.0), 1.2)
	passed += _assert_near("peak_torque",
		VehicleDynamics.get_engine_torque_curve(30.0, 100.0, 1.2, 0.3, 0.5, 2.0), 1.0)
	passed += _assert_near("max_speed_torque",
		VehicleDynamics.get_engine_torque_curve(100.0, 100.0, 1.2, 0.3, 0.5, 2.0), 0.5)
	passed += _assert_near("mid_falloff",
		VehicleDynamics.get_engine_torque_curve(65.0, 100.0, 1.2, 0.3, 0.5, 2.0),
		lerpf(1.0, 0.5, pow((65.0/100.0 - 0.3) / 0.7, 2.0)))
	passed += _assert_near("zero_max_speed",
		VehicleDynamics.get_engine_torque_curve(50.0, 0.0, 1.2, 0.3, 0.5, 2.0), 0.0)
	var falloff_a := VehicleDynamics.get_engine_torque_curve(45.0, 100.0, 1.2, 0.3, 0.5, 2.0)
	var falloff_b := VehicleDynamics.get_engine_torque_curve(70.0, 100.0, 1.2, 0.3, 0.5, 2.0)
	var falloff_c := VehicleDynamics.get_engine_torque_curve(100.0, 100.0, 1.2, 0.3, 0.5, 2.0)
	passed += _assert_true("torque_falloff_monotonic", falloff_a > falloff_b and falloff_b > falloff_c)

	# ── Drag force ──
	passed += _assert_near("drag_100",
		VehicleDynamics.calculate_drag_force(100.0, 0.001), 10.0)
	passed += _assert_near("drag_negative",
		VehicleDynamics.calculate_drag_force(-100.0, 0.001), -10.0)
	passed += _assert_near("drag_zero",
		VehicleDynamics.calculate_drag_force(0.0, 0.001), 0.0)
	passed += _assert_true("drag_opposes_positive_motion",
		-VehicleDynamics.calculate_drag_force(100.0, 0.001) * 100.0 < 0.0)
	passed += _assert_true("drag_opposes_negative_motion",
		-VehicleDynamics.calculate_drag_force(-100.0, 0.001) * -100.0 < 0.0)

	# ── Rolling resistance ──
	passed += _assert_near("rolling_positive",
		VehicleDynamics.calculate_rolling_resistance(50.0, 18.0), 18.0)
	passed += _assert_near("rolling_negative",
		VehicleDynamics.calculate_rolling_resistance(-50.0, 18.0), -18.0)

	# ── Braking distance ──
	passed += _assert_near("brake_100_to_0",
		VehicleDynamics.get_braking_distance(100.0, 0.0, 50.0), 100.0)
	passed += _assert_near("brake_100_to_50",
		VehicleDynamics.get_braking_distance(100.0, 50.0, 50.0), 75.0)
	passed += _assert_near("brake_already_below",
		VehicleDynamics.get_braking_distance(50.0, 100.0, 50.0), 0.0)
	passed += _assert_near("brake_zero_decel",
		VehicleDynamics.get_braking_distance(100.0, 0.0, 0.0), 0.0)

	# ── Safe corner speed ──
	passed += _assert_near("corner_r100_a4",
		VehicleDynamics.get_safe_corner_speed(100.0, 4.0), 20.0)
	passed += _assert_near("corner_r0",
		VehicleDynamics.get_safe_corner_speed(0.0, 4.0), 0.0)
	passed += _assert_near("corner_r300_a980",
		VehicleDynamics.get_safe_corner_speed(300.0, 980.0), sqrt(980.0 * 300.0))

	# ── Tire lateral force (linear region) ──
	passed += _assert_near("tire_linear",
		VehicleDynamics.calculate_tire_lateral_force(0.1, 5000.0, 1.0, 1000.0, 0.8, 0.5), -500.0)

	# ── Tire lateral force (post-peak with falloff) ──
	# peak = 1000, demand = 2500, ratio = 2.5, falloff = max(0.8, 1-0.5*1.5) = max(0.8, 0.25) = 0.8
	passed += _assert_near("tire_postpeak",
		VehicleDynamics.calculate_tire_lateral_force(0.5, 5000.0, 1.0, 1000.0, 0.8, 0.5), -800.0)

	# ── Tire lateral force (negative slip) ──
	passed += _assert_near("tire_negative_slip",
		VehicleDynamics.calculate_tire_lateral_force(-0.1, 5000.0, 1.0, 1000.0, 0.8, 0.5), 500.0)
	var at_peak := absf(VehicleDynamics.calculate_tire_lateral_force(0.2, 5000.0, 1.0, 1000.0, 0.5, 0.25))
	var just_post_peak := absf(VehicleDynamics.calculate_tire_lateral_force(0.24, 5000.0, 1.0, 1000.0, 0.5, 0.25))
	var far_post_peak := absf(VehicleDynamics.calculate_tire_lateral_force(4.0, 5000.0, 1.0, 1000.0, 0.5, 0.25))
	passed += _assert_true("tire_peak_clamp", just_post_peak <= at_peak)
	passed += _assert_true("tire_post_peak_monotonic", far_post_peak <= just_post_peak)
	passed += _assert_near("tire_post_peak_floor", far_post_peak, 500.0)

	# ── Tire zero peak grip ──
	passed += _assert_near("tire_zero_peak",
		VehicleDynamics.calculate_tire_lateral_force(0.1, 5000.0, 0.0, 1000.0, 0.8, 0.5), 0.0)

	# ── Load split ──
	passed += _assert_near("front_normal_load",
		VehicleDynamics.calculate_axle_normal_load(0.88, 0.52, true),
		0.88 * 980.0 * 0.52)
	passed += _assert_near("rear_normal_load",
		VehicleDynamics.calculate_axle_normal_load(0.88, 0.52, false),
		0.88 * 980.0 * 0.48)

	# ── Progressive stiffness ──
	passed += _assert_near("prog_stiffness_1.0",
		VehicleDynamics.calculate_progressive_stiffness(1.0), 1.0)
	passed += _assert_near("prog_stiffness_0.25",
		VehicleDynamics.calculate_progressive_stiffness(0.25), 0.5)
	passed += _assert_near("prog_stiffness_low",
		VehicleDynamics.calculate_progressive_stiffness(0.45), sqrt(0.45))
	passed += _assert_true("surface_reduces_lateral_accel",
		VehicleDynamics.get_effective_lat_accel(_make_test_stats(), 0.45)
		< VehicleDynamics.get_effective_lat_accel(_make_test_stats(), 1.0))

	# ── Steering rack ──
	var target_deg := 32.0
	var target_rad := deg_to_rad(target_deg)
	passed += _assert_near("steer_target_low_speed",
		VehicleDynamics.calculate_target_steer_angle(1.0, target_deg, 0.0, 680.0, 0.48, 0.30),
		target_rad)
	# At max speed, should be reduced to target * high_speed_steer_ratio
	passed += _assert_near("steer_target_max_speed",
		VehicleDynamics.calculate_target_steer_angle(1.0, target_deg, 680.0, 680.0, 0.48, 0.30),
		target_rad * 0.48)
	var steer_mid := VehicleDynamics.calculate_target_steer_angle(1.0, target_deg, 400.0, 680.0, 0.48, 0.30)
	passed += _assert_true("steering_monotonic_with_speed",
		target_rad > steer_mid and steer_mid > target_rad * 0.48)

	# ── Rack angle update ──
	var rack := VehicleDynamics.update_rack_angle(0.0, 0.5, 8.5, 1.0 / 60.0)
	passed += _assert_true("rack_moves_toward_target", rack > 0.0 and rack < 0.5)
	var rack2 := VehicleDynamics.update_rack_angle(0.5, 0.5, 8.5, 1.0 / 60.0)
	passed += _assert_near("rack_at_target", rack2, 0.5)

	# ── Slip angles ──
	var slips := VehicleDynamics.calculate_slip_angles(
		100.0, 0.0, 0.0, 39.0, 0.52, 0.0)
	passed += _assert_near("slip_straight", float(slips["front"]), 0.0)
	passed += _assert_near("slip_rear_straight", float(slips["rear"]), 0.0)
	# Below threshold returns zero
	var slips_slow := VehicleDynamics.calculate_slip_angles(
		0.5, 10.0, 1.0, 39.0, 0.52, 0.1)
	passed += _assert_near("slip_slow_front", float(slips_slow["front"]), 0.0)

	# ── Friction circle braking ──
	var brakes := VehicleDynamics.calculate_brake_forces(
		1.0, 100.0, _make_test_stats(), 1.0, 0.0, 0.0)
	var front_brake := float(brakes["front_brake"])
	var rear_brake := float(brakes["rear_brake"])
	passed += _assert_true("brake_front_positive", front_brake > 0.0)
	passed += _assert_true("brake_rear_positive", rear_brake > 0.0)
	passed += _assert_true("brake_front_bias",
		front_brake > rear_brake)  # 62% front bias

	# Friction circle: with large lateral demand, brake capacity reduces
	var brakes_lat := VehicleDynamics.calculate_brake_forces(
		1.0, 100.0, _make_test_stats(), 1.0, 800.0, 600.0)
	var front_brake_lat := float(brakes_lat["front_brake"])
	passed += _assert_true("friction_circle_reduces_brake",
		front_brake_lat <= front_brake + 0.1)
	var light_stats := _make_test_stats()
	var heavy_stats := _make_test_stats()
	light_stats.mass = 0.70
	heavy_stats.mass = 1.20
	var light_distance := VehicleDynamics.get_braking_distance(
		500.0, 0.0, VehicleDynamics.get_effective_brake_accel(light_stats, 1.0))
	var heavy_distance := VehicleDynamics.get_braking_distance(
		500.0, 0.0, VehicleDynamics.get_effective_brake_accel(heavy_stats, 1.0))
	passed += _assert_true("braking_scales_with_mass", heavy_distance > light_distance)
	var dry_distance := VehicleDynamics.get_braking_distance(
		500.0, 0.0, VehicleDynamics.get_effective_brake_accel(_make_test_stats(), 1.0))
	var low_grip_distance := VehicleDynamics.get_braking_distance(
		500.0, 0.0, VehicleDynamics.get_effective_brake_accel(_make_test_stats(), 0.45))
	passed += _assert_true("braking_grows_on_low_grip", low_grip_distance > dry_distance)

	# ── Handbrake is rear-only ──
	var hb := VehicleDynamics.calculate_handbrake_force(true, 100.0, _make_test_stats())
	passed += _assert_true("handbrake_positive", hb > 0.0)
	var hb_off := VehicleDynamics.calculate_handbrake_force(false, 100.0, _make_test_stats())
	passed += _assert_near("handbrake_off", hb_off, 0.0)

	# ── Soft cap ──
	var soft_below := VehicleDynamics.calculate_soft_cap_force(600.0, 680.0, 0.88)
	passed += _assert_near("soft_cap_below", soft_below, 0.0)
	var soft_at := VehicleDynamics.calculate_soft_cap_force(680.0, 680.0, 0.88)
	passed += _assert_true("soft_cap_at_max", soft_at > 0.0)
	var soft_over := VehicleDynamics.calculate_soft_cap_force(700.0, 680.0, 0.88)
	passed += _assert_true("soft_cap_over_max", soft_over > 0.0)
	# Bounded: far overspeed saturates at SOFT_CAP_MAX_DECEL (0.5g), never an
	# unbounded quadratic spike after a sudden surface target change.
	var soft_far := VehicleDynamics.calculate_soft_cap_force(2000.0, 680.0, 0.88)
	passed += _assert_near("soft_cap_bounded", soft_far, soft_at)
	passed += _assert_true("soft_cap_le_half_g",
		absf(soft_far) / 0.88 <= VehicleDynamics.SOFT_CAP_MAX_DECEL + 0.01)

	# ── AI query consistency ──
	for vid: String in VEHICLE_IDS:
		var s := CATALOG.create_vehicle_stats(vid)
		s.physics_model_version = 1
		var eff_max := VehicleDynamics.get_effective_max_speed(s, 1.0)
		passed += _assert_near("eff_max_%s" % vid, eff_max, s.max_speed)
		var eff_grip := VehicleDynamics.get_effective_grip(s, 1.0)
		passed += _assert_near("eff_grip_%s" % vid, eff_grip,
			s.front_grip * s.front_weight_ratio + s.rear_grip * (1.0 - s.front_weight_ratio))
		var lat_accel := VehicleDynamics.get_effective_lat_accel(s, 1.0)
		passed += _assert_near("lat_accel_%s" % vid, lat_accel, eff_grip * 980.0)
		var corner := VehicleDynamics.get_safe_corner_speed(300.0, lat_accel)
		passed += _assert_near("corner_300_%s" % vid, corner, sqrt(lat_accel * 300.0))
		var brake_accel := VehicleDynamics.get_effective_brake_accel(s, 1.0)
		passed += _assert_true("brake_accel_pos_%s" % vid, brake_accel > 0.0)

	# ── Low-grip corner speed scales with sqrt(grip) ──
	var s_rb := CATALOG.create_vehicle_stats("rustbug")
	s_rb.physics_model_version = 1
	var corner_dry := VehicleDynamics.get_safe_corner_speed(
		300.0, VehicleDynamics.get_effective_lat_accel(s_rb, 1.0))
	var corner_wet := VehicleDynamics.get_safe_corner_speed(
		300.0, VehicleDynamics.get_effective_lat_accel(s_rb, 0.45))
	var grip_ratio := sqrt(0.45)  # expect roughly this ratio
	var actual_ratio := corner_wet / maxf(corner_dry, 0.001)
	passed += _assert_true("low_grip_corner_sqrt",
		absf(actual_ratio - grip_ratio) < 0.15)

	# ── 60 Hz Simulation agreement: straight-line speed within 8% ──
	for vid2: String in VEHICLE_IDS:
		var s2 := CATALOG.create_vehicle_stats(vid2)
		s2.physics_model_version = 1
		var sim := VehicleDynamics.simulate_straight_line(s2, 1.0, 0.0, 1.0, 1.0, 12.0)
		var analytical_max := s2.max_speed
		var sim_speed := float(sim["final_speed"])
		var agreement := absf(sim_speed - analytical_max) / maxf(analytical_max, 0.001)
		passed += _assert_true("sim_agreement_%s (%.1f vs %.1f = %.1f%%)" % [vid2, sim_speed, analytical_max, agreement * 100.0],
			agreement < 0.08)

	# ── Simulation braking agreement ──
	for vid3: String in VEHICLE_IDS:
		var s3 := CATALOG.create_vehicle_stats(vid3)
		s3.physics_model_version = 1
		var sim_brake := VehicleDynamics.simulate_braking(s3, 500.0, 1.0, 5.0)
		var analytical_dist := VehicleDynamics.predict_braking_distance(500.0, 0.0, s3, 1.0)
		var sim_dist := float(sim_brake["stop_distance"])
		var dist_agreement := absf(sim_dist - analytical_dist) / maxf(analytical_dist, 0.001)
		passed += _assert_true("brake_sim_%s (%.1f vs %.1f = %.1f%%)" % [vid3, sim_dist, analytical_dist, dist_agreement * 100.0],
			dist_agreement < 0.08)

	# ── Steady-state lateral accel agreement (skidpad) ──
	for vid4: String in VEHICLE_IDS:
		var s4 := CATALOG.create_vehicle_stats(vid4)
		s4.physics_model_version = 1
		var sim_skid := VehicleDynamics.simulate_skidpad(s4, 500.0, 1.0, 1.0, 3.0)
		var analytical_g := VehicleDynamics.get_effective_grip(s4, 1.0)
		var sim_g := float(sim_skid["lat_g"])
		passed += _assert_true("skidpad_sim_%s (%.3f vs %.3f)" % [vid4, sim_g, analytical_g],
			absf(sim_g - analytical_g) < analytical_g * 0.10)

	# ── Arcade downforce, transfer, and toy-scale speed ──
	passed += _assert_near("downforce_q_rest", VehicleDynamics.downforce_q(0.0, 680.0, 0.32), 0.0)
	passed += _assert_near("downforce_q_top", VehicleDynamics.downforce_q(680.0, 680.0, 0.32), 0.32)
	passed += _assert_true("downforce_q_capped", VehicleDynamics.downforce_q(680.0, 680.0, 4.0) <= 0.6)
	var coast_loads := VehicleDynamics.axle_loads_with_transfer(1.0, 0.52, 0.0, 0.16, 0.0)
	var accel_loads := VehicleDynamics.axle_loads_with_transfer(1.0, 0.52, 1.0, 0.16, 0.0)
	var brake_loads := VehicleDynamics.axle_loads_with_transfer(1.0, 0.52, -1.0, 0.16, 0.0)
	passed += _assert_true("transfer_accel_unloads_front", float(accel_loads["front"]) < float(coast_loads["front"]))
	passed += _assert_true("transfer_brake_loads_front", float(brake_loads["front"]) > float(coast_loads["front"]))
	var aero_brake := VehicleDynamics.calculate_brake_forces(1.0, 1.0, _make_test_stats(), 1.0, 0.0, 0.0, 0.32)
	var dry_brake := VehicleDynamics.calculate_brake_forces(1.0, 1.0, _make_test_stats(), 1.0, 0.0, 0.0, 0.0)
	passed += _assert_true(
		"downforce_boosts_brakes",
		absf(float(aero_brake["front_brake"])) + absf(float(aero_brake["rear_brake"]))
		> absf(float(dry_brake["front_brake"])) + absf(float(dry_brake["rear_brake"]))
	)
	for vid_len: String in VEHICLE_IDS:
		var slen := CATALOG.create_vehicle_stats(vid_len)
		var lps := VehicleDynamics.car_lengths_per_second(slen)
		passed += _assert_true("toy_scale_speed_%s (%.2f lengths/s)" % [vid_len, lps], lps >= 9.0 and lps <= 15.0)

	# ── Parameter range validation (all cars valid) ──
	for vid5: String in VEHICLE_IDS:
		var s5 := CATALOG.create_vehicle_stats(vid5)
		var errors := s5.get_validation_errors()
		passed += _assert_true("valid_%s (%d errors)" % [vid5, errors.size()],
			errors.is_empty())

	print("")
	if _failed > 0:
		push_error("VehicleDynamics unit tests: %d PASSED, %d FAILED" % [passed, _failed])
		quit(1)
	else:
		print("VehicleDynamics unit tests: %d PASSED, 0 FAILED" % passed)
		print("VehicleDynamics unit tests passed!")
		print("VEHICLE_DYNAMICS_UNIT_TEST PASS")
		quit(0)


func _assert_near(name: String, actual: float, expected: float, tolerance: float = EPSILON) -> int:
	if absf(actual - expected) <= tolerance:
		return 1
	push_error("FAIL %s: expected %.6f, got %.6f (diff %.6f)" % [name, expected, actual, absf(actual - expected)])
	_failed += 1
	return 0


func _assert_true(name: String, condition: bool) -> int:
	if condition:
		return 1
	push_error("FAIL %s" % name)
	_failed += 1
	return 0


func _make_test_stats() -> VehicleStats:
	var s := VehicleStats.new()
	s.physics_model_version = 1
	s.mass = 0.88
	s.wheelbase = 39.0
	s.front_weight_ratio = 0.52
	s.engine_force = 820.0
	s.launch_torque_multiplier = 1.08
	s.torque_peak_ratio = 0.30
	s.torque_at_max_speed = 0.37
	s.torque_falloff_exponent = 1.65
	s.max_speed = 680.0
	s.reverse_speed = 240.0
	s.rolling_resistance = 18.0
	s.aero_drag_coefficient = 0.000617
	s.front_grip = 1.15
	s.rear_grip = 1.18
	s.front_cornering_stiffness = 3600.0
	s.rear_cornering_stiffness = 3500.0
	s.post_peak_grip_ratio = 0.68
	s.slip_falloff_rate = 0.28
	s.max_steer_angle_deg = 32.0
	s.steering_response = 8.5
	s.high_speed_steer_ratio = 0.48
	s.steer_fade_start_ratio = 0.30
	s.yaw_stability_rate = 8.0
	s.brake_force = 1050.0
	s.handbrake_force = 270.0
	s.drift_min_speed = 130.0
	s.drift_entry_steer = 0.35
	s.drift_rear_grip_ratio = 0.40
	s.drift_yaw_assist = 2.0
	s.drift_grip_recovery_rate = 7.0
	s.drift_optimal_slip_deg = 26.0
	s.drift_boost_max_reward = 16.0
	s.boost_power = 560.0
	s.boost_capacity = 100.0
	s.boost_recharge = 10.0
	s.boost_drain_rate = 32.0
	s.durability = 52.0
	return s
