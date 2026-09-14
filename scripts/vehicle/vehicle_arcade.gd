class_name VehicleArcade
extends RefCounted

## Body-space arcade stepper. Live handling for physics_model_version 2.
## Integrates with dt. Same model for player and AI. No Pacejka, no per-wheel.

const GRAVITY := 980.0


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


static func integrate(
	dt: float,
	steer: float,
	throttle: float,
	brake: float,
	handbrake: bool,
	boost_active: bool,
	fwd: float,
	lat: float,
	yaw: float,
	stats: VehicleStats,
	surface_grip_mult: float,
	surface_speed_mult: float,
	external_power_mult: float,
) -> Dictionary:
	dt = clampf(dt, 0.001, 0.05)
	steer = clampf(steer, -1.0, 1.0)
	throttle = clampf(throttle, 0.0, 1.0)
	brake = clampf(brake, 0.0, 1.0)
	var mass := maxf(stats.mass, 0.2)
	var vmax := get_effective_max_speed(stats, surface_speed_mult)
	var speed := absf(fwd)
	var speed_ratio := clampf(speed / maxf(vmax, 1.0), 0.0, 1.2)

	fwd = _integrate_longitudinal(
		dt, fwd, throttle, brake, handbrake, boost_active,
		stats, mass, vmax, surface_speed_mult, external_power_mult,
	)
	speed = absf(fwd)
	speed_ratio = clampf(speed / maxf(vmax, 1.0), 0.0, 1.2)

	var lock := deg_to_rad(stats.max_steer_angle_deg) * lerpf(
		1.0,
		stats.arcade_high_speed_steer_ratio,
		smoothstep(0.28, 0.88, speed_ratio),
	)
	var steer_rad := steer * lock
	var curvature := tan(steer_rad) / maxf(stats.wheelbase, 1.0)
	var yaw_wanted := fwd * curvature

	var over := 0.0
	if speed > vmax * 0.32 and absf(steer) > 0.12 and throttle > 0.2:
		over = stats.arcade_throttle_oversteer * throttle * smoothstep(0.32, 0.88, speed_ratio)
	if handbrake and speed > stats.drift_min_speed * 0.7:
		over = maxf(over, 0.78)

	yaw_wanted *= 1.0 + 0.7 * over

	var countering := absf(steer) > 0.12 and absf(yaw) > 0.08 and signf(steer) != signf(yaw)
	if countering:
		yaw = move_toward(yaw, 0.0, stats.steering_response * 2.4 * dt)
	elif handbrake:
		yaw += steer * 12.0 * dt
	else:
		var rate := stats.steering_response * (0.42 if over > 0.12 else 1.0)
		yaw = lerpf(yaw, yaw_wanted, 1.0 - exp(-rate * dt))

	var mu := get_effective_grip(stats, surface_grip_mult) * (1.0 - 0.5 * over)
	var lat_damp := mu * GRAVITY / maxf(speed, 90.0)
	lat = move_toward(lat, 0.0, lat_damp * dt)
	if over > 0.08 and not countering:
		lat += -signf(steer) * over * speed * 0.12 * dt

	var sliding := over > 0.1 and speed > 110.0 and absf(steer) > 0.12
	var drifting := handbrake and speed >= stats.drift_min_speed and absf(steer) >= stats.drift_entry_steer
	return {
		"fwd": fwd,
		"lat": lat,
		"yaw": yaw,
		"rack": steer_rad,
		"is_sliding": sliding,
		"is_drifting": drifting,
	}


static func _integrate_longitudinal(
	dt: float,
	fwd: float,
	throttle: float,
	brake: float,
	handbrake: bool,
	boost_active: bool,
	stats: VehicleStats,
	mass: float,
	vmax: float,
	surface_speed_mult: float,
	external_power_mult: float,
) -> float:
	var curve := VehicleDynamics.get_engine_torque_curve(
		absf(fwd), vmax,
		stats.launch_torque_multiplier, stats.torque_peak_ratio,
		stats.torque_at_max_speed, stats.torque_falloff_exponent,
	)
	if throttle > 0.0 and fwd < vmax:
		fwd += (throttle * stats.engine_force * curve * external_power_mult * surface_speed_mult / mass) * dt
	if boost_active:
		fwd += (stats.boost_power / mass) * dt
	if brake > 0.0:
		if fwd > 8.0:
			fwd -= (stats.brake_force * brake / mass) * dt
		elif fwd < -8.0:
			fwd += (stats.brake_force * brake / mass) * dt
		else:
			fwd = move_toward(fwd, -stats.reverse_speed * brake * 0.55, (stats.engine_force * 0.4 / mass) * dt)
	if handbrake:
		fwd = move_toward(fwd, 0.0, (stats.handbrake_force / mass) * dt)
	fwd -= (stats.aero_drag_coefficient * fwd * absf(fwd) / mass) * dt
	fwd -= (stats.rolling_resistance * signf(fwd) / mass) * dt
	return clampf(fwd, -stats.reverse_speed, vmax * 1.2)
