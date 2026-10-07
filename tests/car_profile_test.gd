extends SceneTree

## CarProfile: a roll moves every stat of its axis toward the edge of the
## parameter's range in the roll's direction, by the roll's share of the room
## left, so rolls of either sign apply in full and never leave the range; the
## shape reads stats back as 0..1 per axis.

const CATALOG := preload("res://data/championship/catalog.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for vehicle_id: String in CATALOG.vehicle_ids():
		var base := CATALOG.create_vehicle_stats(vehicle_id)
		var still := CarProfile.apply_roll(base, {})
		for axis: String in CarProfile.AXES:
			for field: String in CarProfile.AXIS_FIELDS[axis]:
				if not _expect(is_equal_approx(float(still.get(field)), float(base.get(field))), "%s: no roll leaves %s alone" % [vehicle_id, field]):
					return
		for amount: float in [0.3, -0.3]:
			for axis: String in CarProfile.AXES:
				var rolled := CarProfile.apply_roll(base, {axis: amount})
				for field: String in CarProfile.AXIS_FIELDS[axis]:
					var limits: Array = VehicleStats.PARAMETER_RANGES[field]
					var value := float(base.get(field))
					var moved := float(rolled.get(field))
					var edge := float(limits[1]) if amount > 0.0 else float(limits[0])
					if not _expect(moved >= float(limits[0]) and moved <= float(limits[1]), "%s %s stays inside its range" % [vehicle_id, field]):
						return
					if not _expect(is_equal_approx(moved - value, (edge - value) * absf(amount)), "%s %s moves %.1f of its room toward the edge" % [vehicle_id, field, amount]):
						return
				for other: String in CarProfile.AXES:
					if other == axis:
						continue
					for field: String in CarProfile.AXIS_FIELDS[other]:
						if not _expect(is_equal_approx(float(rolled.get(field)), float(base.get(field))), "%s: a %s roll leaves %s alone" % [vehicle_id, axis, field]):
							return
				var shape_before := CarProfile.shape(base)
				var shape_after := CarProfile.shape(rolled)
				var direction := signf(float(shape_after[axis]) - float(shape_before[axis]))
				if not _expect(direction == signf(amount) or is_equal_approx(float(shape_before[axis]), 1.0 if amount > 0.0 else 0.0), "%s: a %+.1f %s roll moves its corner the same way" % [vehicle_id, amount, axis]):
					return
		var shape := CarProfile.shape(base)
		if not _expect(shape.keys() == CarProfile.AXES, "%s has the six axes in order" % vehicle_id):
			return
		for axis: String in CarProfile.AXES:
			if not _expect(float(shape[axis]) >= 0.0 and float(shape[axis]) <= 1.0, "%s %s sits inside 0..1" % [vehicle_id, axis]):
				return
	print("CAR_PROFILE_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("CAR_PROFILE_TEST FAIL: " + message)
		quit(1)
	return condition
