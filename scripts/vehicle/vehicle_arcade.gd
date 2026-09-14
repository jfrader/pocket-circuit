class_name VehicleArcade
extends RefCounted

## Marco Monster 2D split: longitudinal drive vs lateral friction.
## Forces go into RigidBody2D (do not overwrite velocity — that is ice).
## Lateral damping rate does not fall with speed.

const GRAVITY := 980.0
const LAT_DAMP := 72.0
const OVER_DAMP_REDUCE := 0.18
const OVER_YAW_BOOST := 0.0
const YAW_TORQUE_SCALE := 0.50
const OVER_SPEED_START := 0.62


static func get_effective_max_speed(stats: VehicleStats, surface_speed_mult: float) -> float:
	return stats.max_speed * surface_speed_mult


static func get_effective_grip(stats: VehicleStats, surface_grip_mult: float) -> float:
	return (
		stats.front_grip * stats.front_weight_ratio
		+ stats.rear_grip * (1.0 - stats.front_weight_ratio)
	) * surface_grip_mult


static func get_effective_lat_accel(stats: VehicleStats, surface_grip_mult: float) -> float:
	return get_effective_grip(stats, surface_grip_mult) * GRAVITY


static func get_safe_corner_speed(radius: float, effective_lat_accel: float) -> float:
	if radius <= 0.0 or effective_lat_accel <= 0.0:
		return 0.0
	return sqrt(effective_lat_accel * radius)


static func compute_forces(
	steer: float,
	throttle: float,
	brake: float,
	handbrake: bool,
	boost_active: bool,
	fwd: float,
	lat: float,
	yaw: float,
	stats: VehicleStats,
	mass: float,
	surface_grip_mult: float,
	surface_speed_mult: float,
	external_power_mult: float,
) -> Dictionary:
	steer = clampf(steer, -1.0, 1.0)
	throttle = clampf(throttle, 0.0, 1.0)
	brake = clampf(brake, 0.0, 1.0)
	mass = maxf(mass, 0.2)
	var vmax := get_effective_max_speed(stats, surface_speed_mult)
	var speed := absf(fwd)
	var speed_ratio := clampf(speed / maxf(vmax, 1.0), 0.0, 1.2)
	var curve := VehicleDynamics.get_engine_torque_curve(
		speed, vmax,
		stats.launch_torque_multiplier, stats.torque_peak_ratio,
		stats.torque_at_max_speed, stats.torque_falloff_exponent,
	)
	var engine := 0.0
	if throttle > 0.0 and fwd < vmax:
		engine = throttle * stats.engine_force * curve * external_power_mult * surface_speed_mult
	var boost_f := stats.boost_power if boost_active else 0.0
	var brake_f := 0.0
	if brake > 0.0 and absf(fwd) > 6.0:
		brake_f = stats.brake_force * brake * signf(fwd)
	var hb_f := 0.0
	if handbrake and absf(fwd) > 6.0:
		hb_f = stats.handbrake_force * signf(fwd)
	var drag := stats.aero_drag_coefficient * fwd * absf(fwd)
	var roll := stats.rolling_resistance * signf(fwd)
	var long_force := engine + boost_f - brake_f - hb_f - drag - roll
	var over := 0.0
	if speed > vmax * OVER_SPEED_START and absf(steer) > 0.18 and throttle > 0.35:
		over = stats.arcade_throttle_oversteer * throttle * smoothstep(OVER_SPEED_START, 0.92, speed_ratio)
	if handbrake and speed > stats.drift_min_speed * 0.65:
		over = maxf(over, 0.62)
	var damp := LAT_DAMP * surface_grip_mult * (1.0 - OVER_DAMP_REDUCE * over)
	var lat_force := -lat * mass * damp
	var lock := deg_to_rad(stats.max_steer_angle_deg) * lerpf(
		1.0,
		stats.arcade_high_speed_steer_ratio,
		smoothstep(0.22, 0.85, speed_ratio),
	)
	var steer_rad := steer * lock
	var yaw_wanted := 0.0
	if absf(fwd) > 5.0:
		yaw_wanted = fwd * tan(steer_rad) / maxf(stats.wheelbase, 1.0)
	yaw_wanted *= 1.0 + OVER_YAW_BOOST * over
	if speed_ratio > 0.74:
		yaw_wanted *= 0.52
	var inertia := mass * (stats.wheelbase * stats.wheelbase + 324.0) / 12.0
	var yaw_torque := 0.0
	var countering := absf(steer) > 0.12 and absf(yaw) > 0.08 and steer * yaw < 0.0
	if countering:
		yaw_torque = -yaw * inertia * 14.0
	elif handbrake:
		yaw_torque = steer * inertia * 8.0
	else:
		yaw_torque = (yaw_wanted - yaw) * inertia * stats.steering_response * YAW_TORQUE_SCALE
	return {
		"long_force": long_force,
		"lat_force": lat_force,
		"yaw_torque": yaw_torque,
		"rack": steer_rad,
		"is_sliding": over > 0.14 and speed > 150.0 and absf(steer) > 0.18,
		"is_drifting": handbrake and speed >= stats.drift_min_speed and absf(steer) >= stats.drift_entry_steer,
	}
