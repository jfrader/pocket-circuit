class_name TrackRouteGrammar
## Compositional macro-route grammar. Programs define an ordering rule while
## seed streams choose straight extents, bay/waist dimensions, and optional
## sections. The output is a new route skeleton, not displaced control points.

const NAMES: Array[StringName] = [&"perimeter", &"lobes", &"wedge"]
const MACRO_SALT := 0x36D1A77


static func count() -> int:
	return NAMES.size()


static func construct(index: int, seed: int) -> Dictionary:
	var program_index := posmod(index, NAMES.size())
	var program := NAMES[program_index]
	var section := _roll_int(seed, 0x51A7 + program_index * 97, 3)
	var extent := _roll_int(seed, 0x62B9 + program_index * 131, 2)
	var anchors := PackedVector2Array()
	match program:
		&"perimeter":
			anchors = _perimeter(seed, section)
		&"lobes":
			anchors = _lobes(seed, section)
		_:
			anchors = _wedge(seed, section)
	anchors = _apply_extent(anchors, extent)
	return {
		"program": program,
		"recipe": StringName("%s_section_%d_extent_%d" % [program, section, extent]),
		"anchors": anchors,
	}


static func _perimeter(seed: int, section: int) -> PackedVector2Array:
	var top_split := _roll(seed, 11, -0.24, 0.18)
	var bottom_split := _roll(seed, 17, -0.20, 0.30)
	var top_depth := _roll(seed, 23, 0.08, 0.24)
	var lower_depth := _roll(seed, 29, 0.04, 0.20)
	var points := PackedVector2Array([
		Vector2(-0.94, -0.08), Vector2(-0.86, -0.48), Vector2(-0.58, -0.80),
		Vector2(top_split - 0.24, -0.72 - top_depth), Vector2(top_split + 0.26, -0.84 + top_depth * 0.30),
		Vector2(0.66, -0.70), Vector2(0.92, -0.34), Vector2(0.92, 0.18),
		Vector2(0.68, 0.70), Vector2(bottom_split + 0.25, 0.84 - lower_depth),
		Vector2(bottom_split - 0.30, 0.68 + lower_depth), Vector2(-0.68, 0.76), Vector2(-0.92, 0.38),
	])
	return _insert_optional_section(points, section, seed, [3, 8, 11])


static func _lobes(seed: int, section: int) -> PackedVector2Array:
	var waist_x := _roll(seed, 71, -0.14, 0.16)
	var upper_waist := _roll(seed, 73, -0.48, -0.30)
	var lower_waist := _roll(seed, 79, 0.30, 0.50)
	var left_size := _roll(seed, 83, 0.62, 0.82)
	var right_size := _roll(seed, 89, 0.62, 0.84)
	var points := PackedVector2Array([
		Vector2(-0.94, 0.00), Vector2(-0.82, -0.48), Vector2(-0.52, -left_size),
		Vector2(-0.22, -0.68), Vector2(waist_x - 0.18, upper_waist), Vector2(waist_x + 0.20, upper_waist - 0.03),
		Vector2(0.42, -0.70), Vector2(0.72, -right_size), Vector2(0.94, -0.28),
		Vector2(0.90, 0.28), Vector2(0.66, right_size), Vector2(0.30, 0.70),
		Vector2(waist_x + 0.18, lower_waist), Vector2(waist_x - 0.20, lower_waist + 0.03),
		Vector2(-0.38, 0.72), Vector2(-0.72, left_size),
	])
	return _insert_optional_section(points, section, seed, [2, 7, 14])


static func _wedge(seed: int, section: int) -> PackedVector2Array:
	var apex_x := _roll(seed, 101, -0.24, 0.22)
	var east_shoulder := _roll(seed, 103, 0.42, 0.62)
	var south_split := _roll(seed, 107, -0.28, 0.28)
	var west_kink := _roll(seed, 109, -0.16, 0.12)
	var points := PackedVector2Array([
		Vector2(-0.74, -0.36), Vector2(-0.58, -0.70), Vector2(apex_x - 0.22, -0.88),
		Vector2(apex_x + 0.24, -0.82), Vector2(east_shoulder, -0.50), Vector2(0.84, -0.10),
		Vector2(0.90, 0.34), Vector2(0.80, 0.62),
		Vector2(0.46, 0.82), Vector2(south_split + 0.20, 0.66), Vector2(south_split - 0.18, 0.86),
		Vector2(-0.70, 0.68), Vector2(-0.92, 0.34), Vector2(-0.68 + west_kink, -0.04),
	])
	return _insert_optional_section(points, section, seed, [3, 8, 11])


static func _insert_optional_section(points: PackedVector2Array, section: int, seed: int, segment_choices: Array[int]) -> PackedVector2Array:
	if section == 0:
		return points
	var segment := segment_choices[section - 1]
	var from := points[segment]
	var to := points[(segment + 1) % points.size()]
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point
	center /= float(points.size())
	var inward := (center - from.lerp(to, 0.5)).normalized()
	var depth := _roll(seed, 131 + section * 11, 0.36, 0.52)
	var result := points.duplicate()
	for offset in range(-1, 3):
		var weight := 1.0 if offset in [0, 1] else 0.48
		var index := posmod(segment + offset, result.size())
		result[index] += inward * depth * weight
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


static func _roll(seed: int, salt: int, minimum: float, maximum: float) -> float:
	return lerpf(minimum, maximum, float(_hash32(seed ^ MACRO_SALT ^ salt)) / 2147483647.0)


static func _roll_int(seed: int, salt: int, maximum: int) -> int:
	return posmod(_hash32(seed ^ MACRO_SALT ^ salt), maximum)


static func _hash32(value: int) -> int:
	var mixed := value & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	return (mixed ^ (mixed >> 16)) & 0x7FFFFFFF
