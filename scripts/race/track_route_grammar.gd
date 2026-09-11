class_name TrackRouteGrammar
## Compositional macro-route grammar. Programs define an ordering rule while
## seed streams choose straight extents, bay/waist dimensions, and optional
## sections. The output is a new route skeleton, not displaced control points.

const NAMES: Array[StringName] = [&"perimeter", &"lobes", &"wedge", &"serpentine"]
const MACRO_SALT := 0x36D1A77


static func count() -> int:
	return NAMES.size()


static func construct(index: int, seed: int, length_bias: float = 0.0) -> Dictionary:
	var program_index := posmod(index, NAMES.size())
	var program := NAMES[program_index]
	var section := _roll_int(seed, 0x51A7 + program_index * 97, 4)
	var extent := _roll_int(seed, 0x62B9 + program_index * 131, 2)
	var anchors := PackedVector2Array()
	match program:
		&"perimeter":
			anchors = _perimeter(seed, section)
		&"lobes":
			anchors = _lobes(seed, section)
		&"serpentine":
			anchors = _serpentine(seed, section)
		_:
			anchors = _wedge(seed, section)
	anchors = _apply_extent(anchors, extent)
	if length_bias > 0.50:
		program = &"endurance"
		anchors = _endurance(anchors, length_bias)
	else:
		anchors = _apply_length_bias(anchors, length_bias)
	anchors = _apply_radial_jitter(anchors, seed)
	var mirrored := _roll_int(seed, 0x11A4D, 2) == 1
	if mirrored:
		for anchor_index in anchors.size():
			var point := anchors[anchor_index]
			point.x *= -1.0
			anchors[anchor_index] = point
	var with_kink := _maybe_chicane(anchors, seed)
	var kinked := with_kink.size() != anchors.size()
	anchors = with_kink
	var length_mode := "_extended" if length_bias > 0.20 and program != &"endurance" else ""
	var recipe := "%s_section_%d_extent_%d%s" % [program, section, extent, length_mode]
	if mirrored:
		recipe += "_mirror"
	if kinked:
		recipe += "_kink"
	return {
		"program": program,
		"recipe": StringName(recipe),
		"anchors": anchors,
	}


static func _perimeter(seed: int, section: int) -> PackedVector2Array:
	var top_split := _roll(seed, 11, -0.24, 0.18)
	var bottom_split := _roll(seed, 17, -0.20, 0.30)
	var top_depth := _roll(seed, 23, 0.08, 0.24)
	var lower_depth := _roll(seed, 29, 0.04, 0.20)
	var points := PackedVector2Array([
		Vector2(-0.94, -0.10), Vector2(-0.72, -0.68),
		Vector2(top_split, -0.82 - top_depth * 0.25), Vector2(0.68, -0.68),
		Vector2(0.94, -0.14), Vector2(0.78, 0.58),
		Vector2(bottom_split, 0.80 + lower_depth * 0.20), Vector2(-0.70, 0.66),
		Vector2(-0.94, 0.24),
	])
	return _insert_optional_section(points, section, seed, [2, 5, 7])


static func _lobes(seed: int, section: int) -> PackedVector2Array:
	var waist_x := _roll(seed, 71, -0.14, 0.16)
	var upper_waist := _roll(seed, 73, -0.48, -0.30)
	var lower_waist := _roll(seed, 79, 0.30, 0.50)
	var left_size := _roll(seed, 83, 0.62, 0.82)
	var right_size := _roll(seed, 89, 0.62, 0.84)
	var points := PackedVector2Array([
		Vector2(-0.94, -0.14), Vector2(-0.68, -left_size), Vector2(-0.06, -0.70),
		Vector2(waist_x + 0.20, upper_waist), Vector2(0.70, -right_size),
		Vector2(0.94, -0.10), Vector2(0.70, right_size), Vector2(0.08, 0.72),
		Vector2(waist_x - 0.20, lower_waist), Vector2(-0.68, left_size), Vector2(-0.94, 0.22),
	])
	return _insert_optional_section(points, section, seed, [1, 5, 8])


static func _wedge(seed: int, section: int) -> PackedVector2Array:
	var apex_x := _roll(seed, 101, -0.24, 0.22)
	var east_shoulder := _roll(seed, 103, 0.42, 0.62)
	var south_split := _roll(seed, 107, -0.28, 0.28)
	var west_kink := _roll(seed, 109, -0.16, 0.12)
	var points := PackedVector2Array([
		Vector2(apex_x, -0.90), Vector2(east_shoulder, -0.52),
		Vector2(0.90, 0.28), Vector2(0.72, 0.68),
		Vector2(south_split, 0.84), Vector2(-0.68, 0.66),
		Vector2(-0.92, 0.18), Vector2(-0.58 + west_kink, -0.48),
	])
	return _insert_optional_section(points, section, seed, [1, 3, 5])


static func _serpentine(seed: int, section: int) -> PackedVector2Array:
	# Placeholder skeleton only: TrackBuilderSeedGen._serpentine_controls builds
	# the S in world space with radius-safe arcs so every turn clears the
	# minimum drive radius and the crossings stay long enough for literal
	# straights. Keeping a light anchor set here preserves recipe identity.
	var waist := _roll(seed, 201, -0.30, 0.30)
	return PackedVector2Array([
		Vector2(0.90, 0.55), Vector2(0.90, -0.55),
		Vector2(waist, -0.84), Vector2(-0.90, -0.55),
		Vector2(-0.90, 0.55), Vector2(-waist, 0.84),
	])


static func _insert_optional_section(points: PackedVector2Array, section: int, seed: int, segment_choices: Array[int]) -> PackedVector2Array:
	if section == 0:
		return points
	var result := points.duplicate()
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point
	center /= float(points.size())
	var is_double := section >= 3
	var segments: Array[int] = []
	var depths: Array[float] = []
	if is_double:
		# second optional bay: two segments at smaller depths to stay inside bypass/self-distance limits
		var idx1 := section % segment_choices.size()
		var idx2 := (section + 2) % segment_choices.size()
		if idx2 == idx1:
			idx2 = (section + 1) % segment_choices.size()
		segments = [segment_choices[idx1], segment_choices[idx2]]
		depths = [
			_roll(seed, 131 + section * 11, 0.14, 0.24),
			_roll(seed, 137 + section * 13, 0.12, 0.22)
		]
	else:
		var segment := segment_choices[section - 1]
		segments = [segment]
		depths = [_roll(seed, 131 + section * 11, 0.46, 0.66)]
	for k in segments.size():
		var segment := segments[k]
		var depth := depths[k]
		var from := points[segment]
		var to := points[(segment + 1) % points.size()]
		var inward := (center - from.lerp(to, 0.5)).normalized()
		for offset in range(-1, 2):
			var weight := 1.0 if offset == 0 else 0.42
			var index := posmod(segment + offset, result.size())
			result[index] += inward * depth * weight
	return result


static func _maybe_chicane(points: PackedVector2Array, seed: int) -> PackedVector2Array:
	if _roll_int(seed, 0xC41CE, 6) == 0:
		return points
	var best := -1
	var best_length := 0.0
	for index in points.size():
		var length := points[index].distance_squared_to(points[(index + 1) % points.size()])
		if length > best_length:
			best_length = length
			best = index
	if best < 0 or best_length < 0.42:
		return points
	var from := points[best]
	var to := points[(best + 1) % points.size()]
	var along := to - from
	var normal := Vector2(-along.y, along.x).normalized()
	var side := -1.0 if _roll_int(seed, 0x51DE, 2) == 0 else 1.0
	# Amplitude grows with the square of edge length so the S kinks always hold
	# MIN_DRIVE_RADIUS in the tightest room; validation remains the final gate.
	var amplitude := minf(0.20, 0.105 * best_length * best_length)
	var first := from.lerp(to, 0.34) + normal * amplitude * side
	var second := from.lerp(to, 0.66) + normal * amplitude * -side
	first = Vector2(clampf(first.x, -0.96, 0.96), clampf(first.y, -0.92, 0.92))
	second = Vector2(clampf(second.x, -0.96, 0.96), clampf(second.y, -0.92, 0.92))
	var result := PackedVector2Array()
	for index in points.size():
		result.append(points[index])
		if index == best:
			result.append(first)
			result.append(second)
	return result


static func _apply_extent(points: PackedVector2Array, extent: int) -> PackedVector2Array:
	var result := points.duplicate()
	var delta := 0.14 if extent == 1 else -0.06
	for index in result.size():
		var point := result[index]
		if point.y < -0.32:
			point.x += delta
		elif point.y > 0.32:
			point.x -= delta * 0.65
		point.x = clampf(point.x, -0.96, 0.96)
		result[index] = point
	return result


static func _endurance(source: PackedVector2Array, length_bias: float) -> PackedVector2Array:
	var notch_x := clampf(source[0].x * 0.16, -0.14, 0.14)
	var notch_depth := lerpf(0.48, 0.30, length_bias)
	return PackedVector2Array([
		Vector2(-0.96, -0.16), Vector2(-0.86, -0.86), Vector2(0.76, -0.90),
		Vector2(0.96, -0.18), Vector2(0.88, 0.82), Vector2(0.48, 0.90),
		Vector2(notch_x, notch_depth), Vector2(-0.48, 0.90),
		Vector2(-0.86, 0.80), Vector2(-0.96, 0.18),
	])


static func _apply_length_bias(points: PackedVector2Array, length_bias: float) -> PackedVector2Array:
	var result := points.duplicate()
	for index in result.size():
		var point := result[index]
		if absf(point.x) > 0.48:
			point.x = signf(point.x) * lerpf(absf(point.x), minf(0.97, absf(point.x) + 0.18), length_bias)
		if absf(point.y) > 0.48:
			point.y = signf(point.y) * lerpf(absf(point.y), minf(0.92, absf(point.y) + 0.14), length_bias)
		result[index] = point
	if length_bias <= 0.20:
		return result
	var longest_segment := 0
	var longest_length := 0.0
	for index in result.size():
		var length := result[index].distance_squared_to(result[(index + 1) % result.size()])
		if length > longest_length:
			longest_length = length
			longest_segment = index
	var from := result[longest_segment]
	var to := result[(longest_segment + 1) % result.size()]
	var center := Vector2.ZERO
	for point: Vector2 in result:
		center += point
	center /= float(result.size())
	var inward := (center - from.lerp(to, 0.5)).normalized()
	var depth := lerpf(0.18, 0.58, length_bias)
	var lengthened := PackedVector2Array()
	for index in result.size():
		lengthened.append(result[index])
		if index == longest_segment:
			lengthened.append(from.lerp(to, 0.28) + inward * depth * 0.45)
			lengthened.append(from.lerp(to, 0.50) + inward * depth)
			lengthened.append(from.lerp(to, 0.72) + inward * depth * 0.45)
	return lengthened


static func _apply_radial_jitter(points: PackedVector2Array, seed: int) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var center := Vector2.ZERO
	for p: Vector2 in points:
		center += p
	center /= float(points.size())
	var result := PackedVector2Array()
	for i in points.size():
		var p := points[i]
		var rad_dir := (p - center)
		if rad_dir.length_squared() < 0.0001:
			rad_dir = Vector2(1, 0)
		else:
			rad_dir = rad_dir.normalized()
		var j := _roll(seed, 0x7A11 + i * 5, -0.02, 0.02)
		var jp := p + rad_dir * j
		jp.x = clampf(jp.x, -0.96, 0.96)
		jp.y = clampf(jp.y, -0.92, 0.92)
		result.append(jp)
	return result


static func _roll(seed: int, salt: int, minimum: float, maximum: float) -> float:
	return lerpf(minimum, maximum, float(_hash32(seed ^ MACRO_SALT ^ salt)) / 2147483647.0)


static func _roll_int(seed: int, salt: int, maximum: int) -> int:
	return posmod(_hash32(seed ^ MACRO_SALT ^ salt), maximum)


static func _hash32(value: int) -> int:
	var mixed := value & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	return (mixed ^ (mixed >> 16)) & 0x7FFFFFFF
