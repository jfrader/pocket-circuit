class_name VehicleFeel
## Arcade chassis feel: downforce, axle load, and recoverable high-speed oversteer.
## Pure math. VehicleController applies forces; handbrake drift stays separate.

enum Slide { CALM, LOOSE, SAVING }

const Q_HARD_CAP := 0.6
const TRANSFER_CAP := 0.12
const FRONT_RATIO_MIN := 0.40
const FRONT_RATIO_MAX := 0.66
const DEMAND_LOOSE := 0.85
const DEMAND_SAVE := 0.72
const DEMAND_SPIN := 2.35
const SAVE_HOLD := 0.22
const AERO_FRONT_SHARE := 0.62
const REAR_MU_FLOOR := 0.86
const CORNER_ROTATE := 0.28
static func chassis(stats: VehicleStats, forward_speed: float, effective_max_speed: float, longitudinal_demand: float) -> Dictionary:
	var q := VehicleDynamics.downforce_q(forward_speed, effective_max_speed, stats.downforce_q_max)
	var loads := VehicleDynamics.axle_loads_with_transfer(
		stats.mass,
		stats.front_weight_ratio,
		longitudinal_demand,
		stats.weight_transfer_ratio,
		0.0,
	)
	var extra := clampf(q, 0.0, Q_HARD_CAP) * stats.mass * VehicleDynamics.REFERENCE_GRAVITY
	var front_load := float(loads["front"]) + extra * AERO_FRONT_SHARE
	var rear_load := float(loads["rear"]) + extra * (1.0 - AERO_FRONT_SHARE)
	return {
		"q": q,
		"front_load": front_load,
		"rear_load": rear_load,
		"front_ratio": float(loads["front_ratio"]),
		"speed_ratio": clampf(absf(forward_speed) / maxf(effective_max_speed, 0.001), 0.0, 1.2),
	}


static func rear_mu_scale(speed_ratio: float, throttle: float, steer: float) -> float:
	# Arcade stand-in for rear drive eating the friction circle: at speed the
	# tail is the weaker axle, more so with throttle and lock. Low speed is 1.
	var turning := clampf(absf(steer), 0.0, 1.0)
	var speed_w := smoothstep(0.48, 0.84, speed_ratio)
	var cut := lerpf(1.0, 0.90, speed_w * lerpf(0.35, 1.0, turning))
	cut *= lerpf(1.0, 0.94, speed_w * clampf(throttle, 0.0, 1.0))
	return clampf(cut, REAR_MU_FLOOR, 1.0)


static func corner_rotate(speed_ratio: float, steer: float, yaw_rate: float) -> float:
	# Unitless steer-directed yaw at speed. Zero when slow, straight, or
	# counter-steering — recovery is damping, not more spin.
	if absf(steer) < 0.16:
		return 0.0
	if absf(yaw_rate) > 0.05 and signf(steer) != signf(yaw_rate):
		return 0.0
	var speed_w := smoothstep(0.50, 0.86, speed_ratio)
	var already := clampf(absf(yaw_rate) / 3.6, 0.0, 1.0)
	return steer * speed_w * (1.0 - already * 0.7) * CORNER_ROTATE


static func rear_demand(slip_rad: float, cornering_stiffness: float, peak_grip: float, rear_load: float) -> float:
	var peak := peak_grip * rear_load
	if peak <= 0.001:
		return 0.0
	return absf(cornering_stiffness * slip_rad) / peak


static func step_slide(previous: Dictionary, sample: Dictionary, delta: float) -> Dictionary:
	var mode := int(previous.get("mode", Slide.CALM))
	var hold := float(previous.get("hold", 0.0))
	var handbrake := bool(sample.get("handbrake", false))
	var speed_ratio := float(sample.get("speed_ratio", 0.0))
	var min_ratio := float(sample.get("min_speed_ratio", 0.72))
	var demand := float(sample.get("rear_demand", 0.0))
	var steer := float(sample.get("steer", 0.0))
	var yaw_rate := float(sample.get("yaw_rate", 0.0))
	var fwd := float(sample.get("fwd_speed", 0.0))
	var pushing := absf(steer) >= 0.4 or float(sample.get("throttle", 0.0)) >= 0.55
	if handbrake:
		return {"mode": Slide.CALM, "hold": 0.0, "dust": false, "recover_damp": 0.0, "spin_cancel": false}
	var fast_enough := speed_ratio >= min_ratio and absf(fwd) > 80.0
	var loose_now := fast_enough and pushing and demand >= DEMAND_LOOSE
	var counter := absf(steer) > 0.12 and absf(yaw_rate) > 0.05 and signf(steer) != signf(yaw_rate)
	var spin := demand >= DEMAND_SPIN or fwd <= 0.0
	match mode:
		Slide.CALM:
			if loose_now:
				return {"mode": Slide.LOOSE, "hold": SAVE_HOLD, "dust": true, "recover_damp": 0.0, "spin_cancel": false}
			return {"mode": Slide.CALM, "hold": 0.0, "dust": false, "recover_damp": 0.0, "spin_cancel": false}
		Slide.LOOSE:
			if spin:
				return {"mode": Slide.CALM, "hold": 0.0, "dust": false, "recover_damp": 2.4, "spin_cancel": true}
			if counter:
				return {"mode": Slide.SAVING, "hold": SAVE_HOLD, "dust": true, "recover_damp": 3.0, "spin_cancel": false}
			if demand < DEMAND_SAVE or not fast_enough:
				hold -= delta
				if hold <= 0.0:
					return {"mode": Slide.CALM, "hold": 0.0, "dust": false, "recover_damp": 1.2, "spin_cancel": false}
				return {"mode": Slide.LOOSE, "hold": hold, "dust": true, "recover_damp": 0.6, "spin_cancel": false}
			return {"mode": Slide.LOOSE, "hold": SAVE_HOLD, "dust": true, "recover_damp": 0.4, "spin_cancel": false}
		_:
			if spin:
				return {"mode": Slide.CALM, "hold": 0.0, "dust": false, "recover_damp": 2.4, "spin_cancel": true}
			if demand < DEMAND_SAVE:
				hold -= delta
				if hold <= 0.0:
					return {"mode": Slide.CALM, "hold": 0.0, "dust": false, "recover_damp": 1.6, "spin_cancel": false}
				return {"mode": Slide.SAVING, "hold": hold, "dust": true, "recover_damp": 2.6, "spin_cancel": false}
			if counter:
				return {"mode": Slide.SAVING, "hold": SAVE_HOLD, "dust": true, "recover_damp": 3.0, "spin_cancel": false}
			return {"mode": Slide.LOOSE, "hold": SAVE_HOLD, "dust": true, "recover_damp": 0.8, "spin_cancel": false}


static func idle_slide() -> Dictionary:
	return {"mode": Slide.CALM, "hold": 0.0, "dust": false, "recover_damp": 0.0, "spin_cancel": false}
