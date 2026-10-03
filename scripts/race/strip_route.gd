extends RefCounted

const SAMPLER := preload("res://scripts/race/track_curve_sampling.gd")
const HALF_WIDTH := 125.0
const CLEARANCE := HALF_WIDTH + 65.0
const MIN_RADIUS := 95.0
const START_STRAIGHT := 310.0
const MIN_ENDPOINT_DISTANCE := 820.0
const ATTEMPTS := 12
const POINT_SPACING := 30.0
const ROW_PITCH := 430.0
const TURN_RADIUS := ROW_PITCH * 0.5
const END_MARGIN := CLEARANCE + TURN_RADIUS + 12.0
const BAND_STEP := 20.0


static func generate(seed: int, room_polygon: PackedVector2Array, force_fallback: bool = false) -> Dictionary:
	if room_polygon.size() < 3:
		return {}
	var bounds := _bounds(room_polygon)
	var horizontal := bounds.size.x >= bounds.size.y
	for attempt in ATTEMPTS:
		if force_fallback:
			break
		var rng := RandomNumberGenerator.new()
		rng.seed = (seed * 1103515245 + attempt * 2654435761) & 0x7FFFFFFFFFFFFFFF
		var centerline := _serpentine(bounds, room_polygon, horizontal, rng, attempt)
		if validate(centerline, room_polygon):
			return {"controls": centerline.duplicate(), "centerline": centerline, "fallback": false, "attempt": attempt}
	# Scan the room rect for the longest clearance-valid axis-aligned line.
	# Unlike a loop retry this always has an open, drivable A and B in supported rooms.
	var best := PackedVector2Array()
	for axis in [horizontal, not horizontal]:
		for row in [-0.35, -0.2, 0.0, 0.2, 0.35]:
			var safe := _safe_line(bounds, room_polygon, axis, row)
			if safe.size() == 2 and safe[0].distance_to(safe[1]) > (best[0].distance_to(best[1]) if best.size() == 2 else 0.0):
				best = safe
	if best.size() != 2:
		return {}
	var centerline := SAMPLER.sample_open(best, POINT_SPACING)
	return {"controls": best, "centerline": centerline, "fallback": true, "attempt": ATTEMPTS} if validate(centerline, room_polygon) else {}


static func _serpentine(bounds: Rect2, polygon: PackedVector2Array, horizontal: bool, rng: RandomNumberGenerator, attempt: int) -> PackedVector2Array:
	var along_min := bounds.position.x if horizontal else bounds.position.y
	var along_max := bounds.end.x if horizontal else bounds.end.y
	var cross_min := bounds.position.y if horizontal else bounds.position.x
	var cross_max := bounds.end.y if horizontal else bounds.end.x
	var left := along_min + END_MARGIN + rng.randf_range(0.0, 55.0)
	var right := along_max - END_MARGIN - rng.randf_range(0.0, 55.0)
	if right - left < MIN_ENDPOINT_DISTANCE:
		return PackedVector2Array()
	var bands: Array[Vector2] = []
	var band_start := INF
	var previous := cross_min
	var count := maxi(2, ceili((cross_max - cross_min) / BAND_STEP))
	for index in count + 1:
		var cross := lerpf(cross_min, cross_max, float(index) / count)
		var valid := true
		for along in [left - TURN_RADIUS, left, right, right + TURN_RADIUS]:
			if not _clear(_point(along, cross, horizontal), polygon):
				valid = false
				break
		if valid and is_inf(band_start):
			band_start = cross
		if not valid and not is_inf(band_start):
			bands.append(Vector2(band_start, previous))
			band_start = INF
		previous = cross
	if not is_inf(band_start):
		bands.append(Vector2(band_start, cross_max))
	bands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y - a.x > b.y - b.x)
	if bands.is_empty():
		return PackedVector2Array()
	var band := bands[0]
	var rows := floori((band.y - band.x) / ROW_PITCH) + 1
	if rows < 3:
		return PackedVector2Array()
	var slack := maxf(0.0, band.y - band.x - ROW_PITCH * (rows - 1))
	var first_row := band.x + (slack * float(attempt % 3) / 2.0)
	var start_right := rng.randi_range(0, 1) == 1
	var points := PackedVector2Array()
	for row in rows:
		var direction := -1.0 if (row % 2 == 0) == start_right else 1.0
		var start := right if direction < 0.0 else left
		var finish := left if direction < 0.0 else right
		var cross := first_row + ROW_PITCH * row
		_append_straight(points, _point(start, cross, horizontal), _point(finish, cross, horizontal))
		if row < rows - 1:
			var segments := maxi(12, ceili(PI * TURN_RADIUS / POINT_SPACING))
			for step in range(1, segments + 1):
				var angle := -PI * 0.5 + PI * float(step) / segments
				points.append(_point(finish + direction * TURN_RADIUS * cos(angle), cross + TURN_RADIUS + TURN_RADIUS * sin(angle), horizontal))
	return points


static func _append_straight(points: PackedVector2Array, from: Vector2, to: Vector2) -> void:
	if points.is_empty():
		points.append(from)
	var segments := maxi(1, ceili(from.distance_to(to) / POINT_SPACING))
	for step in range(1, segments + 1):
		points.append(from.lerp(to, float(step) / segments))


static func _point(along: float, cross: float, horizontal: bool) -> Vector2:
	return Vector2(along, cross) if horizontal else Vector2(cross, along)


static func _safe_line(bounds: Rect2, polygon: PackedVector2Array, horizontal: bool, row: float) -> PackedVector2Array:
	var span := bounds.size.x if horizontal else bounds.size.y
	var cross := bounds.size.y if horizontal else bounds.size.x
	var center := bounds.get_center()
	var current := PackedVector2Array()
	var best := PackedVector2Array()
	var steps := maxi(2, ceili(span / 18.0))
	for index in steps + 1:
		var along := -span * 0.5 + span * float(index) / steps
		var point := center + (Vector2(along, row * cross) if horizontal else Vector2(row * cross, along))
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
	if line.size() < 2 or line[0].distance_to(line[-1]) < MIN_ENDPOINT_DISTANCE:
		return false
	var start_direction := (line[1] - line[0]).normalized()
	for index in line.size():
		if not _clear(line[index], polygon):
			return false
		if index < line.size() - 1 and line[index].distance_to(line[index + 1]) < 0.01:
			return false
		if index > 0 and line[index].distance_to(line[0]) < START_STRAIGHT and (line[index] - line[0]).normalized().dot(start_direction) < 0.995:
			return false
	for index in range(2, line.size()):
		var a := line[index - 1] - line[index - 2]
		var b := line[index] - line[index - 1]
		var sine := absf(a.normalized().cross(b.normalized()))
		if sine > 0.001 and minf(a.length(), b.length()) / sine < MIN_RADIUS:
			return false
		for previous in range(index - 2):
			if Geometry2D.segment_intersects_segment(line[previous], line[previous + 1], line[index - 1], line[index]) != null:
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
