extends SceneTree

const SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")
const SAMPLER := preload("res://scripts/race/track_curve_sampling.gd")

const ROOM_RECT := Rect2(-940.0, -540.0, 1880.0, 1080.0)
const SHAPE_SAMPLE_COUNT := 32
const DISTINCT_SHAPE_DISTANCE := 0.06

static var ROOM_SHAPES := {
	"classic": PackedVector2Array([Vector2(-875, -575) * 1.75, Vector2(875, -575) * 1.75, Vector2(875, 575) * 1.75, Vector2(-875, 575) * 1.75]),
	"wide": PackedVector2Array([Vector2(-1175, -600) * 1.75, Vector2(1175, -600) * 1.75, Vector2(1175, 600) * 1.75, Vector2(-1175, 600) * 1.75]),
	"tall": PackedVector2Array([Vector2(-575, -725) * 1.75, Vector2(575, -725) * 1.75, Vector2(575, 725) * 1.75, Vector2(-575, 725) * 1.75]),
	"long": PackedVector2Array([Vector2(-1300, -550) * 1.75, Vector2(1300, -550) * 1.75, Vector2(1300, 550) * 1.75, Vector2(-1300, 550) * 1.75]),
	"square": PackedVector2Array([Vector2(-750, -750) * 1.75, Vector2(750, -750) * 1.75, Vector2(750, 750) * 1.75, Vector2(-750, 750) * 1.75]),
	"el": PackedVector2Array([Vector2(-1200, -700) * 1.75, Vector2(360, -700) * 1.75, Vector2(360, -60) * 1.75, Vector2(1200, -60) * 1.75, Vector2(1200, 700) * 1.75, Vector2(-1200, 700) * 1.75]),
}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _test_profile_bands():
		return
	if not _test_tier_coverage():
		return
	if not _test_safe_sampling():
		return
	if not _test_el_shape_variance():
		return
	if not _test_compact_el_real_infield():
		return
	print("TRACK_LENGTH_PROFILES_TEST PASS")
	quit(0)


func _test_profile_bands() -> bool:
	for tier: String in ["compact", "standard", "long", "endurance"]:
		var profile := SEED_GEN.length_profile(StringName(tier))
		if not _expect(not profile.is_empty(), "length_profile(%s) should resolve" % tier):
			return false
		if not _expect(profile.has("min_length") and profile.has("max_length") and profile.has("room_scale"), "%s profile should expose band + room_scale" % tier):
			return false
		if not _expect(float(profile["min_length"]) < float(profile["max_length"]), "%s band should be ordered" % tier):
			return false
	if not _expect(SEED_GEN.length_profile(StringName("bogus")).is_empty(), "invalid tier should resolve empty"):
		return false
	return true


func _test_tier_coverage() -> bool:
	# Each of the four tiers must land selected seeds in-band across the room set.
	for tier: String in ["compact", "standard", "long", "endurance"]:
		var profile := SEED_GEN.length_profile(StringName(tier))
		var room_scale := float(profile["room_scale"])
		for room_name: String in ROOM_SHAPES:
			var scaled := PackedVector2Array()
			for point: Vector2 in ROOM_SHAPES[room_name]:
				scaled.append(point * room_scale)
			var in_band := 0
			# Unseen window seeds so a pass is not a single lucky fixture.
			for seed in range(100000, 100000 + 5):
				var params := {
					"margin": 190.0,
					"min_self_distance": 320.0,
					"min_loop_length": 1900.0 * SEED_GEN.WORLD_SCALE,
					"room_polygon": scaled,
					"room_shape": StringName(room_name),
					"length_tier": StringName(tier),
				}
				var result := SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
				var points: PackedVector2Array = result["points"]
				if not _expect(not points.is_empty(), "%s/%s seed %d must generate a valid loop" % [tier, room_name, seed]):
					return false
				if not _expect(StringName(result.get("length_tier", &"")) == StringName(tier), "%s/%s should retain the requested tier metadata" % [tier, room_name]):
					return false
				var length := float(result["length"])
				if length >= float(profile["min_length"]) and length <= float(profile["max_length"]):
					in_band += 1
			if not _expect(in_band == 5, "%s/%s must land every selected seed in-band (got %d/5)" % [tier, room_name, in_band]):
				return false
	return true


func _test_safe_sampling() -> bool:
	var room: PackedVector2Array = ROOM_SHAPES["classic"]
	var params := {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1900.0 * SEED_GEN.WORLD_SCALE,
		"room_polygon": room,
		"room_shape": StringName("classic"),
		"length_tier": StringName("standard"),
	}
	for seed in [0, 11, 29]:
		var result := SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
		var controls: PackedVector2Array = result["points"]
		if not _expect(not controls.is_empty(), "sampling fixture seed %d must generate" % seed):
			return false
		var centerline := SEED_GEN.centerline_checkpoints(controls)
		if not _expect(centerline.size() >= 260, "seed %d centerline should be arc-length-uniform at >=260 samples (got %d)" % [seed, centerline.size()]):
			return false
		var max_gap := 0.0
		for index in centerline.size():
			max_gap = maxf(max_gap, centerline[index].distance_to(centerline[(index + 1) % centerline.size()]))
		if not _expect(max_gap <= 35.0 + 1.0, "seed %d centerline should respect the 35u max spacing (got %.1f)" % [seed, max_gap]):
			return false
		# The public checkpoints must be the same distance-aware geometry the
		# shared sampler produces for the built road, not a fixed-260 shortcut.
		var direct := SAMPLER.sample(controls)
		if not _expect(direct == centerline, "seed %d checkpoints should equal the shared sampler output" % seed):
			return false
	return true


func _test_el_shape_variance() -> bool:
	var room: PackedVector2Array = ROOM_SHAPES["el"]
	var params := {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1500.0 * SEED_GEN.WORLD_SCALE,
		"room_polygon": room,
		"room_shape": StringName("el"),
		"length_tier": StringName("standard"),
	}
	var shapes: Array[PackedVector2Array] = []
	for seed in [0, 5, 11, 17, 29, 3, 7, 13]:
		var result := SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
		var points: PackedVector2Array = result["points"]
		if points.is_empty() or bool(result.get("fallback", false)):
			continue
		var centerline := SEED_GEN.centerline_checkpoints(points)
		shapes.append(_arc_resample(centerline, SHAPE_SAMPLE_COUNT))
	if not _expect(shapes.size() >= 3, "seeded EL routes should produce at least three distinct shapes (got %d)" % shapes.size()):
		return false
	var distinct := 0
	for index in shapes.size():
		var unique := true
		for other in range(index):
			if _shape_distance(shapes[index], shapes[other]) < DISTINCT_SHAPE_DISTANCE:
				unique = false
				break
		if unique:
			distinct += 1
	if not _expect(distinct >= 3, "seeded EL routes should be mutually distinct (got %d distinct of %d)" % [distinct, shapes.size()]):
		return false
	return true


func _test_compact_el_real_infield() -> bool:
	# Regression (GURI-657): compact EL used only the shallow bottom/wide arm, so
	# some seeds fell through to the oval technical_perimeter and lost their real
	# infield (seed 39608 read hull deficit 0.03 / depth 194). The left/tall arm
	# now hosts the compact route, so the seeded dogleg/U keeps a substantial
	# infield pocket. Assert the geometry directly (hull deficit + deepest pocket),
	# never the recipe/fallback label: a technical-perimeter fallback can still
	# carry a real excursion, so a label check would both over- and under-reject.
	var room: PackedVector2Array = ROOM_SHAPES["el"]
	var room_scale := float(SEED_GEN.length_profile(StringName("compact"))["room_scale"])
	var scaled := PackedVector2Array()
	for point: Vector2 in room:
		scaled.append(point * room_scale)
	var params := {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1900.0 * SEED_GEN.WORLD_SCALE,
		"room_polygon": scaled,
		"room_shape": StringName("el"),
		"length_tier": StringName("compact"),
	}
	var profile := SEED_GEN.length_profile(StringName("compact"))
	for seed in [39608, 72777, 81111, 93939, 654321]:
		var result := SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
		var points: PackedVector2Array = result["points"]
		if not _expect(not points.is_empty(), "compact EL seed %d must generate a valid loop" % seed):
			return false
		var length := float(result["length"])
		if not _expect(length >= float(profile["min_length"]) and length <= float(profile["max_length"]), "compact EL seed %d must land in-band (got %.1f)" % [seed, length]):
			return false
		var centerline := SEED_GEN.centerline_checkpoints(points)
		var metrics := _hull_deficit_and_depth(centerline)
		if not _expect(float(metrics[0]) >= 0.10, "compact EL seed %d hull deficit %.3f should be >= 0.10 (a real infield, not an oval)" % [seed, metrics[0]]):
			return false
		if not _expect(float(metrics[1]) >= SEED_GEN.HALF_WIDTH * 2.0, "compact EL seed %d deepest pocket %.1f should be >= %.0fu" % [seed, metrics[1], SEED_GEN.HALF_WIDTH * 2.0]):
			return false
	return true


func _hull_deficit_and_depth(points: PackedVector2Array) -> Array:
	# Rotation-independent infield quality: the convex-hull area shortfall and the
	# deepest point's distance from the nearest hull edge.
	var hull := Geometry2D.convex_hull(points)
	var hull_area := absf(SEED_GEN._polygon_area(hull))
	var area := absf(SEED_GEN._polygon_area(points))
	var deficit := 1.0 - area / hull_area if hull_area >= 1.0 else 0.0
	var deepest := 0.0
	for point: Vector2 in points:
		var distance := INF
		for i in range(hull.size() - 1):
			distance = minf(distance, SEED_GEN._point_segment_distance(point, hull[i], hull[i + 1]))
		deepest = maxf(deepest, distance)
	return [deficit, deepest]


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


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_LENGTH_PROFILES_TEST FAIL: " + message)
	quit(1)
	return false
