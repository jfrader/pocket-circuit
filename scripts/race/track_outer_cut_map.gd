class_name TrackOuterCutMap
extends RefCounted
## Pure outside-apron chord candidates. Footprint fitting and engine collision
## acceptance remain separate from this geometric map.

const CORE := preload("res://scripts/race/track_builder_core.gd")
const SECTOR_COUNT := 8
const INDEX_CELLS_PER_HALF_WIDTH := 4.0
# Broad phase only: near-boundary cells retain the original engine predicates.
const INDEX_BOUNDARY_GUARD_MM := 1.0
const LOOP_BOUNDS_GROUP_SIZE := 8


class LoopIndex:
	var line: PackedVector2Array
	var segments := PackedVector2Array()
	var denominators := PackedFloat64Array()
	var bounds: Array[Rect2] = []
	var sectors_cache := {}

	func _init(points: PackedVector2Array) -> void:
		line = points
		for index in points.size():
			var segment := points[(index + 1) % points.size()] - points[index]
			segments.append(segment)
			denominators.append(maxf(segment.length_squared(), 0.001))
		for first in range(0, points.size(), LOOP_BOUNDS_GROUP_SIZE):
			var box := Rect2(points[first], Vector2.ZERO)
			for index in range(first, mini(first + LOOP_BOUNDS_GROUP_SIZE, points.size())):
				box = box.expand(points[index]).expand(points[(index + 1) % points.size()])
			bounds.append(box.grow(INDEX_BOUNDARY_GUARD_MM))

	func closest_index(point: Vector2) -> int:
		var nearest_distance := INF
		var nearest_index := 0
		for group in bounds.size():
			var box := bounds[group]
			var closest := point.clamp(box.position, box.end)
			if point.distance_squared_to(closest) > nearest_distance:
				continue
			var first := group * LOOP_BOUNDS_GROUP_SIZE
			for index in range(first, mini(first + LOOP_BOUNDS_GROUP_SIZE, line.size())):
				# Keep the original projection arithmetic and ascending tie order.
				var fraction := clampf((point - line[index]).dot(segments[index]) / denominators[index], 0.0, 1.0)
				var candidate := line[index] + segments[index] * fraction
				var distance := point.distance_squared_to(candidate)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_index = index
		return nearest_index


class PolygonIndex:
	var polygon: PackedVector2Array
	var cell_size: float
	var boundary_cells := {}
	var inside_cells := {}

	func _init(points: PackedVector2Array, spacing: float) -> void:
		polygon = points
		cell_size = maxf(INDEX_BOUNDARY_GUARD_MM, spacing)
		for index in points.size():
			var bounds := Rect2(points[index], points[(index + 1) % points.size()] - points[index]).abs().grow(INDEX_BOUNDARY_GUARD_MM)
			var first := cell(bounds.position)
			var last := cell(bounds.end)
			for x in range(first.x, last.x + 1):
				for y in range(first.y, last.y + 1):
					boundary_cells[Vector2i(x, y)] = true

	func cell(point: Vector2) -> Vector2i:
		return Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))

	func interior(point: Vector2) -> bool:
		var key := cell(point)
		if boundary_cells.has(key):
			return false
		if not inside_cells.has(key):
			# Certify the whole cell; native point parity is not constant even
			# in edge-free cells because its ray can pass through distant vertices.
			var first := Vector2(key) * cell_size
			var last := first + Vector2.ONE * cell_size
			var square := PackedVector2Array([first, Vector2(last.x, first.y), last, Vector2(first.x, last.y)])
			inside_cells[key] = Geometry2D.clip_polygons(square, polygon).is_empty()
		return inside_cells[key]


static func candidates(
		line: PackedVector2Array,
		outer_boundary: PackedVector2Array,
		island: PackedVector2Array,
		half_width: float,
		open_sector: int,
		settings: Dictionary
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var count := line.size()
	if count < CORE.CUT_MAX_LOOKAHEAD * 2 or outer_boundary.size() < 3:
		return found
	var outer := outer_boundary.duplicate()
	if outer[0].is_equal_approx(outer[-1]):
		outer.remove_at(outer.size() - 1)
	var expanded := PackedVector2Array()
	for polygon: PackedVector2Array in Geometry2D.offset_polygon(outer, CORE.CUT_MIN_OFF_CORRIDOR_MM, Geometry2D.JOIN_ROUND):
		if absf(CORE._polygon_area(polygon)) > absf(CORE._polygon_area(expanded)):
			expanded = polygon
	if expanded.size() < 3:
		return found

	var island_rect := Rect2()
	if island.size() >= 3:
		island_rect = CORE._polygon_bounds_rect(island)
	var fractions: Array = settings["lane_fractions"]
	var edge_margin := float(settings["vehicle_radius_mm"])
	var lane_reach := maxf(0.0, half_width - edge_margin)
	var normals := PackedVector2Array()
	var outward_sign := -1.0 if CORE._polygon_area(line) > 0.0 else 1.0
	var prefix := PackedFloat64Array()
	prefix.resize(count + 1)
	for index in count:
		var tangent := (line[(index + 1) % count] - line[posmod(index - 1, count)]).normalized()
		normals.append(tangent.rotated(PI * 0.5) * outward_sign)
		prefix[index + 1] = prefix[index] + line[index].distance_to(line[(index + 1) % count])
	var total := prefix[count]
	var seen := {}
	var island_index := PolygonIndex.new(island, half_width / INDEX_CELLS_PER_HALF_WIDTH)
	var chords := {}
	var loop_index := LoopIndex.new(line)
	for start in count:
		if CORE._turn_strength(line, start, 6) < CORE.CUT_TURN_THRESHOLD:
			continue
		for span in range(CORE.CUT_MIN_LOOKAHEAD, CORE.CUT_MAX_LOOKAHEAD + 1):
			_consider(line, normals, prefix, total, expanded, island, fractions, lane_reach, open_sector, start, (start + span) % count, seen, found, island_rect, island_index, chords, loop_index)

	# Nearby non-local folds need not be sharp at either endpoint.
	var buckets := {}
	var spacing := CORE.CUT_FOLD_MAX_SPACING_MM
	for index in count:
		var cell := Vector2i(floori(line[index].x / spacing), floori(line[index].y / spacing))
		if not buckets.has(cell):
			buckets[cell] = []
		(buckets[cell] as Array).append(index)
	for index in count:
		var cell := Vector2i(floori(line[index].x / spacing), floori(line[index].y / spacing))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var nearby: Array = buckets.get(cell + Vector2i(dx, dy), [])
				for other: int in nearby:
					if other <= index or line[index].distance_squared_to(line[other]) > spacing * spacing:
						continue
					var forward := other - index
					if mini(forward, count - forward) < int(CORE.CUT_FOLD_MIN_LAP_FRACTION * count):
						continue
					if forward <= count - forward:
						_consider(line, normals, prefix, total, expanded, island, fractions, lane_reach, open_sector, index, other, seen, found, island_rect, island_index, chords, loop_index)
					else:
						_consider(line, normals, prefix, total, expanded, island, fractions, lane_reach, open_sector, other, index, seen, found, island_rect, island_index, chords, loop_index)
	found.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return float(left["saved_mm"]) > float(right["saved_mm"]))
	return found


static func _consider(
		line: PackedVector2Array, normals: PackedVector2Array, prefix: PackedFloat64Array,
		total: float, expanded: PackedVector2Array, island: PackedVector2Array,
		fractions: Array, lane_reach: float, open_sector: int, start: int, finish: int,
		seen: Dictionary, found: Array[Dictionary], island_rect: Rect2,
		island_index: PolygonIndex, chords: Dictionary, loop_index: LoopIndex
) -> void:
	var count := line.size()
	var key := mini(start, finish) * count + maxi(start, finish)
	if seen.has(key):
		return
	seen[key] = true
	var arc := prefix[finish] - prefix[start]
	if arc <= 0.0:
		arc += total
	# The centre chord is only a cheap rejection: shifted lane endpoints get their own checks.
	if arc - line[start].distance_to(line[finish]) + 2.0 * lane_reach < CORE.CUT_MIN_SAVED_MM:
		return
	for start_fraction: float in fractions:
		for finish_fraction: float in fractions:
			var a := line[start] + normals[start] * (start_fraction * lane_reach)
			var b := line[finish] + normals[finish] * (finish_fraction * lane_reach)
			var chord := a.distance_to(b)
			if arc - chord < CORE.CUT_MIN_SAVED_MM or arc < chord * CORE.CUT_MIN_ARC_RATIO:
				continue
			var chord_key := Vector4(a.x, a.y, b.x, b.y)
			if not chords.has(chord_key):
				chords[chord_key] = _deep_chord(a, b, expanded, island, island_rect, island_index)
			var deep: PackedVector2Array = chords[chord_key]
			if deep.size() < CORE.CUT_MIN_DEEP_SAMPLES:
				continue
			var crosses_open := false
			if open_sector >= 0:
				crosses_open = true
				# Check rejoining samples first; any non-open point ends the same all-points predicate.
				for index in range(deep.size() - 1, -1, -1):
					var point := deep[index]
					var sectors := loop_index.sectors_cache
					if not sectors.has(point):
						sectors[point] = mini(SECTOR_COUNT - 1, int(float(loop_index.closest_index(point)) / count * SECTOR_COUNT))
					var sector: int = sectors[point]
					if sector != open_sector:
						crosses_open = false
						break
			if crosses_open:
				continue
			found.append({"a":a, "b":b, "start_index":start, "end_index":finish, "saved_mm":arc - chord, "deep_points":deep})


static func _deep_chord(
		a: Vector2, b: Vector2, expanded: PackedVector2Array, island: PackedVector2Array,
		island_rect: Rect2, island_index: PolygonIndex
) -> PackedVector2Array:
	var deep := PackedVector2Array()
	var segment := PackedVector2Array([a, b])
	if island.size() >= 3:
		# An edge-free cell is wholly inside or outside. A strictly interior
		# sample proves intersection; boundary cells never use this rejection.
		if island_index.interior(a.lerp(b, 0.5)) or island_index.interior(a.lerp(b, 0.25)) or island_index.interior(a.lerp(b, 0.75)):
			return deep
		var seg_rect := Rect2(a, b - a).abs()
		if island_rect.intersects(seg_rect, true) and not Geometry2D.intersect_polyline_with_polygon(segment, island).is_empty():
			return deep
	if Geometry2D.clip_polyline_with_polygon(segment, expanded).is_empty():
		return deep
	for sample in CORE.CUT_SAMPLES:
		var point := a.lerp(b, float(sample) / float(CORE.CUT_SAMPLES - 1))
		# Keep the exact native sample decisions, including ray-parity edge cases.
		if not Geometry2D.is_point_in_polygon(point, expanded):
			deep.append(point)
	return deep
