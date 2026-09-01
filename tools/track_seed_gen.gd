class_name TrackSeedGen
## Deterministic procedural circuit generation from smooth, normalized route
## families. Family, length, and per-attempt variation use independent hash
## streams so changing the room does not change a seed's identity.

const SAMPLE_COUNT := 260
const CONTROL_COUNT := 24
const HALF_WIDTH := 125.0
const CORRIDOR_CLEARANCE := HALF_WIDTH + 10.0
const SPLINE_GUARD := 12.0
const MAX_VARIANTS := 12

const FAMILY_NAMES: Array[StringName] = [
	&"speed_loop",
	&"kidney",
	&"dogbone",
	&"broad_triangle",
	&"offset_s",
	&"deep_notch",
]

const FAMILY_SALT := 0x13579BDF
const LENGTH_SALT := 0x2468ACE
const VARIANT_SALT := 0x51A7E3D
const FALLBACK_SALT := 0x6C8E9CF
const RHYTHM_SALT := 0x4A71C9D


static func generate_with_retries(seed: int, room_rect: Rect2, params: Dictionary = {}) -> Dictionary:
	# Attempts vary only the requested seed's family parameters. The caller must
	# never receive a neighboring seed because seed identity is player-facing.
	return _generate_result(seed, room_rect, params)


static func generate(seed: int, room_rect: Rect2, params: Dictionary = {}) -> PackedVector2Array:
	return _generate_result(seed, room_rect, params)["points"] as PackedVector2Array


static func centerline_checkpoints(controls: PackedVector2Array) -> PackedVector2Array:
	return _sample_centerline(controls)


static func _generate_result(seed: int, room_rect: Rect2, params: Dictionary) -> Dictionary:
	var family_index := posmod(_hash32(seed ^ FAMILY_SALT), FAMILY_NAMES.size())
	var family: StringName = FAMILY_NAMES[family_index]
	var length_roll := _hash_unit(seed, LENGTH_SALT)
	var target_length := lerpf(2500.0, 5500.0, length_roll)
	var configured_max := float(params.get("max_loop_length", 0.0))
	if configured_max > 0.0:
		target_length = minf(target_length, configured_max)

	var room_polygon: PackedVector2Array = params.get("room_polygon", PackedVector2Array())
	var room_shape := StringName(params.get("room_shape", &""))
	var source_rect := _generation_rect(room_rect, params, room_polygon)
	var requested_margin := float(params.get("margin", 150.0))
	var centerline_margin := maxf(requested_margin, CORRIDOR_CLEARANCE)
	var usable_rect := source_rect.grow(-centerline_margin).grow(-SPLINE_GUARD)
	if usable_rect.size.x < HALF_WIDTH * 2.0 or usable_rect.size.y < HALF_WIDTH * 2.0:
		return _empty_result(seed, family)

	var requested_self_distance := maxf(float(params.get("min_self_distance", 250.0)), HALF_WIDTH * 2.0)
	# A narrow room cannot honor an arbitrarily large requested branch gap after
	# reserving the corridor and wall margin. Keep the full corridor clear while
	# accepting that physical maximum instead of rejecting every candidate.
	var physical_self_distance := maxf(HALF_WIDTH * 2.0, minf(usable_rect.size.x, usable_rect.size.y) * 0.55)
	var min_self_distance := minf(requested_self_distance, physical_self_distance)
	var room_check_margin := maxf(float(params.get("room_check_margin", 0.0)), CORRIDOR_CLEARANCE)
	var minimum_length := float(params.get("min_loop_length", 1900.0))
	var last_reason := "no candidate"

	for attempt in MAX_VARIANTS:
		var controls := _el_controls(family, seed, attempt, source_rect, target_length, min_self_distance) \
			if room_shape == &"el" else _family_controls(family, family, seed, attempt, usable_rect, target_length, min_self_distance)
		var validation := _validate_controls(
			controls,
			source_rect,
			room_polygon,
			room_check_margin,
			min_self_distance,
			minimum_length
		)
		last_reason = String(validation.get("reason", "unknown"))
		if bool(validation["valid"]):
			var centerline: PackedVector2Array = validation["centerline"]
			var ordered_controls := _reorder_to_longest_straight(controls, centerline)
			var ordered_validation := _validate_controls(
				ordered_controls,
				source_rect,
				room_polygon,
				room_check_margin,
				min_self_distance,
				minimum_length
			)
			if not bool(ordered_validation["valid"]):
				last_reason = "post-order " + String(ordered_validation.get("reason", "unknown"))
				continue
			return {
				"points": ordered_controls,
				"seed": seed,
				"family": family,
				"length": float(ordered_validation["length"]),
				"attempt": attempt,
				"fallback": false,
				"realization": &"el_safe" if room_shape == &"el" else family,
			}

	var family_reason := last_reason
	# The fallback is deterministic and never changes the requested seed or its
	# selected family metadata. EL rooms retain their dedicated L-safe route.
	for fallback_attempt in 4:
		var controls := _el_controls(family, seed, MAX_VARIANTS + fallback_attempt, source_rect, target_length, min_self_distance) \
			if room_shape == &"el" else _family_controls(&"conservative", family, seed, fallback_attempt, usable_rect, target_length, min_self_distance)
		var validation := _validate_controls(
			controls,
			source_rect,
			room_polygon,
			room_check_margin,
			min_self_distance,
			minf(minimum_length, target_length * 0.72)
		)
		last_reason = String(validation.get("reason", "unknown"))
		if bool(validation["valid"]):
			var centerline: PackedVector2Array = validation["centerline"]
			var ordered_controls := _reorder_to_longest_straight(controls, centerline)
			var ordered_validation := _validate_controls(
				ordered_controls,
				source_rect,
				room_polygon,
				room_check_margin,
				min_self_distance,
				minf(minimum_length, target_length * 0.72)
			)
			if not bool(ordered_validation["valid"]):
				last_reason = "post-order " + String(ordered_validation.get("reason", "unknown"))
				continue
			return {
				"points": ordered_controls,
				"seed": seed,
				"family": family,
				"length": float(ordered_validation["length"]),
				"attempt": MAX_VARIANTS + fallback_attempt,
				"fallback": true,
				"realization": &"el_safe" if room_shape == &"el" else &"technical_perimeter",
				"fallback_reason": family_reason,
			}
	var empty := _empty_result(seed, family)
	empty["reason"] = last_reason
	return empty


static func _empty_result(seed: int, family: StringName) -> Dictionary:
	return {
		"points": PackedVector2Array(),
		"seed": seed,
		"family": family,
		"length": 0.0,
		"attempt": -1,
		"fallback": true,
		"realization": &"none",
	}


static func _generation_rect(room_rect: Rect2, params: Dictionary, room_polygon: PackedVector2Array) -> Rect2:
	if not room_polygon.is_empty():
		return _points_rect(room_polygon)
	return room_rect


static func _family_controls(
	template_family: StringName,
	rhythm_family: StringName,
	seed: int,
	attempt: int,
	usable_rect: Rect2,
	target_length: float,
	min_self_distance: float
) -> PackedVector2Array:
	var anchors := _family_template(template_family, seed)
	if anchors.is_empty():
		return PackedVector2Array()

	# Templates are authored horizontally. Rotate them before fitting a tall room
	# so dogbones become vertical dogbones, not stretched horizontal circles.
	var orientation := 0.0
	if usable_rect.size.y > usable_rect.size.x * 1.12:
		orientation = PI * 0.5
	elif maxf(usable_rect.size.x, usable_rect.size.y) < minf(usable_rect.size.x, usable_rect.size.y) * 1.12:
		orientation = float(posmod(_hash32(seed ^ (VARIANT_SALT + 0x37)), 4)) * PI * 0.5
	var mirror := -1.0 if _hash_unit(seed, VARIANT_SALT + 7) < 0.5 else 1.0
	for index in anchors.size():
		var point := anchors[index]
		point.x *= mirror
		anchors[index] = point.rotated(orientation)
	var normalized := _resample_template(anchors, CONTROL_COUNT)
	normalized = _apply_turn_rhythm(
		normalized,
		rhythm_family,
		seed,
		attempt,
		target_length,
		template_family == &"conservative"
	)

	var mapped := _map_to_rect(normalized, usable_rect)
	var full_centerline := _sample_centerline(mapped)
	var full_length := _polyline_length(full_centerline)
	if full_length < 1.0:
		return PackedVector2Array()

	# Keep enough of the full-size candidate to preserve nonlocal clearance. This
	# lets short length rolls stay within their family instead of collapsing a
	# waist and falling through to a generic loop.
	var minimum_scale := maxf(0.62, 285.0 / minf(usable_rect.size.x, usable_rect.size.y))
	var full_clearance := _minimum_branch_distance(full_centerline, min_self_distance)
	if full_clearance < INF:
		minimum_scale = maxf(minimum_scale, minf(1.0, min_self_distance / maxf(full_clearance, 1.0)))
	var retry_ceiling := maxf(minimum_scale, 1.0 - float(attempt) * 0.012)
	var length_scale := clampf(target_length / full_length, minimum_scale, retry_ceiling)
	var center := usable_rect.get_center()
	var slack := usable_rect.size * (1.0 - length_scale) * 0.18
	var offset := Vector2(
		(_hash_unit(seed, LENGTH_SALT + 31) * 2.0 - 1.0) * slack.x,
		(_hash_unit(seed, LENGTH_SALT + 47) * 2.0 - 1.0) * slack.y
	)
	for index in mapped.size():
		mapped[index] = center + (mapped[index] - center) * length_scale + offset
	return mapped


static func _family_template(family: StringName, seed: int) -> PackedVector2Array:
	match family:
		&"speed_loop":
			return PackedVector2Array([
				Vector2(-0.96, -0.08), Vector2(-0.88, -0.42), Vector2(-0.68, -0.70),
				Vector2(-0.42, -0.84), Vector2(-0.16, -0.56), Vector2(0.10, -0.88),
				Vector2(0.40, -0.62), Vector2(0.70, -0.72), Vector2(0.92, -0.24),
				Vector2(0.94, 0.10), Vector2(0.78, 0.44), Vector2(0.52, 0.70),
				Vector2(0.24, 0.56), Vector2(-0.04, 0.88), Vector2(-0.36, 0.66),
				Vector2(-0.66, 0.58), Vector2(-0.88, 0.32),
			])
		&"kidney":
			return PackedVector2Array([
				Vector2(-0.74, -0.52), Vector2(-0.30, -0.80), Vector2(0.25, -0.84),
				Vector2(0.70, -0.58), Vector2(0.88, -0.16), Vector2(0.80, 0.30),
				Vector2(0.48, 0.68), Vector2(-0.02, 0.82), Vector2(-0.45, 0.68),
				Vector2(-0.72, 0.48), Vector2(-0.48, 0.25), Vector2(-0.02, 0.02),
				Vector2(-0.40, -0.30), Vector2(-0.72, -0.36),
			])
		&"dogbone":
			return PackedVector2Array([
				Vector2(-0.94, 0.00), Vector2(-0.84, -0.48), Vector2(-0.56, -0.76),
				Vector2(-0.28, -0.68), Vector2(-0.15, -0.43), Vector2(0.00, -0.38),
				Vector2(0.15, -0.43), Vector2(0.28, -0.68), Vector2(0.56, -0.76),
				Vector2(0.84, -0.48), Vector2(0.94, 0.00), Vector2(0.84, 0.48),
				Vector2(0.56, 0.76), Vector2(0.28, 0.68), Vector2(0.15, 0.43),
				Vector2(0.00, 0.38), Vector2(-0.15, 0.43), Vector2(-0.28, 0.68),
				Vector2(-0.56, 0.76), Vector2(-0.84, 0.48),
			])
		&"broad_triangle":
			return PackedVector2Array([
				Vector2(0.00, -0.94), Vector2(0.15, -0.84), Vector2(0.23, -0.62),
				Vector2(0.40, -0.48), Vector2(0.47, -0.20), Vector2(0.72, 0.28),
				Vector2(0.86, 0.54), Vector2(0.72, 0.72), Vector2(0.44, 0.80),
				Vector2(0.20, 0.68), Vector2(-0.04, 0.84), Vector2(-0.30, 0.70),
				Vector2(-0.54, 0.80), Vector2(-0.78, 0.64), Vector2(-0.86, 0.44),
				Vector2(-0.68, 0.16), Vector2(-0.52, -0.20), Vector2(-0.40, -0.50),
				Vector2(-0.22, -0.64), Vector2(-0.15, -0.84),
			])
		&"offset_s":
			return PackedVector2Array([
				Vector2(-0.86, -0.35), Vector2(-0.65, -0.70), Vector2(-0.20, -0.86),
				Vector2(0.30, -0.78), Vector2(0.72, -0.55), Vector2(0.88, -0.32),
				Vector2(0.68, -0.18), Vector2(0.25, -0.05), Vector2(0.55, 0.18),
				Vector2(0.88, 0.38), Vector2(0.65, 0.72), Vector2(0.20, 0.86),
				Vector2(-0.30, 0.78), Vector2(-0.72, 0.55), Vector2(-0.88, 0.32),
				Vector2(-0.68, 0.18), Vector2(-0.25, 0.05), Vector2(-0.55, -0.18),
			])
		&"deep_notch":
			return PackedVector2Array([
				Vector2(-0.88, 0.00), Vector2(-0.76, -0.48), Vector2(-0.38, -0.78),
				Vector2(0.10, -0.84), Vector2(0.58, -0.66), Vector2(0.86, -0.42),
				Vector2(0.90, -0.32), Vector2(0.48, -0.30), Vector2(0.18, 0.00),
				Vector2(0.48, 0.30), Vector2(0.90, 0.32), Vector2(0.86, 0.42),
				Vector2(0.58, 0.66), Vector2(0.10, 0.84), Vector2(-0.38, 0.78),
				Vector2(-0.76, 0.48),
			])
		_:
			# A broad technical perimeter is safer than the concave family shapes,
			# while staggered top and bottom sectors retain real corner rhythm in
			# narrow rooms instead of collapsing to the old perturbed circle.
			return PackedVector2Array([
				Vector2(-0.96, -0.08), Vector2(-0.88, -0.48), Vector2(-0.68, -0.76),
				Vector2(-0.46, -0.62), Vector2(-0.22, -0.84), Vector2(0.02, -0.66),
				Vector2(0.28, -0.82), Vector2(0.54, -0.64), Vector2(0.80, -0.74),
				Vector2(0.96, -0.36), Vector2(0.90, 0.04), Vector2(0.96, 0.38),
				Vector2(0.74, 0.74), Vector2(0.48, 0.62), Vector2(0.20, 0.84),
				Vector2(-0.06, 0.64), Vector2(-0.34, 0.82), Vector2(-0.60, 0.62),
				Vector2(-0.84, 0.74), Vector2(-0.96, 0.34),
			])


static func _apply_turn_rhythm(
	points: PackedVector2Array,
	family: StringName,
	seed: int,
	attempt: int,
	target_length: float,
	conservative: bool,
	strength_multiplier: float = 1.0
) -> PackedVector2Array:
	if points.size() < 8:
		return points
	var attempt_strength := _attempt_rhythm_strength(attempt, conservative)
	if attempt_strength <= 0.0:
		return points
	var family_index := maxi(FAMILY_NAMES.find(family), 0)
	var rhythm_seed := _hash32(seed ^ RHYTHM_SALT ^ ((family_index + 1) * 0x1F123BB) ^ (attempt * 0x51A7E3D))
	var phase_broad := TAU * _hash_unit(rhythm_seed, RHYTHM_SALT + 17)
	var phase_detail := TAU * _hash_unit(rhythm_seed, RHYTHM_SALT + 41)
	var chicane_center := posmod(_hash32(rhythm_seed ^ (RHYTHM_SALT + 73)), points.size())
	var quiet_center := posmod(chicane_center + points.size() / 2, points.size())
	var length_strength := lerpf(0.82, 1.18, clampf(inverse_lerp(2500.0, 5500.0, target_length), 0.0, 1.0))
	var amplitude := _family_rhythm_strength(family) * attempt_strength * length_strength * strength_multiplier
	if conservative:
		amplitude *= 0.78

	var offsets := PackedFloat32Array()
	var chicane_half_span := 4.5
	for index in points.size():
		var angle := TAU * float(index) / float(points.size())
		var field := sin(angle * 3.0 + phase_broad) * 0.58
		field += sin(angle * 6.0 + phase_detail) * 0.42
		var chicane_distance := _signed_cyclic_distance(index, chicane_center, points.size())
		if absf(chicane_distance) < chicane_half_span:
			field += sin(PI * chicane_distance / chicane_half_span) * 0.82
		offsets.append(field * amplitude)
	# Circular smoothing turns the displacement field into readable corner
	# sequences instead of spline-scale wiggles.
	for _pass in 2:
		var smoothed := PackedFloat32Array()
		for index in offsets.size():
			smoothed.append((offsets[posmod(index - 1, offsets.size())] + offsets[index] * 2.0 + offsets[(index + 1) % offsets.size()]) * 0.25)
		offsets = smoothed
	var mean := 0.0
	for offset: float in offsets:
		mean += offset
	mean /= float(offsets.size())

	var result := PackedVector2Array()
	for index in points.size():
		var tangent := points[posmod(index - 1, points.size())].direction_to(points[(index + 1) % points.size()])
		var normal := tangent.rotated(PI * 0.5)
		var quiet_distance := _cyclic_index_distance(index, quiet_center, points.size())
		var quiet_factor := smoothstep(2.0, 5.0, float(quiet_distance))
		result.append(points[index] + normal * (offsets[index] - mean) * quiet_factor)
	return result


static func _attempt_rhythm_strength(attempt: int, conservative: bool) -> float:
	if conservative:
		match attempt:
			0:
				return 0.90
			1:
				return 0.60
			2:
				return 0.30
			_:
				return 0.0
	return clampf(1.0 - float(attempt) * 0.09, 0.0, 1.0)


static func _family_rhythm_strength(family: StringName) -> float:
	match family:
		&"speed_loop":
			return 0.16
		&"kidney":
			return 0.16
		&"dogbone":
			return 0.15
		&"broad_triangle":
			return 0.15
		&"offset_s":
			return 0.16
		&"deep_notch":
			return 0.16
	return 0.10


static func _signed_cyclic_distance(index: int, center: int, count: int) -> float:
	var distance := posmod(index - center + count / 2, count) - count / 2
	return float(distance)


static func _cyclic_index_distance(first: int, second: int, count: int) -> int:
	var direct := absi(first - second)
	return mini(direct, count - direct)


static func _resample_template(anchors: PackedVector2Array, target_count: int) -> PackedVector2Array:
	var cumulative := PackedFloat32Array([0.0])
	for index in anchors.size():
		cumulative.append(cumulative[index] + anchors[index].distance_to(anchors[(index + 1) % anchors.size()]))
	var total := cumulative[anchors.size()]
	if total < 0.001:
		return PackedVector2Array()
	var result := PackedVector2Array()
	var segment := 0
	for output_index in target_count:
		var target := total * float(output_index) / float(target_count)
		while segment < anchors.size() - 1 and cumulative[segment + 1] < target:
			segment += 1
		var segment_length := cumulative[segment + 1] - cumulative[segment]
		var local := (target - cumulative[segment]) / maxf(segment_length, 0.001)
		result.append(anchors[segment].lerp(anchors[(segment + 1) % anchors.size()], local))
	return result


static func _el_controls(
	family: StringName,
	seed: int,
	attempt: int,
	source_rect: Rect2,
	target_length: float,
	min_self_distance: float
) -> PackedVector2Array:
	# This route follows the eroded L footprint instead of pretending the room is
	# its left rectangle. The rounded elbow stays clear of the concave corner.
	var anchors := PackedVector2Array([
		Vector2(-0.84, -0.70), Vector2(-0.38, -0.76), Vector2(0.04, -0.72),
		Vector2(0.13, -0.56), Vector2(0.12, -0.24), Vector2(0.10, -0.08),
		Vector2(0.16, 0.12), Vector2(0.30, 0.26), Vector2(0.62, 0.26),
		Vector2(0.84, 0.36), Vector2(0.84, 0.70), Vector2(0.35, 0.76),
		Vector2(-0.30, 0.76), Vector2(-0.84, 0.68), Vector2(-0.86, 0.26),
		Vector2(-0.86, -0.28),
	])
	var normalized := _resample_template(anchors, CONTROL_COUNT)
	normalized = _apply_turn_rhythm(normalized, family, seed, attempt, target_length, false, 0.62)
	var mapped := PackedVector2Array()
	for point: Vector2 in normalized:
		mapped.append(source_rect.get_center() + point * source_rect.size * 0.5)
	var full_length := _polyline_length(_sample_centerline(mapped))
	if full_length < 1.0:
		return PackedVector2Array()
	var minimum_scale := 0.94
	var full_clearance := _minimum_branch_distance(_sample_centerline(mapped), min_self_distance)
	if full_clearance < INF:
		minimum_scale = maxf(minimum_scale, minf(1.0, min_self_distance / maxf(full_clearance, 1.0)))
	var retry_ceiling := maxf(minimum_scale, 1.0 - float(mini(attempt, MAX_VARIANTS - 1)) * 0.006)
	var length_scale := clampf(target_length / full_length, minimum_scale, retry_ceiling)
	var center := source_rect.get_center()
	var offset_roll := _hash_unit(seed, VARIANT_SALT + 0x6E1) * 2.0 - 1.0
	var offset := Vector2(offset_roll * source_rect.size.x * (1.0 - length_scale) * 0.03, 0.0)
	for index in mapped.size():
		mapped[index] = center + (mapped[index] - center) * length_scale + offset
	return mapped


static func _map_to_rect(points: PackedVector2Array, target: Rect2) -> PackedVector2Array:
	var source := _points_rect(points)
	if source.size.x < 0.001 or source.size.y < 0.001:
		return PackedVector2Array()
	var result := PackedVector2Array()
	for point: Vector2 in points:
		var normalized := Vector2(
			(point.x - source.position.x) / source.size.x,
			(point.y - source.position.y) / source.size.y
		)
		result.append(target.position + normalized * target.size)
	return result


static func _validate_controls(
	controls: PackedVector2Array,
	source_rect: Rect2,
	room_polygon: PackedVector2Array,
	room_margin: float,
	min_self_distance: float,
	minimum_length: float
) -> Dictionary:
	if controls.size() < 8:
		return {"valid": false, "reason": "too few controls"}
	var centerline := _sample_centerline(controls)
	if _has_self_intersection(centerline):
		return {"valid": false, "reason": "self intersection"}
	var branch_clearance := _minimum_branch_distance(centerline, min_self_distance)
	if branch_clearance < min_self_distance:
		return {"valid": false, "reason": "self distance %.1f < %.1f" % [branch_clearance, min_self_distance]}
	for point: Vector2 in centerline:
		if not source_rect.has_point(point):
			return {"valid": false, "reason": "outside source rect"}
		if not room_polygon.is_empty() and not _inside_with_margin(point, room_polygon, room_margin):
			return {"valid": false, "reason": "outside room margin"}
	var loop_length := _polyline_length(centerline)
	if loop_length < minimum_length:
		return {"valid": false, "reason": "below minimum length"}
	return {"valid": true, "centerline": centerline, "length": loop_length}


static func _inside_with_margin(point: Vector2, polygon: PackedVector2Array, margin: float) -> bool:
	if not Geometry2D.is_point_in_polygon(point, polygon):
		return false
	for index in polygon.size():
		var from: Vector2 = polygon[index]
		var to: Vector2 = polygon[(index + 1) % polygon.size()]
		if _point_segment_distance(point, from, to) < margin:
			return false
	return true


static func _point_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared < 0.001:
		return point.distance_to(from)
	var fraction := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * fraction)


static func _points_rect(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum = Vector2(minf(minimum.x, point.x), minf(minimum.y, point.y))
		maximum = Vector2(maxf(maximum.x, point.x), maxf(maximum.y, point.y))
	return Rect2(minimum, maximum - minimum)


static func _sample_centerline(controls: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	if controls.size() < 4:
		return points
	for index in SAMPLE_COUNT:
		points.append(_catmull_rom_closed(controls, float(index) / float(SAMPLE_COUNT)))
	return points


static func _catmull_rom_closed(points: PackedVector2Array, t: float) -> Vector2:
	var count := points.size()
	var scaled := t * float(count)
	var index := int(floor(scaled))
	var local := scaled - float(index)
	var p0: Vector2 = points[posmod(index - 1, count)]
	var p1: Vector2 = points[posmod(index, count)]
	var p2: Vector2 = points[posmod(index + 1, count)]
	var p3: Vector2 = points[posmod(index + 2, count)]
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


static func _minimum_branch_distance(centerline: PackedVector2Array, min_distance: float) -> float:
	var count := centerline.size()
	var cumulative := PackedFloat32Array([0.0])
	for index in count:
		cumulative.append(cumulative[index] + centerline[index].distance_to(centerline[(index + 1) % count]))
	var total_length := cumulative[count]
	# Ignore a local run by traveled distance rather than sample count. Tight but
	# legitimate corners can keep nearby samples within a corridor width.
	# Samples within this traveled distance belong to the same corner. Treating
	# a broad 180-degree bend as two branches rejects safe concave silhouettes.
	var local_arc := maxf(850.0, min_distance * 3.0)
	var minimum := INF
	for first in count:
		for second in range(first + 1, count):
			var forward_arc := cumulative[second] - cumulative[first]
			if minf(forward_arc, total_length - forward_arc) < local_arc:
				continue
			minimum = minf(minimum, centerline[first].distance_to(centerline[second]))
	return minimum


static func _has_self_intersection(points: PackedVector2Array) -> bool:
	var count := points.size()
	for first in count:
		var first_next := (first + 1) % count
		for second in range(first + 1, count):
			var second_next := (second + 1) % count
			if first == second or first_next == second or second_next == first:
				continue
			if _segments_intersect(points[first], points[first_next], points[second], points[second_next]):
				return true
	return false


static func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := _cross(a, b, c)
	var ab_d := _cross(a, b, d)
	var cd_a := _cross(c, d, a)
	var cd_b := _cross(c, d, b)
	if ((ab_c > 0.0 and ab_d < 0.0) or (ab_c < 0.0 and ab_d > 0.0)) \
	and ((cd_a > 0.0 and cd_b < 0.0) or (cd_a < 0.0 and cd_b > 0.0)):
		return true
	return false


static func _cross(origin: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)


static func _reorder_to_longest_straight(controls: PackedVector2Array, centerline: PackedVector2Array) -> PackedVector2Array:
	var count := controls.size()
	var span := 28
	var best_control := 0
	var best_straight := -1.0
	for index in count:
		var sample_index := int(round(float(index) * float(SAMPLE_COUNT) / float(count))) % centerline.size()
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


static func _hash32(value: int) -> int:
	# A compact integer avalanche with bounded intermediate products. Masking to
	# 31 bits keeps behavior identical across native and headless builds.
	var mixed := value & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	return (mixed ^ (mixed >> 16)) & 0x7FFFFFFF


static func _hash_unit(seed: int, salt: int) -> float:
	return float(_hash32(seed ^ salt)) / 2147483647.0
