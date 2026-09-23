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
const MIN_EXCLUSIVE_REGION_LENGTH := 450.0
const POSITION_EPSILON := 0.01
const FLATTEN_STEP := 20.0
const FLATTEN_ERROR := 0.02
# Guard band for the nonlocal AABB skip. The exact segment distance is a
# float32 `Vector2.distance_to` result (relative error ~1e-7), while the AABB
# gap is computed in float64. The margin must dominate that rounding so a
# skipped pair can never have produced a smaller certified distance.
const SKIP_MARGIN_ABSOLUTE := 0.01
const SKIP_MARGIN_RELATIVE := 0.0001
# Safety pad for the arc-near windowing bounds. The s-coordinates are float64
# cumulative lengths; a one-ULP wobble at a primitive boundary must never let a
# window stop before the exact arc-near condition flips. It only ever extends a
# window by a handful of already-nonlocal pairs, never reclassifies one.
const LOCAL_WINDOW_MARGIN := 0.000001


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
	var cell_count := cells.size()
	var cell_bounds: Array[Rect2] = []
	var cell_errors := PackedFloat64Array()
	var cell_s0 := PackedFloat64Array()
	var cell_s1 := PackedFloat64Array()
	cell_bounds.resize(cell_count)
	cell_errors.resize(cell_count)
	cell_s0.resize(cell_count)
	cell_s1.resize(cell_count)
	var max_cell_error := 0.0
	for index in cell_count:
		var cell: Dictionary = cells[index]
		cell_bounds[index] = _segment_bounds(cell["from"], cell["to"])
		var error := float(cell["error"])
		cell_errors[index] = error
		cell_s0[index] = float(cell["s0"])
		cell_s1[index] = float(cell["s1"])
		max_cell_error = maxf(max_cell_error, error)
	var minimum_nonlocal := INF
	var minimum_return_limb := _minimum_endpoint_return_distance(primitives)
	if minimum_return_limb < MIN_SELF_DISTANCE:
		return _failure(&"clearance", &"return_limb_spacing", "Continuous endpoint return-limb distance is %.2f, below %.0f." % [minimum_return_limb, MIN_SELF_DISTANCE])
	var local_result := _local_return_limb_pass(cells, cell_s0, cell_s1, cell_errors, float(route["length"]), primitives.size(), minimum_return_limb)
	if local_result.has("failure"):
		return local_result["failure"]
	minimum_return_limb = float(local_result["minimum"])
	var nonlocal_result := _nonlocal_sweep(cells, cell_bounds, cell_errors, cell_s0, cell_s1, float(route["length"]), max_cell_error, minimum_nonlocal)
	if nonlocal_result.has("failure"):
		return nonlocal_result["failure"]
	minimum_nonlocal = float(nonlocal_result["minimum"])
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


# Pure exact query: how much of the analytic route lies in each supplied region
# and in NO other supplied region (the "exclusive" length per region). Every
# line/arc primitive is intersected against every region polygon edge with
# `_primitive_intersections`; each crossing becomes a primitive fraction (line
# projection or directed arc angle), the fractions are sorted/deduped/clamped
# into intervals, and each interval midpoint is classified with `_primitive_point`.
# A midpoint contributes `primitive.length * (hi - lo)` to a region only when it
# is inside that region and outside every other supplied region, so overlaps
# contribute to neither. No chord/sample approximation is used. Every actual
# primitive-edge intersection counts as one query operation against `max_queries`;
# the result never reports `ok` for a measurement that stopped on the budget.
static func validate_region_occupation(route: Dictionary, room: Dictionary, max_queries: int = 2147483647) -> Dictionary:
	var regions: Array[Dictionary] = []
	for region: Dictionary in room.get("regions", []):
		if bool(region.get("required", false)):
			regions.append(region)
	var overlapping := {}
	for first in regions.size():
		for second in range(first + 1, regions.size()):
			if not Geometry2D.intersect_polygons(regions[first]["polygon"], regions[second]["polygon"]).is_empty():
				overlapping[regions[first]["id"]] = true
				overlapping[regions[second]["id"]] = true
	if overlapping.is_empty():
		return {"ok": true, "valid": true, "lengths": {}, "query_operations": 0}
	var measured := exclusive_region_lengths(route, regions, max_queries)
	if not bool(measured["ok"]):
		measured["valid"] = false
		return measured
	for region_id: StringName in overlapping:
		var length := float(measured["lengths"].get(region_id, 0.0))
		if length < MIN_EXCLUSIVE_REGION_LENGTH:
			var failure := _failure(&"region_assignment", &"required_region_length", "Required region '%s' carries %.2f exclusive route units; minimum is %.0f." % [region_id, length, MIN_EXCLUSIVE_REGION_LENGTH])
			failure["query_operations"] = measured["query_operations"]
			return failure
	measured["valid"] = true
	return measured


static func exclusive_region_lengths(route: Dictionary, regions: Array, max_queries: int = 2147483647) -> Dictionary:
	var lengths := {}
	for region: Dictionary in regions:
		lengths[region["id"]] = 0.0
	if not bool(route.get("ok", false)):
		return {"ok": false, "budget_exhausted": false, "query_operations": 0, "lengths": lengths, "kind": &"invalid_route", "reason": "Exclusive region lengths need a composed analytic route."}
	var primitives: Array = route.get("primitives", [])
	var query_operations := 0
	var cap := maxi(max_queries, 0)
	for primitive: Dictionary in primitives:
		var fractions := PackedFloat64Array([0.0, 1.0])
		for region: Dictionary in regions:
			var polygon: PackedVector2Array = region.get("polygon", PackedVector2Array())
			for edge_index in polygon.size():
				if query_operations >= cap:
					return {"ok": false, "budget_exhausted": true, "query_operations": query_operations, "lengths": lengths, "kind": &"query_budget_exhausted", "reason": "Exclusive region measurement needs more than %d primitive-edge queries." % cap}
				query_operations += 1
				var edge_primitive := {"kind": &"line", "start": polygon[edge_index], "end": polygon[(edge_index + 1) % polygon.size()]}
				for point: Vector2 in _primitive_intersections(primitive, edge_primitive):
					fractions.append(_primitive_fraction(primitive, point))
		fractions.sort()
		var unique := PackedFloat64Array()
		for value: float in fractions:
			var clamped := clampf(value, 0.0, 1.0)
			if unique.is_empty() or clamped - unique[unique.size() - 1] > 0.000001:
				unique.append(clamped)
		for interval_index in range(unique.size() - 1):
			var lo := unique[interval_index]
			var hi := unique[interval_index + 1]
			if hi - lo <= 0.000001:
				continue
			var midpoint := _primitive_point(primitive, (lo + hi) * 0.5)
			var owner := -1
			var overlap := false
			for region_index in regions.size():
				if not Geometry2D.is_point_in_polygon(midpoint, (regions[region_index] as Dictionary)["polygon"]):
					continue
				if owner >= 0:
					overlap = true
					break
				owner = region_index
			if not overlap and owner >= 0:
				var region_id = (regions[owner] as Dictionary)["id"]
				lengths[region_id] = float(lengths[region_id]) + float(primitive["length"]) * (hi - lo)
	return {"ok": true, "budget_exhausted": false, "query_operations": query_operations, "lengths": lengths}


static func _sampled_segment_checks(points: PackedVector2Array, total_length: float, room_polygon: PackedVector2Array, approximation_error: float) -> Dictionary:
	var cumulative := PackedFloat64Array([0.0])
	for index in points.size():
		cumulative.append(cumulative[index] + points[index].distance_to(points[(index + 1) % points.size()]))
	var sampled_length := float(cumulative[cumulative.size() - 1])
	var segment_bounds: Array[Rect2] = []
	for index in points.size():
		segment_bounds.append(_segment_bounds(points[index], points[(index + 1) % points.size()]))
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
			if _nonlocal_skip_safe(segment_bounds[first], segment_bounds[second], approximation_error, approximation_error, minimum_nonlocal):
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


static func _segment_bounds(from: Vector2, to: Vector2) -> Rect2:
	return Rect2(Vector2(minf(from.x, to.x), minf(from.y, to.y)), Vector2(absf(from.x - to.x), absf(from.y - to.y)))


static func _aabb_gap_distance(a: Rect2, b: Rect2) -> float:
	var gap_x := maxf(0.0, maxf(a.position.x, b.position.x) - minf(a.end.x, b.end.x))
	var gap_y := maxf(0.0, maxf(a.position.y, b.position.y) - minf(a.end.y, b.end.y))
	return sqrt(gap_x * gap_x + gap_y * gap_y)


static func _nonlocal_skip_safe(a_bounds: Rect2, b_bounds: Rect2, a_error: float, b_error: float, current_minimum: float) -> bool:
	if not is_finite(current_minimum):
		return false
	var gap := _aabb_gap_distance(a_bounds, b_bounds)
	var lower := gap - a_error - b_error
	var margin := SKIP_MARGIN_ABSOLUTE + SKIP_MARGIN_RELATIVE * gap
	return lower >= current_minimum + margin


static func _pair_possible_separation(s0_a: float, s1_a: float, s0_b: float, s1_b: float, total: float) -> float:
	var midpoint_separation := _cyclic_separation((s0_a + s1_a) * 0.5, (s0_b + s1_b) * 0.5, total)
	return midpoint_separation + (s1_a - s0_a + s1_b - s0_b) * 0.5


# Arc-near stationary-return pass, in original route order. Only intervals whose
# arc distance to `first` is inside LOCAL_ARC_CUTOFF are enumerated: the forward
# window (non-wrapping) and the wrap window (across the loop seam). The two
# windows are disjoint whenever `total > 2 * LOCAL_ARC_CUTOFF`; shorter routes
# fall back to the exhaustive route-order loop, which is bit-identical to the
# reference and only runs for tiny cell counts.
static func _local_return_limb_pass(cells: Array[Dictionary], s0: PackedFloat64Array, s1: PackedFloat64Array, errors: PackedFloat64Array, total: float, primitive_count: int, minimum_return_limb: float) -> Dictionary:
	var cutoff := LOCAL_ARC_CUTOFF
	if total <= cutoff * 2.0 + LOCAL_WINDOW_MARGIN * 2.0:
		for first in cells.size():
			var a: Dictionary = cells[first]
			for second in range(first + 1, cells.size()):
				var b: Dictionary = cells[second]
				if _pair_possible_separation(s0[first], s1[first], s0[second], s1[second], total) >= cutoff:
					continue
				var closest := _segment_closest(a["from"], a["to"], b["from"], b["to"])
				if not _stationary_return_pair(a, b, closest, primitive_count):
					continue
				var certified := float(closest["distance"]) - errors[first] - errors[second]
				minimum_return_limb = minf(minimum_return_limb, certified)
				if certified < MIN_SELF_DISTANCE:
					return {"failure": _failure(&"clearance", &"return_limb_spacing", "Continuous return-limb distance is %.2f, below %.0f." % [certified, MIN_SELF_DISTANCE], int(a["primitive_index"]), int(b["primitive_index"]))}
		return {"minimum": minimum_return_limb}
	for first in cells.size():
		var a: Dictionary = cells[first]
		var a_s0 := s0[first]
		var a_s1 := s1[first]
		# Forward arc-near window: second advances in route order until the arc
		# gap from `first` clears the cutoff. `s1` is monotonically increasing.
		var second := first + 1
		while second < cells.size() and s1[second] - a_s0 < cutoff + LOCAL_WINDOW_MARGIN:
			if _pair_possible_separation(a_s0, a_s1, s0[second], s1[second], total) < cutoff:
				var b: Dictionary = cells[second]
				var closest := _segment_closest(a["from"], a["to"], b["from"], b["to"])
				if _stationary_return_pair(a, b, closest, primitive_count):
					var certified := float(closest["distance"]) - errors[first] - errors[second]
					minimum_return_limb = minf(minimum_return_limb, certified)
					if certified < MIN_SELF_DISTANCE:
						return {"failure": _failure(&"clearance", &"return_limb_spacing", "Continuous return-limb distance is %.2f, below %.0f." % [certified, MIN_SELF_DISTANCE], int(a["primitive_index"]), int(b["primitive_index"]))}
			second += 1
		# Wrap arc-near window: cells just behind the loop seam whose arc gap to
		# `first` (through the seam) is inside the cutoff. `s0` increases with
		# index, so iterating downward is monotonic.
		second = cells.size() - 1
		while second > first and s0[second] > a_s1 + (total - cutoff) - LOCAL_WINDOW_MARGIN:
			if _pair_possible_separation(a_s0, a_s1, s0[second], s1[second], total) < cutoff:
				var b: Dictionary = cells[second]
				var closest := _segment_closest(a["from"], a["to"], b["from"], b["to"])
				if _stationary_return_pair(a, b, closest, primitive_count):
					var certified := float(closest["distance"]) - errors[first] - errors[second]
					minimum_return_limb = minf(minimum_return_limb, certified)
					if certified < MIN_SELF_DISTANCE:
						return {"failure": _failure(&"clearance", &"return_limb_spacing", "Continuous return-limb distance is %.2f, below %.0f." % [certified, MIN_SELF_DISTANCE], int(a["primitive_index"]), int(b["primitive_index"]))}
			second -= 1
	return {"minimum": minimum_return_limb}


# Deterministic x-sorted sweep over the continuous NONLOCAL pairs. Cells are
# ordered by minimum-x, then original index, so the inner loop can stop as soon
# as the x-gap (minus a conservative flatten-error bound) exceeds the running
# minimum by the skip margin. Each candidate pair is canonicalized back to
# original index order before `_segment_closest`, so the distance arithmetic is
# bit-identical to the reference double loop. Arc-near pairs are skipped here;
# the local pass owns them.
static func _nonlocal_sweep(cells: Array[Dictionary], bounds: Array[Rect2], errors: PackedFloat64Array, s0: PackedFloat64Array, s1: PackedFloat64Array, total: float, max_cell_error: float, minimum_nonlocal: float) -> Dictionary:
	var count := cells.size()
	var order: Array[int] = []
	order.resize(count)
	for index in count:
		order[index] = index
	order.sort_custom(func(a: int, b: int) -> bool:
		var a_x: float = bounds[a].position.x
		var b_x: float = bounds[b].position.x
		if a_x != b_x:
			return a_x < b_x
		return a < b
	)
	var cutoff := LOCAL_ARC_CUTOFF
	for position in count:
		var a_index: int = order[position]
		var a_bounds: Rect2 = bounds[a_index]
		var a_error := errors[a_index]
		for right_position in range(position + 1, count):
			var b_index: int = order[right_position]
			var b_bounds: Rect2 = bounds[b_index]
			if is_finite(minimum_nonlocal):
				var x_gap := b_bounds.position.x - a_bounds.end.x
				if x_gap - a_error - max_cell_error >= minimum_nonlocal + SKIP_MARGIN_ABSOLUTE + SKIP_MARGIN_RELATIVE * x_gap:
					break
			var low := a_index if a_index < b_index else b_index
			var high := b_index if a_index < b_index else a_index
			if _pair_possible_separation(s0[low], s1[low], s0[high], s1[high], total) < cutoff:
				continue
			if _nonlocal_skip_safe(a_bounds, b_bounds, a_error, errors[b_index], minimum_nonlocal):
				continue
			var low_cell: Dictionary = cells[low]
			var high_cell: Dictionary = cells[high]
			var closest := _segment_closest(low_cell["from"], low_cell["to"], high_cell["from"], high_cell["to"])
			var certified := float(closest["distance"]) - errors[low] - errors[high]
			minimum_nonlocal = minf(minimum_nonlocal, certified)
			if certified < MIN_SELF_DISTANCE:
				return {"failure": _failure(&"clearance", &"self_distance", "Continuous nonlocal self-distance is %.2f, below %.0f." % [certified, MIN_SELF_DISTANCE], int(low_cell["primitive_index"]), int(high_cell["primitive_index"]))}
	return {"minimum": minimum_nonlocal}


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


# Inverse of `_primitive_point` for an exact on-primitive position: a line uses
# the axial projection, an arc uses the directed angle traveled from its start.
# Matches the `_point_on_arc` winding convention so round-tripping a generated
# midpoint recovers its fraction exactly.
static func _primitive_fraction(primitive: Dictionary, point: Vector2) -> float:
	if primitive["kind"] == &"line":
		var segment := (primitive["end"] as Vector2) - (primitive["start"] as Vector2)
		var length_squared := segment.length_squared()
		if length_squared <= POSITION_EPSILON * POSITION_EPSILON:
			return 0.0
		return clampf((point - (primitive["start"] as Vector2)).dot(segment) / length_squared, 0.0, 1.0)
	var center: Vector2 = primitive["center"]
	var turn := float(primitive["signed_turn"])
	var start_angle := ((primitive["start"] as Vector2) - center).angle()
	var point_angle := (point - center).angle()
	var traveled := fposmod(point_angle - start_angle, TAU) if turn > 0.0 else fposmod(start_angle - point_angle, TAU)
	return traveled / maxf(absf(turn), 0.000001)


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
