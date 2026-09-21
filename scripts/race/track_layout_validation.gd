class_name TrackLayoutValidation
extends RefCounted

const MODULE_CATALOG := preload("res://scripts/race/track_module_catalog.gd")
const LEGACY_VALIDATION := preload("res://scripts/race/track_seed_gen.gd")

const HALF_WIDTH := 125.0
const RESERVED_RADIUS := 135.0
const MIN_TURN_RADIUS := 147.0
const MIN_SELF_DISTANCE := 320.0
const LOCAL_ARC_CUTOFF := 960.0
const MIN_SETUP_LENGTH := 450.0
const POSITION_EPSILON := 0.01
const FLATTEN_STEP := 20.0
const FLATTEN_ERROR := 0.02


static func validate_continuous(route: Dictionary, room_polygon: PackedVector2Array) -> Dictionary:
	if not bool(route.get("ok", false)):
		return _failure(&"analytic", &"invalid_route", "Route was not composed by the catalog kernel.")
	var primitives: Array = route.get("primitives", [])
	if primitives.size() < 4:
		return _failure(&"analytic", &"too_few_primitives", "A closed route needs at least four analytic primitives.")
	if room_polygon.size() < 3:
		return _failure(&"clearance", &"invalid_room", "Continuous validation needs a room polygon.")
	for index in primitives.size():
		var primitive: Dictionary = primitives[index]
		if float(primitive.get("length", 0.0)) <= 0.0:
			return _failure(&"analytic", &"zero_length", "Primitive %d has zero length." % index, index)
		if primitive["kind"] == &"arc" and float(primitive["radius"]) < MIN_TURN_RADIUS:
			return _failure(&"analytic", &"radius_floor", "Primitive %d radius is below %.0f." % [index, MIN_TURN_RADIUS], index)
		var next: Dictionary = primitives[(index + 1) % primitives.size()]
		var join := MODULE_CATALOG.validate_join(_primitive_exit_port(primitive), _primitive_entry_port(next))
		if not bool(join["valid"]):
			return _failure(&"analytic", &"port_join", "Primitive %d does not share an exact G1 pose with its successor." % index, index)
	var closure := MODULE_CATALOG.validate_join(route["exit_port"], route["entry_port"])
	if not bool(closure["valid"]):
		return _failure(&"analytic", &"loop_closure", "The final module does not close on the entry pose.")
	if absf(absf(float(route["signed_turn"])) - TAU) > 0.0001:
		return _failure(&"analytic", &"winding", "Total signed tangent turn is not +/-2PI.")
	for first in primitives.size():
		for second in range(first + 1, primitives.size()):
			var adjacent := second == first + 1 or (first == 0 and second == primitives.size() - 1)
			var contacts := _primitive_intersections(primitives[first], primitives[second])
			if contacts.is_empty():
				continue
			if adjacent and contacts.size() == 1 and (contacts[0] as Vector2).distance_to(primitives[first]["end"] if second == first + 1 else primitives[first]["start"]) <= POSITION_EPSILON:
				continue
			return _failure(&"analytic", &"self_intersection", "Primitives %d and %d intersect or retrace." % [first, second], first, second)
	var setup_count := _protected_setup_count(route)
	if setup_count < 2:
		return _failure(&"analytic", &"setup_straights", "Route has only %d distinct protected setup straight(s)." % setup_count)
	for pair: Dictionary in route.get("return_limb_pairs", []):
		if not bool(pair.get("certified", false)) or float(pair.get("separation", 0.0)) < MIN_SELF_DISTANCE:
			return _failure(&"clearance", &"return_limb_spacing", "A declared return-limb pair is below %.0f." % MIN_SELF_DISTANCE, int(pair.get("module_index", -1)))
	var cells := _flatten_route(route)
	for cell: Dictionary in cells:
		if not _cell_inside_room(cell, room_polygon, RESERVED_RADIUS):
			return _failure(&"clearance", &"room_sweep", "Reserved radius-135 sweep leaves the room polygon.", int(cell["primitive_index"]))
	var minimum_nonlocal := INF
	var minimum_return_limb := _minimum_endpoint_return_distance(primitives)
	if minimum_return_limb < MIN_SELF_DISTANCE:
		return _failure(&"clearance", &"return_limb_spacing", "Continuous endpoint return-limb distance is %.2f, below %.0f." % [minimum_return_limb, MIN_SELF_DISTANCE])
	for first in cells.size():
		var a: Dictionary = cells[first]
		for second in range(first + 1, cells.size()):
			var b: Dictionary = cells[second]
			var midpoint_separation := _cyclic_separation((float(a["s0"]) + float(a["s1"])) * 0.5, (float(b["s0"]) + float(b["s1"])) * 0.5, float(route["length"]))
			var possible_separation := midpoint_separation + (float(a["s1"]) - float(a["s0"]) + float(b["s1"]) - float(b["s0"])) * 0.5
			var closest := _segment_closest(a["from"], a["to"], b["from"], b["to"])
			var certified_distance := float(closest["distance"]) - float(a["error"]) - float(b["error"])
			if possible_separation >= LOCAL_ARC_CUTOFF:
				minimum_nonlocal = minf(minimum_nonlocal, certified_distance)
				if certified_distance < MIN_SELF_DISTANCE:
					return _failure(&"clearance", &"self_distance", "Continuous nonlocal self-distance is %.2f, below %.0f." % [certified_distance, MIN_SELF_DISTANCE], int(a["primitive_index"]), int(b["primitive_index"]))
			elif _stationary_return_pair(a, b, closest, primitives.size()):
				minimum_return_limb = minf(minimum_return_limb, certified_distance)
				if certified_distance < MIN_SELF_DISTANCE:
					return _failure(&"clearance", &"return_limb_spacing", "Continuous return-limb distance is %.2f, below %.0f." % [certified_distance, MIN_SELF_DISTANCE], int(a["primitive_index"]), int(b["primitive_index"]))
	return {
		"ok": true,
		"valid": true,
		"stage": &"continuous",
		"primitive_count": primitives.size(),
		"module_count": (route.get("modules", []) as Array).size(),
		"length": float(route["length"]),
		"signed_turn": float(route["signed_turn"]),
		"minimum_radius": _minimum_analytic_radius(primitives),
		"minimum_nonlocal_distance": minimum_nonlocal,
		"minimum_return_limb_distance": minimum_return_limb,
		"setup_straight_count": setup_count,
		"corridor_half_width": HALF_WIDTH,
		"reserved_sweep_radius": RESERVED_RADIUS,
	}


static func validate_sampled(route: Dictionary, sampling: Dictionary, room_polygon: PackedVector2Array) -> Dictionary:
	if not bool(sampling.get("ok", false)):
		return _failure(&"runtime_samples", &"sampling_failed", String(sampling.get("error", "Sampling failed.")))
	var points: PackedVector2Array = sampling["points"]
	if points.size() < 260:
		return _failure(&"runtime_samples", &"sample_count", "Runtime route has fewer than 260 samples.")
	if float(sampling.get("maximum_arc_step", INF)) > 35.0 + 0.0001:
		return _failure(&"runtime_samples", &"arc_step", "Runtime arc step exceeds 35 units.")
	if float(sampling.get("maximum_chord_deviation", INF)) > 0.25 + 0.0001:
		return _failure(&"runtime_samples", &"chord_deviation", "Runtime chord deviation exceeds 0.25 units.")
	var polyline_check := _sampled_segment_checks(points, float(route["length"]), room_polygon, float(sampling["maximum_chord_deviation"]))
	if not bool(polyline_check.get("valid", false)):
		return polyline_check
	var room_bounds := _points_rect(room_polygon)
	var gameplay := LEGACY_VALIDATION.validate_centerline_samples(points, room_bounds, room_polygon, RESERVED_RADIUS, MIN_SELF_DISTANCE, 0.0, INF)
	if not bool(gameplay.get("valid", false)):
		return _failure(&"gameplay", &"sampled_gameplay", String(gameplay.get("reason", "Existing gameplay validation failed.")))
	return {
		"ok": true,
		"valid": true,
		"stage": &"sampled",
		"sample_count": points.size(),
		"maximum_step": float(sampling["maximum_step"]),
		"maximum_arc_step": float(sampling["maximum_arc_step"]),
		"maximum_chord_deviation": float(sampling["maximum_chord_deviation"]),
		"minimum_turn_radius": float(gameplay["minimum_turn_radius"]),
		"minimum_nonlocal_distance": float(polyline_check["minimum_nonlocal_distance"]),
		"setup_straight_count": int(gameplay["setup_straight_count"]),
		"literal_straight_count": int(gameplay["literal_straight_count"]),
		"length": float(gameplay["length"]),
	}


static func _sampled_segment_checks(points: PackedVector2Array, total_length: float, room_polygon: PackedVector2Array, approximation_error: float) -> Dictionary:
	var cumulative := PackedFloat64Array([0.0])
	for index in points.size():
		cumulative.append(cumulative[index] + points[index].distance_to(points[(index + 1) % points.size()]))
	var sampled_length := float(cumulative[cumulative.size() - 1])
	var minimum_nonlocal := INF
	for first in points.size():
		var first_next := (first + 1) % points.size()
		var room_cell := {"from": points[first], "to": points[first_next], "error": approximation_error}
		if not _cell_inside_room(room_cell, room_polygon, RESERVED_RADIUS):
			return _failure(&"runtime_samples", &"room_sweep", "Inflated sampled corridor leaves the room polygon.", first)
		for second in range(first + 1, points.size()):
			var second_next := (second + 1) % points.size()
			if first_next == second or second_next == first:
				continue
			if Geometry2D.segment_intersects_segment(points[first], points[first_next], points[second], points[second_next]) != null:
				return _failure(&"runtime_samples", &"self_intersection", "Sampled route segments intersect.", first, second)
			var first_s := (float(cumulative[first]) + float(cumulative[first + 1])) * 0.5
			var second_s := (float(cumulative[second]) + float(cumulative[second + 1])) * 0.5
			var half_lengths := (points[first].distance_to(points[first_next]) + points[second].distance_to(points[second_next])) * 0.5
			if _cyclic_separation(first_s, second_s, sampled_length) + half_lengths < LOCAL_ARC_CUTOFF:
				continue
			var distance := float(_segment_closest(points[first], points[first_next], points[second], points[second_next])["distance"]) - approximation_error * 2.0
			minimum_nonlocal = minf(minimum_nonlocal, distance)
			if distance < MIN_SELF_DISTANCE:
				return _failure(&"runtime_samples", &"self_distance", "Sampled nonlocal self-distance is %.2f, below %.0f." % [distance, MIN_SELF_DISTANCE], first, second)
	if absf(sampled_length - total_length) > maxf(1.0, total_length * 0.001):
		return _failure(&"runtime_samples", &"length_error", "Sampled length exceeds the analytic error budget.")
	return {"ok": true, "valid": true, "minimum_nonlocal_distance": minimum_nonlocal}


static func _flatten_route(route: Dictionary) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for primitive: Dictionary in route["primitives"]:
		var steps := maxi(1, ceili(float(primitive["length"]) / FLATTEN_STEP))
		if primitive["kind"] == &"arc":
			var deviation_angle := 2.0 * acos(clampf(1.0 - FLATTEN_ERROR / float(primitive["radius"]), -1.0, 1.0))
			steps = maxi(steps, ceili(absf(float(primitive["signed_turn"])) / maxf(deviation_angle, 0.000001)))
		for step in steps:
			var from_fraction := float(step) / float(steps)
			var to_fraction := float(step + 1) / float(steps)
			var error := 0.0
			if primitive["kind"] == &"arc":
				error = float(primitive["radius"]) * (1.0 - cos(absf(float(primitive["signed_turn"])) * 0.5 / float(steps)))
			cells.append({
				"from": _primitive_point(primitive, from_fraction),
				"to": _primitive_point(primitive, to_fraction),
				"error": error,
				"s0": lerpf(float(primitive["s_start"]), float(primitive["s_end"]), from_fraction),
				"s1": lerpf(float(primitive["s_start"]), float(primitive["s_end"]), to_fraction),
				"primitive_index": int(primitive["index"]),
			})
	return cells


static func _cell_inside_room(cell: Dictionary, polygon: PackedVector2Array, radius: float) -> bool:
	var from: Vector2 = cell["from"]
	var to: Vector2 = cell["to"]
	var midpoint := from.lerp(to, 0.5)
	if not Geometry2D.is_point_in_polygon(from, polygon) or not Geometry2D.is_point_in_polygon(to, polygon) or not Geometry2D.is_point_in_polygon(midpoint, polygon):
		return false
	var required := radius + float(cell.get("error", 0.0))
	for index in polygon.size():
		var distance := float(_segment_closest(from, to, polygon[index], polygon[(index + 1) % polygon.size()])["distance"])
		if distance < required:
			return false
	return true


static func _stationary_return_pair(a: Dictionary, b: Dictionary, closest: Dictionary, primitive_count: int) -> bool:
	var first_index := int(a["primitive_index"])
	var second_index := int(b["primitive_index"])
	var index_distance := mini(absi(first_index - second_index), primitive_count - absi(first_index - second_index))
	if index_distance <= 1:
		return false
	var t := float(closest["t"])
	var u := float(closest["u"])
	if t <= 0.0001 or t >= 0.9999 or u <= 0.0001 or u >= 0.9999:
		return false
	var tangent_a := ((a["to"] as Vector2) - (a["from"] as Vector2)).normalized()
	var tangent_b := ((b["to"] as Vector2) - (b["from"] as Vector2)).normalized()
	var chord: Vector2 = closest["point_b"] - closest["point_a"]
	if chord.length_squared() < 0.0001:
		return true
	var normal := chord.normalized()
	return absf(normal.dot(tangent_a)) <= 0.03 and absf(normal.dot(tangent_b)) <= 0.03


static func _protected_setup_count(route: Dictionary) -> int:
	var qualified: Array[Dictionary] = []
	for interval: Dictionary in route.get("protected_setup_intervals", []):
		if float(interval["to"]) - float(interval["from"]) >= MIN_SETUP_LENGTH:
			qualified.append(interval)
	if qualified.size() < 2:
		return qualified.size()
	var distinct := 1
	var anchor: Dictionary = qualified[0]
	for index in range(1, qualified.size()):
		var candidate: Dictionary = qualified[index]
		if _turn_between_modules(route.get("modules", []), int(anchor["module_index"]), int(candidate["module_index"])):
			distinct += 1
			anchor = candidate
	return distinct


static func _minimum_endpoint_return_distance(primitives: Array) -> float:
	var minimum := INF
	for first in primitives.size():
		for second in range(first + 1, primitives.size()):
			var index_distance := mini(second - first, primitives.size() - (second - first))
			if index_distance <= 1:
				continue
			for a: Dictionary in _primitive_endpoint_poses(primitives[first]):
				for b: Dictionary in _primitive_endpoint_poses(primitives[second]):
					var chord: Vector2 = b["position"] - a["position"]
					if chord.length_squared() <= POSITION_EPSILON * POSITION_EPSILON:
						return 0.0
					var normal := chord.normalized()
					if absf(normal.dot(a["tangent"])) <= 0.0001 and absf(normal.dot(b["tangent"])) <= 0.0001:
						minimum = minf(minimum, chord.length())
	return minimum


static func _primitive_endpoint_poses(primitive: Dictionary) -> Array[Dictionary]:
	return [
		{"position": primitive["start"], "tangent": Vector2.RIGHT.rotated(float(primitive["heading"]))},
		{"position": primitive["end"], "tangent": Vector2.RIGHT.rotated(float(primitive["end_heading"]))},
	]


static func _turn_between_modules(modules: Array, first: int, second: int) -> bool:
	var cursor := (first + 1) % modules.size()
	while cursor != second:
		if absf(float((modules[cursor] as Dictionary)["signed_turn"])) > 0.0001:
			return true
		cursor = (cursor + 1) % modules.size()
	return false


static func _primitive_intersections(a: Dictionary, b: Dictionary) -> PackedVector2Array:
	if a["kind"] == &"line" and b["kind"] == &"line":
		return _line_line_intersections(a["start"], a["end"], b["start"], b["end"])
	if a["kind"] == &"line" and b["kind"] == &"arc":
		return _line_arc_intersections(a["start"], a["end"], b)
	if a["kind"] == &"arc" and b["kind"] == &"line":
		return _line_arc_intersections(b["start"], b["end"], a)
	return _arc_arc_intersections(a, b)


static func _line_line_intersections(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	var crossing: Variant = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
	if crossing is Vector2:
		result.append(crossing)
		return result
	var a_direction := a1 - a0
	if absf(a_direction.cross(b0 - a0)) <= 0.0001 and absf(a_direction.cross(b1 - a0)) <= 0.0001:
		var axis := 0 if absf(a_direction.x) >= absf(a_direction.y) else 1
		var a_min := minf(a0[axis], a1[axis])
		var a_max := maxf(a0[axis], a1[axis])
		var b_min := minf(b0[axis], b1[axis])
		var b_max := maxf(b0[axis], b1[axis])
		var overlap_from := maxf(a_min, b_min)
		var overlap_to := minf(a_max, b_max)
		if overlap_to >= overlap_from - POSITION_EPSILON:
			if overlap_to - overlap_from <= POSITION_EPSILON:
				for endpoint_a: Vector2 in [a0, a1]:
					for endpoint_b: Vector2 in [b0, b1]:
						if endpoint_a.distance_to(endpoint_b) <= POSITION_EPSILON:
							result.append(endpoint_a)
							return result
			result.append(a0.lerp(a1, 0.5))
	return result


static func _line_arc_intersections(from: Vector2, to: Vector2, arc: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	var delta := to - from
	var relative := from - (arc["center"] as Vector2)
	var qa := delta.dot(delta)
	var qb := 2.0 * relative.dot(delta)
	var qc := relative.dot(relative) - float(arc["radius"]) * float(arc["radius"])
	var discriminant := qb * qb - 4.0 * qa * qc
	if discriminant < -0.0001:
		return result
	for root_sign: float in ([-1.0, 1.0] if discriminant > 0.0001 else [0.0]):
		var t := (-qb + root_sign * sqrt(maxf(discriminant, 0.0))) / (2.0 * qa)
		if t >= -0.0001 and t <= 1.0001:
			var point := from + delta * clampf(t, 0.0, 1.0)
			if _point_on_arc(point, arc):
				result.append(point)
	return _deduplicate_points(result)


static func _arc_arc_intersections(a: Dictionary, b: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	var c0: Vector2 = a["center"]
	var c1: Vector2 = b["center"]
	var r0 := float(a["radius"])
	var r1 := float(b["radius"])
	var distance := c0.distance_to(c1)
	if distance <= 0.0001 and absf(r0 - r1) <= 0.0001:
		for point: Vector2 in [a["start"], a["end"], b["start"], b["end"]]:
			if _point_on_arc(point, a) and _point_on_arc(point, b):
				result.append(point)
		return _deduplicate_points(result)
	if distance > r0 + r1 + 0.0001 or distance < absf(r0 - r1) - 0.0001 or distance <= 0.0001:
		return result
	var along := (r0 * r0 - r1 * r1 + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(r0 * r0 - along * along, 0.0))
	var base := c0 + (c1 - c0) * (along / distance)
	var offset := (c1 - c0).normalized().rotated(PI * 0.5) * height
	for point: Vector2 in ([base] if height <= 0.0001 else [base + offset, base - offset]):
		if _point_on_arc(point, a) and _point_on_arc(point, b):
			result.append(point)
	return _deduplicate_points(result)


static func _point_on_arc(point: Vector2, arc: Dictionary) -> bool:
	var angle := (point - (arc["center"] as Vector2)).angle()
	var start := float(arc["start_angle"])
	var turn := float(arc["signed_turn"])
	var traveled := fposmod(angle - start, TAU) if turn > 0.0 else fposmod(start - angle, TAU)
	return traveled <= absf(turn) + 0.0001


static func _deduplicate_points(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		var duplicate := false
		for existing: Vector2 in result:
			if point.distance_to(existing) <= POSITION_EPSILON:
				duplicate = true
				break
		if not duplicate:
			result.append(point)
	return result


static func _segment_closest(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Dictionary:
	var u := a1 - a0
	var v := b1 - b0
	var w := a0 - b0
	var aa := u.dot(u)
	var bb := u.dot(v)
	var cc := v.dot(v)
	var dd := u.dot(w)
	var ee := v.dot(w)
	var denominator := aa * cc - bb * bb
	var s_numerator := 0.0
	var s_denominator := denominator
	var t_numerator := 0.0
	var t_denominator := denominator
	if denominator < 0.0000001:
		s_numerator = 0.0
		s_denominator = 1.0
		t_numerator = ee
		t_denominator = cc
	else:
		s_numerator = bb * ee - cc * dd
		t_numerator = aa * ee - bb * dd
		if s_numerator < 0.0:
			s_numerator = 0.0
			t_numerator = ee
			t_denominator = cc
		elif s_numerator > s_denominator:
			s_numerator = s_denominator
			t_numerator = ee + bb
			t_denominator = cc
	if t_numerator < 0.0:
		t_numerator = 0.0
		if -dd < 0.0:
			s_numerator = 0.0
		elif -dd > aa:
			s_numerator = s_denominator
		else:
			s_numerator = -dd
			s_denominator = aa
	elif t_numerator > t_denominator:
		t_numerator = t_denominator
		if -dd + bb < 0.0:
			s_numerator = 0.0
		elif -dd + bb > aa:
			s_numerator = s_denominator
		else:
			s_numerator = -dd + bb
			s_denominator = aa
	var s := 0.0 if absf(s_numerator) < 0.0000001 else s_numerator / maxf(s_denominator, 0.0000001)
	var t := 0.0 if absf(t_numerator) < 0.0000001 else t_numerator / maxf(t_denominator, 0.0000001)
	var point_a := a0 + u * s
	var point_b := b0 + v * t
	return {"distance": point_a.distance_to(point_b), "t": s, "u": t, "point_a": point_a, "point_b": point_b}


static func _primitive_entry_port(primitive: Dictionary) -> Dictionary:
	return _port(primitive["start"], float(primitive["heading"]))


static func _primitive_exit_port(primitive: Dictionary) -> Dictionary:
	return _port(primitive["end"], float(primitive["end_heading"]))


static func _port(position: Vector2, heading: float) -> Dictionary:
	var tangent := Vector2.RIGHT.rotated(heading)
	var normal := tangent.rotated(PI * 0.5)
	return {"position": position, "heading": heading, "tangent": tangent, "left": position + normal * HALF_WIDTH, "right": position - normal * HALF_WIDTH, "width": HALF_WIDTH * 2.0, "elevation": 0.0, "surface": &"road", "support": &"floor"}


static func _primitive_point(primitive: Dictionary, fraction: float) -> Vector2:
	if primitive["kind"] == &"line":
		return (primitive["start"] as Vector2).lerp(primitive["end"], fraction)
	return (primitive["center"] as Vector2) + ((primitive["start"] as Vector2) - (primitive["center"] as Vector2)).rotated(float(primitive["signed_turn"]) * fraction)


static func _minimum_analytic_radius(primitives: Array) -> float:
	var minimum := INF
	for primitive: Dictionary in primitives:
		if primitive["kind"] == &"arc":
			minimum = minf(minimum, float(primitive["radius"]))
	return minimum


static func _cyclic_separation(first: float, second: float, total: float) -> float:
	var forward := absf(second - first)
	return minf(forward, total - forward)


static func _points_rect(points: PackedVector2Array) -> Rect2:
	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum = Vector2(minf(minimum.x, point.x), minf(minimum.y, point.y))
		maximum = Vector2(maxf(maximum.x, point.x), maxf(maximum.y, point.y))
	return Rect2(minimum, maximum - minimum)


static func _failure(stage: StringName, kind: StringName, reason: String, first: int = -1, second: int = -1) -> Dictionary:
	return {"ok": false, "valid": false, "stage": stage, "kind": kind, "reason": reason, "error": reason, "first": first, "second": second}
