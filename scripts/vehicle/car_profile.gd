class_name CarProfile
extends RefCounted

## A car's six-axis shape and the one mapping between those axes and its
## physics. A roll moves each axis's stats by that fraction of the room the
## base car has left toward the edge of the parameter's range, so a +0.18 and a
## -0.18 move the same distance in their own direction and nothing is clipped.
## The shape reads the same stats back inside VehicleStats ranges, so a shipped
## car and a won car are measured by the same rule.

const AXES: Array[String] = ["speed", "accel", "grip", "drift", "boost", "tough"]
const AXIS_FIELDS := {
	"speed": ["max_speed"],
	"accel": ["engine_force"],
	"grip": ["front_grip", "rear_grip"],
	"drift": ["drift_yaw_assist", "drift_boost_max_reward"],
	"boost": ["boost_power", "boost_capacity"],
	"tough": ["durability"],
}


## A copy of `base` with each axis's stats moved by roll[axis] (-1..1) of their
## remaining room toward the range edge in that direction.
static func apply_roll(base: VehicleStats, roll: Dictionary) -> VehicleStats:
	var rolled := base.duplicate(true) as VehicleStats
	for axis: String in AXES:
		var amount := clampf(float(roll.get(axis, 0.0)), -1.0, 1.0)
		for field: String in AXIS_FIELDS[axis]:
			var limits: Array = VehicleStats.PARAMETER_RANGES[field]
			var value := float(base.get(field))
			var edge := float(limits[1]) if amount > 0.0 else float(limits[0])
			rolled.set(field, value + (edge - value) * absf(amount))
	return rolled


## Each axis as 0..1: the mean position of its stats inside their ranges.
static func shape(stats: VehicleStats) -> Dictionary:
	var out := {}
	for axis: String in AXES:
		var total := 0.0
		for field: String in AXIS_FIELDS[axis]:
			var limits: Array = VehicleStats.PARAMETER_RANGES[field]
			total += inverse_lerp(float(limits[0]), float(limits[1]), float(stats.get(field)))
		out[axis] = clampf(total / float((AXIS_FIELDS[axis] as Array).size()), 0.0, 1.0)
	return out
