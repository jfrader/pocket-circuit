extends SceneTree

const FEEL := preload("res://scripts/vehicle/vehicle_feel.gd")


func _init() -> void:
	var stats := VehicleStats.new()
	stats.max_speed = 680.0
	stats.mass = 1.0
	stats.front_weight_ratio = 0.52
	stats.downforce_q_max = 0.32
	stats.weight_transfer_ratio = 0.16
	var rest := FEEL.chassis(stats, 0.0, 680.0, 0.0)
	var top := FEEL.chassis(stats, 680.0, 680.0, 0.0)
	var accel := FEEL.chassis(stats, 400.0, 680.0, 1.0)
	var brake := FEEL.chassis(stats, 400.0, 680.0, -1.0)
	if not _expect(is_equal_approx(float(rest["q"]), 0.0), "downforce is off at rest"):
		return
	if not _expect(is_equal_approx(float(top["q"]), 0.32), "downforce reaches q_max at top speed"):
		return
	if not _expect(float(accel["front_load"]) < float(rest["front_load"]), "throttle unloads the nose"):
		return
	if not _expect(float(brake["front_load"]) > float(rest["front_load"]), "braking loads the nose"):
		return
	var peak_demand := FEEL.rear_demand(0.2, 3500.0, 1.18, 500.0)
	if not _expect(peak_demand > 1.0, "large slip is past the tire peak"):
		return
	var idle := FEEL.idle_slide()
	var loose := FEEL.step_slide(idle, {
		"speed_ratio": 0.9,
		"min_speed_ratio": 0.72,
		"rear_demand": 1.2,
		"steer": 1.0,
		"throttle": 0.8,
		"handbrake": false,
		"yaw_rate": 1.0,
		"fwd_speed": 600.0,
	}, 0.016)
	if not _expect(int(loose["mode"]) == FEEL.Slide.LOOSE and bool(loose["dust"]), "past-peak rear at speed should go loose"):
		return
	var saving := FEEL.step_slide(loose, {
		"speed_ratio": 0.9,
		"min_speed_ratio": 0.72,
		"rear_demand": 1.1,
		"steer": -0.8,
		"throttle": 0.4,
		"handbrake": false,
		"yaw_rate": 1.0,
		"fwd_speed": 580.0,
	}, 0.016)
	if not _expect(int(saving["mode"]) == FEEL.Slide.SAVING and float(saving["recover_damp"]) > 1.0, "counter-steer should enter a savable slide"):
		return
	var calm := idle
	for _step in 20:
		calm = FEEL.step_slide(saving if _step == 0 else calm, {
			"speed_ratio": 0.9,
			"min_speed_ratio": 0.72,
			"rear_demand": 0.4,
			"steer": -0.5,
			"throttle": 0.4,
			"handbrake": false,
			"yaw_rate": 0.2,
			"fwd_speed": 500.0,
		}, 0.05)
	if not _expect(int(calm["mode"]) == FEEL.Slide.CALM, "holding counter-steer after the tires grip should recover"):
		return
	var blocked := FEEL.step_slide(idle, {
		"speed_ratio": 0.9,
		"min_speed_ratio": 0.72,
		"rear_demand": 1.4,
		"steer": 1.0,
		"throttle": 1.0,
		"handbrake": true,
		"yaw_rate": 2.0,
		"fwd_speed": 600.0,
	}, 0.016)
	if not _expect(int(blocked["mode"]) == FEEL.Slide.CALM, "handbrake drift owns the tires; slide stays out"):
		return
	if not _expect(is_equal_approx(FEEL.rear_mu_scale(0.0, 1.0, 1.0), 1.0), "low speed keeps full rear grip"):
		return
	if not _expect(FEEL.rear_mu_scale(0.95, 0.2, 1.0) < FEEL.rear_mu_scale(0.2, 1.0, 1.0), "fast corners weaken the rear first"):
		return
	if not _expect(is_zero_approx(FEEL.corner_rotate(0.2, 1.0, 0.0)), "slow steering does not add rotation"):
		return
	if not _expect(FEEL.corner_rotate(0.9, 1.0, 0.2) > 0.0, "fast lock rotates the tail into the turn"):
		return
	if not _expect(is_zero_approx(FEEL.corner_rotate(0.9, -1.0, 1.0)), "counter-steer does not add spin"):
		return
	print("VEHICLE_FEEL_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("VEHICLE_FEEL_TEST FAIL: " + message)
	quit(1)
	return false
