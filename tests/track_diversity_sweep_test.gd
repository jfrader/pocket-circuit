extends SceneTree

## Track diversity sweep: measures topological variety of generated circuits
## across EVERY room shape and EVERY length tier (the general problem, not
## marathon-only). Reports distinct route sequences (canonical turn/straight
## rhythms) and shape-similarity clusters per cell, plus turn/straight
## distributions and any generation failures.
##
## Default 4 seeds per cell; PC_DIVERSITY_SEEDS=1..200 expands the baseline.
## Sequence signatures are sampling-sensitive, NOT counts of macro topologies.
## Also report collapsed L/R/S rhythms and 128-point normalized shape clusters.
## Shape distance follows track_length_profiles_test, caching normalization and
## solving the best rotation analytically. Clusters use seed-order greedy reps;
## they are threshold-dependent estimates, not equivalence classes.
##
## Run:
##   godot --path . --headless --script res://tests/track_diversity_sweep_test.gd
##   PC_DIVERSITY_SEEDS=40 godot --path . --headless --script res://tests/track_diversity_sweep_test.gd
##
## Output includes per-cell lines and a baseline table. Ends with
## TRACK_DIVERSITY_SWEEP_TEST PASS ...
##
## Low diversity is diagnostic; generation or validation failures fail the test.

const TRACK_SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")
const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const CATALOG := preload("res://scripts/race/track_builder_catalog.gd")

const SAMPLE_SEEDS := 4
const SHAPE_SAMPLE_COUNT := 128
const DISTINCT_SHAPE_DISTANCE := 0.055

const ROOMS: Array[String] = GENERATED_RULES.ROOMS
const TIERS: Array[String] = GENERATED_RULES.LENGTH_TIERS


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var started := Time.get_ticks_msec()
	if not _test_measurements():
		return
	var seed_count: int = SAMPLE_SEEDS
	var requested := OS.get_environment("PC_DIVERSITY_SEEDS")
	if not requested.is_empty():
		if not _expect(requested.is_valid_int() and int(requested) >= 1 and int(requested) <= 200, "PC_DIVERSITY_SEEDS must be 1..200"):
			return
		seed_count = int(requested)

	var per_cell: Dictionary = {}
	var total_fails: int = 0
	var total_seq: int = 0
	var total_shapes: int = 0
	var total_invalid := 0
	var all_failing_seeds: Dictionary = {}

	print("TRACK_DIVERSITY_SWEEP seeds_per_cell=%d rooms=%d tiers=%d" % [seed_count, ROOMS.size(), TIERS.size()])
	print("room/tier | seq | rhythms | shapes | fails | avg_L_runs | avg_R_runs | avg_literal_S | min_turn_runs | max_turn_runs")

	for room: String in ROOMS:
		for tier: String in TIERS:
			var cell: String = "%s/%s" % [room, tier]
			var seq_set: Dictionary = {}
			var rhythm_set: Dictionary = {}
			var shape_reps: Array[PackedVector2Array] = []
			var fail_list: Array = []
			var programs := {}
			var turn_hist := {}
			var straight_hist := {}
			var fallback_count := 0
			var sum_l := 0
			var sum_r := 0
			var sum_s := 0
			var n_samples := 0
			var min_turns := 999
			var max_turns := 0

			var profile: Dictionary = TRACK_SEED_GEN.length_profile(tier)
			if not _expect(not profile.is_empty(), "missing profile for tier %s" % tier):
				return
			var room_scale: float = float(profile.get("room_scale", 1.0))
			var poly: PackedVector2Array = CATALOG.ROOM_SHAPES[room]
			var scaled_poly: PackedVector2Array = PackedVector2Array()
			for p: Vector2 in poly:
				scaled_poly.append(p * room_scale)

			var params: Dictionary = {
				"margin": 190.0,
				"min_self_distance": 320.0,
				"min_loop_length": 1900.0 * TRACK_SEED_GEN.WORLD_SCALE,
				"room_polygon": scaled_poly,
				"room_shape": StringName(room),
				"length_tier": StringName(tier),
			}
			var room_rect: Rect2 = Rect2(-940.0, -540.0, 1880.0, 1080.0)
			match room:
				"el": params["min_loop_length"] = 1500.0 * TRACK_SEED_GEN.WORLD_SCALE
				"long": params["min_loop_length"] = 2000.0 * TRACK_SEED_GEN.WORLD_SCALE
				"square": params["min_loop_length"] = 2200.0 * TRACK_SEED_GEN.WORLD_SCALE

			for s in seed_count:
				var seed: int = s
				var res: Dictionary = TRACK_SEED_GEN.generate_with_retries(seed, room_rect, params)
				var pts: PackedVector2Array = res.get("points", PackedVector2Array())
				if pts.is_empty():
					fail_list.append(seed)
					total_fails += 1
					if not all_failing_seeds.has(cell):
						all_failing_seeds[cell] = []
					(all_failing_seeds[cell] as Array).append(seed)
					print("GENERATION_FAIL %s seed=%d reason=%s" % [cell, seed, res.get("reason", "unknown")])
					continue

				var validation := TRACK_SEED_GEN._validate_controls(
					pts, TRACK_SEED_GEN._points_rect(scaled_poly), scaled_poly,
					TRACK_SEED_GEN.CORRIDOR_CLEARANCE, 320.0, float(params["min_loop_length"])
				)
				if not bool(validation["valid"]) or int(res.get("seed", -1)) != seed:
					total_invalid += 1
					print("INVALID_CIRCUIT %s seed=%d reason=%s" % [cell, seed, validation.get("reason", "seed identity changed")])
				var seq: String = String(res.get("route_sequence", ""))
				if seq.is_empty():
					total_invalid += 1
					print("INVALID_CIRCUIT %s seed=%d empty sequence" % [cell, seed])
				seq_set[seq] = true
				var rhythm := _turn_runs(seq)
				rhythm_set[TRACK_SEED_GEN._canonical_symbol_sequence(rhythm)] = true
				# L/R are canonical handedness, not the race's travel direction.
				sum_l += rhythm.count("L")
				sum_r += rhythm.count("R")
				var centerline := TRACK_SEED_GEN.centerline_checkpoints(pts)
				var s_count := TRACK_SEED_GEN._literal_straight_count(centerline)
				sum_s += s_count
				var total_turns: int = rhythm.count("L") + rhythm.count("R")
				_increment(turn_hist, total_turns)
				_increment(straight_hist, s_count)
				_increment(programs, String(res.get("route_program", "unknown")))
				fallback_count += int(bool(res.get("fallback", false)))
				min_turns = mini(min_turns, total_turns)
				max_turns = maxi(max_turns, total_turns)
				n_samples += 1

				var shape := _normalized_shape(centerline)
				var is_distinct: bool = true
				for rep: PackedVector2Array in shape_reps:
					if _shape_distance(shape, rep) < DISTINCT_SHAPE_DISTANCE:
						is_distinct = false
						break
				if is_distinct:
					shape_reps.append(shape)

			var d_seq: int = seq_set.size()
			var d_shape: int = shape_reps.size()
			total_seq += d_seq
			total_shapes += d_shape

			var avg_l: float = float(sum_l) / maxf(1, n_samples)
			var avg_r: float = float(sum_r) / maxf(1, n_samples)
			var avg_s: float = float(sum_s) / maxf(1, n_samples)
			if n_samples == 0:
				min_turns = 0
				max_turns = 0

			per_cell[cell] = {
				"seq": d_seq,
				"shapes": d_shape,
			}

			print("%-18s | %3d | %3d | %3d | %2d | %5.1f | %5.1f | %5.1f | %2d | %2d" % [
				cell, d_seq, rhythm_set.size(), d_shape, fail_list.size(), avg_l, avg_r, avg_s, min_turns, max_turns
			])
			print("DISTRIBUTION %s turns=%s literal_straights=%s programs=%s fallbacks=%d" % [
				cell, JSON.stringify(turn_hist, "", true), JSON.stringify(straight_hist, "", true), JSON.stringify(programs, "", true), fallback_count
			])

	# Baseline table
	print("\n=== BASELINE (room x tier -> sampled sequences / shape clusters; NOT exact topology counts) ===")
	print("Seeds per cell: %d   Distinct threshold for shapes: < %.3f normalized rms" % [seed_count, DISTINCT_SHAPE_DISTANCE])
	var header: String = "room      "
	for t: String in TIERS:
		header += "  %11s" % t
	print(header)
	print("".lpad(header.length(), "-"))
	for room: String in ROOMS:
		var line: String = "%-9s" % room
		for t: String in TIERS:
			var c: Dictionary = per_cell.get("%s/%s" % [room, t], {})
			var val: String = "%d/%d" % [c.get("seq", 0), c.get("shapes", 0)]
			line += "  %11s" % val
		print(line)

	print("\nTotals: cells=%d  sum_distinct_seq=%d  sum_distinct_shapes=%d  generation_fails=%d" % [
		per_cell.size(), total_seq, total_shapes, total_fails
	])

	if total_fails > 0:
		print("FAILING SEEDS (report these for triage):")
		for cell in all_failing_seeds:
			print("  %s: %s" % [cell, all_failing_seeds[cell]])

	print("TRACK_DIVERSITY_SWEEP elapsed_ms=%d invalid=%d" % [Time.get_ticks_msec() - started, total_invalid])
	if not _expect(total_fails == 0 and total_invalid == 0, "%d generation failures, %d invalid circuits" % [total_fails, total_invalid]):
		return
	print("TRACK_DIVERSITY_SWEEP_TEST PASS cells=%d seq=%d shapes=%d fails=%d seeds_per=%d" % [
		per_cell.size(), total_seq, total_shapes, total_fails, seed_count
	])
	quit(0)


func _increment(histogram: Dictionary, key: Variant) -> void:
	histogram[key] = int(histogram.get(key, 0)) + 1


func _turn_runs(sequence: String) -> Array[String]:
	var runs: Array[String] = []
	for token: String in sequence.split(".", false):
		var hand := token.substr(0, 1)
		if runs.is_empty() or runs.back() != hand:
			runs.append(hand)
	if runs.size() > 1 and runs.front() == runs.back():
		runs.pop_back()
	return runs


func _shape_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best: float = INF
	for reflected in 2:
		for direction: int in [1, -1]:
			for shift in SHAPE_SAMPLE_COUNT:
				var dot_sum: float = 0.0
				var cross_sum: float = 0.0
				for index in SHAPE_SAMPLE_COUNT:
					var other: Vector2 = b[posmod(shift + direction * index, SHAPE_SAMPLE_COUNT)]
					if reflected == 1:
						other.x *= -1.0
					dot_sum += other.dot(a[index])
					cross_sum += other.cross(a[index])
				var correlation := Vector2(dot_sum, cross_sum).length() / float(SHAPE_SAMPLE_COUNT)
				best = minf(best, sqrt(maxf(0.0, 2.0 - 2.0 * correlation)))
				if best < 0.001:
					return best
	return best


func _normalized_shape(points: PackedVector2Array) -> PackedVector2Array:
	var sampled: PackedVector2Array = _arc_resample(points, SHAPE_SAMPLE_COUNT)
	var center: Vector2 = Vector2.ZERO
	for point: Vector2 in sampled:
		center += point
	center /= float(sampled.size())
	var rms: float = 0.0
	for point: Vector2 in sampled:
		rms += point.distance_squared_to(center)
	rms = sqrt(rms / float(sampled.size()))
	for index in sampled.size():
		sampled[index] = (sampled[index] - center) / maxf(rms, 0.001)
	return sampled


func _arc_resample(points: PackedVector2Array, count: int) -> PackedVector2Array:
	var cumulative: PackedFloat32Array = PackedFloat32Array([0.0])
	for index in points.size():
		cumulative.append(cumulative[index] + points[index].distance_to(points[(index + 1) % points.size()]))
	var result: PackedVector2Array = PackedVector2Array()
	var segment: int = 0
	for output in count:
		var target: float = cumulative[points.size()] * float(output) / float(count)
		while segment < points.size() - 1 and cumulative[segment + 1] < target:
			segment += 1
		var fraction: float = (target - cumulative[segment]) / maxf(cumulative[segment + 1] - cumulative[segment], 0.001)
		result.append(points[segment].lerp(points[(segment + 1) % points.size()], fraction))
	return result


func _test_measurements() -> bool:
	if not _expect(_turn_runs("L1.L2.S.S.R2.R1.L3") == ["L", "S", "R"], "turn runs must merge strength bins and the cyclic seam"):
		return false
	if not _expect(_turn_runs("").is_empty() and _turn_runs("S.S.S") == ["S"], "empty and single-run signatures"):
		return false
	var polygon := PackedVector2Array([
		Vector2(-900, -600), Vector2(-100, -600), Vector2(-100, 50),
		Vector2(900, 50), Vector2(900, 600), Vector2(-900, 600),
	])
	var shape := _normalized_shape(polygon)
	var transformed := PackedVector2Array()
	for point: Vector2 in polygon:
		transformed.append(Vector2(-point.x, point.y).rotated(0.73) * 1.8 + Vector2(431, -287))
	if not _expect(_shape_distance(shape, _normalized_shape(transformed)) < 0.002, "shape metric must discount mirror/rotation/translation/scale"):
		return false
	var reversed := PackedVector2Array()
	for i in polygon.size():
		reversed.append(polygon[posmod(2 - i, polygon.size())])
	if not _expect(_shape_distance(shape, _normalized_shape(reversed)) < DISTINCT_SHAPE_DISTANCE, "shape metric must discount traversal and shifted starting vertex"):
		return false
	var oval := PackedVector2Array()
	for i in SHAPE_SAMPLE_COUNT:
		oval.append(Vector2(cos(TAU * i / SHAPE_SAMPLE_COUNT) * 900, sin(TAU * i / SHAPE_SAMPLE_COUNT) * 600))
	return _expect(_shape_distance(shape, _normalized_shape(oval)) > DISTINCT_SHAPE_DISTANCE, "shape metric must distinguish a dogleg from an oval")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_DIVERSITY_SWEEP_TEST FAIL: " + message)
	quit(1)
	return false
