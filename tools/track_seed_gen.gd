class_name TrackSeedGen
## Procedural circuit generation (ported from juangallostra/procedural-tracks +
## ChrisPHP/ProceduralRacetrack): random points -> convex hull -> displaced
## midpoints -> angle clamp -> point separation, then the room builder's
## Catmull-Rom sweep. Every seed is reproducible; bad seeds are rejected
## (self-overlap, too short, no straight long enough for the grid) and the
## caller walks to the next seed.

const SAMPLE_COUNT := 260
const HALF_WIDTH := 125.0

static var _rng := RandomNumberGenerator.new()


static func generate_with_retries(seed: int, room_rect: Rect2, params: Dictionary = {}) -> Dictionary:
	var current := seed
	for attempt in 40:
		var points := generate(current, room_rect, params)
		if not points.is_empty():
			return {"points": points, "seed": current}
		current += 1
	return {"points": PackedVector2Array(), "seed": current}


static func archetype_params(seed: int, base: Dictionary) -> Dictionary:
	# Four track personalities, deterministic from the seed: fast (long straights,
	# gentle corners), technical (tight and busy), asymmetric (one dominant side),
	# hairpin (a genuine U-turn).
	var result := base.duplicate()
	var base_self := float(base.get("min_self_distance", 0.0))
	match posmod(seed, 4):
		0:
			result["min_point_distance"] = 250.0
			result["max_angle_deg"] = 62.0
			result["min_self_distance"] = base_self if base_self > 0.0 else 300.0
			result["point_count"] = 10
			result["displacement_min"] = 0.04
			result["displacement_max"] = 0.10
		1:
			result["min_point_distance"] = 185.0
			result["max_angle_deg"] = 82.0
			result["min_self_distance"] = 268.0
			result["point_count"] = 15
			result["displacement_min"] = 0.07
			result["displacement_max"] = 0.16
		2:
			result["min_point_distance"] = 210.0
			result["max_angle_deg"] = 78.0
			result["min_self_distance"] = base_self if base_self > 0.0 else 290.0
			result["point_count"] = 13
			result["displacement_min"] = 0.06
			result["displacement_max"] = 0.14
			result["side_bias"] = Vector2(-0.6, 0.0) if posmod(seed, 8) < 4 else Vector2(0.6, 0.0)
		_:
			result["min_point_distance"] = 200.0
			result["max_angle_deg"] = 94.0
			result["min_self_distance"] = 258.0
			result["point_count"] = 12
			result["displacement_min"] = 0.08
			result["displacement_max"] = 0.18
	return result


static func generate(seed: int, room_rect: Rect2, params: Dictionary = {}) -> PackedVector2Array:
	var profile := archetype_params(seed, params)
	_rng.seed = seed
	var margin := float(profile.get("margin", 150.0))
	var min_point_distance := float(profile.get("min_point_distance", 200.0))
	var max_angle_deg := float(profile.get("max_angle_deg", 80.0))
	var min_self_distance := float(profile.get("min_self_distance", 300.0))
	var min_loop_length := float(profile.get("min_loop_length", 1900.0))
	var point_count := int(profile.get("point_count", 0))
	var displacement_min := float(profile.get("displacement_min", 0.05)) * float(profile.get("displacement_scale", 1.0))
	var displacement_max := float(profile.get("displacement_max", 0.16)) * float(profile.get("displacement_scale", 1.0))
	var side_bias := profile.get("side_bias", Vector2.ZERO) as Vector2
	var room_polygon: PackedVector2Array = profile.get("room_polygon", PackedVector2Array())
	var sample_rect: Rect2 = profile.get("sample_rect", Rect2())
	var bounds := Rect2(room_rect.position + Vector2(margin, margin), room_rect.size - Vector2(margin, margin) * 2.0)
	if sample_rect.size.x > 0.0 and sample_rect.size.y > 0.0:
		bounds = Rect2(sample_rect.position + Vector2(margin, margin), sample_rect.size - Vector2(margin, margin) * 2.0)
	elif not room_polygon.is_empty():
		var min_point := Vector2(INF, INF)
		var max_point := Vector2(-INF, -INF)
		for point: Vector2 in room_polygon:
			min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
			max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))
		bounds = Rect2(min_point + Vector2(margin, margin), (max_point - min_point) - Vector2(margin, margin) * 2.0)

	# 1. Random spread points, kept apart
	var seeds := PackedVector2Array()
	for attempt in 200:
		if point_count > 0 and seeds.size() >= point_count:
			break
		var candidate := Vector2(
			_rng.randf_range(bounds.position.x, bounds.end.x),
			_rng.randf_range(bounds.position.y, bounds.end.y))
		if side_bias != Vector2.ZERO and _rng.randf() < 0.45:
			candidate.x = bounds.position.x + (bounds.end.x - bounds.position.x) * (0.5 + side_bias.x * _rng.randf_range(0.2, 0.5))
		if not room_polygon.is_empty() and not _inside_with_margin(candidate, room_polygon, margin):
			continue
		var too_close := false
		for existing: Vector2 in seeds:
			if existing.distance_to(candidate) < min_point_distance:
				too_close = true
				break
		if not too_close:
			seeds.append(candidate)
	if seeds.size() < 6:
		return PackedVector2Array()

	# 2. Convex hull (Andrew monotone chain)
	var hull := _convex_hull(seeds)
	if hull.size() < 6:
		return PackedVector2Array()

	# 3. Displaced midpoints on every hull edge (rounded organic outline)
	var shaped := PackedVector2Array()
	var count := hull.size()
	for index in count:
		var next := (index + 1) % count
		shaped.append(hull[index])
		var edge := hull[next] - hull[index]
		var mid := hull[index] + edge * 0.5
		var displacement := edge.length() * _rng.randf_range(displacement_min, displacement_max)
		var direction := Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
		var displaced := mid + direction * displacement
		# Pull displaced midpoints slightly toward the loop centroid for concave notches
		var centroid := _centroid(hull)
		displaced = displaced.lerp(centroid, 0.15)
		shaped.append(displaced)

	# 4. Clamp corner angles
	for iteration in 3:
		shaped = _fix_angles(shaped, deg_to_rad(max_angle_deg))
		shaped = _push_apart(shaped, 120.0)

	# 5. Keep inside bounds
	for index in shaped.size():
		shaped[index] = Vector2(
			clampf(shaped[index].x, bounds.position.x, bounds.end.x),
			clampf(shaped[index].y, bounds.position.y, bounds.end.y))

	# 6. Resample the spline into evenly spaced control points, clamp the
	# resampled loop's corners, then validate
	var even := _resample_arc(shaped, 22)
	if even.size() < 8:
		return PackedVector2Array()
	for iteration in 2:
		even = _fix_angles(even, deg_to_rad(max_angle_deg))
		even = _push_apart(even, 130.0)
	if not room_polygon.is_empty():
		var check_margin := float(profile.get("room_check_margin", 42.0))
		for check_point: Vector2 in centerline_checkpoints(even):
			if not _inside_with_margin(check_point, room_polygon, check_margin):
				return PackedVector2Array()
	var centerline := _sample_centerline(even)
	if _polyline_length(centerline) < min_loop_length:
		return PackedVector2Array()
	if not _self_distance_ok(centerline, min_self_distance):
		return PackedVector2Array()

	# 7. Start at the longest straight (aligned grid + checker on a straight)
	return _reorder_to_longest_straight(even, centerline)


static func _convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	var ordered: Array[Vector2] = []
	for point: Vector2 in points:
		ordered.append(point)
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	var lower := PackedVector2Array()
	for point: Vector2 in ordered:
		while lower.size() >= 2 and _cross(lower[lower.size() - 2], lower[lower.size() - 1], point) <= 0.0:
			lower.remove_at(lower.size() - 1)
		lower.append(point)
	var upper := PackedVector2Array()
	for index in range(ordered.size() - 1, -1, -1):
		var point := ordered[index]
		while upper.size() >= 2 and _cross(upper[upper.size() - 2], upper[upper.size() - 1], point) <= 0.0:
			upper.remove_at(upper.size() - 1)
		upper.append(point)
	lower.remove_at(lower.size() - 1)
	upper.remove_at(upper.size() - 1)
	lower.append_array(upper)
	return lower


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


static func _inside_with_margin(point: Vector2, polygon: PackedVector2Array, margin: float) -> bool:
	if not Geometry2D.is_point_in_polygon(point, polygon):
		return false
	var count := polygon.size()
	for index in count:
		var from: Vector2 = polygon[index]
		var to: Vector2 = polygon[(index + 1) % count]
		var edge := to - from
		var length := edge.length()
		if length < 0.001:
			continue
		var normal := Vector2(-edge.y, edge.x) / length
		if absf((point - from).dot(normal)) < margin:
			return false
	return true


static func centerline_checkpoints(controls: PackedVector2Array) -> PackedVector2Array:
	return _sample_centerline(controls)


static func _centroid(points: PackedVector2Array) -> Vector2:
	var total := Vector2.ZERO
	for point: Vector2 in points:
		total += point
	return total / float(points.size())


static func _fix_angles(points: PackedVector2Array, max_angle: float) -> PackedVector2Array:
	var result := points.duplicate()
	var count := result.size()
	for index in count:
		var prev := result[(index - 1 + count) % count]
		var next := result[(index + 1) % count]
		var incoming := (result[index] - prev).normalized()
		var outgoing := (next - result[index]).normalized()
		var angle := incoming.angle_to(outgoing)
		if absf(angle) <= max_angle:
			continue
		var clamped := max_angle * signf(angle)
		result[(index + 1) % count] = result[index] + outgoing.rotated(clamped - angle) * next.distance_to(result[index])
	return result


static func _push_apart(points: PackedVector2Array, min_distance: float) -> PackedVector2Array:
	var result := points.duplicate()
	for i in result.size():
		for j in range(i + 1, result.size()):
			var delta := result[j] - result[i]
			var distance := delta.length()
			if distance > 0.001 and distance < min_distance:
				var push := delta.normalized() * (min_distance - distance) * 0.5
				result[i] -= push
				result[j] += push
	return result


static func _sample_centerline(controls: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in SAMPLE_COUNT:
		points.append(_catmull_rom_closed(controls, float(index) / float(SAMPLE_COUNT)))
	return points


static func _catmull_rom_closed(points: PackedVector2Array, t: float) -> Vector2:
	var count := points.size()
	var scaled := t * float(count)
	var i := int(floor(scaled))
	var local := scaled - float(i)
	var p0: Vector2 = points[posmod(i - 1, count)]
	var p1: Vector2 = points[posmod(i, count)]
	var p2: Vector2 = points[posmod(i + 1, count)]
	var p3: Vector2 = points[posmod(i + 2, count)]
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * local
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * local * local
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * local * local * local
	)


static func _polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		total += points[index].distance_to(points[(index + 1) % points.size()])
	return total


static func _self_distance_ok(centerline: PackedVector2Array, min_distance: float) -> bool:
	var count := centerline.size()
	for index in count:
		var point := centerline[index]
		for offset in range(24, count - 24):
			var other := centerline[(index + offset) % count]
			if point.distance_to(other) < min_distance:
				return false
	return true


static func _resample_arc(controls: PackedVector2Array, target_count: int) -> PackedVector2Array:
	var dense := PackedVector2Array()
	var steps := 1600
	for step in steps:
		dense.append(_catmull_rom_closed(controls, float(step) / float(steps)))
	var cumulative := PackedFloat32Array()
	cumulative.append(0.0)
	for index in range(1, dense.size()):
		cumulative.append(cumulative[index - 1] + dense[index - 1].distance_to(dense[index]))
	var total := cumulative[cumulative.size() - 1]
	if total < 200.0:
		return PackedVector2Array()
	var result := PackedVector2Array()
	var cursor := 0
	for point_index in target_count:
		var target := total * float(point_index) / float(target_count)
		while cursor < cumulative.size() - 2 and cumulative[cursor + 1] < target:
			cursor += 1
		var local := 0.0
		if cumulative[cursor + 1] > cumulative[cursor]:
			local = (target - cumulative[cursor]) / (cumulative[cursor + 1] - cumulative[cursor])
		result.append(dense[cursor].lerp(dense[cursor + 1], clampf(local, 0.0, 1.0)))
	return result


static func _reorder_to_longest_straight(controls: PackedVector2Array, centerline: PackedVector2Array) -> PackedVector2Array:
	var count := controls.size()
	var span := 28
	var sample_span := int(floor(260.0 / float(count)))
	var best_control := 0
	var best_straight := -1.0
	for index in count:
		var sample_index := int(round(float(index) * 260.0 / float(count))) % centerline.size()
		var ahead := centerline[(sample_index + span) % centerline.size()]
		var behind := centerline[(sample_index + centerline.size() - span) % centerline.size()]
		var chord := behind.distance_to(ahead)
		if chord < 380.0:
			continue
		var path := 0.0
		for offset in range(1, span * 2 + 1):
			var from := (sample_index + centerline.size() - span + offset - 1) % centerline.size()
			var to := (sample_index + centerline.size() - span + offset) % centerline.size()
			path += centerline[from].distance_to(centerline[to])
		var straightness := chord / maxf(path, 1.0)
		if straightness > best_straight:
			best_straight = straightness
			best_control = index
	var result := PackedVector2Array()
	for index in count:
		result.append(controls[(best_control + index) % count])
	return result
