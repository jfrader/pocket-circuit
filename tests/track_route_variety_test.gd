extends SceneTree

const TRACK_SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")
const ROOM_RECT := Rect2(-940.0, -540.0, 1880.0, 1080.0)
const SHAPE_SAMPLE_COUNT := 32
const DISTINCT_SHAPE_DISTANCE := 0.055

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
	var recipes := {}
	var sequences := {}
	var representatives := {}
	var program_variants := {}
	var svg_representatives := {}
	var non_axis_headings := 0
	var minimum_control_count := 999
	var maximum_control_count := 0
	for seed in 24:
		var result := TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, _room_params("classic"))
		if not _check_result("classic", seed, result, seed < 4):
			return
		if bool(result.get("fallback", false)):
			continue
		var recipe := String(result.get("route_recipe", "none"))
		var program := String(result.get("route_program", "none"))
		var sequence := String(result.get("route_sequence", ""))
		var centerline := TRACK_SEED_GEN.centerline_checkpoints(result["points"])
		minimum_control_count = mini(minimum_control_count, (result["points"] as PackedVector2Array).size())
		maximum_control_count = maxi(maximum_control_count, (result["points"] as PackedVector2Array).size())
		recipes[recipe] = true
		sequences[sequence] = true
		if not representatives.has(recipe):
			representatives[recipe] = centerline
		if not program_variants.has(program):
			program_variants[program] = []
		(program_variants[program] as Array).append(centerline)
		if (program_variants[program] as Array).size() <= 4:
			svg_representatives["%s_seed_%d" % [program, seed]] = centerline
		if _off_axis_heading(centerline) >= 0.05:
			non_axis_headings += 1

	if not _expect(recipes.size() >= 8, "24 classic seeds should realize at least eight complete route programs, got %s" % [recipes.keys()]):
		return
	if not _expect(sequences.size() >= 8, "normalized turn/straight signatures should contain at least eight rhythms, got %d" % sequences.size()):
		return
	if not _expect(non_axis_headings >= 12, "at least half of classic routes should put their longest straight on a meaningful non-axis heading, got %d" % non_axis_headings):
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
	if not _expect(varied_programs >= 3 and strongest_program_cluster >= 3, "macro parameters should create multiple invariant shapes within each program (varied=%d strongest=%d %s)" % [varied_programs, strongest_program_cluster, " ".join(program_cluster_evidence)]):
		return

	var clusters: Array[PackedVector2Array] = []
	for recipe: String in representatives:
		var candidate: PackedVector2Array = representatives[recipe]
		var distinct := true
		for existing: PackedVector2Array in clusters:
			if _shape_distance(candidate, existing) < DISTINCT_SHAPE_DISTANCE:
				distinct = false
				break
		if distinct:
			clusters.append(candidate)
	if not _expect(clusters.size() >= 6, "rotation/mirror/scale-invariant shape distance should retain at least six material macro shapes, got %d from %d recipes" % [clusters.size(), representatives.size()]):
		return

	var transformed := PackedVector2Array()
	for point: Vector2 in clusters[0]:
		transformed.append(Vector2(-point.x, point.y).rotated(0.73) * 1.8 + Vector2(431.0, -287.0))
	if not _expect(_shape_distance(clusters[0], transformed) < 0.002, "shape distance must discount translation, scale, rotation, and mirror-only changes"):
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
	print("TRACK_ROUTE_VARIETY_TEST PASS recipes=%d sequences=%d shape_clusters=%d within_programs=%d/%d strongest=%d off_axis=%d controls=%d..%d matrix=%d diagnostics=%d" % [recipes.size(), sequences.size(), clusters.size(), varied_programs, program_variants.size(), strongest_program_cluster, non_axis_headings, minimum_control_count, maximum_control_count, matrix_count, diagnostic_cases.size()])
	quit(0)


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


func _write_svg(path: String, representatives: Dictionary) -> void:
	var names: Array = representatives.keys()
	names.sort()
	var rows := ceili(float(names.size()) / 4.0)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="960" height="%d" viewBox="0 0 960 %d"><rect width="100%%" height="100%%" fill="#111316"/>' % [rows * 180, rows * 180]
	for index in names.size():
		var name := String(names[index])
		var points: PackedVector2Array = representatives[name]
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point: Vector2 in points:
			bounds = bounds.expand(point)
		var scale := minf(200.0 / maxf(bounds.size.x, 1.0), 120.0 / maxf(bounds.size.y, 1.0))
		var origin := Vector2(120.0 + float(index % 4) * 240.0, 82.0 + float(index / 4) * 180.0)
		var svg_points := PackedStringArray()
		for point: Vector2 in points:
			var mapped := origin + (point - bounds.get_center()) * scale
			svg_points.append("%.1f,%.1f" % [mapped.x, mapped.y])
		svg += '<polyline points="%s" fill="none" stroke="#f5c451" stroke-width="5" stroke-linejoin="round"/>' % " ".join(svg_points)
		svg += '<text x="%.1f" y="%.1f" fill="#f3f1ea" font-family="sans-serif" font-size="16" text-anchor="middle">%s</text>' % [origin.x, origin.y + 76.0, name]
	svg += "</svg>"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(svg)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_ROUTE_VARIETY_TEST FAIL: " + message)
	quit(1)
	return false
