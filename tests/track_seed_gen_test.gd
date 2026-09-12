extends SceneTree

const TRACK_SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const ROOM_RECT := Rect2(-940.0, -540.0, 1880.0, 1080.0)
const HALF_WIDTH := 125.0
const SAMPLE_SEEDS := 60
const PHYSICAL_BYPASS_MIN_ARC := 900.0
const PHYSICAL_BYPASS_MAX_ARC := 3000.0
const PHYSICAL_BYPASS_MIN_SAVING := 450.0
const PHYSICAL_BYPASS_MIN_RATIO := 1.65

static var ROOM_SHAPES := TRACK_BUILDER.ROOM_SHAPES


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var families := {}
	var family_seeds := {}
	var seed_families := {}
	var fingerprints := {}
	var route_recipes := {}
	var route_sequences := {}
	var length_buckets := {}
	var fallback_count := 0
	var minimum_length := INF
	var maximum_length := 0.0
	var classic_params := _room_params("classic")
	var sample_seed_count := SAMPLE_SEEDS
	if OS.get_environment("PC_TRACK_SAMPLE_SEEDS").is_valid_int():
		sample_seed_count = clampi(int(OS.get_environment("PC_TRACK_SAMPLE_SEEDS")), 12, SAMPLE_SEEDS)
	for seed in sample_seed_count:
		var result: Dictionary = TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, classic_params)
		if not _expect(int(result["seed"]) == seed, "seed %d must not walk to a neighboring seed" % seed):
			return
		var controls: PackedVector2Array = result["points"]
		if not _expect(not controls.is_empty(), "classic seed %d should generate a loop (%s)" % [seed, result.get("reason", "unknown")]):
			return
		if not _expect(float(result.get("length", 0.0)) >= 1500.0 * TRACK_SEED_GEN.WORLD_SCALE, "classic seed %d should report a world-scaled loop length" % seed):
			return
		var loop_length := float(result["length"])
		length_buckets[int(round(loop_length / 250.0))] = true
		minimum_length = minf(minimum_length, loop_length)
		maximum_length = maxf(maximum_length, loop_length)
		var family := String(result.get("family", ""))
		families[family] = true
		seed_families[seed] = family
		if not family_seeds.has(family):
			family_seeds[family] = seed
		if bool(result.get("fallback", false)):
			fallback_count += 1
		fingerprints[_shape_fingerprint(controls)] = true
		route_recipes[String(result.get("route_recipe", ""))] = true
		route_sequences[String(result.get("route_sequence", ""))] = true
		if not _check_loop(seed, "classic", controls, ROOM_SHAPES["classic"], 320.0):
			return
		if seed < 8:
			var repeated: Dictionary = TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, classic_params)
			if not _expect(repeated["points"] == controls, "seed %d should be exactly deterministic" % seed):
				return
			if not _expect(TRACK_SEED_GEN.generate(seed, ROOM_RECT, classic_params) == controls, "generate() and generate_with_retries() should agree for seed %d" % seed):
				return

	if not _expect(families.size() == 6, "representative seeds should exercise all six families (got %s)" % [families.keys()]):
		return
	if not _expect(fingerprints.size() >= 12, "representative seeds should produce many distinct shape fingerprints (got %d)" % fingerprints.size()):
		return
	if not _expect(route_recipes.size() >= 5, "independent route grammar should realize multiple macro programs (got %s)" % [route_recipes.keys()]):
		return
	if not _expect(route_sequences.size() >= 5, "routes should expose varied normalized turn/straight sequences (got %d)" % route_sequences.size()):
		return
	if not _expect(length_buckets.size() >= 3, "independent length rolls should produce varied loop lengths (got %d buckets)" % length_buckets.size()):
		return
	if not _expect(minimum_length >= 2500.0 and maximum_length >= 5000.0 and maximum_length <= 9800.0, "classic length stream should span a scaled world range (got %.0f..%.0f)" % [minimum_length, maximum_length]):
		return
	if not _expect(fallback_count <= 14, "classic seeds should usually retain their selected family while rejecting complex-bypass variants (fallbacks=%d)" % fallback_count):
		return

	var representative_seeds := {
		"speed_loop": 0,
		"dogbone": 1,
		"broad_triangle": 2,
		"kidney": 3,
		"deep_notch": 5,
		"offset_s": 11,
	}
	for family_name: String in representative_seeds:
		var result: Dictionary = TRACK_SEED_GEN.generate_with_retries(int(representative_seeds[family_name]), ROOM_RECT, classic_params)
		if not _expect(String(result["family"]) == family_name, "%s representative must retain family identity while using the route grammar" % family_name):
			return
		if not _expect(StringName(result.get("route_recipe", &"none")) != &"none", "%s representative should report its accepted macro route program" % family_name):
			return

	for room_name: String in ROOM_SHAPES:
		var params := _room_params(room_name)
		for expected_family: String in family_seeds:
			var room_seed := int(family_seeds[expected_family])
			var result: Dictionary = TRACK_SEED_GEN.generate_with_retries(room_seed, ROOM_RECT, params)
			if not _expect(int(result["seed"]) == room_seed, "%s room should preserve requested seed %d" % [room_name, room_seed]):
				return
			var controls: PackedVector2Array = result["points"]
			if not _expect(not controls.is_empty(), "%s/%s seed %d should generate a loop (%s)" % [room_name, expected_family, room_seed, result.get("reason", "unknown")]):
				return
			if not _expect(String(result["family"]) == expected_family, "%s room selection must not change seed %d's family" % [room_name, room_seed]):
				return
			var repeated: Dictionary = TRACK_SEED_GEN.generate_with_retries(room_seed, ROOM_RECT, params)
			if not _expect(repeated["points"] == controls and repeated["family"] == result["family"], "%s/%s must be exactly deterministic" % [room_name, expected_family]):
				return
			if not _check_loop(room_seed, room_name, controls, ROOM_SHAPES[room_name], 320.0):
				return
			if room_name == "el":
				var centerline: PackedVector2Array = TRACK_SEED_GEN.centerline_checkpoints(controls)
				var enters_right_extension := false
				var occupies_upper_left := false
				for point: Vector2 in centerline:
					enters_right_extension = enters_right_extension or point.x > 450.0
					occupies_upper_left = occupies_upper_left or (point.x < 0.0 and point.y < -200.0)
				if not _expect(enters_right_extension and occupies_upper_left, "el/%s must occupy both the upper-left arm and right/lower extension" % expected_family):
					return
				if not _expect(StringName(result.get("realization", &"")) == &"el_safe", "el/%s should report its dedicated L-safe realization" % expected_family):
					return

	var long_speed: Dictionary = TRACK_SEED_GEN.generate_with_retries(0, ROOM_RECT, _room_params("long"))
	var tall_speed: Dictionary = TRACK_SEED_GEN.generate_with_retries(0, ROOM_RECT, _room_params("tall"))
	var long_bounds := _points_bounds(TRACK_SEED_GEN.centerline_checkpoints(long_speed["points"]))
	var tall_bounds := _points_bounds(TRACK_SEED_GEN.centerline_checkpoints(tall_speed["points"]))
	if not _expect(long_bounds.size.x > long_bounds.size.y * 2.5, "long room should orient the speed loop horizontally"):
		return
	if not _expect(tall_bounds.size.y > tall_bounds.size.x * 1.2, "tall room should rotate the speed loop vertically"):
		return

	var matrix_count := 0
	var matrix_fallbacks := 0
	var total_turn_complexes := 0
	var total_setup_straight_regions := 0
	var minimum_setup_straight_regions := 999
	var maximum_setup_straight_regions := 0
	var matrix_seed_count := SAMPLE_SEEDS
	if OS.get_environment("PC_TRACK_MATRIX_SEEDS").is_valid_int():
		matrix_seed_count = clampi(int(OS.get_environment("PC_TRACK_MATRIX_SEEDS")), 1, sample_seed_count)
	for room_name: String in ROOM_SHAPES:
		var params := _room_params(room_name)
		for seed in matrix_seed_count:
			var result: Dictionary = TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
			if not _expect(int(result["seed"]) == seed and String(result["family"]) == String(seed_families[seed]), "%s seed %d must preserve seed and family identity" % [room_name, seed]):
				return
			var controls: PackedVector2Array = result["points"]
			if not _expect(not controls.is_empty(), "%s seed %d should produce a matrix route" % [room_name, seed]):
				return
			if not _check_loop(seed, room_name, controls, ROOM_SHAPES[room_name], 320.0):
				return
			var gameplay: Dictionary = TRACK_SEED_GEN.gameplay_metrics(controls)
			if not _expect(float(gameplay.get("minimum_turn_radius", 0.0)) >= TRACK_SEED_GEN.MIN_DRIVE_RADIUS, "%s seed %d must retain driveable curve radius" % [room_name, seed]):
				return
			var setup_straight_regions := int(gameplay.get("setup_straight_count", 0))
			if not _expect(setup_straight_regions >= 2, "%s seed %d needs at least two distinct %.0fu setup straights (got %d)" % [room_name, seed, TRACK_SEED_GEN.MIN_SETUP_DISTANCE, setup_straight_regions]):
				return
			if not _expect(int(gameplay.get("literal_straight_count", 0)) >= 2, "%s seed %d needs two literal heading-stable straight runs" % [room_name, seed]):
				return
			if not _expect(not bool((gameplay.get("complex_bypass", {}) as Dictionary).get("found", false)), "%s seed %d must resist a straight chord replacing a whole complex" % [room_name, seed]):
				return
			var physical_bypass := _physical_complex_bypass(TRACK_SEED_GEN.centerline_checkpoints(controls), result.get("pockets", []))
			if not _expect(not bool(physical_bypass.get("found", false)), "%s seed %d route geometry must reject a %.0fu route-to-chord bypass (arc=%.0f chord=%.0f samples=%d->%d)" % [room_name, seed, float(physical_bypass.get("saving", 0.0)), float(physical_bypass.get("arc", 0.0)), float(physical_bypass.get("chord", 0.0)), int(physical_bypass.get("start", -1)), int(physical_bypass.get("finish", -1))]):
				return
			total_setup_straight_regions += setup_straight_regions
			minimum_setup_straight_regions = mini(minimum_setup_straight_regions, setup_straight_regions)
			maximum_setup_straight_regions = maxi(maximum_setup_straight_regions, setup_straight_regions)
			var turn_complexes := _broad_turn_complex_count(TRACK_SEED_GEN.centerline_checkpoints(controls))
			if not _expect(turn_complexes >= 1 and turn_complexes <= 10, "%s seed %d should contain a bounded set of broad setup-separated complexes (got %d)" % [room_name, seed, turn_complexes]):
				return
			if bool(result.get("fallback", false)):
				matrix_fallbacks += 1
				if not _expect(StringName(result.get("realization", &"")) == &"technical_perimeter", "%s seed %d fallback must report its conservative perimeter realization" % [room_name, seed]):
					return
			total_turn_complexes += turn_complexes
			matrix_count += 1
	if not _expect(matrix_fallbacks <= 96, "the 360-route matrix should retain selected-family geometry when it fits (fallbacks=%d)" % matrix_fallbacks):
		return
	if not _expect(total_turn_complexes <= matrix_count * 8, "the richer route grammar should average no more than eight broad complexes (got %.1f)" % (float(total_turn_complexes) / float(matrix_count))):
		return

	print("TRACK_SEED_GEN_TEST PASS families=%d fingerprints=%d classic_fallbacks=%d matrix_fallbacks=%d broad_complexes_avg=%.1f setup_regions=%d..%d avg=%.1f classic_length=%.0f..%.0f" % [families.size(), fingerprints.size(), fallback_count, matrix_fallbacks, float(total_turn_complexes) / float(matrix_count), minimum_setup_straight_regions, maximum_setup_straight_regions, float(total_setup_straight_regions) / float(matrix_count), minimum_length, maximum_length])
	quit(0)


func _room_params(room_name: String) -> Dictionary:
	var params := {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1500.0 * TRACK_SEED_GEN.WORLD_SCALE,
		"room_polygon": ROOM_SHAPES[room_name],
		"room_shape": StringName(room_name),
	}
	match room_name:
		"el":
			params["min_loop_length"] = 1500.0 * TRACK_SEED_GEN.WORLD_SCALE
		"long":
			params["min_loop_length"] = 2000.0 * TRACK_SEED_GEN.WORLD_SCALE
		"square":
			params["min_loop_length"] = 2200.0 * TRACK_SEED_GEN.WORLD_SCALE
	return params


func _check_loop(seed: int, room_name: String, controls: PackedVector2Array, room_polygon: PackedVector2Array, min_distance: float) -> bool:
	var centerline: PackedVector2Array = TRACK_SEED_GEN.centerline_checkpoints(controls)
	if not _expect(centerline.size() == 260, "%s seed %d should expose 260 centerline checkpoints" % [room_name, seed]):
		return false
	if not _expect(not _has_self_intersection(centerline), "%s seed %d should be a simple loop" % [room_name, seed]):
		return false
	if not _expect(_self_distance_ok(centerline, min_distance), "%s seed %d should keep a 250-unit corridor clear" % [room_name, seed]):
		return false
	for point: Vector2 in centerline:
		if not _expect(_inside_with_margin(point, room_polygon, HALF_WIDTH - 1.0), "%s seed %d corridor should stay inside its room polygon" % [room_name, seed]):
			return false
	return true


func _broad_turn_complex_count(points: PackedVector2Array) -> int:
	var profile := PackedFloat32Array()
	var span := 8
	for index in points.size():
		var behind := (points[index] - points[posmod(index - span, points.size())]).normalized()
		var ahead := (points[posmod(index + span, points.size())] - points[index]).normalized()
		profile.append(absf(behind.angle_to(ahead)))
	var candidates: Array[Dictionary] = []
	for index in profile.size():
		var strength := profile[index]
		if strength < 0.18:
			continue
		var local_maximum := 0.0
		var local_minimum := INF
		for offset in range(-10, 11):
			var nearby := profile[posmod(index + offset, profile.size())]
			local_minimum = minf(local_minimum, nearby)
			if absi(offset) <= 4:
				local_maximum = maxf(local_maximum, nearby)
		if strength + 0.0001 < local_maximum or strength - local_minimum < 0.045:
			continue
		candidates.append({"index": index, "strength": strength})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["strength"]) > float(b["strength"]))
	var selected: Array[int] = []
	for candidate: Dictionary in candidates:
		var index := int(candidate["index"])
		var separated := true
		for other: int in selected:
			var direct := absi(index - other)
			if mini(direct, profile.size() - direct) < 14:
				separated = false
				break
		if separated:
			selected.append(index)
	if selected.is_empty():
		return 0
	selected.sort()
	var arc := PackedFloat32Array([0.0])
	for index in points.size():
		arc.append(arc[index] + points[index].distance_to(points[(index + 1) % points.size()]))
	var separated_gaps := 0
	for index in selected.size():
		var first := selected[index]
		var second := selected[(index + 1) % selected.size()]
		var gap := arc[second] - arc[first] if second > first else arc[arc.size() - 1] - arc[first] + arc[second]
		# Peak centers need the 450u setup run plus room for both corner mouths.
		if gap >= TRACK_SEED_GEN.MIN_SETUP_DISTANCE + 200.0:
			separated_gaps += 1
	return maxi(separated_gaps, 1)


func _physical_complex_bypass(centerline: PackedVector2Array, pockets: Array = []) -> Dictionary:
	var edges: Dictionary = TRACK_BUILDER._corridor_edges(centerline)
	var left: PackedVector2Array = edges["left"]
	var right: PackedVector2Array = edges["right"]
	var outer_raw := left if absf(_polygon_area(left)) > absf(_polygon_area(right)) else right
	var inner_raw := left if absf(_polygon_area(left)) < absf(_polygon_area(right)) else right
	var outer_boundary: PackedVector2Array = TRACK_BUILDER._simple_boundary_loop(outer_raw, centerline)
	var inner_boundary: PackedVector2Array = TRACK_BUILDER._simple_inner_boundary_loop(inner_raw, centerline)
	for start in range(0, centerline.size(), 3):
		var route_arc := 0.0
		for step in range(1, centerline.size() / 2):
			route_arc += centerline[(start + step - 1) % centerline.size()].distance_to(centerline[(start + step) % centerline.size()])
			if route_arc < PHYSICAL_BYPASS_MIN_ARC or step % 3 != 0:
				continue
			if route_arc > PHYSICAL_BYPASS_MAX_ARC:
				break
			var finish := (start + step) % centerline.size()
			var chord := centerline[start].distance_to(centerline[finish])
			var saving := route_arc - chord
			if chord < 1.0:
				continue
			var ratio := route_arc / chord
			var egregious_bypass := saving >= PHYSICAL_BYPASS_MIN_SAVING and ratio >= PHYSICAL_BYPASS_MIN_RATIO
			var unvalidated_long_bypass := route_arc > TRACK_SEED_GEN.BYPASS_MAX_ARC and saving >= TRACK_SEED_GEN.BYPASS_MIN_SAVING and ratio >= TRACK_SEED_GEN.BYPASS_MIN_RATIO
			if not egregious_bypass and not unvalidated_long_bypass:
				continue
			if _chord_matches_pocket(centerline[start], centerline[finish], pockets):
				continue
			if _segment_touches_loop(centerline[start], centerline[finish], outer_boundary, 22.0) or _segment_touches_loop(centerline[start], centerline[finish], inner_boundary, 22.0):
				continue
			return {"found": true, "saving": saving, "arc": route_arc, "chord": chord, "start": start, "finish": finish}
	return {"found": false, "saving": 0.0}


func _chord_matches_pocket(from: Vector2, to: Vector2, pockets: Array) -> bool:
	# A chord is excused when it matches a declared pocket mouth: the scene
	# builder seals those with solid walls.
	for pocket: Dictionary in pockets:
		if from.distance_to(pocket.get("from", Vector2.ZERO)) < 40.0 and to.distance_to(pocket.get("to", Vector2.ZERO)) < 40.0:
			return true
		if from.distance_to(pocket.get("to", Vector2.ZERO)) < 40.0 and to.distance_to(pocket.get("from", Vector2.ZERO)) < 40.0:
			return true
	return false


func _segment_touches_loop(from: Vector2, to: Vector2, loop: PackedVector2Array, clearance: float) -> bool:
	for index in loop.size():
		var boundary_from := loop[index]
		var boundary_to := loop[(index + 1) % loop.size()]
		if Geometry2D.segment_intersects_segment(from, to, boundary_from, boundary_to) != null:
			return true
		var distance := minf(
			minf(_point_segment_distance(from, boundary_from, boundary_to), _point_segment_distance(to, boundary_from, boundary_to)),
			minf(_point_segment_distance(boundary_from, from, to), _point_segment_distance(boundary_to, from, to))
		)
		if distance <= clearance:
			return true
	return false


func _shape_fingerprint(controls: PackedVector2Array) -> String:
	var center := Vector2.ZERO
	for point: Vector2 in controls:
		center += point
	center /= float(controls.size())
	var radial_mean := 0.0
	var radial_variance := 0.0
	var minimum_radius := INF
	var maximum_radius := 0.0
	for point: Vector2 in controls:
		var radius := point.distance_to(center)
		radial_mean += radius
		minimum_radius = minf(minimum_radius, radius)
		maximum_radius = maxf(maximum_radius, radius)
	radial_mean /= float(controls.size())
	for point: Vector2 in controls:
		var delta := point.distance_to(center) - radial_mean
		radial_variance += delta * delta
	radial_variance /= float(controls.size())
	var area := absf(_polygon_area(controls))
	return "%d:%d:%d:%d" % [
		int(round(area / 20000.0)),
		int(round(minimum_radius / maxf(maximum_radius, 1.0) * 20.0)),
		int(round(sqrt(radial_variance) / maxf(radial_mean, 1.0) * 40.0)),
		int(round(controls[0].distance_to(controls[controls.size() / 2]) / 40.0)),
	]


func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var next := (index + 1) % points.size()
		total += points[index].x * points[next].y - points[next].x * points[index].y
	return total * 0.5


func _silhouette_features(controls: PackedVector2Array) -> Dictionary:
	var points: PackedVector2Array = TRACK_SEED_GEN.centerline_checkpoints(controls)
	var bounds := Rect2(points[0], Vector2.ZERO)
	var center := Vector2.ZERO
	for point: Vector2 in points:
		bounds = bounds.expand(point)
		center += point
	center /= float(points.size())
	var hull := Geometry2D.convex_hull(points)
	var hull_area := absf(_polygon_area(hull))
	var area := absf(_polygon_area(points))
	var center_band_min := INF
	var center_band_max := -INF
	var top_min := INF
	var top_max := -INF
	var bottom_min := INF
	var bottom_max := -INF
	var top_x := 0.0
	var top_count := 0
	var bottom_x := 0.0
	var bottom_count := 0
	var upper_mid_min := INF
	var upper_mid_max := -INF
	var lower_mid_min := INF
	var lower_mid_max := -INF
	var minimum_radius := INF
	var maximum_radius := 0.0
	for point: Vector2 in points:
		if absf(point.x - center.x) < bounds.size.x * 0.12:
			center_band_min = minf(center_band_min, point.y)
			center_band_max = maxf(center_band_max, point.y)
		if point.y < bounds.position.y + bounds.size.y * 0.22:
			top_min = minf(top_min, point.x)
			top_max = maxf(top_max, point.x)
			top_x += point.x
			top_count += 1
		if point.y > bounds.end.y - bounds.size.y * 0.22:
			bottom_min = minf(bottom_min, point.x)
			bottom_max = maxf(bottom_max, point.x)
			bottom_x += point.x
			bottom_count += 1
		var y_fraction := (point.y - bounds.position.y) / maxf(bounds.size.y, 1.0)
		if y_fraction > 0.28 and y_fraction < 0.48:
			upper_mid_min = minf(upper_mid_min, point.x)
			upper_mid_max = maxf(upper_mid_max, point.x)
		if y_fraction > 0.52 and y_fraction < 0.72:
			lower_mid_min = minf(lower_mid_min, point.x)
			lower_mid_max = maxf(lower_mid_max, point.x)
		var radius := point.distance_to(center)
		minimum_radius = minf(minimum_radius, radius)
		maximum_radius = maxf(maximum_radius, radius)
	var top_span := top_max - top_min
	var bottom_span := bottom_max - bottom_min
	var mirror_error := 0.0
	for point: Vector2 in points:
		var reflected := Vector2(point.x, bounds.get_center().y * 2.0 - point.y)
		var nearest := INF
		for other: Vector2 in points:
			nearest = minf(nearest, reflected.distance_to(other))
		mirror_error += nearest
	mirror_error /= float(points.size()) * maxf(bounds.size.length(), 1.0)
	return {
		"aspect": snappedf(bounds.size.x / maxf(bounds.size.y, 1.0), 0.01),
		"concavity": snappedf(1.0 - area / maxf(hull_area, 1.0), 0.01),
		"waist": snappedf((center_band_max - center_band_min) / maxf(bounds.size.y, 1.0), 0.01),
		"alternation": snappedf(absf(top_x / float(top_count) - bottom_x / float(bottom_count)) / maxf(bounds.size.x, 1.0), 0.01),
		"mid_shift": snappedf(absf((upper_mid_min + upper_mid_max) * 0.5 - (lower_mid_min + lower_mid_max) * 0.5) / maxf(bounds.size.x, 1.0), 0.01),
		"triangle_taper": snappedf(minf(top_span, bottom_span) / maxf(maxf(top_span, bottom_span), 1.0), 0.01),
		"radial_min": snappedf(minimum_radius / maxf(maximum_radius, 1.0), 0.01),
		"centroid_offset": snappedf(center.distance_to(bounds.get_center()) / maxf(bounds.size.length(), 1.0), 0.01),
		"mirror_error": snappedf(mirror_error, 0.001),
	}


func _feature_distance(first: Dictionary, second: Dictionary) -> float:
	var keys := ["concavity", "waist", "triangle_taper", "radial_min", "mirror_error", "alternation"]
	var weights := [1.0, 1.0, 1.0, 1.0, 5.0, 3.0]
	var squared := 0.0
	for index in keys.size():
		var delta := (float(first[keys[index]]) - float(second[keys[index]])) * float(weights[index])
		squared += delta * delta
	return sqrt(squared)


func _points_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


func _inside_with_margin(point: Vector2, polygon: PackedVector2Array, margin: float) -> bool:
	if not Geometry2D.is_point_in_polygon(point, polygon):
		return false
	for index in polygon.size():
		if _point_segment_distance(point, polygon[index], polygon[(index + 1) % polygon.size()]) < margin:
			return false
	return true


func _point_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	if segment.length_squared() < 0.001:
		return point.distance_to(from)
	var fraction := clampf((point - from).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(from + segment * fraction)


func _self_distance_ok(points: PackedVector2Array, min_distance: float) -> bool:
	var count := points.size()
	var cumulative := PackedFloat32Array([0.0])
	for index in count:
		cumulative.append(cumulative[index] + points[index].distance_to(points[(index + 1) % count]))
	var total_length := cumulative[count]
	var local_arc := maxf(850.0, min_distance * 3.0)
	for first in count:
		for second in range(first + 1, count):
			var forward_arc := cumulative[second] - cumulative[first]
			if minf(forward_arc, total_length - forward_arc) < local_arc:
				continue
			if points[first].distance_to(points[second]) < min_distance:
				return false
	return true


func _has_self_intersection(points: PackedVector2Array) -> bool:
	var count := points.size()
	for first in count:
		var first_next := (first + 1) % count
		for second in range(first + 1, count):
			var second_next := (second + 1) % count
			if first_next == second or second_next == first:
				continue
			if _segments_intersect(points[first], points[first_next], points[second], points[second_next]):
				return true
	return false


func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := _cross(a, b, c)
	var ab_d := _cross(a, b, d)
	var cd_a := _cross(c, d, a)
	var cd_b := _cross(c, d, b)
	return (((ab_c > 0.0 and ab_d < 0.0) or (ab_c < 0.0 and ab_d > 0.0))
		and ((cd_a > 0.0 and cd_b < 0.0) or (cd_a < 0.0 and cd_b > 0.0)))


func _cross(origin: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_SEED_GEN_TEST FAIL: " + message)
	quit(1)
	return false
