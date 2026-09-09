class_name TrackSeedGen
## Deterministic procedural circuit generation from bounded macro-route grammar.
## Family, length, and route-program selection use independent hash streams.

const ROUTE_GRAMMAR := preload("res://scripts/race/track_route_grammar.gd")

const SAMPLE_COUNT := 260
const HALF_WIDTH := 125.0
const CORRIDOR_CLEARANCE := HALF_WIDTH + 10.0
const SPLINE_GUARD := 12.0
const MAX_VARIANTS := 12
const WORLD_SCALE := 1.75
const MIN_SETUP_DISTANCE := 450.0
# A v1 vehicle sweeps roughly 22u around its center. Requiring the full 125u
# half-corridor plus that hull prevents a legal centerline from demanding a
# near-pivot turn while preserving the constrained L-room realization.
const VEHICLE_HULL_RADIUS := 22.0
const MIN_DRIVE_RADIUS := HALF_WIDTH + VEHICLE_HULL_RADIUS
const FILLET_RADIUS_MARGIN := 24.0
const STRAIGHT_CONTROL_SPACING := 110.0
const LITERAL_STRAIGHT_HEADING_TOLERANCE := 0.04
const SETUP_STRAIGHTNESS := 0.985
const BYPASS_MIN_ARC := 500.0
const BYPASS_MAX_ARC := 3000.0
const BYPASS_MIN_SAVING := 220.0
const BYPASS_MIN_RATIO := 1.40

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
const RHYTHM_SALT := 0x4A71C9D
const ROUTE_SALT := 0x2D91F3B


static func generate_with_retries(seed: int, room_rect: Rect2, params: Dictionary = {}) -> Dictionary:
	# Attempts vary only the requested seed's family parameters. The caller must
	# never receive a neighboring seed because seed identity is player-facing.
	return _generate_result(seed, room_rect, params)


static func generate(seed: int, room_rect: Rect2, params: Dictionary = {}) -> PackedVector2Array:
	return _generate_result(seed, room_rect, params)["points"] as PackedVector2Array


static func centerline_checkpoints(controls: PackedVector2Array) -> PackedVector2Array:
	return _sample_centerline(controls)


static func gameplay_metrics(controls: PackedVector2Array) -> Dictionary:
	var centerline := _sample_centerline(controls)
	if centerline.is_empty():
		return {}
	var bypass := _best_complex_bypass(centerline)
	var setup_straight_count := _setup_straight_count(centerline)
	var literal_straight_count := _literal_straight_count(centerline)
	return {
		"length": _polyline_length(centerline),
		"minimum_turn_radius": _minimum_turn_radius(centerline),
		"has_setup_straight": setup_straight_count > 0,
		"setup_straight_count": setup_straight_count,
		"literal_straight_count": literal_straight_count,
		"complex_bypass": bypass,
		"route_sequence": normalized_route_sequence(controls),
	}


static func normalized_route_sequence(controls: PackedVector2Array) -> String:
	var centerline := _sample_centerline(controls)
	if centerline.is_empty():
		return ""
	var symbols: Array[String] = []
	var span := 5
	for index in range(0, centerline.size(), span):
		var incoming := centerline[posmod(index - span, centerline.size())].direction_to(centerline[index])
		var outgoing := centerline[index].direction_to(centerline[(index + span) % centerline.size()])
		var angle := incoming.angle_to(outgoing)
		if absf(angle) < 0.10:
			symbols.append("S")
		else:
			var strength := "1" if absf(angle) < 0.28 else ("2" if absf(angle) < 0.52 else "3")
			symbols.append(("L" if angle > 0.0 else "R") + strength)
	return _canonical_symbol_sequence(symbols)


static func _canonical_symbol_sequence(symbols: Array[String]) -> String:
	var mirrored: Array[String] = []
	var reversed: Array[String] = []
	var reversed_mirrored: Array[String] = []
	for symbol: String in symbols:
		mirrored.append(_swap_turn_symbol(symbol))
	for index in range(symbols.size() - 1, -1, -1):
		reversed.append(_swap_turn_symbol(symbols[index]))
		reversed_mirrored.append(symbols[index])
	var best := ""
	for variant: Array[String] in [symbols, mirrored, reversed, reversed_mirrored]:
		for offset in variant.size():
			var ordered := PackedStringArray()
			for index in variant.size():
				ordered.append(variant[(offset + index) % variant.size()])
			var candidate := ".".join(ordered)
			if best.is_empty() or candidate < best:
				best = candidate
	return best


static func _swap_turn_symbol(symbol: String) -> String:
	if symbol.begins_with("L"):
		return "R" + symbol.substr(1)
	if symbol.begins_with("R"):
		return "L" + symbol.substr(1)
	return symbol


static func _generate_result(seed: int, room_rect: Rect2, params: Dictionary) -> Dictionary:
	var family_index := posmod(_hash32(seed ^ FAMILY_SALT), FAMILY_NAMES.size())
	var family: StringName = FAMILY_NAMES[family_index]
	var length_roll := _hash_unit(seed, LENGTH_SALT)
	var target_length := lerpf(2500.0, 5500.0, length_roll) * WORLD_SCALE
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
	var minimum_length := float(params.get("min_loop_length", 1900.0 * WORLD_SCALE))
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
				"target_length": target_length,
				"attempt": attempt,
				"fallback": false,
				"realization": &"el_safe" if room_shape == &"el" else family,
				"route_recipe": &"el_safe" if room_shape == &"el" else _route_name(seed, attempt, target_length),
				"route_program": &"el_safe" if room_shape == &"el" else _route_program_name(seed, attempt, target_length),
				"route_sequence": normalized_route_sequence(ordered_controls),
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
				"target_length": target_length,
				"attempt": MAX_VARIANTS + fallback_attempt,
				"fallback": true,
				"realization": &"el_safe" if room_shape == &"el" else &"technical_perimeter",
				"route_recipe": &"el_safe" if room_shape == &"el" else &"technical_perimeter",
				"route_program": &"el_safe" if room_shape == &"el" else &"technical_perimeter",
				"route_sequence": normalized_route_sequence(ordered_controls),
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
		"target_length": 0.0,
		"attempt": -1,
		"fallback": true,
		"realization": &"none",
		"route_recipe": &"none",
		"route_program": &"none",
		"route_sequence": "",
	}


static func _generation_rect(room_rect: Rect2, params: Dictionary, room_polygon: PackedVector2Array) -> Rect2:
	if not room_polygon.is_empty():
		return _points_rect(room_polygon)
	return room_rect


static func _family_controls(
	template_family: StringName,
	_rhythm_family: StringName,
	seed: int,
	attempt: int,
	usable_rect: Rect2,
	target_length: float,
	min_self_distance: float
) -> PackedVector2Array:
	var definition := {} if template_family == &"conservative" else _route_definition(seed, attempt, target_length)
	var anchors := _technical_perimeter_template() if template_family == &"conservative" else definition["anchors"] as PackedVector2Array
	if anchors.is_empty():
		return PackedVector2Array()

	# Templates are authored horizontally. Rotate them before fitting a tall room
	# so dogbones become vertical dogbones, not stretched horizontal circles.
	var orientation := 0.0
	var heading_sign := -1.0 if _hash_unit(seed, ROUTE_SALT + 0x91 + attempt * 17) < 0.5 else 1.0
	var heading_roll := _hash_unit(seed, ROUTE_SALT + 0xB3 + attempt * 29)
	if usable_rect.size.y > usable_rect.size.x * 1.12:
		orientation = PI * 0.5 + heading_sign * lerpf(0.08, 0.20, heading_roll)
	elif maxf(usable_rect.size.x, usable_rect.size.y) < minf(usable_rect.size.x, usable_rect.size.y) * 1.12:
		orientation = float(posmod(_hash32(seed ^ (VARIANT_SALT + 0x37)), 4)) * PI * 0.5 + heading_sign * lerpf(0.16, 0.42, heading_roll)
	elif usable_rect.size.x > usable_rect.size.y * 1.75:
		orientation = heading_sign * lerpf(0.06, 0.14, heading_roll)
	else:
		orientation = heading_sign * lerpf(0.10, 0.26, heading_roll)
	var mirror := -1.0 if _hash_unit(seed, VARIANT_SALT + 7) < 0.5 else 1.0
	for index in anchors.size():
		var point := anchors[index]
		point.x *= mirror
		anchors[index] = point.rotated(orientation)
	# Fit the macro vertices first, then build world-space quadratic fillets.
	# Collinear controls remain between fillets so Catmull sampling cannot turn a
	# declared straight into the blanket-smoothed bends used by the old generator.
	var mapped_vertices := _map_to_rect(anchors, usable_rect)
	var fillet_radius := MIN_DRIVE_RADIUS + FILLET_RADIUS_MARGIN + lerpf(0.0, 24.0, _hash_unit(seed, ROUTE_SALT + 0xD7 + attempt * 37))
	var full_controls := _filleted_controls(mapped_vertices, fillet_radius)
	var full_centerline := _sample_centerline(full_controls)
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
	for index in mapped_vertices.size():
		mapped_vertices[index] = center + (mapped_vertices[index] - center) * length_scale + offset
	return _filleted_controls(mapped_vertices, fillet_radius)


static func _filleted_controls(vertices: PackedVector2Array, desired_radius: float) -> PackedVector2Array:
	if vertices.size() < 3:
		return PackedVector2Array()
	var entries := PackedVector2Array()
	var exits := PackedVector2Array()
	for index in vertices.size():
		var previous := vertices[posmod(index - 1, vertices.size())]
		var corner := vertices[index]
		var following := vertices[(index + 1) % vertices.size()]
		var incoming := previous.direction_to(corner)
		var outgoing := corner.direction_to(following)
		var turn := absf(incoming.angle_to(outgoing))
		var half_turn := turn * 0.5
		var tangent := desired_radius * sin(half_turn) / maxf(cos(half_turn) * cos(half_turn), 0.08)
		tangent = minf(tangent, minf(previous.distance_to(corner), corner.distance_to(following)) * 0.42)
		entries.append(corner - incoming * tangent)
		exits.append(corner + outgoing * tangent)

	var result := PackedVector2Array()
	for index in vertices.size():
		var entry := entries[index]
		var corner := vertices[index]
		var exit := exits[index]
		result.append(entry)
		for step in range(1, 4):
			var t := float(step) / 4.0
			var inverse := 1.0 - t
			result.append(entry * inverse * inverse + corner * 2.0 * inverse * t + exit * t * t)
		result.append(exit)
		var next_entry := entries[(index + 1) % vertices.size()]
		var straight_length := exit.distance_to(next_entry)
		var subdivisions := maxi(1, ceili(straight_length / STRAIGHT_CONTROL_SPACING))
		for step in range(1, subdivisions):
			result.append(exit.lerp(next_entry, float(step) / float(subdivisions)))
	return result


static func _route_index(seed: int, attempt: int) -> int:
	var base := posmod(_hash32(seed ^ ROUTE_SALT), ROUTE_GRAMMAR.count())
	return posmod(base + attempt, ROUTE_GRAMMAR.count())


static func _route_name(seed: int, attempt: int, target_length: float) -> StringName:
	return StringName(_route_definition(seed, attempt, target_length)["recipe"])


static func _route_program_name(seed: int, attempt: int, target_length: float) -> StringName:
	return StringName(_route_definition(seed, attempt, target_length)["program"])


static func _route_definition(seed: int, attempt: int, target_length: float = 2500.0 * WORLD_SCALE) -> Dictionary:
	var length_bias := clampf(inverse_lerp(8500.0, 9600.0, target_length), 0.0, 1.0)
	return ROUTE_GRAMMAR.construct(_route_index(seed, attempt), _hash32(seed ^ (attempt * RHYTHM_SALT)), length_bias)


static func _technical_perimeter_template() -> PackedVector2Array:
	# A broad perimeter is safer than concave programs after all twelve bounded
	# grammar attempts fail. Its long opposing edges preserve literal straights.
	return PackedVector2Array([
		Vector2(-0.92, -0.18), Vector2(-0.70, -0.74),
		Vector2(0.56, -0.78), Vector2(0.92, -0.28),
		Vector2(0.90, 0.30), Vector2(0.64, 0.74),
		Vector2(-0.56, 0.78), Vector2(-0.92, 0.28),
	])


static func _smooth_controls(points: PackedVector2Array, passes: int) -> PackedVector2Array:
	var result := points.duplicate()
	for _pass in passes:
		var smoothed := PackedVector2Array()
		for index in result.size():
			smoothed.append(
				result[posmod(index - 1, result.size())] * 0.125
				+ result[index] * 0.75
				+ result[(index + 1) % result.size()] * 0.125
			)
		result = smoothed
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
		Vector2(-0.84, -0.35), Vector2(-0.84, -0.58), Vector2(-0.74, -0.72),
		Vector2(-0.50, -0.76), Vector2(-0.20, -0.76), Vector2(0.02, -0.70),
		Vector2(0.12, -0.55), Vector2(0.12, -0.30), Vector2(0.10, -0.12),
		Vector2(0.16, 0.02), Vector2(0.28, 0.16), Vector2(0.48, 0.24),
		Vector2(0.70, 0.28), Vector2(0.84, 0.38), Vector2(0.84, 0.58),
		Vector2(0.72, 0.70), Vector2(0.45, 0.76), Vector2(0.10, 0.76),
		Vector2(-0.30, 0.76), Vector2(-0.65, 0.72), Vector2(-0.82, 0.60),
		Vector2(-0.86, 0.35), Vector2(-0.86, 0.05), Vector2(-0.86, -0.20),
	])
	var normalized := _smooth_controls(anchors, 2)
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
	var corridor_boundaries := _corridor_boundary_loops(centerline)
	if corridor_boundaries.is_empty():
		return {"valid": false, "reason": "corridor offset did not produce valid inner and outer contours"}
	for point: Vector2 in centerline:
		if not source_rect.has_point(point):
			return {"valid": false, "reason": "outside source rect"}
		if not room_polygon.is_empty() and not _inside_with_margin(point, room_polygon, room_margin):
			return {"valid": false, "reason": "outside room margin"}
	var loop_length := _polyline_length(centerline)
	if loop_length < minimum_length:
		return {"valid": false, "reason": "below minimum length"}
	var setup_straight_count := _setup_straight_count(centerline)
	if setup_straight_count < 2:
		return {"valid": false, "reason": "only %d setup straight region(s)" % setup_straight_count}
	var literal_straight_count := _literal_straight_count(centerline)
	if literal_straight_count < 2:
		return {"valid": false, "reason": "only %d literal straight region(s)" % literal_straight_count}
	var minimum_turn_radius := _minimum_turn_radius(centerline)
	if minimum_turn_radius < MIN_DRIVE_RADIUS:
		return {"valid": false, "reason": "turn radius %.1f < %.1f" % [minimum_turn_radius, MIN_DRIVE_RADIUS]}
	var bypass := _best_complex_bypass(centerline)
	if bool(bypass.get("found", false)):
		return {
			"valid": false,
			"reason": "driveable chord saves %.0fu over %.0fu" % [float(bypass["saving"]), float(bypass["arc"])],
		}
	return {"valid": true, "centerline": centerline, "length": loop_length, "minimum_turn_radius": minimum_turn_radius, "literal_straight_count": literal_straight_count}


static func _corridor_boundary_loops(centerline: PackedVector2Array) -> Dictionary:
	var centerline_area := absf(_polygon_area(centerline))
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	var inner_area := 0.0
	var outer_area := 0.0
	var contours: Array[PackedVector2Array] = Geometry2D.offset_polyline(
		centerline,
		HALF_WIDTH,
		Geometry2D.JOIN_ROUND,
		Geometry2D.END_JOINED
	)
	for contour: PackedVector2Array in contours:
		var resolved: Array[PackedVector2Array] = Geometry2D.intersect_polygons(contour, contour)
		var pieces: Array[PackedVector2Array] = resolved if not resolved.is_empty() else [contour]
		for piece: PackedVector2Array in pieces:
			var cleaned := _deduplicate_loop(piece)
			if cleaned.size() < 3 or _has_self_intersection(cleaned) or not _boundary_loop_hugs_centerline(cleaned, centerline):
				continue
			var area := absf(_polygon_area(cleaned))
			if area > centerline_area and area > outer_area:
				outer = cleaned
				outer_area = area
			elif area < centerline_area and area > inner_area:
				inner = cleaned
				inner_area = area
	if inner.is_empty() or outer.is_empty():
		return {}
	return {"inner": inner, "outer": outer}


static func _boundary_loop_hugs_centerline(loop: PackedVector2Array, centerline: PackedVector2Array) -> bool:
	for index in loop.size():
		var from := loop[index]
		var to := loop[(index + 1) % loop.size()]
		for fraction: float in [0.0, 0.5]:
			var sample := from.lerp(to, fraction)
			var nearest := INF
			for center_index in centerline.size():
				nearest = minf(nearest, _point_segment_distance(sample, centerline[center_index], centerline[(center_index + 1) % centerline.size()]))
			if nearest < HALF_WIDTH * 0.62 or nearest > HALF_WIDTH * 1.42:
				return false
	return true


static func _deduplicate_loop(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		if result.is_empty() or point.distance_squared_to(result[result.size() - 1]) > 0.01:
			result.append(point)
	if result.size() > 1 and result[0].distance_squared_to(result[result.size() - 1]) <= 0.01:
		result.remove_at(result.size() - 1)
	return result


static func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		total += points[index].cross(points[(index + 1) % points.size()])
	return total * 0.5


static func _setup_straight_count(centerline: PackedVector2Array) -> int:
	var count := centerline.size()
	var straight_starts := PackedByteArray()
	for start in count:
		straight_starts.append(1 if _straight_window_length(centerline, start) >= MIN_SETUP_DISTANCE else 0)
	var straight_start_count := straight_starts.count(1)
	if straight_start_count == 0:
		return 0
	if straight_start_count == count:
		return 1
	var regions := 0
	for index in count:
		if straight_starts[index] == 1 and straight_starts[posmod(index - 1, count)] == 0:
			regions += 1
	return regions


static func _straight_window_length(centerline: PackedVector2Array, start: int) -> float:
	var traveled := 0.0
	var longest := 0.0
	for step in range(1, centerline.size() / 2):
		traveled += centerline[(start + step - 1) % centerline.size()].distance_to(centerline[(start + step) % centerline.size()])
		var chord := centerline[start].distance_to(centerline[(start + step) % centerline.size()])
		if chord / maxf(traveled, 1.0) >= SETUP_STRAIGHTNESS:
			longest = traveled
		elif traveled >= MIN_SETUP_DISTANCE:
			break
	return longest


static func _literal_straight_count(centerline: PackedVector2Array) -> int:
	var count := centerline.size()
	var starts := PackedByteArray()
	for start in count:
		starts.append(1 if _literal_straight_window_length(centerline, start) >= MIN_SETUP_DISTANCE else 0)
	if starts.count(1) == 0:
		return 0
	if starts.count(1) == count:
		return 1
	var regions := 0
	for index in count:
		if starts[index] == 1 and starts[posmod(index - 1, count)] == 0:
			regions += 1
	return regions


static func _literal_straight_window_length(centerline: PackedVector2Array, start: int) -> float:
	var reference := centerline[start].direction_to(centerline[(start + 1) % centerline.size()])
	var traveled := 0.0
	for step in range(1, centerline.size() / 2):
		var from := centerline[(start + step - 1) % centerline.size()]
		var to := centerline[(start + step) % centerline.size()]
		if absf(reference.angle_to(from.direction_to(to))) > LITERAL_STRAIGHT_HEADING_TOLERANCE:
			break
		traveled += from.distance_to(to)
	return traveled


static func _minimum_turn_radius(centerline: PackedVector2Array) -> float:
	var minimum := INF
	var span := 3
	for index in centerline.size():
		var before := centerline[posmod(index - span, centerline.size())]
		var current := centerline[index]
		var after := centerline[(index + span) % centerline.size()]
		var incoming := before.direction_to(current)
		var outgoing := current.direction_to(after)
		if absf(incoming.angle_to(outgoing)) < 0.08:
			continue
		var area_twice := absf((current - before).cross(after - before))
		if area_twice < 0.01:
			continue
		var radius := before.distance_to(current) * current.distance_to(after) * before.distance_to(after) / (2.0 * area_twice)
		minimum = minf(minimum, radius)
	return minimum


static func _best_complex_bypass(centerline: PackedVector2Array) -> Dictionary:
	var best := {"found": false, "saving": 0.0}
	var count := centerline.size()
	var drive_radius := HALF_WIDTH - 22.0
	for start in range(0, count, 3):
		var route_arc := 0.0
		for step in range(1, count / 2):
			route_arc += centerline[(start + step - 1) % count].distance_to(centerline[(start + step) % count])
			if route_arc < BYPASS_MIN_ARC or step % 3 != 0:
				continue
			if route_arc > BYPASS_MAX_ARC:
				break
			var finish := (start + step) % count
			var chord := centerline[start].distance_to(centerline[finish])
			var saving := route_arc - chord
			if chord < 1.0 or saving < BYPASS_MIN_SAVING or route_arc / chord < BYPASS_MIN_RATIO:
				continue
			if not _chord_inside_corridor(centerline[start], centerline[finish], centerline, drive_radius):
				continue
			if saving > float(best["saving"]):
				best = {
					"found": true,
					"saving": saving,
					"ratio": route_arc / chord,
					"arc": route_arc,
					"chord": chord,
				}
	return best


static func _chord_inside_corridor(
	from: Vector2,
	to: Vector2,
	centerline: PackedVector2Array,
	drive_radius: float
) -> bool:
	for sample in range(1, 20):
		var point := from.lerp(to, float(sample) / 20.0)
		var nearest := INF
		for index in centerline.size():
			nearest = minf(nearest, _point_segment_distance(point, centerline[index], centerline[(index + 1) % centerline.size()]))
		if nearest > drive_radius:
			return false
	return true


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
			if Geometry2D.segment_intersects_segment(points[first], points[first_next], points[second], points[second_next]) != null:
				return true
	return false


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
