extends RefCounted

const SAMPLER := preload("res://scripts/race/track_curve_sampling.gd")
const HALF_WIDTH := 125.0
const CLEARANCE := HALF_WIDTH + 65.0
const MIN_RADIUS := 95.0
const START_STRAIGHT := 310.0
const MIN_ENDPOINT_DISTANCE := 500.0
const ATTEMPTS := 12
const POINT_SPACING := 30.0
const END_INSET := CLEARANCE + 25.0
const MAX_HEADING := PI * 0.25
const HEADING_TOLERANCE := 0.002
const MAX_SLOPE := 0.7
const MAX_WAVES := 3


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
			var waves := rng.randi_range(1, MAX_WAVES)
			var center_x := bounds.get_center().x + rng.randf_range(-0.10, 0.10) * bounds.size.x
			var amplitude := minf(bounds.size.x * 0.12, (height - START_STRAIGHT) * MAX_SLOPE / (TAU * waves + PI * 2.0))
			amplitude *= rng.randf_range(0.55, 0.9)
			var line := _north_line(center_x, amplitude, waves, south, north)
			if validate(line, room_polygon):
				return {"controls": line.duplicate(), "centerline": line, "fallback": false, "attempt": attempt}
	# The longest clearance-valid north lane; no loop or reversal on fallback.
	var best := PackedVector2Array()
	for row in [-0.35, -0.2, 0.0, 0.2, 0.35]:
		var lane := _safe_line(bounds, room_polygon, row)
		if lane.size() == 2 and (best.size() != 2 or lane[0].distance_to(lane[1]) > best[0].distance_to(best[1])):
			best = lane
	if best.size() != 2:
		return {}
	var centerline := SAMPLER.sample_open(best, POINT_SPACING)
	return {"controls": best, "centerline": centerline, "fallback": true, "attempt": ATTEMPTS} if validate(centerline, room_polygon) else {}


static func _north_line(center_x: float, amplitude: float, waves: int, south: float, north: float) -> PackedVector2Array:
	var height := south - north
	var count := maxi(2, ceili(height / POINT_SPACING))
	var line := PackedVector2Array()
	for index in count + 1:
		var distance := height * float(index) / count
		var u := clampf((distance - START_STRAIGHT) / maxf(height - START_STRAIGHT, 0.001), 0.0, 1.0)
		var envelope := pow(sin(PI * u), 2.0)
		line.append(Vector2(center_x + amplitude * sin(TAU * waves * u) * envelope, south - distance))
	return line


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
