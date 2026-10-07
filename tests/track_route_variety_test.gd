extends SceneTree

const TRACK_SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")
const ROOM_RECT := Rect2(-940.0, -540.0, 1880.0, 1080.0)
const SHAPE_SAMPLE_COUNT := 32
const DISTINCT_SHAPE_DISTANCE := 0.055

# Directional-variation gate: a route deformed past right-angle corners must
# carry at least three distinct straight-heading families. Thresholds are chosen
# from geometry, not from observed output:
#   - A straight run must sustain 200u at a fixed heading. 200u is clearly longer
#     than the ~180u corner fillet arcs (CORNER_RADIUS) and the 55-110u control
#     spacing, so it cannot be a corner blend.
#   - The heading tolerance 0.04 rad (~2.3 deg) matches
#     LITERAL_STRAIGHT_HEADING_TOLERANCE, the generator's own definition of a
#     literal straight.
#   - Two runs are distinct families only when their headings (mod PI) are at
#     least 11 degrees apart — about 5x the 0.04 rad run tolerance, so sampling
#     noise can neither invent nor hide a family, while a visible diagonal wall
#     (well under a 45 deg shears) still registers as its own family.
const STRAIGHT_RUN_MIN_LENGTH := 200.0
const STRAIGHT_RUN_HEADING_TOLERANCE := 0.04
const HEADING_FAMILY_SEPARATION := 11.0 * PI / 180.0
const MIN_HEADING_FAMILIES := 3
const DIRECTIONAL_VARIETY_SHARE := 0.5
const UNSEEN_WINDOW_OFFSET := 100000
const UNSEEN_WINDOW_SIZE := 4

static var ROOM_SHAPES := {
	"classic": PackedVector2Array([Vector2(-875, -575) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(875, -575) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(875, 575) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(-875, 575) * TRACK_SEED_GEN.WORLD_SCALE]),
	"wide": PackedVector2Array([Vector2(-1175, -600) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(1175, -600) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(1175, 600) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(-1175, 600) * TRACK_SEED_GEN.WORLD_SCALE]),
	"tall": PackedVector2Array([Vector2(-575, -725) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(575, -725) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(575, 725) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(-575, 725) * TRACK_SEED_GEN.WORLD_SCALE]),
	"long": PackedVector2Array([Vector2(-1300, -550) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(1300, -550) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(1300, 550) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(-1300, 550) * TRACK_SEED_GEN.WORLD_SCALE]),
	"square": PackedVector2Array([Vector2(-750, -750) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(750, -750) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(750, 750) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(-750, 750) * TRACK_SEED_GEN.WORLD_SCALE]),
	"el": PackedVector2Array([Vector2(-1200, -700) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(360, -700) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(360, -60) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(1200, -60) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(1200, 700) * TRACK_SEED_GEN.WORLD_SCALE, Vector2(-1200, 700) * TRACK_SEED_GEN.WORLD_SCALE]),
}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if OS.get_environment("PC_TRACK_LENGTH_ONLY") == "1":
		_run_high_length_test()
		return
	if not _verify_directional_fixtures():
		return
	var recipes := {}
	var sequences := {}
	var representatives := {}
	var program_variants := {}
	var svg_representatives := {}
	var non_axis_headings := 0
	var mixed_turn_routes := 0
	var directional_varied := 0
	var minimum_control_count := 999
	var maximum_control_count := 0
	var sample_seed_count := 6
	var seed_offset := int(OS.get_environment("PC_ROUTE_SEED_OFFSET"))
	if OS.get_environment("PC_ROUTE_SAMPLE_SEEDS").is_valid_int():
		sample_seed_count = clampi(int(OS.get_environment("PC_ROUTE_SAMPLE_SEEDS")), 3, 24)
	for sample in sample_seed_count:
		var seed := seed_offset + sample
		var result := TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, _room_params("classic"))
		if not _check_result("classic", seed, result, seed < 4):
			return
		if not _expect(_has_real_infield(TRACK_SEED_GEN.centerline_checkpoints(result["points"])), "seed %d must have a substantial infield, not an oval or cosmetic notch (%s)" % [seed, result.get("route_program", "unknown")]):
			return
		if bool(result.get("fallback", false)):
			continue
		var recipe := String(result.get("route_recipe", "none"))
		var program := String(result.get("route_program", "none"))
		var sequence := String(result.get("route_sequence", ""))
		var centerline := TRACK_SEED_GEN.centerline_checkpoints(result["points"])
		minimum_control_count = mini(minimum_control_count, (result["points"] as PackedVector2Array).size())
		maximum_control_count = maxi(maximum_control_count, (result["points"] as PackedVector2Array).size())
		if _heading_family_count(centerline) >= MIN_HEADING_FAMILIES:
			directional_varied += 1
		recipes[recipe] = true
		sequences[sequence] = true
		if not representatives.has(recipe):
			representatives[recipe] = centerline
		if not program_variants.has(program):
			program_variants[program] = []
		(program_variants[program] as Array).append(centerline)
		svg_representatives["%02d · %s" % [seed, program]] = centerline
		if _off_axis_heading(centerline) >= 0.05:
			non_axis_headings += 1
		var mix := TRACK_SEED_GEN.raw_turn_mix(result["points"])
		if mix.x > 0 and mix.y > 0:
			mixed_turn_routes += 1

	if not _expect(recipes.size() >= 3, "classic seeds should realize at least three complete route programs, got %s" % [recipes.keys()]):
		return
	if not _expect(sequences.size() >= 3, "normalized turn/straight signatures should contain at least three rhythms, got %d" % sequences.size()):
		return
	if not _expect(non_axis_headings >= ceili(float(sample_seed_count) * 0.5), "at least half of classic routes should put their longest straight on a meaningful non-axis heading, got %d" % non_axis_headings):
		return
	if not _expect(mixed_turn_routes >= ceili(float(sample_seed_count) * 0.7), "procedural routes should mix left and right corners instead of one-handed ovals, got %d" % mixed_turn_routes):
		return
	if not _expect(minimum_control_count >= 40 and maximum_control_count < TRACK_SEED_GEN.SAMPLE_COUNT, "fillets and literal straights need bounded higher-density controls, got %d..%d" % [minimum_control_count, maximum_control_count]):
		return
	var varied_programs := 0
	var strongest_program_cluster := 0
	var program_cluster_evidence: Array[String] = []
	for program: String in program_variants:
		var program_clusters: Array[PackedVector2Array] = []
		for candidate: PackedVector2Array in program_variants[program]:
			var distinct := true
			for existing: PackedVector2Array in program_clusters:
				if _shape_distance(candidate, existing) < DISTINCT_SHAPE_DISTANCE:
					distinct = false
					break
			if distinct:
				program_clusters.append(candidate)
		if program_clusters.size() >= 2:
			varied_programs += 1
		strongest_program_cluster = maxi(strongest_program_cluster, program_clusters.size())
		program_cluster_evidence.append("%s:%d/%d" % [program, program_clusters.size(), (program_variants[program] as Array).size()])
	if not _expect(varied_programs >= 2 and strongest_program_cluster >= 2, "macro parameters should create multiple invariant shapes within each program (varied=%d strongest=%d %s)" % [varied_programs, strongest_program_cluster, " ".join(program_cluster_evidence)]):
		return

	var clusters: Array[PackedVector2Array] = []
	for program: String in program_variants:
		for candidate: PackedVector2Array in program_variants[program]:
			var distinct := true
			for existing: PackedVector2Array in clusters:
				if _shape_distance(candidate, existing) < DISTINCT_SHAPE_DISTANCE:
					distinct = false
					break
			if distinct:
				clusters.append(candidate)
	if not _expect(clusters.size() >= 3, "rotation/mirror/scale-invariant shape distance should retain at least three material macro shapes, got %d from %d routes" % [clusters.size(), sample_seed_count]):
		return

	var transformed := PackedVector2Array()
	for point: Vector2 in clusters[0]:
		transformed.append(Vector2(-point.x, point.y).rotated(0.73) * 1.8 + Vector2(431.0, -287.0))
	if not _expect(_shape_distance(clusters[0], transformed) < 0.002, "shape distance must discount translation, scale, rotation, and mirror-only changes"):
		return
	var oval := PackedVector2Array()
	for i in 80:
		oval.append(Vector2(cos(TAU * i / 80.0) * 1100.0, sin(TAU * i / 80.0) * 700.0).rotated(0.37))
	var cosmetic_notch := PackedVector2Array([Vector2(-1100, -700), Vector2(-80, -700), Vector2(0, -650), Vector2(80, -700), Vector2(1100, -700), Vector2(1100, 700), Vector2(-1100, 700)])
	if not _expect(not _has_real_infield(oval) and not _has_real_infield(cosmetic_notch), "infield gate must reject rotated ovals and shallow notches"):
		return

	if not _expect(directional_varied >= ceili(float(sample_seed_count) * DIRECTIONAL_VARIETY_SHARE), "at least half of classic routes must carry >=%d distinct straight-heading families (internal diagonals / acute-obtuse corners), got %d/%d varied" % [MIN_HEADING_FAMILIES, directional_varied, sample_seed_count]):
		return
	var unseen_directional_varied := 0
	for sample in UNSEEN_WINDOW_SIZE:
		var unseen_seed := seed_offset + UNSEEN_WINDOW_OFFSET + sample
		var unseen_result := TRACK_SEED_GEN.generate_with_retries(unseen_seed, ROOM_RECT, _room_params("classic"))
		if not _check_result("classic-unseen", unseen_seed, unseen_result):
			return
		if bool(unseen_result.get("fallback", false)):
			continue
		var unseen_centerline := TRACK_SEED_GEN.centerline_checkpoints(unseen_result["points"])
		if not _expect(_has_real_infield(unseen_centerline), "unseen seed %d must retain a substantial infield (%s)" % [unseen_seed, unseen_result.get("route_program", "unknown")]):
			return
		if _heading_family_count(unseen_centerline) >= MIN_HEADING_FAMILIES:
			unseen_directional_varied += 1
	if not _expect(unseen_directional_varied >= ceili(float(UNSEEN_WINDOW_SIZE) * DIRECTIONAL_VARIETY_SHARE), "unseen classic window must also carry >=%d distinct straight-heading families in at least half its routes, got %d/%d" % [MIN_HEADING_FAMILIES, unseen_directional_varied, UNSEEN_WINDOW_SIZE]):
		return

	var diagnostic_cases := [
		["kitchen/long/24469", "long", 24469],
		["workshop/square/51940", "square", 51940],
		["workshop/long/40912", "long", 40912],
		["workshop/tall/43999", "tall", 43999],
	]
	var diagnostic_evidence: Array[String] = []
	for case: Array in diagnostic_cases:
		var room_name := String(case[1])
		var seed := int(case[2])
		var result := TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, _room_params(room_name))
		if not _check_result(String(case[0]), seed, result, true):
			return
		var metrics := TRACK_SEED_GEN.gameplay_metrics(result["points"])
		diagnostic_evidence.append("%s=%s/attempt%d/fallback%s/length%.0f/radius%.0f/literal%d/controls%d" % [
			String(case[0]), String(result.get("route_recipe", "none")), int(result.get("attempt", -1)),
			str(bool(result.get("fallback", false))), float(result.get("length", 0.0)),
			float(metrics.get("minimum_turn_radius", 0.0)), int(metrics.get("literal_straight_count", 0)),
			(result["points"] as PackedVector2Array).size(),
		])

	var matrix_seeds := [0, 11, 29]
	var matrix_count := 0
	for room_name: String in ROOM_SHAPES:
		for seed: int in matrix_seeds:
			var result := TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, _room_params(room_name))
			if not _check_result(room_name, seed, result):
				return
			matrix_count += 1

	var svg_path := OS.get_environment("PC_ROUTE_SVG")
	if not svg_path.is_empty():
		_write_svg(svg_path, svg_representatives)
	print("TRACK_ROUTE_DIAGNOSTICS " + " ".join(diagnostic_evidence))
	print("TRACK_ROUTE_VARIETY_TEST PASS recipes=%d sequences=%d shape_clusters=%d within_programs=%d/%d strongest=%d off_axis=%d controls=%d..%d matrix=%d diagnostics=%d directional=%d/%d unseen=%d/%d" % [recipes.size(), sequences.size(), clusters.size(), varied_programs, program_variants.size(), strongest_program_cluster, non_axis_headings, minimum_control_count, maximum_control_count, matrix_count, diagnostic_cases.size(), directional_varied, sample_seed_count, unseen_directional_varied, UNSEEN_WINDOW_SIZE])
	quit(0)


func _run_high_length_test() -> void:
	var result := _high_length_evidence()
	if not _expect(bool(result["valid"]), String(result["message"])):
		return
	print("TRACK_ROUTE_LENGTHS " + " ".join(result["evidence"] as Array[String]))
	quit(0)


func _high_length_evidence() -> Dictionary:
	var evidence: Array[String] = []
	var highest_realized := 0.0
	for seed: int in [20, 33, 48]:
		var result := TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, _room_params("classic"))
		if (result.get("points", PackedVector2Array()) as PackedVector2Array).is_empty():
			return {"valid": false, "evidence": evidence, "message": "high target seed %d failed geometry (%s)" % [seed, result.get("reason", "unknown")]}
		var target := float(result.get("target_length", 0.0))
		var realized := float(result.get("length", 0.0))
		highest_realized = maxf(highest_realized, realized)
		evidence.append("%d:target%.0f/realized%.0f(%.1f%% target)" % [seed, target, realized, realized / maxf(target, 1.0) * 100.0])
	return {
		"valid": highest_realized >= 6800.0 and highest_realized <= 9800.0,
		"evidence": evidence,
		"message": "high target stream must retain supported classic length coverage, got %.0f (%s)" % [highest_realized, " ".join(evidence)],
	}


func _check_result(label: String, seed: int, result: Dictionary, check_determinism: bool = false) -> bool:
	var controls: PackedVector2Array = result.get("points", PackedVector2Array())
	if not _expect(not controls.is_empty(), "%s seed %d should generate (%s)" % [label, seed, result.get("reason", "unknown")]):
		return false
	if not _expect(int(result.get("seed", -1)) == seed, "%s must preserve requested seed %d" % [label, seed]):
		return false
	if check_determinism:
		var repeated := TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, _room_params(_room_from_label(label)))
		if not _expect(repeated.get("points") == controls and repeated.get("route_recipe") == result.get("route_recipe"), "%s seed %d must be exactly deterministic" % [label, seed]):
			return false
	var metrics := TRACK_SEED_GEN.gameplay_metrics(controls)
	if not _expect(float(metrics.get("minimum_turn_radius", 0.0)) >= TRACK_SEED_GEN.MIN_DRIVE_RADIUS, "%s seed %d needs driveable radius" % [label, seed]):
		return false
	if not _expect(int(metrics.get("setup_straight_count", 0)) >= 2, "%s seed %d needs two setup straights" % [label, seed]):
		return false
	if not _expect(int(metrics.get("literal_straight_count", 0)) >= 2, "%s seed %d needs two 450u runs whose heading stays within %.1f degrees" % [label, seed, rad_to_deg(TRACK_SEED_GEN.LITERAL_STRAIGHT_HEADING_TOLERANCE)]):
		return false
	if not _expect(not bool((metrics.get("complex_bypass", {}) as Dictionary).get("found", false)), "%s seed %d must not admit a driveable complex bypass" % [label, seed]):
		return false
	if not _expect(String(metrics.get("route_sequence", "")).contains("S"), "%s seed %d sequence should include a normalized straight run" % [label, seed]):
		return false
	return true


func _room_from_label(label: String) -> String:
	if label.contains("/"):
		return label.split("/")[1]
	return label


func _room_params(room_name: String) -> Dictionary:
	var params := {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1900.0 * TRACK_SEED_GEN.WORLD_SCALE,
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


func _off_axis_heading(points: PackedVector2Array) -> float:
	var direction := points[points.size() - 8].direction_to(points[8])
	var angle := fposmod(direction.angle(), PI * 0.5)
	return minf(angle, PI * 0.5 - angle)


func _shape_distance(first: PackedVector2Array, second: PackedVector2Array) -> float:
	var a := _normalized_shape(first)
	var b := _normalized_shape(second)
	var best := INF
	for reflected in 2:
		for direction: int in [1, -1]:
			for shift in SHAPE_SAMPLE_COUNT:
				var dot_sum := 0.0
				var cross_sum := 0.0
				for index in SHAPE_SAMPLE_COUNT:
					var other := b[posmod(shift + direction * index, SHAPE_SAMPLE_COUNT)]
					if reflected == 1:
						other.x *= -1.0
					dot_sum += other.dot(a[index])
					cross_sum += other.cross(a[index])
				var rotation := atan2(cross_sum, dot_sum)
				var squared := 0.0
				for index in SHAPE_SAMPLE_COUNT:
					var other := b[posmod(shift + direction * index, SHAPE_SAMPLE_COUNT)]
					if reflected == 1:
						other.x *= -1.0
					squared += a[index].distance_squared_to(other.rotated(rotation))
				best = minf(best, sqrt(squared / float(SHAPE_SAMPLE_COUNT)))
	return best


func _normalized_shape(points: PackedVector2Array) -> PackedVector2Array:
	var sampled := _arc_resample(points, SHAPE_SAMPLE_COUNT)
	var center := Vector2.ZERO
	for point: Vector2 in sampled:
		center += point
	center /= float(sampled.size())
	var rms := 0.0
	for point: Vector2 in sampled:
		rms += point.distance_squared_to(center)
	rms = sqrt(rms / float(sampled.size()))
	for index in sampled.size():
		sampled[index] = (sampled[index] - center) / maxf(rms, 0.001)
	return sampled


func _arc_resample(points: PackedVector2Array, count: int) -> PackedVector2Array:
	var cumulative := PackedFloat32Array([0.0])
	for index in points.size():
		cumulative.append(cumulative[index] + points[index].distance_to(points[(index + 1) % points.size()]))
	var result := PackedVector2Array()
	var segment := 0
	for output in count:
		var target := cumulative[points.size()] * float(output) / float(count)
		while segment < points.size() - 1 and cumulative[segment + 1] < target:
			segment += 1
		var fraction := (target - cumulative[segment]) / maxf(cumulative[segment + 1] - cumulative[segment], 0.001)
		result.append(points[segment].lerp(points[(segment + 1) % points.size()], fraction))
	return result


func _has_real_infield(points: PackedVector2Array) -> bool:
	var hull := Geometry2D.convex_hull(points)
	var hull_area := absf(TRACK_SEED_GEN._polygon_area(hull))
	var area := absf(TRACK_SEED_GEN._polygon_area(points))
	if hull_area < 1.0 or 1.0 - area / hull_area < 0.10:
		return false
	var deepest := 0.0
	for point: Vector2 in points:
		var distance := INF
		for i in range(hull.size() - 1):
			distance = minf(distance, TRACK_SEED_GEN._point_segment_distance(point, hull[i], hull[i + 1]))
		deepest = maxf(deepest, distance)
	return deepest >= TRACK_SEED_GEN.HALF_WIDTH * 2.0


func _write_svg(path: String, representatives: Dictionary) -> void:
	var names: Array = representatives.keys()
	names.sort()
	var rows := ceili(float(names.size()) / 4.0)
	var height := rows * 280 + 110
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="%d" viewBox="0 0 1440 %d"><rect width="100%%" height="100%%" fill="#111316"/>' % [height, height]
	svg += '<text x="30" y="42" fill="#f3f1ea" font-family="sans-serif" font-size="28">Pocket Circuit — actual generated routes</text>'
	svg += '<text x="30" y="76" fill="#b8bec9" font-family="sans-serif" font-size="17">Consecutive seeds · classic room · same world scale · full racing width · dot = start</text>'
	var room: PackedVector2Array = ROOM_SHAPES["classic"]
	var bounds := Rect2(room[0], Vector2.ZERO)
	for point: Vector2 in room:
		bounds = bounds.expand(point)
	var scale := minf(320.0 / bounds.size.x, 216.0 / bounds.size.y)
	var colors := ["#77d5c4", "#eac46e", "#8eaff5", "#ef9b87"]
	for index in names.size():
		var name := String(names[index])
		var points: PackedVector2Array = representatives[name]
		var origin := Vector2(180.0 + float(index % 4) * 360.0, 222.0 + float(index / 4) * 280.0)
		var top_left := origin - bounds.size * scale * 0.5
		svg += '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="8" fill="#202630" stroke="#47505c"/>' % [top_left.x, top_left.y, bounds.size.x * scale, bounds.size.y * scale]
		var svg_points := PackedStringArray()
		for point: Vector2 in points:
			var mapped := origin + (point - bounds.get_center()) * scale
			svg_points.append("%.1f,%.1f" % [mapped.x, mapped.y])
		svg_points.append(svg_points[0])
		var color: String = colors[index % colors.size()]
		svg += '<polyline points="%s" fill="none" stroke="#52606e" stroke-width="%.1f" stroke-linejoin="round"/>' % [" ".join(svg_points), TRACK_SEED_GEN.HALF_WIDTH * 2.0 * scale]
		svg += '<polyline points="%s" fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round"/>' % [" ".join(svg_points), color]
		for run: Dictionary in _straight_runs(points):
			var run_origin := origin + (points[int(run["start"])] - bounds.get_center()) * scale
			var tick := Vector2.from_angle(float(run["heading"])) * 24.0 * scale
			svg += '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#ffffff" stroke-width="1.2" opacity="0.55"/>' % [run_origin.x - tick.x, run_origin.y - tick.y, run_origin.x + tick.x, run_origin.y + tick.y]
		var start := origin + (points[0] - bounds.get_center()) * scale
		svg += '<circle cx="%.1f" cy="%.1f" r="4" fill="#ffffff"/>' % [start.x, start.y]
		svg += '<text x="%.1f" y="%.1f" fill="#f3f1ea" font-family="sans-serif" font-size="18" text-anchor="middle">%s</text>' % [origin.x, origin.y + 137.0, name]
	svg += "</svg>"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(svg)


func _straight_runs(centerline: PackedVector2Array) -> Array:
	# Returns one {"start", "end", "length", "heading"} entry per maximal straight
	# run of the closed centerline. A run begins where a fixed heading can be
	# sustained for at least STRAIGHT_RUN_MIN_LENGTH and ends where the sampled
	# heading first drifts past STRAIGHT_RUN_HEADING_TOLERANCE.
	var runs: Array = []
	var count := centerline.size()
	if count < 4:
		return runs
	var lengths := PackedFloat32Array()
	var ends := PackedInt32Array()
	for start in count:
		var reference := centerline[start].direction_to(centerline[(start + 1) % count])
		var traveled := 0.0
		var cursor := start
		for _step in range(1, count / 2):
			var from := centerline[cursor]
			var to := centerline[(cursor + 1) % count]
			if absf(reference.angle_to(from.direction_to(to))) > STRAIGHT_RUN_HEADING_TOLERANCE:
				break
			traveled += from.distance_to(to)
			cursor = (cursor + 1) % count
		lengths.append(traveled)
		ends.append(cursor)
	var is_run := PackedByteArray()
	for start in count:
		is_run.append(1 if lengths[start] >= STRAIGHT_RUN_MIN_LENGTH else 0)
	for start in count:
		if is_run[start] == 1 and is_run[posmod(start - 1, count)] == 0:
			var end := ends[start]
			runs.append({
				"start": start,
				"end": end,
				"length": lengths[start],
				"heading": _heading_mod_pi(centerline[start].direction_to(centerline[end]).angle()),
			})
	return runs


func _straight_run_headings(centerline: PackedVector2Array) -> PackedFloat32Array:
	var headings := PackedFloat32Array()
	for run: Dictionary in _straight_runs(centerline):
		headings.append(float(run["heading"]))
	return headings


func _heading_family_count(centerline: PackedVector2Array) -> int:
	return _cluster_heading_count(_straight_run_headings(centerline))


func _cluster_heading_count(headings: PackedFloat32Array) -> int:
	var count := headings.size()
	if count == 0:
		return 0
	var parent := PackedInt32Array()
	for i in count:
		parent.append(i)
	for i in count:
		for j in range(i + 1, count):
			if _heading_distance(headings[i], headings[j]) < HEADING_FAMILY_SEPARATION:
				var root_i := _heading_find_root(parent, i)
				var root_j := _heading_find_root(parent, j)
				if root_i != root_j:
					parent[root_i] = root_j
	var roots := {}
	for i in count:
		roots[_heading_find_root(parent, i)] = true
	return roots.size()


func _heading_find_root(parent: PackedInt32Array, index: int) -> int:
	while parent[index] != index:
		parent[index] = parent[parent[index]]
		index = parent[index]
	return index


func _heading_mod_pi(angle: float) -> float:
	return fposmod(angle, PI)


func _heading_distance(first: float, second: float) -> float:
	var delta := absf(fposmod(first - second, PI))
	return minf(delta, PI - delta)


func _verify_directional_fixtures() -> bool:
	# Synthetic controls that run the detector directly: a rotated orthogonal U
	# (infield) must resolve to exactly two heading families whatever its global
	# rotation, while a skewed/asymmetric route (one slanted side) must resolve
	# to three. A uniform shear/parallelogram would still only have two families,
	# so a passing detector is detecting real directional variety, not rotation.
	var rotations: Array[float] = [0.0, 0.73, 1.61, 2.94]
	var orthogonal := PackedVector2Array([
		Vector2(-600, -400), Vector2(-150, -400), Vector2(-150, 150),
		Vector2(150, 150), Vector2(150, -400), Vector2(600, -400),
		Vector2(600, 400), Vector2(-600, 400),
	])
	var skewed := PackedVector2Array([
		Vector2(-600, -400), Vector2(600, -400), Vector2(600, 400), Vector2(-600, 0),
	])
	for rotation: float in rotations:
		var ortho_centerline := TRACK_SEED_GEN.centerline_checkpoints(_rounded_corner_controls(_rotated_points(orthogonal, rotation), 80.0))
		var ortho_families := _heading_family_count(ortho_centerline)
		if not _expect(ortho_families == 2, "rotated orthogonal U fixture must resolve to exactly two heading families, got %d at %.2f rad" % [ortho_families, rotation]):
			return false
		var skew_centerline := TRACK_SEED_GEN.centerline_checkpoints(_rounded_corner_controls(_rotated_points(skewed, rotation), 80.0))
		var skew_families := _heading_family_count(skew_centerline)
		if not _expect(skew_families >= MIN_HEADING_FAMILIES, "skewed/asymmetric fixture must resolve to at least %d heading families, got %d at %.2f rad" % [MIN_HEADING_FAMILIES, skew_families, rotation]):
			return false
	return true


func _rotated_points(points: PackedVector2Array, angle: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(point.rotated(angle))
	return result


func _rounded_corner_controls(vertices: PackedVector2Array, radius: float) -> PackedVector2Array:
	# Fixture-only rounded-corner control builder mirroring the generator's
	# round_corners shape (arc + collinear straight) so the fixtures exercise the
	# same Catmull sampling the detector sees in production.
	if vertices.size() < 3:
		return PackedVector2Array()
	var entries := PackedVector2Array()
	var exits := PackedVector2Array()
	var centers := PackedVector2Array()
	var turns := PackedFloat32Array()
	for i in vertices.size():
		var previous := vertices[posmod(i - 1, vertices.size())]
		var corner := vertices[i]
		var following := vertices[(i + 1) % vertices.size()]
		var incoming := previous.direction_to(corner)
		var outgoing := corner.direction_to(following)
		var turn := incoming.angle_to(outgoing)
		var tangent := radius * tan(absf(turn) * 0.5)
		tangent = minf(tangent, minf(previous.distance_to(corner), corner.distance_to(following)) * 0.45)
		entries.append(corner - incoming * tangent)
		exits.append(corner + outgoing * tangent)
		centers.append(entries[i] + incoming.rotated(signf(turn) * PI * 0.5) * radius)
		turns.append(turn)
	var controls := PackedVector2Array()
	for i in vertices.size():
		var radial := entries[i] - centers[i]
		var arc_steps := maxi(4, ceili(radius * absf(turns[i]) / 50.0))
		for step in arc_steps:
			controls.append(centers[i] + radial.rotated(turns[i] * float(step) / float(arc_steps)))
		var next_entry := entries[(i + 1) % vertices.size()]
		var straight_length := exits[i].distance_to(next_entry)
		var line_steps := maxi(1, ceili(straight_length / 50.0))
		for step in line_steps:
			controls.append(exits[i].lerp(next_entry, float(step) / float(line_steps)))
	return controls


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_ROUTE_VARIETY_TEST FAIL: " + message)
	quit(1)
	return false