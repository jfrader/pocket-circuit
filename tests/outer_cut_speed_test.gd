extends SceneTree
## Same-process comparison against the pre-optimization implementation (bec6f86).
## Hashes include all layout data, replacing Resource instance IDs with paths.

const CORE := preload("res://scripts/race/track_builder_core.gd")
var cut_map: Variant = load("res://scripts/race/track_outer_cut_map.gd")
const MAX_TIME_RATIO := 0.90
const SEEDS := [24469, 1]
const THEMES := [&"kitchen", &"workshop", &"office"]
const TIERS := [&"standard", &"long"]

const LEGACY_SOURCE := '''extends RefCounted
const CORE := preload("res://scripts/race/track_builder_core.gd")
const SECTOR_COUNT := 8

static func candidates(line: PackedVector2Array, outer_boundary: PackedVector2Array, island: PackedVector2Array, half_width: float, open_sector: int, settings: Dictionary) -> Array[Dictionary]:
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
	for start in count:
		if CORE._turn_strength(line, start, 6) < CORE.CUT_TURN_THRESHOLD:
			continue
		for span in range(CORE.CUT_MIN_LOOKAHEAD, CORE.CUT_MAX_LOOKAHEAD + 1):
			_consider(line, normals, prefix, total, expanded, island, fractions, lane_reach, open_sector, start, (start + span) % count, seen, found, island_rect)
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
						_consider(line, normals, prefix, total, expanded, island, fractions, lane_reach, open_sector, index, other, seen, found, island_rect)
					else:
						_consider(line, normals, prefix, total, expanded, island, fractions, lane_reach, open_sector, other, index, seen, found, island_rect)
	found.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return float(left["saved_mm"]) > float(right["saved_mm"]))
	return found

static func _consider(line: PackedVector2Array, normals: PackedVector2Array, prefix: PackedFloat64Array, total: float, expanded: PackedVector2Array, island: PackedVector2Array, fractions: Array, lane_reach: float, open_sector: int, start: int, finish: int, seen: Dictionary, found: Array[Dictionary], island_rect: Rect2) -> void:
	var count := line.size()
	var key := mini(start, finish) * count + maxi(start, finish)
	if seen.has(key):
		return
	seen[key] = true
	var arc := prefix[finish] - prefix[start]
	if arc <= 0.0:
		arc += total
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
			if island.size() >= 3:
				var seg_rect := Rect2(a, b - a).abs()
				if island_rect.intersects(seg_rect, true) and not Geometry2D.intersect_polyline_with_polygon(segment, island).is_empty():
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
'''

const RECORDING_WRAPPER := '''
static var measured_us := 0
static var scans := 0
static var decisions: Array = []
static var considered: Array = []
static func candidates(line: PackedVector2Array, outer_boundary: PackedVector2Array, island: PackedVector2Array, half_width: float, open_sector: int, settings: Dictionary) -> Array[Dictionary]:
	var started := Time.get_ticks_usec()
	var result := _measured_candidates(line, outer_boundary, island, half_width, open_sector, settings)
	measured_us += Time.get_ticks_usec() - started
	decisions.append(result)
	return result
'''


func _initialize() -> void:
	call_deferred("_run")


func _canonical(value: Variant) -> Variant:
	if value is Resource:
		return [value.get_class(), value.resource_path]
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonical(item))
		return result
	return value


func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(_canonical(value)))
	return context.finish().hex_encode()


func _install(source: String) -> bool:
	var measured := source.replace("static func candidates(", "static func _measured_candidates(")
	measured = measured.replace("\tvar count := line.size()\n\tvar key :=", "\tscans += 1\n\tvar count := line.size()\n\tvar key :=")
	measured = measured.replace("\t\t\tvar chord := a.distance_to(b)", "\t\t\tconsidered.append([start, finish, a, b])\n\t\t\tvar chord := a.distance_to(b)")
	cut_map.source_code = measured + RECORDING_WRAPPER
	if cut_map.reload(true) != OK:
		return false
	cut_map.measured_us = 0
	cut_map.scans = 0
	cut_map.decisions = []
	cut_map.considered = []
	return true


func _fail(message: String, original: String) -> void:
	cut_map.source_code = original
	cut_map.reload(true)
	push_error("OUTER_CUT_SPEED_TEST FAIL: " + message)
	quit(1)


func _run() -> void:
	var original: String = cut_map.source_code
	if not _check_nearest_index():
		_fail("nearest-segment broad phase differs on tie/degenerate/negative-coordinate fixtures", original)
		return
	var old_us := 0
	var new_us := 0
	var checked := 0
	for theme: StringName in THEMES:
		for seed_value: int in SEEDS:
			for tier: StringName in TIERS:
				var snapshots: Array[Dictionary] = []
				var implementations := [LEGACY_SOURCE, original]
				if theme == &"kitchen" and seed_value == 24469 and tier == &"standard":
					implementations.append(original)
				for source: String in implementations:
					if not _install(source):
						_fail("could not install comparison implementation", original)
						return
					# Bypass the disk cache: this test compares two implementations on the same identity.
					var prepared := CORE._prepare_layout_uncached(theme, &"long", seed_value, {"length_tier": tier})
					if prepared.is_empty() or cut_map.decisions.size() != 1:
						_fail("empty fixture or missing scan", original)
						return
					snapshots.append({"layout": _hash(prepared), "decisions": _hash(cut_map.decisions), "considered": _hash(cut_map.considered), "accepted": cut_map.decisions[0].size(), "scans": cut_map.scans, "us": cut_map.measured_us})
				var before: Dictionary = snapshots[0]
				for after: Dictionary in snapshots.slice(1):
					if before.layout != after.layout or before.decisions != after.decisions or before.considered != after.considered or before.scans != after.scans:
						_fail("layout/decisions/scans differ: %s/%d/%s %s" % [theme, seed_value, tier, snapshots], original)
						return
				old_us += int(before.us)
				new_us += int(snapshots[1].us)
				checked += 1
				print("OUTER_CUT_BENCH theme=%s seed=%d tier=%s scans=%d/%d accepted=%d before_ms=%.3f after_ms=%.3f hash=%s" % [theme, seed_value, tier, before.scans, snapshots[1].scans, before.accepted, float(before.us) / 1000.0, float(snapshots[1].us) / 1000.0, before.layout])
	cut_map.source_code = original
	if cut_map.reload(true) != OK:
		push_error("OUTER_CUT_SPEED_TEST FAIL: could not restore implementation")
		quit(1)
		return
	var ratio := float(new_us) / float(old_us)
	if ratio >= MAX_TIME_RATIO:
		push_error("OUTER_CUT_SPEED_TEST FAIL: time ratio %.3f exceeds %.2f" % [ratio, MAX_TIME_RATIO])
		quit(1)
		return
	print("OUTER_CUT_SPEED_TEST PASS fixtures=%d exact_decisions_layout_hashes repeat_fixture=kitchen/24469/standard ratio=%.3f before_ms=%.3f after_ms=%.3f" % [checked, ratio, float(old_us) / 1000.0, float(new_us) / 1000.0])
	quit()


func _check_nearest_index() -> bool:
	var corners := PackedVector2Array([Vector2(-64, -64), Vector2(64, -64), Vector2(64, 64), Vector2(-64, 64)])
	var line := PackedVector2Array()
	for side in corners.size():
		for step in 8:
			line.append(corners[side].lerp(corners[(side + 1) % corners.size()], float(step) / 8.0))
	line.append(line[-1])
	var index: Variant = cut_map.LoopIndex.new(line)
	for x in range(-192, 193, 16):
		for y in range(-192, 193, 16):
			var point := Vector2(x, y)
			if index.closest_index(point) != int(CORE._closest_point_on_loop(point, line)["index"]):
				return false
	return true
