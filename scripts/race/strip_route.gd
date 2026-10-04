extends RefCounted

const SAMPLER := preload("res://scripts/race/track_curve_sampling.gd")
const HALF_WIDTH := 125.0
const CLEARANCE := HALF_WIDTH + 65.0
const MIN_RADIUS := 350.0
const START_STRAIGHT := 1000.0
const MIN_ENDPOINT_DISTANCE := 500.0
const ATTEMPTS := 12
const POINT_SPACING := 30.0
const END_INSET := CLEARANCE + 25.0
const MAX_HEADING := PI * 0.25
const HEADING_TOLERANCE := 0.002
const FINISH_STRAIGHT := 1200.0
const SWEEP_RAMP := 750.0
const CHICANE_RAMP := 650.0
const CHICANE_HOLD := 350.0
const SWEEP_HEADING := Vector2(28.0, 42.0)
const STRAIGHT_LENGTH := Vector2(1600.0, 2800.0)
const LATERAL_USE := 0.30


static func generate(seed: int, room_polygon: PackedVector2Array, force_fallback: bool = false) -> Dictionary:
	if room_polygon.size() < 3:
		return {}
	var bounds := _bounds(room_polygon)
	var south := bounds.end.y - END_INSET
	var north := bounds.position.y + END_INSET
	var height := south - north
	if height < MIN_ENDPOINT_DISTANCE:
		return {}
	if not force_fallback:
		for attempt in ATTEMPTS:
			var rng := RandomNumberGenerator.new()
			rng.seed = (seed * 1103515245 + attempt * 2654435761) & 0x7FFFFFFFFFFFFFFF
			var candidate := _section_route(bounds, south, north, rng)
			var line: PackedVector2Array = candidate["centerline"]
			if validate(line, room_polygon):
				candidate.merge({"controls": line.duplicate(), "fallback": false, "attempt": attempt})
				return candidate
	# The longest clearance-valid north lane; no loop or reversal on fallback.
	var best := PackedVector2Array()
	for row in [-0.35, -0.2, 0.0, 0.2, 0.35]:
		var lane := _safe_line(bounds, room_polygon, row)
		if lane.size() == 2 and (best.size() != 2 or lane[0].distance_to(lane[1]) > best[0].distance_to(best[1])):
			best = lane
	if best.size() != 2:
		return {}
	var centerline := SAMPLER.sample_open(best, POINT_SPACING)
	return {"controls": best, "centerline": centerline, "sections": [], "fallback": true, "attempt": ATTEMPTS} if validate(centerline, room_polygon) else {}


static func _section_route(bounds: Rect2, south: float, north: float, rng: RandomNumberGenerator) -> Dictionary:
	var extent := minf(bounds.size.x * LATERAL_USE, bounds.size.x * 0.5 - CLEARANCE - POINT_SPACING)
	var side := -1.0 if rng.randi() % 2 == 0 else 1.0
	var line := PackedVector2Array([Vector2(bounds.get_center().x + extent * side, south)])
	var sections: Array[Dictionary] = []
	_append_section(line, sections, "start", START_STRAIGHT, 0.0, 0.0)
	var cycle := 0
	while line[-1].y - north > FINISH_STRAIGHT:
		var slope := tan(deg_to_rad(rng.randf_range(SWEEP_HEADING.x, SWEEP_HEADING.y)))
		var span := extent * 2.0 / slope + SWEEP_RAMP
		if line[-1].y - north < span + FINISH_STRAIGHT:
			break
		_append_section(line, sections, "sweeper", span, -side * slope, SWEEP_RAMP)
		side = -side
		cycle += 1
		# A short in/out pair interrupts the long held bends without ever turning south.
		var chicane_span := CHICANE_RAMP * 2.0 + CHICANE_HOLD
		if cycle % 3 == 2 and line[-1].y - north > chicane_span * 2.0 + FINISH_STRAIGHT:
			var chicane_slope := tan(deg_to_rad(rng.randf_range(25.0, 29.0)))
			_append_section(line, sections, "chicane", chicane_span, -side * chicane_slope, CHICANE_RAMP)
			_append_section(line, sections, "chicane", chicane_span, side * chicane_slope, CHICANE_RAMP)
		var straight := minf(rng.randf_range(STRAIGHT_LENGTH.x, STRAIGHT_LENGTH.y), line[-1].y - north - FINISH_STRAIGHT)
		if straight > POINT_SPACING:
			_append_section(line, sections, "straight", straight, 0.0, 0.0)
	_append_section(line, sections, "finish", line[-1].y - north, 0.0, 0.0)
	return {"centerline": line, "sections": sections}


static func _append_section(line: PackedVector2Array, sections: Array[Dictionary], kind: String, span: float, slope: float, ramp: float) -> void:
	var origin := line[-1]
	var first := line.size() - 1
	var count := maxi(1, ceili(span / POINT_SPACING))
	var length := 0.0
	var heading := 0.0
	for index in range(1, count + 1):
		var y := span * float(index) / count
		# Integral of a cosine-eased slope: zero curvature at both joins, constant
		# heading through the middle. End displacement is exactly slope*(span-ramp).
		var x := 0.0
		if ramp > 0.0:
			if y < ramp:
				x = _ramp_integral(y, ramp)
			elif y <= span - ramp:
				x = y - ramp * 0.5
			else:
				x = span - ramp - _ramp_integral(span - y, ramp)
		var point := origin + Vector2(slope * x, -y)
		var segment := point - line[-1]
		length += segment.length()
		heading = maxf(heading, rad_to_deg(absf(Vector2.UP.angle_to(segment))))
		line.append(point)
	var start_arc := 0.0 if sections.is_empty() else float(sections[-1]["end_arc"])
	sections.append({"kind": kind, "first_index": first, "last_index": line.size() - 1, "start_arc": start_arc, "end_arc": start_arc + length, "length": length, "heading_degrees": heading * signf(slope), "max_heading_degrees": heading, "hold_length": maxf(0.0, span - ramp * 2.0) * sqrt(1.0 + slope * slope) if ramp > 0.0 else length})


static func _ramp_integral(distance: float, ramp: float) -> float:
	return distance * 0.5 - ramp * sin(PI * distance / ramp) / (2.0 * PI)


static func _safe_line(bounds: Rect2, polygon: PackedVector2Array, row: float) -> PackedVector2Array:
	var x := bounds.get_center().x + row * bounds.size.x
	var current := PackedVector2Array()
	var best := PackedVector2Array()
	var count := maxi(2, ceili(bounds.size.y / POINT_SPACING))
	for index in count + 1:
		var point := Vector2(x, bounds.end.y - bounds.size.y * float(index) / count)
		if _clear(point, polygon):
			if current.is_empty():
				current.append(point)
			if current.size() == 1:
				current.append(point)
			else:
				current[1] = point
		elif current.size() == 2:
			if best.size() != 2 or current[0].distance_to(current[1]) > best[0].distance_to(best[1]):
				best = current.duplicate()
			current.clear()
	if current.size() == 2 and (best.size() != 2 or current[0].distance_to(current[1]) > best[0].distance_to(best[1])):
		best = current
	return best


static func validate(line: PackedVector2Array, polygon: PackedVector2Array) -> bool:
	if line.size() < 2 or line[0].y - line[-1].y < MIN_ENDPOINT_DISTANCE:
		return false
	var heading_floor := cos(MAX_HEADING) - HEADING_TOLERANCE
	for index in line.size():
		if not _clear(line[index], polygon):
			return false
		if index == 0:
			continue
		var segment := line[index] - line[index - 1]
		if segment.length_squared() < 0.001 or segment.normalized().dot(Vector2.UP) < heading_floor:
			return false
		if line[0].y - line[index].y <= START_STRAIGHT and absf(line[index].x - line[0].x) > 1.0:
			return false
	for index in range(2, line.size()):
		var a := line[index - 1] - line[index - 2]
		var b := line[index] - line[index - 1]
		var sine := absf(a.normalized().cross(b.normalized()))
		if sine > 0.001 and minf(a.length(), b.length()) / sine < MIN_RADIUS:
			return false
	return true


static func _clear(point: Vector2, polygon: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon(point, polygon):
		return false
	for index in polygon.size():
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])) < CLEARANCE:
			return false
	return true


static func _bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	return bounds
