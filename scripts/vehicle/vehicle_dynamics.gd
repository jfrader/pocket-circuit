class_name VehicleDynamics
extends RefCounted

const REFERENCE_GRAVITY := 980.0

static func get_safe_corner_speed(radius: float, effective_lat_accel: float) -> float:
	return sqrt(effective_lat_accel * radius)

static func get_braking_distance(v_now: float, v_target: float, effective_brake_accel: float) -> float:
	if v_now <= v_target or effective_brake_accel <= 0.0:
		return 0.0
	return (v_now * v_now - v_target * v_target) / (2.0 * effective_brake_accel)

static func get_effective_max_speed(stats: VehicleStats, surface_speed_mult: float) -> float:
	return stats.max_speed * surface_speed_mult

static func get_effective_grip(stats: VehicleStats, surface_grip_mult: float) -> float:
	return (stats.front_grip + stats.rear_grip) * 0.5 * surface_grip_mult

static func get_engine_torque_curve(speed: float, max_speed: float, launch_mult: float, peak_ratio: float, at_max_speed: float, falloff_exp: float) -> float:
	if max_speed <= 0.0:
		return 0.0
	var ratio := clampf(speed / max_speed, 0.0, 1.0)
	if ratio < peak_ratio:
		return lerpf(launch_mult, 1.0, ratio / maxf(peak_ratio, 0.001))
	else:
		var post_peak_ratio := (ratio - peak_ratio) / maxf(1.0 - peak_ratio, 0.001)
		return lerpf(1.0, at_max_speed, pow(post_peak_ratio, falloff_exp))

static func calculate_drag_force(speed: float, drag_coeff: float) -> float:
	return drag_coeff * speed * absf(speed)

static func calculate_rolling_resistance(speed: float, rolling_res: float) -> float:
	return rolling_res * signf(speed)

static func calculate_tire_lateral_force(slip_angle_rad: float, cornering_stiffness: float, peak_grip: float, normal_load: float, post_peak_ratio: float, falloff_rate: float) -> float:
	var peak_force := peak_grip * normal_load
	if is_zero_approx(peak_force):
		return 0.0
	var linear_force := cornering_stiffness * slip_angle_rad
	var demand_ratio := absf(linear_force) / maxf(peak_force, 0.001)
	if demand_ratio <= 1.0:
		return linear_force
	else:
		var falloff := maxf(post_peak_ratio, 1.0 - falloff_rate * (demand_ratio - 1.0))
		return signf(linear_force) * peak_force * falloff
