class_name VehicleArcade
extends RefCounted

## Pure functions for the arcade (v2) vehicle model.
## Small interface, no state, no RigidBody, no Pacejka, no per-wheel.
## Controller applies the returned forces/torques.
## Tuned for toy-car arcade: low-speed tight, high-speed tail can step out on throttle+steer (no handbrake required),
## handbrake is the strong committed drift for boost.

const REFERENCE_GRAVITY := 980.0


static func get_effective_max_speed(stats: VehicleStats, surface_speed_mult: float) -> float:
	return stats.max_speed * surface_speed_mult


static func get_effective_grip(stats: VehicleStats, surface_grip_mult: float) -> float:
	# Weighted by axle for consistency with dynamics queries; v2 uses front/rear grip values.
	return (
		stats.front_grip * stats.front_weight_ratio
		+ stats.rear_grip * (1.0 - stats.front_weight_ratio)
	) * surface_grip_mult


static func get_effective_lat_accel(stats: VehicleStats, surface_grip_mult: float) -> float:
	return get_effective_grip(stats, surface_grip_mult) * REFERENCE_GRAVITY


static func get_safe_corner_speed(radius: float, effective_lat_accel: float) -> float:
	if radius <= 0.0 or effective_lat_accel <= 0.0:
		return 0.0
	return sqrt(effective_lat_accel * radius)


static func calculate_engine_force(
	throttle: float,
	forward_speed: float,
	stats: VehicleStats,
	surface_speed_mult: float,
	external_power_mult: float,
) -> float:
	# Reuse the v1 curve logic; longitudinal is shared.
	if throttle <= 0.0:
		return 0.0
	var eff_max := get_effective_max_speed(stats, surface_speed_mult)
	if forward_speed >= eff_max:
		return 0.0
	var curve := VehicleDynamics.get_engine_torque_curve(
		absf(forward_speed), eff_max,
		stats.launch_torque_multiplier, stats.torque_peak_ratio,
		stats.torque_at_max_speed, stats.torque_falloff_exponent,
	)
	return throttle * stats.engine_force * curve * external_power_mult * surface_speed_mult


static func calculate_drag_force(speed: float, drag_coeff: float) -> float:
	return drag_coeff * speed * absf(speed)


static func calculate_rolling_resistance(speed: float, rolling_res: float) -> float:
	return rolling_res * signf(speed)


# ─────────────────────────────────────────────────────────────────────────
# Arcade step: computes forces and flags. Pure; caller applies to body.
# Returns: {
#   "engine_force": float, "drag_force": float, "brake_force": float, "boost_force": float,
#   "lateral_force": float,   # signed in body-right
#   "yaw_torque": float,
#   "rear_force_offset": float,  # for apply pos
#   "is_sliding": bool,
#   "is_drifting": bool,
# }
# Controller decides positions and calls apply.
static func compute_forces(
	steer: float,
	throttle: float,
	brake: float,
	handbrake: bool,
	dt: float,
	forward_vel: float,   # signed fwd speed
	lat_vel: float,
	yaw_rate: float,
	mass: float,
	stats: VehicleStats,
	surface_grip_mult: float,
	surface_speed_mult: float,
	external_power_mult: float,
	boost_active: bool,
) -> Dictionary:
	var eff_max := get_effective_max_speed(stats, surface_speed_mult)
	var speed := absf(forward_vel)
	var speed_ratio := clampf(speed / maxf(eff_max, 0.001), 0.0, 1.2)

	# 1. Longitudinal (reuse curve + drag/roll)
	var engine := calculate_engine_force(throttle, forward_vel, stats, surface_speed_mult, external_power_mult)
	var drag := calculate_drag_force(forward_vel, stats.aero_drag_coefficient)
	var roll := calculate_rolling_resistance(forward_vel, stats.rolling_resistance)
	var brake_f := 0.0
	if brake > 0.0:
		brake_f = stats.brake_force * brake
	var boost_f := 0.0
	if boost_active:
		boost_f = stats.boost_power

	# Handbrake adds rear long brake
	var hb_long := 0.0
	if handbrake:
		hb_long = VehicleDynamics.calculate_handbrake_force(true, forward_vel, stats)

	# 2. Steering: mild fade only (0.75-0.85 at top, default 0.82)
	var hsr := stats.arcade_high_speed_steer_ratio
	var fade := smoothstep(0.25, 0.85, speed_ratio)
	var steer_lock := deg_to_rad(stats.max_steer_angle_deg) * lerpf(1.0, hsr, fade)
	var steer_rad := clampf(steer, -1.0, 1.0) * steer_lock

	# Ideal yaw for no-slip cornering (ackermann approx)
	var ideal_yaw := 0.0
	if speed > 5.0:
		ideal_yaw = forward_vel * tan(steer_rad) / maxf(stats.wheelbase, 1.0)

	# 3. Single grip budget (use weighted grip for consistency)
	var mu := get_effective_grip(stats, surface_grip_mult)
	var max_lat_f := mu * mass * REFERENCE_GRAVITY

	# Throttle oversteer: reduce rear grip share at speed+throttle+steer (no hb needed)
	var rear_grip_mult := 1.0
	if speed > eff_max * 0.45 and absf(steer) > 0.08 and throttle > 0.25:
		var sw := smoothstep(0.45, 1.0, speed_ratio)
		rear_grip_mult = clampf(1.0 - stats.arcade_throttle_oversteer * sw * throttle, 0.35, 1.0)

	# Handbrake further reduces rear + adds committed yaw
	if handbrake:
		rear_grip_mult *= stats.drift_rear_grip_ratio

	# Demanded lat from current slip + steering desire (yaw error drives correction)
	var lat_demand := -lat_vel * 6.5   # base side-slip restoring stiffness (tuned for toy feel)
	var yaw_error := ideal_yaw - yaw_rate
	var yaw_correction := yaw_error * mass * stats.wheelbase * 0.55 * stats.steering_response * 0.08
	var demanded_lat := lat_demand + yaw_correction

	# Rear weakness shrinks the budget so throttle+steer at speed exceeds grip.
	max_lat_f *= clampf(0.50 + 0.50 * rear_grip_mult, 0.45, 1.0)
	var applied_lat := clampf(demanded_lat, -max_lat_f, max_lat_f)
	var excess := demanded_lat - applied_lat

	var inertia := mass * (stats.wheelbase * stats.wheelbase + 18.0 * 18.0) / 12.0
	var countering := absf(steer) > 0.12 and absf(yaw_rate) > 0.05 and signf(steer) != signf(yaw_rate)
	var yaw_torque := 0.0
	if countering:
		yaw_torque = -yaw_rate * inertia * stats.steering_response * 1.6
	else:
		yaw_torque = yaw_error * inertia * stats.steering_response * 0.55
		yaw_torque += signf(steer) * absf(excess) * stats.wheelbase * 0.22
		yaw_torque += steer * (1.0 - rear_grip_mult) * mass * stats.wheelbase * 2.8 * speed_ratio
		if handbrake:
			yaw_torque += stats.drift_yaw_assist * mass * 22.0 * steer

	var over_grip := absf(demanded_lat) > max_lat_f * 0.88
	var is_sliding := (over_grip or rear_grip_mult < 0.92) and speed > 120.0 and absf(steer) > 0.12

	# is_drifting only for committed handbrake (set by caller state machine too)
	var is_drifting := handbrake and speed >= stats.drift_min_speed and absf(steer) >= stats.drift_entry_steer * 0.7

	return {
		"engine_force": engine,
		"drag_force": drag,
		"roll_force": roll,
		"brake_force": brake_f,
		"hb_long_force": hb_long,
		"boost_force": boost_f,
		"lateral_force": applied_lat,
		"yaw_torque": yaw_torque,
		"is_sliding": is_sliding,
		"is_drifting": is_drifting,
		"rear_grip_mult": rear_grip_mult,  # informational
		"ideal_yaw": ideal_yaw,
	}
