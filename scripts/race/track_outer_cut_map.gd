class_name TrackOuterCutMap
extends RefCounted
## Pure outside-apron chord candidates. Footprint fitting and engine collision
## acceptance remain separate from this geometric map.

const CORE := preload("res://scripts/race/track_builder_core.gd")
const SECTOR_COUNT := 8


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
	for start in count:
		if CORE._turn_strength(line, start, 6) < CORE.CUT_TURN_THRESHOLD:
			continue
		for span in range(CORE.CUT_MIN_LOOKAHEAD, CORE.CUT_MAX_LOOKAHEAD + 1):
			_consider(line, normals, prefix, total, expanded, island, fractions, lane_reach, open_sector, start, (start + span) % count, seen, found)

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
						_consider(line, normals, prefix, total, expanded, island, fractions, lane_reach, open_sector, index, other, seen, found)
					else:
						_consider(line, normals, prefix, total, expanded, island, fractions, lane_reach, open_sector, other, index, seen, found)
	found.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return float(left["saved_mm"]) > float(right["saved_mm"]))
	return found


static func _consider(
		line: PackedVector2Array, normals: PackedVector2Array, prefix: PackedFloat64Array,
		total: float, expanded: PackedVector2Array, island: PackedVector2Array,
		fractions: Array, lane_reach: float, open_sector: int, start: int, finish: int,
		seen: Dictionary, found: Array[Dictionary]
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
			var segment := PackedVector2Array([a, b])
			if island.size() >= 3 and not Geometry2D.intersect_polyline_with_polygon(segment, island).is_empty():
				continue
			if Geometry2D.clip_polyline_with_polygon(segment, expanded).is_empty():
				continue
			var deep := PackedVector2Array()
			for sample in CORE.CUT_SAMPLES:
				var point := a.lerp(b, float(sample) / float(CORE.CUT_SAMPLES - 1))
				if not Geometry2D.is_point_in_polygon(point, expanded):
					deep.append(point)
			if deep.size() < CORE.CUT_MIN_DEEP_SAMPLES:
				continue
			var crosses_open := false
			if open_sector >= 0:
				crosses_open = true
				# Check rejoining samples first; any non-open point ends the same all-points predicate.
				for index in range(deep.size() - 1, -1, -1):
					var point := deep[index]
					var nearest := CORE._closest_point_on_loop(point, line)
					var sector := mini(SECTOR_COUNT - 1, int(float(nearest["index"]) / count * SECTOR_COUNT))
					if sector != open_sector:
						crosses_open = false
						break
			if crosses_open:
				continue
			found.append({"a":a, "b":b, "start_index":start, "end_index":finish, "saved_mm":arc - chord, "deep_points":deep})
