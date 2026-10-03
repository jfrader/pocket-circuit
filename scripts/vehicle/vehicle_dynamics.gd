class_name VehicleDynamics
extends RefCounted

## Pure-math helpers for the bicycle/tire vehicle model (v1).
## No scene tree, no RigidBody2D — deterministic functions only.
## Used by both VehicleController and AI planner for consistent predictions.

const REFERENCE_GRAVITY := 980.0  # wu/s²
const SOFT_CAP_MAX_DECEL := 0.5 * REFERENCE_GRAVITY  # 490 wu/s² — passive surface-scrub bound
const FRONT_BRAKE_BIAS := 0.62
const KINEMATIC_BLEND_SPEED := 35.0  # wu/s
const HOLD_SPEED_THRESHOLD := 12.0  # wu/s below which brakes hold
const DRIFT_EXIT_SLIP_DEG := 6.0
const DRIFT_SPIN_SLIP_DEG := 60.0
const DRIFT_GRACE_DURATION := 0.20  # seconds
const DRIFT_MIN_QUALIFIED_TIME := 0.35  # seconds

# ─── Torque curve ────────────────────────────────────────────────────

static func get_engine_torque_curve(
	speed: float,
	max_speed: float,
	launch_mult: float,
	peak_ratio: float,
	at_max_speed: float,
	falloff_exp: float,
) -> float:
	if max_speed <= 0.0:
		return 0.0
	var ratio := clampf(speed / max_speed, 0.0, 1.0)
	if ratio < peak_ratio:
		return lerpf(launch_mult, 1.0, ratio / maxf(peak_ratio, 0.001))
	else:
		var post_peak_ratio := (ratio - peak_ratio) / maxf(1.0 - peak_ratio, 0.001)
		return lerpf(1.0, at_max_speed, pow(post_peak_ratio, falloff_exp))


# ─── Longitudinal forces ────────────────────────────────────────────

static func calculate_engine_force(
	throttle: float,
	forward_speed: float,
	stats: VehicleStats,
	surface_speed_mult: float,
	external_power_mult: float,
) -> float:
	var eff_max := stats.max_speed * surface_speed_mult
	if throttle <= 0.0 or forward_speed >= eff_max:
		return 0.0
	var curve := get_engine_torque_curve(
		absf(forward_speed), eff_max,
		stats.launch_torque_multiplier, stats.torque_peak_ratio,
		stats.torque_at_max_speed, stats.torque_falloff_exponent,
	)
	# Surface scales drive via speed_mult (spec: engine drive scaled by surface_speed_multiplier)
	return throttle * stats.engine_force * curve * external_power_mult * surface_speed_mult


static func calculate_drag_force(speed: float, drag_coeff: float) -> float:
	return drag_coeff * speed * absf(speed)


static func calculate_rolling_resistance(speed: float, rolling_res: float) -> float:
	return rolling_res * signf(speed)


static func calculate_soft_cap_force(
	forward_speed: float,
	effective_max_speed: float,
	mass: float,
) -> float:
	## Drag-like overspeed force that ramps up near the target speed and
	## saturates at SOFT_CAP_MAX_DECEL. Returns a decelerating force magnitude
	## (positive = opposes direction).
	##
	## Bounded so a sudden surface target change (e.g. entering a slow zone at
	## speed) cannot produce an unbounded quadratic deceleration spike. The
	## bound is 0.5g ≈ 43% of the vehicle's friction-circle braking capacity,
	## a clearly passive magnitude that never approaches active braking.
	if absf(forward_speed) <= effective_max_speed * 0.95:
		return 0.0
	var overspeed_ratio := (absf(forward_speed) - effective_max_speed * 0.95) / maxf(effective_max_speed * 0.05, 0.01)
	var force := signf(forward_speed) * overspeed_ratio * overspeed_ratio * mass * REFERENCE_GRAVITY * 0.5
	var max_force := mass * SOFT_CAP_MAX_DECEL
	return clampf(force, -max_force, max_force)


# ─── Braking ─────────────────────────────────────────────────────────

static func calculate_brake_forces(
	brake_input: float,
	forward_speed: float,
	stats: VehicleStats,
	surface_grip_mult: float,
	front_lateral_demand: float,
	rear_lateral_demand: float,
	downforce_q_value: float = 0.0,
) -> Dictionary:
	## Returns {front_brake: float, rear_brake: float} accounting for
	## 62/38 front/rear bias and friction-circle capacity.
	var result: Array[float] = [0.0, 0.0]
	var loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
	calculate_brake_forces_into(brake_input, forward_speed, stats, surface_grip_mult, front_lateral_demand, rear_lateral_demand, result, loads, downforce_q_value)
	return {"front_brake": result[0], "rear_brake": result[1]}


# Caller-owned Array[float] layouts (64-bit float, not PackedFloat32Array):
# brakes [front_brake, rear_brake], loads [front, rear, front_ratio, q],
# slips [front, rear]. Keep arrays sized to the documented layout across physics
# ticks. With zero brake input, brake forces are cleared but axle loads remain
# unchanged because no load-transfer calculation is needed.
static func calculate_brake_forces_into(
	brake_input: float,
	forward_speed: float,
	stats: VehicleStats,
	surface_grip_mult: float,
	front_lateral_demand: float,
	rear_lateral_demand: float,
	out: Array[float],
	loads: Array[float],
	downforce_q_value: float = 0.0,
) -> void:
	if brake_input <= 0.0:
		out[0] = 0.0
		out[1] = 0.0
		return

	var total_brake := stats.brake_force * brake_input
	var raw_front := total_brake * FRONT_BRAKE_BIAS
	var raw_rear := total_brake * (1.0 - FRONT_BRAKE_BIAS)

	# Friction circle: brake demand limited by remaining capacity after lateral
	axle_loads_with_transfer_into(stats.mass, stats.front_weight_ratio, -brake_input, stats.weight_transfer_ratio, downforce_q_value, loads)
	var front_normal := loads[0]
	var rear_normal := loads[1]
	var front_peak := stats.front_grip * surface_grip_mult * front_normal
	var rear_peak := stats.rear_grip * surface_grip_mult * rear_normal

	var front_lat_used := clampf(absf(front_lateral_demand) / maxf(front_peak, 0.001), 0.0, 1.0)
	var rear_lat_used := clampf(absf(rear_lateral_demand) / maxf(rear_peak, 0.001), 0.0, 1.0)

	# ABS-style clamp: remaining friction capacity (circle)
	var front_remaining := maxf(0.0, sqrt(maxf(0.0, 1.0 - front_lat_used * front_lat_used))) * front_peak
	var rear_remaining := maxf(0.0, sqrt(maxf(0.0, 1.0 - rear_lat_used * rear_lat_used))) * rear_peak

	var front_brake := minf(raw_front, front_remaining) * signf(forward_speed)
	var rear_brake := minf(raw_rear, rear_remaining) * signf(forward_speed)

	out[0] = front_brake
	out[1] = rear_brake


static func calculate_handbrake_force(
	handbrake_active: bool,
	forward_speed: float,
	stats: VehicleStats,
) -> float:
	## Rear-only longitudinal braking from handbrake.
	if not handbrake_active:
		return 0.0
	return stats.handbrake_force * signf(forward_speed)


# ─── Tire model ──────────────────────────────────────────────────────

static func calculate_tire_lateral_force(
	slip_angle_rad: float,
	cornering_stiffness: float,
	peak_grip: float,
	normal_load: float,
	post_peak_ratio: float,
	falloff_rate: float,
) -> float:
	var peak_force := peak_grip * normal_load
	if is_zero_approx(peak_force):
		return 0.0
	# Tire force always opposes the axle slip angle.
	var linear_force := -cornering_stiffness * slip_angle_rad
	var demand_ratio := absf(linear_force) / maxf(peak_force, 0.001)
	if demand_ratio <= 1.0:
		return linear_force
	else:
		var falloff := maxf(post_peak_ratio, 1.0 - falloff_rate * (demand_ratio - 1.0))
		return signf(linear_force) * peak_force * falloff


static func calculate_axle_normal_load(
	mass: float,
	front_weight_ratio: float,
	is_front: bool,
) -> float:
	var ratio := front_weight_ratio if is_front else (1.0 - front_weight_ratio)
	return mass * REFERENCE_GRAVITY * ratio


static func car_length_wu(stats: VehicleStats) -> float:
	return stats.wheelbase * 1.45


static func car_lengths_per_second(stats: VehicleStats) -> float:
	return stats.max_speed / maxf(car_length_wu(stats), 1.0)


static func downforce_q(speed: float, max_speed: float, q_max: float) -> float:
	var ratio := clampf(absf(speed) / maxf(max_speed, 0.001), 0.0, 1.0)
	return clampf(q_max, 0.0, 0.6) * ratio * ratio


static func axle_loads_with_transfer(
	mass: float,
	front_weight_ratio: float,
	longitudinal_demand: float,
	h_over_l: float,
	q: float,
) -> Dictionary:
	var result: Array[float] = [0.0, 0.0, 0.0, 0.0]
	axle_loads_with_transfer_into(mass, front_weight_ratio, longitudinal_demand, h_over_l, q, result)
	return {"front": result[0], "rear": result[1], "front_ratio": result[2], "q": result[3]}


static func axle_loads_with_transfer_into(
	mass: float, front_weight_ratio: float, longitudinal_demand: float,
	h_over_l: float, q: float, out: Array[float],
) -> void:
	var transfer := clampf(h_over_l * clampf(longitudinal_demand, -1.0, 1.0), -0.12, 0.12)
	var front_ratio := clampf(front_weight_ratio - transfer, 0.40, 0.66)
	var extra := clampf(q, 0.0, 0.6) * mass * REFERENCE_GRAVITY
	var base := mass * REFERENCE_GRAVITY
	out[0] = (base + extra) * front_ratio
	out[1] = (base + extra) * (1.0 - front_ratio)
	out[2] = front_ratio
	out[3] = clampf(q, 0.0, 0.6)


static func calculate_progressive_stiffness(surface_grip_mult: float) -> float:
	## Stiffness scales by sqrt(grip) for progressive feel on low-grip surfaces.
	return sqrt(maxf(surface_grip_mult, 0.01))


# ─── Steering rack ──────────────────────────────────────────────────

static func calculate_target_steer_angle(
	steer_input: float,
	max_steer_angle_deg: float,
	forward_speed: float,
	effective_max_speed: float,
	high_speed_steer_ratio: float,
	steer_fade_start_ratio: float,
) -> float:
	## Returns target steering angle in radians with speed-sensitive fade.
	var target := steer_input * deg_to_rad(max_steer_angle_deg)
	var speed_ratio := clampf(absf(forward_speed) / maxf(effective_max_speed, 0.001), 0.0, 1.0)
	if speed_ratio > steer_fade_start_ratio:
		var fade := (speed_ratio - steer_fade_start_ratio) / maxf(1.0 - steer_fade_start_ratio, 0.001)
		target *= lerpf(1.0, high_speed_steer_ratio, fade)
	return target


static func update_rack_angle(
	current_angle: float,
	target_angle: float,
	steering_response: float,
	delta: float,
) -> float:
	## Smoothly track target angle at the configured response rate.
	## Faster recenter (toward zero) for responsive turn-in but limited overshoot on release.
	var resp := steering_response
	if absf(target_angle) < absf(current_angle) or is_zero_approx(target_angle):
		resp *= 5.0  # faster recenter to limit overshoot on release (tap regression fix); attack rate unchanged
	var response := 1.0 - exp(-resp * delta)
	return lerpf(current_angle, target_angle, response)


# ─── Slip angles ─────────────────────────────────────────────────────

static func calculate_slip_angles(
	forward_speed: float,
	lateral_speed: float,
	yaw_rate: float,
	wheelbase: float,
	front_weight_ratio: float,
	steer_angle_rad: float,
) -> Dictionary:
	## Returns {front: float, rear: float} slip angles in radians.
	var result: Array[float] = [0.0, 0.0]
	calculate_slip_angles_into(forward_speed, lateral_speed, yaw_rate, wheelbase, front_weight_ratio, steer_angle_rad, result)
	return {"front": result[0], "rear": result[1]}


static func calculate_slip_angles_into(
	forward_speed: float, lateral_speed: float, yaw_rate: float,
	wheelbase: float, front_weight_ratio: float, steer_angle_rad: float,
	out: Array[float],
) -> void:
	if absf(forward_speed) < 1.0:
		out[0] = 0.0
		out[1] = 0.0
		return
	var front_arm := wheelbase * (1.0 - front_weight_ratio)
	var rear_arm := wheelbase * front_weight_ratio
	var v_front_lat := lateral_speed + yaw_rate * front_arm
	var v_rear_lat := lateral_speed - yaw_rate * rear_arm
	var front_slip := atan2(v_front_lat, absf(forward_speed)) - steer_angle_rad * signf(forward_speed)
	var rear_slip := atan2(v_rear_lat, absf(forward_speed))
	out[0] = front_slip
	out[1] = rear_slip


# ─── AI query helpers ────────────────────────────────────────────────

static func get_effective_max_speed(stats: VehicleStats, surface_speed_mult: float) -> float:
	return stats.max_speed * surface_speed_mult


static func get_effective_grip(stats: VehicleStats, surface_grip_mult: float) -> float:
	return (
		stats.front_grip * stats.front_weight_ratio
		+ stats.rear_grip * (1.0 - stats.front_weight_ratio)
	) * surface_grip_mult


static func get_effective_lat_accel(stats: VehicleStats, surface_grip_mult: float) -> float:
	## Returns the peak lateral acceleration in wu/s² for AI predictions.
	return get_effective_grip(stats, surface_grip_mult) * REFERENCE_GRAVITY


static func get_safe_corner_speed(radius: float, effective_lat_accel: float) -> float:
	## sqrt(a_lat * R) — steady-state cornering speed.
	if radius <= 0.0 or effective_lat_accel <= 0.0:
		return 0.0
	return sqrt(effective_lat_accel * radius)


static func get_braking_distance(
	v_now: float,
	v_target: float,
	effective_brake_accel: float,
) -> float:
	## Kinematic braking distance: (v² - v_t²) / (2a).
	if v_now <= v_target or effective_brake_accel <= 0.0:
		return 0.0
	return (v_now * v_now - v_target * v_target) / (2.0 * effective_brake_accel)


static func get_effective_brake_accel(stats: VehicleStats, surface_grip_mult: float, scratch: Array[float] = [], loads: Array[float] = []) -> float:
	## Effective braking deceleration in wu/s² for AI predictions.
	if scratch.is_empty():
		scratch = [0.0, 0.0]
	if loads.is_empty():
		loads = [0.0, 0.0, 0.0, 0.0]
	calculate_brake_forces_into(1.0, 1.0, stats, surface_grip_mult, 0.0, 0.0, scratch, loads)
	return (scratch[0] + scratch[1]) / maxf(stats.mass, 0.001)


static func predict_braking_distance(
	v_now: float,
	v_target: float,
	stats: VehicleStats,
	surface_grip_mult: float,
	surface_speed_mult: float = 1.0,
	scratch: Array[float] = [],
	loads: Array[float] = [],
) -> float:
	## Deterministic 60 Hz prediction using the same brake, drag, and rolling
	## terms as the controller. This is the public planner model query.
	## surface_speed_mult is retained for API compatibility; the controller no
	## longer scales drag/rolling by it (the surface target is enforced by the
	## bounded soft overspeed cap, which does not act during braking).
	if v_now <= v_target:
		return 0.0
	var speed := v_now
	var distance := 0.0
	var delta := 1.0 / 60.0
	if scratch.is_empty():
		scratch = [0.0, 0.0]
	if loads.is_empty():
		loads = [0.0, 0.0, 0.0, 0.0]
	for _step in 60 * 30:
		if speed <= v_target:
			break
		var brake_accel := get_effective_brake_accel(stats, surface_grip_mult, scratch, loads)
		var drag := calculate_drag_force(speed, stats.aero_drag_coefficient)
		var rolling := stats.rolling_resistance
		var decel := brake_accel + (drag + rolling) / maxf(stats.mass, 0.001)
		speed = maxf(v_target, speed - decel * delta)
		distance += speed * delta
	return distance


# ─── 60 Hz Euler simulation (for unit-test agreement) ────────────────

static func simulate_straight_line(
	stats: VehicleStats,
	throttle: float,
	initial_speed: float,
	surface_speed_mult: float,
	surface_grip_mult: float,
	duration_seconds: float,
	external_power_mult: float = 1.0,
) -> Dictionary:
	## Simulate a straight-line run at 60 Hz. Returns {final_speed, peak_speed,
	## time_to_400, time_to_95pct, distance}.
	var dt := 1.0 / 60.0
	var steps := int(duration_seconds * 60.0)
	var speed := initial_speed
	var distance := 0.0
	var peak_speed := initial_speed
	var time_to_400 := -1.0
	var time_to_95 := -1.0
	var eff_max := stats.max_speed * surface_speed_mult
	var target_95 := eff_max * 0.95

	for step in steps:
		var elapsed := float(step + 1) * dt
		var engine := calculate_engine_force(throttle, speed, stats, surface_speed_mult, external_power_mult)
		var drag := calculate_drag_force(speed, stats.aero_drag_coefficient)
		var rolling := calculate_rolling_resistance(speed, stats.rolling_resistance)
		var soft_cap := calculate_soft_cap_force(speed, eff_max, stats.mass)
		var net_force := engine - drag - rolling - soft_cap
		speed += (net_force / stats.mass) * dt
		speed = maxf(speed, 0.0)
		distance += speed * dt
		peak_speed = maxf(peak_speed, speed)
		if time_to_400 < 0.0 and speed >= 400.0:
			time_to_400 = elapsed
		if time_to_95 < 0.0 and speed >= target_95:
			time_to_95 = elapsed

	return {
		"final_speed": speed,
		"peak_speed": peak_speed,
		"time_to_400": time_to_400,
		"time_to_95pct": time_to_95,
		"distance": distance,
	}


static func simulate_braking(
	stats: VehicleStats,
	initial_speed: float,
	surface_grip_mult: float,
	duration_seconds: float,
) -> Dictionary:
	## Simulate braking at 60 Hz. Returns {stop_distance, stop_time}.
	var dt := 1.0 / 60.0
	var steps := int(duration_seconds * 60.0)
	var speed := initial_speed
	var distance := 0.0
	var brakes: Array[float] = [0.0, 0.0]
	var loads: Array[float] = [0.0, 0.0, 0.0, 0.0]

	for step in steps:
		if speed <= 1.0:
			return {"stop_distance": distance, "stop_time": float(step) * dt}
		calculate_brake_forces_into(1.0, speed, stats, surface_grip_mult, 0.0, 0.0, brakes, loads)
		var total_brake := absf(brakes[0]) + absf(brakes[1])
		var drag := calculate_drag_force(speed, stats.aero_drag_coefficient)
		var rolling := calculate_rolling_resistance(speed, stats.rolling_resistance)
		var decel := (total_brake + absf(drag) + absf(rolling)) / stats.mass
		speed = maxf(0.0, speed - decel * dt)
		distance += speed * dt

	return {"stop_distance": distance, "stop_time": duration_seconds}


static func simulate_skidpad(
	stats: VehicleStats,
	entry_speed: float,
	steer_input: float,
	surface_grip_mult: float,
	duration_seconds: float,
) -> Dictionary:
	## Approximate steady-state skidpad by computing the peak lateral g
	## achievable given the tire model. Returns {lat_g, min_radius}.
	var avg_grip := get_effective_grip(stats, surface_grip_mult)
	var peak_lat_accel := avg_grip * REFERENCE_GRAVITY
	var lat_g := peak_lat_accel / REFERENCE_GRAVITY
	var min_radius := 0.0
	if peak_lat_accel > 0.0:
		min_radius = entry_speed * entry_speed / peak_lat_accel
	return {"lat_g": lat_g, "min_radius": min_radius}
