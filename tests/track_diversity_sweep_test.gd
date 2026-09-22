extends SceneTree

## Track diversity sweep: measures topological variety of generated circuits
## across EVERY room shape and EVERY length tier (the general problem, not
## marathon-only). Reports distinct route sequences (canonical turn/straight
## rhythms) and shape-similarity clusters per cell, plus turn/straight
## distributions and any generation failures.
##
## Default 4 seeds per cell; PC_DIVERSITY_SEEDS=1..200 expands the baseline.
## PC_DIVERSITY_GENERATOR=7|8, PC_DIVERSITY_START, PC_DIVERSITY_CELL=room/tier,
## and PC_DIVERSITY_SHARD=index/count select reproducible farm slices.
## PC_DIVERSITY_OUTPUT writes one JSON shard document. PC_DIVERSITY_INPUTS
## (comma-separated documents) validates and aggregates a complete shard set.
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
const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const REGISTRY := preload("res://scripts/race/track_generator_registry.gd")
const V8_GENERATOR := preload("res://scripts/race/track_v8_development_generator.gd")
const ROOM_MODEL := preload("res://scripts/race/track_room_model.gd")
const VALIDATION := preload("res://scripts/race/track_layout_validation.gd")
const SIGNATURES := preload("res://scripts/race/track_layout_signatures.gd")
const MODULES := preload("res://scripts/race/track_module_catalog.gd")

const SAMPLE_SEEDS := 4
const SHAPE_SAMPLE_COUNT := 128
const DISTINCT_SHAPE_DISTANCE := 0.055
const FARM_FORMAT := "pocket-circuit-expressive-range-v1"
const GENERATOR_VERSION := 7

const ROOMS: Array[String] = GENERATED_RULES.ROOMS
const TIERS: Array[String] = GENERATED_RULES.LENGTH_TIERS

var generator_version := GENERATOR_VERSION


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var started := Time.get_ticks_msec()
	if not _test_measurements():
		return
	var aggregate_inputs := OS.get_environment("PC_DIVERSITY_INPUTS")
	if not aggregate_inputs.is_empty():
		_run_offline_aggregation(aggregate_inputs)
		return
	var seed_count: int = SAMPLE_SEEDS
	var requested := OS.get_environment("PC_DIVERSITY_SEEDS")
	if not requested.is_empty():
		if not _expect(requested.is_valid_int() and int(requested) >= 1 and int(requested) <= 200, "PC_DIVERSITY_SEEDS must be 1..200"):
			return
		seed_count = int(requested)

	var config := _farm_config(seed_count)
	if not _expect(bool(config.get("ok", false)), String(config.get("error", "invalid farm configuration"))):
		return
	var seed_start := int(config["seed_start"])
	generator_version = int(config["generator"])
	var selected_cell := String(config["cell"])
	var shard_index := int(config["shard_index"])
	var shard_count := int(config["shard_count"])
	var per_cell: Dictionary = {}
	var records: Array[Dictionary] = []
	var total_fails: int = 0
	var total_seq: int = 0
	var total_shapes: int = 0
	var total_invalid := 0
	var all_failing_seeds: Dictionary = {}

	print("TRACK_DIVERSITY_SWEEP generator=%d seed_start=%d seeds_per_cell=%d cell=%s shard=%d/%d" % [generator_version, seed_start, seed_count, selected_cell if not selected_cell.is_empty() else "all", shard_index, shard_count])
	print("room/tier | seq | rhythms | shapes | fails | avg_L_runs | avg_R_runs | avg_literal_S | min_turn_runs | max_turn_runs")

	for room: String in ROOMS:
		for tier: String in TIERS:
			var cell: String = "%s/%s" % [room, tier]
			if not selected_cell.is_empty() and selected_cell != cell:
				continue
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
				"instrument_rejections": true,
			}
			var room_rect: Rect2 = Rect2(-940.0, -540.0, 1880.0, 1080.0)
			match room:
				"el": params["min_loop_length"] = 1500.0 * TRACK_SEED_GEN.WORLD_SCALE
				"long": params["min_loop_length"] = 2000.0 * TRACK_SEED_GEN.WORLD_SCALE
				"square": params["min_loop_length"] = 2200.0 * TRACK_SEED_GEN.WORLD_SCALE

			for s in seed_count:
				var case_ordinal := _case_ordinal(room, tier, s, seed_count, selected_cell)
				if posmod(case_ordinal, shard_count) != shard_index:
					continue
				var seed: int = seed_start + s
				var generation_started := Time.get_ticks_usec()
				var res: Dictionary = _generate_v8(room, tier, seed) if generator_version == 8 else TRACK_SEED_GEN.generate_with_retries(seed, room_rect, params)
				var case_polygon: PackedVector2Array = (res.get("room_model", {}) as Dictionary).get("outer", PackedVector2Array()) if generator_version == 8 else scaled_poly
				var generation_ms := (Time.get_ticks_usec() - generation_started) / 1000.0
				var pts: PackedVector2Array = res.get("points", PackedVector2Array())
				if pts.is_empty():
					fail_list.append(seed)
					total_fails += 1
					if not all_failing_seeds.has(cell):
						all_failing_seeds[cell] = []
					(all_failing_seeds[cell] as Array).append(seed)
					print("GENERATION_FAIL %s seed=%d reason=%s" % [cell, seed, res.get("reason", "unknown")])
					records.append(_case_record(room, tier, seed, case_polygon, res, {}, PackedVector2Array(), generation_ms, 0.0, &"generation_failed"))
					continue

				var validation_started := Time.get_ticks_usec()
				var validation := _validate_v8(res, room, tier, seed) if generator_version == 8 else TRACK_SEED_GEN._validate_controls(
					pts, TRACK_SEED_GEN._points_rect(scaled_poly), scaled_poly,
					TRACK_SEED_GEN.CORRIDOR_CLEARANCE, 320.0, float(params["min_loop_length"])
				)
				var validation_ms := (Time.get_ticks_usec() - validation_started) / 1000.0
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
				var centerline := pts if generator_version == 8 else TRACK_SEED_GEN.centerline_checkpoints(pts)
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
				records.append(_case_record(
					room, tier, seed, case_polygon, res, validation, shape,
					generation_ms, validation_ms,
					&"ok" if bool(validation["valid"]) and int(res.get("seed", -1)) == seed and not seq.is_empty() else &"invalid"
				))
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
	var expected_cases := _expected_shard_cases(seed_count, selected_cell, shard_index, shard_count)
	if not _expect(records.size() == expected_cases, "farm shard should retain every case, including failures (got %d/%d)" % [records.size(), expected_cases]):
		return
	var aggregation := _aggregate_records(records, generator_version)
	if not _expect(bool(aggregation.get("ok", false)), String(aggregation.get("error", "farm aggregation failed"))):
		return
	print("TRACK_DIVERSITY_AGGREGATE " + JSON.stringify(aggregation["summary"], "", true))
	var output_path := OS.get_environment("PC_DIVERSITY_OUTPUT")
	if not output_path.is_empty():
		var document := {
			"format": FARM_FORMAT,
			"generator": generator_version,
			"seed_start": seed_start,
			"seed_count": seed_count,
			"cell": selected_cell,
			"shard_index": shard_index,
			"shard_count": shard_count,
			"records": records,
			"summary": aggregation["summary"],
		}
		if not _expect(_write_json(output_path, document), "could not write PC_DIVERSITY_OUTPUT to %s" % output_path):
			return
		print("TRACK_DIVERSITY_OUTPUT path=%s records=%d" % [output_path, records.size()])
	if not _expect(total_fails == 0 and total_invalid == 0, "%d generation failures, %d invalid circuits" % [total_fails, total_invalid]):
		return
	print("TRACK_DIVERSITY_SWEEP_TEST PASS cells=%d seq=%d shapes=%d fails=%d seeds_per=%d" % [
		per_cell.size(), total_seq, total_shapes, total_fails, seed_count
	])
	quit(0)


func _farm_config(seed_count: int) -> Dictionary:
	var generator_text := OS.get_environment("PC_DIVERSITY_GENERATOR")
	if generator_text.is_empty():
		generator_text = str(GENERATOR_VERSION)
	if not generator_text.is_valid_int() or int(generator_text) not in [7, 8]:
		return {"ok": false, "error": "PC_DIVERSITY_GENERATOR must be 7 or 8"}
	var start_text := OS.get_environment("PC_DIVERSITY_START")
	if start_text.is_empty():
		start_text = "0"
	if not start_text.is_valid_int() or int(start_text) < 0 or int(start_text) + seed_count - 1 > GENERATED_RULES.MAX_SEED:
		return {"ok": false, "error": "PC_DIVERSITY_START must keep the selected seed window within 0..%d" % GENERATED_RULES.MAX_SEED}
	var cell := OS.get_environment("PC_DIVERSITY_CELL")
	if not cell.is_empty():
		var cell_parts := cell.split("/", false)
		if cell_parts.size() != 2 or not ROOMS.has(cell_parts[0]) or not TIERS.has(cell_parts[1]):
			return {"ok": false, "error": "PC_DIVERSITY_CELL must be room/tier using a supported value"}
	var shard_text := OS.get_environment("PC_DIVERSITY_SHARD")
	if shard_text.is_empty():
		shard_text = "0/1"
	var shard_parts := shard_text.split("/", false)
	if shard_parts.size() != 2 or not shard_parts[0].is_valid_int() or not shard_parts[1].is_valid_int():
		return {"ok": false, "error": "PC_DIVERSITY_SHARD must be index/count"}
	var shard_index := int(shard_parts[0])
	var shard_count := int(shard_parts[1])
	if shard_count < 1 or shard_index < 0 or shard_index >= shard_count:
		return {"ok": false, "error": "PC_DIVERSITY_SHARD requires 0 <= index < count"}
	return {
		"ok": true,
		"generator": int(generator_text),
		"seed_start": int(start_text),
		"cell": cell,
		"shard_index": shard_index,
		"shard_count": shard_count,
	}


func _case_ordinal(room: String, tier: String, seed_offset: int, seed_count: int, selected_cell: String) -> int:
	if not selected_cell.is_empty():
		return seed_offset
	return (ROOMS.find(room) * TIERS.size() + TIERS.find(tier)) * seed_count + seed_offset


func _expected_shard_cases(seed_count: int, selected_cell: String, shard_index: int, shard_count: int) -> int:
	var total := seed_count if not selected_cell.is_empty() else ROOMS.size() * TIERS.size() * seed_count
	var count := 0
	for ordinal in total:
		count += int(posmod(ordinal, shard_count) == shard_index)
	return count


func _expected_identity_keys(seed_start: int, seed_count: int, selected_cell: String) -> Dictionary:
	var expected := {}
	for room: String in ROOMS:
		for tier: String in TIERS:
			if not selected_cell.is_empty() and selected_cell != "%s/%s" % [room, tier]:
				continue
			for seed_offset in seed_count:
				expected["%d|%s|%s|%d" % [generator_version, room, tier, seed_start + seed_offset]] = true
	return expected


func _generate_v8(room: String, tier: String, seed: int) -> Dictionary:
	var identity := IDENTITIES.create_v8(&"kitchen", StringName(room), seed, false, 1, "", "", {}, tier)
	var options := IDENTITIES.generation_options(identity)
	var model := ROOM_MODEL.generate_recipe(StringName(room), int(identity["room_geometry_seed"]), StringName(tier))
	var result := REGISTRY.dispatch(options, {
		"seed": seed, "room_shape": StringName(room), "room_model": model,
		"room_polygon": model.get("outer", PackedVector2Array()), "generation_options": options,
	}, Callable(), Callable(V8_GENERATOR, "generate"), false)
	result["farm_identity"] = identity
	if not result.has("room_model"):
		result["room_model"] = model
	return result


func _validate_v8(result: Dictionary, room: String, tier: String, seed: int) -> Dictionary:
	var identity: Dictionary = result.get("identity", {})
	var model: Dictionary = result.get("room_model", {})
	var expected: Dictionary = result["farm_identity"]
	if int(identity.get("seed", -1)) != seed or identity.get("room_shape") != StringName(room) or identity.get("length_tier") != StringName(tier) or int(identity.get("room_geometry_seed", -1)) != int(expected["room_geometry_seed"]) or int(identity.get("generator_version", -1)) != 8 or int(identity.get("schema_version", -1)) != 2 or identity.get("room_digest") != ROOM_MODEL.polygon_digest(model):
		return {"valid": false, "reason": "v8 identity or room digest changed"}
	var route: Dictionary = result["analytic_route"]
	var placement := ROOM_MODEL.route_fits(model, route)
	if not bool(placement.get("valid", false)):
		return placement
	var continuous := VALIDATION.validate_continuous(route, model["outer"])
	if not bool(continuous.get("valid", false)):
		return continuous
	var band := GENERATED_RULES.length_profile(tier)
	if float(route["length"]) < float(band["min_length"]) or float(route["length"]) > float(band["max_length"]):
		return {"valid": false, "reason": "analytic length outside requested tier"}
	if result["points"] != result["sampling"]["points"]:
		return {"valid": false, "reason": "runtime samples differ from the analytic sampling"}
	if result["points"] != MODULES.sample_route(route)["points"]:
		return {"valid": false, "reason": "runtime samples do not evaluate the returned analytic route"}
	return VALIDATION.validate_sampled(route, result["sampling"], model["outer"])


func _case_record(
	room: String,
	tier: String,
	seed: int,
	room_polygon: PackedVector2Array,
	result: Dictionary,
	validation: Dictionary,
	shape: PackedVector2Array,
	generation_ms: float,
	validation_ms: float,
	status: StringName
) -> Dictionary:
	var diagnostics: Dictionary = result.get("generation_diagnostics", {})
	var sequence := String(result.get("route_sequence", ""))
	var turn_runs := _turn_runs(sequence)
	var record := {
		"identity": {"schema": 1, "generator": generator_version, "room": room, "tier": tier, "seed": seed},
		"generator": generator_version,
		"room": room,
		"tier": tier,
		"seed": seed,
		"room_digest": _packed_points_digest(room_polygon),
		"status": String(status),
		"reason": String(result.get("reason", validation.get("reason", ""))),
		"rejection_classes": (diagnostics.get("rejection_counts", {}) as Dictionary).duplicate(true),
		"rejections": (diagnostics.get("rejections", []) as Array).duplicate(true),
		"structural_signature": "",
		"profile_signature": JSON.stringify(result.get("corner_profiles", {}), "", true),
		"route_sequence": sequence,
		"rhythm_signature": TRACK_SEED_GEN._canonical_symbol_sequence(turn_runs),
		"primitive_count": null,
		"semantic_count": null,
		"control_count": (result.get("points", PackedVector2Array()) as PackedVector2Array).size(),
		"signed_turn_runs": turn_runs,
		"literal_straight_count": int(validation.get("literal_straight_count", 0)),
		"setup_straight_count": int(validation.get("setup_straight_count", 0)),
		"curvature_class_histogram": _curvature_class_histogram(sequence),
		"length": float(result.get("length", 0.0)),
		"region_occupancy": [],
		"portal_traversals": [],
		"minimum_portal_width": null,
		"shape_descriptor": _shape_descriptor(shape),
		"repair_count": 0,
		"expansion_count": 0,
		"attempt_count": int(result.get("attempt", -1)) + 1,
		"stage_times_ms": {"generation": generation_ms, "validation": validation_ms},
		"output_digest": _packed_points_digest(result.get("points", PackedVector2Array())),
	}
	if generator_version == 8:
		var search: Dictionary = result.get("search", {})
		var route: Dictionary = result.get("analytic_route", {})
		var classes := {}
		for module: Dictionary in route.get("modules", []):
			_increment(classes, String(module["id"]))
		var curvature := {"straight": 0, "tight": 0, "medium": 0, "sweeper": 0}
		for primitive: Dictionary in route.get("primitives", []):
			var radius := float(primitive.get("radius", INF))
			_increment(curvature, "straight" if primitive["kind"] == &"line" else ("tight" if radius < 260.0 else ("medium" if radius < 520.0 else "sweeper")))
		var minimum_width := INF
		for traversal: Dictionary in result.get("portal_traversals", []):
			minimum_width = minf(minimum_width, float(traversal["clear_width"]))
		record.merge({
			"identity": result["farm_identity"],
			"room_digest": (result.get("room_model", {}) as Dictionary).get("polygon_digest", ""),
			"failure_kind": result.get("kind", ""),
			"failure_stage": result.get("stage", ""),
			"structural_signature": result.get("structural_signature", ""),
			"profile_signature": result.get("profile_signature", ""),
			"primitive_count": (route.get("primitives", []) as Array).size(),
			"module_count": (route.get("modules", []) as Array).size(),
			"module_class_histogram": classes,
			"semantic_count": SIGNATURES.describe(route)["semantic_count"],
			"curvature_class_histogram": curvature,
			"minimum_portal_width": minimum_width if is_finite(minimum_width) else null,
			"region_occupancy": result.get("region_visits", []),
			"portal_traversals": result.get("portal_traversals", []),
			"expansion_count": search.get("placement_expansions", 0),
			"repair_count": search.get("repair_passes", 0),
			"search": search,
		}, true)
	return record


func _curvature_class_histogram(sequence: String) -> Dictionary:
	var histogram := {"straight": 0, "gentle": 0, "medium": 0, "tight": 0}
	for token: String in sequence.split(".", false):
		if token == "S":
			histogram["straight"] += 1
		elif token.ends_with("1"):
			histogram["gentle"] += 1
		elif token.ends_with("2"):
			histogram["medium"] += 1
		elif token.ends_with("3"):
			histogram["tight"] += 1
	return histogram


func _shape_descriptor(shape: PackedVector2Array) -> Array[float]:
	var descriptor: Array[float] = []
	for point: Vector2 in shape:
		descriptor.append(point.x)
		descriptor.append(point.y)
	return descriptor


func _shape_from_descriptor(descriptor: Array) -> PackedVector2Array:
	var shape := PackedVector2Array()
	for index in range(0, descriptor.size(), 2):
		shape.append(Vector2(float(descriptor[index]), float(descriptor[index + 1])))
	return shape


func _packed_points_digest(value: Variant) -> String:
	if value is not PackedVector2Array:
		return ""
	var points: PackedVector2Array = value
	if points.is_empty():
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(points.to_byte_array())
	return context.finish().hex_encode()


func _aggregate_records(records: Array[Dictionary], expected_generator: int) -> Dictionary:
	var ordered: Array[Dictionary] = records.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_cell := ROOMS.find(String(a.get("room", ""))) * TIERS.size() + TIERS.find(String(a.get("tier", "")))
		var b_cell := ROOMS.find(String(b.get("room", ""))) * TIERS.size() + TIERS.find(String(b.get("tier", "")))
		return int(a.get("seed", -1)) < int(b.get("seed", -1)) if a_cell == b_cell else a_cell < b_cell
	)
	var identities := {}
	var status_counts := {}
	var rejection_counts := {}
	var cells := {}
	var accepted_classes := {}
	var class_layouts := {}
	for record: Dictionary in ordered:
		if int(record.get("generator", -1)) != expected_generator:
			return {"ok": false, "error": "mismatched generator version in farm records"}
		var cell := "%s/%s" % [record.get("room", ""), record.get("tier", "")]
		if not ROOMS.has(String(record.get("room", ""))) or not TIERS.has(String(record.get("tier", ""))):
			return {"ok": false, "error": "unsupported cell in farm records: %s" % cell}
		var identity_key := "%d|%s|%s|%d" % [expected_generator, record.get("room", ""), record.get("tier", ""), int(record.get("seed", -1))]
		if identities.has(identity_key):
			return {"ok": false, "error": "duplicate farm identity: %s" % identity_key}
		identities[identity_key] = true
		_increment(status_counts, String(record.get("status", "unknown")))
		if not cells.has(cell):
			cells[cell] = {"cases": 0, "successes": 0, "structures": {}, "sequences": {}, "rhythms": {}, "shape_reps": [], "rejections": {}, "accepted_module_instances": {}, "accepted_class_layouts": {}}
		var aggregate: Dictionary = cells[cell]
		aggregate["cases"] = int(aggregate["cases"]) + 1
		for category: String in (record.get("rejection_classes", {}) as Dictionary):
			var count := int((record["rejection_classes"] as Dictionary)[category])
			(aggregate["rejections"] as Dictionary)[category] = int((aggregate["rejections"] as Dictionary).get(category, 0)) + count
			rejection_counts[category] = int(rejection_counts.get(category, 0)) + count
		if record.get("status") != "ok":
			continue
		aggregate["successes"] = int(aggregate["successes"]) + int(record.get("status") == "ok")
		for module_class: String in record.get("module_class_histogram", {}):
			var count := int(record["module_class_histogram"][module_class])
			if count <= 0:
				continue
			var instances: Dictionary = aggregate["accepted_module_instances"]
			instances[module_class] = int(instances.get(module_class, 0)) + count
			accepted_classes[module_class] = int(accepted_classes.get(module_class, 0)) + count
			_increment(aggregate["accepted_class_layouts"], module_class)
			_increment(class_layouts, module_class)
		var structure := String(record.get("structural_signature", ""))
		if not structure.is_empty():
			(aggregate["structures"] as Dictionary)[structure] = true
		var sequence := String(record.get("route_sequence", ""))
		if not sequence.is_empty():
			(aggregate["sequences"] as Dictionary)[sequence] = true
		var rhythm := String(record.get("rhythm_signature", ""))
		if not rhythm.is_empty():
			(aggregate["rhythms"] as Dictionary)[rhythm] = true
		var descriptor: Array = record.get("shape_descriptor", [])
		if descriptor.size() == SHAPE_SAMPLE_COUNT * 2:
			var shape := _shape_from_descriptor(descriptor)
			var distinct := true
			for representative: PackedVector2Array in aggregate["shape_reps"]:
				if _shape_distance(shape, representative) < DISTINCT_SHAPE_DISTANCE:
					distinct = false
					break
			if distinct:
				(aggregate["shape_reps"] as Array).append(shape)
	var cell_summaries := {}
	for cell: String in cells:
		var aggregate: Dictionary = cells[cell]
		cell_summaries[cell] = {
			"cases": aggregate["cases"],
			"successes": aggregate["successes"],
			"distinct_structures": (aggregate["structures"] as Dictionary).size(),
			"distinct_sequences": (aggregate["sequences"] as Dictionary).size(),
			"distinct_rhythms": (aggregate["rhythms"] as Dictionary).size(),
			"shape_clusters": (aggregate["shape_reps"] as Array).size(),
			"rejections": aggregate["rejections"],
			"accepted_module_instances": aggregate["accepted_module_instances"],
			"accepted_class_layouts": aggregate["accepted_class_layouts"],
		}
	return {"ok": true, "summary": {"cases": ordered.size(), "statuses": status_counts, "rejections": rejection_counts, "cells": cell_summaries, "accepted_module_instances": accepted_classes, "accepted_class_layouts": class_layouts}}


func _write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "", true))
	return true


func _run_offline_aggregation(input_list: String) -> void:
	var documents: Array[Dictionary] = []
	for path: String in input_list.split(",", false):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.strip_edges()))
		if not _expect(parsed is Dictionary, "PC_DIVERSITY_INPUTS contains unreadable JSON: %s" % path):
			return
		documents.append(parsed)
	if not _expect(not documents.is_empty(), "PC_DIVERSITY_INPUTS must name at least one shard document"):
		return
	var first: Dictionary = documents[0]
	if not _expect(first.get("format") == FARM_FORMAT and int(first.get("generator", -1)) in [7, 8], "farm documents must use a supported expressive-range format and generator"):
		return
	generator_version = int(first["generator"])
	var shard_count := int(first.get("shard_count", 0))
	var seen_shards := {}
	var records: Array[Dictionary] = []
	for document: Dictionary in documents:
		for key: String in ["format", "generator", "seed_start", "seed_count", "cell", "shard_count"]:
			if not _expect(document.get(key) == first.get(key), "farm shard manifests disagree on %s" % key):
				return
		var index := int(document.get("shard_index", -1))
		if not _expect(index >= 0 and index < shard_count and not seen_shards.has(index), "farm shard indexes must be unique and in range"):
			return
		seen_shards[index] = true
		for record: Dictionary in document.get("records", []):
			records.append(record)
	if not _expect(seen_shards.size() == shard_count, "farm aggregation requires all %d shards (got %d)" % [shard_count, seen_shards.size()]):
		return
	var expected := int(first["seed_count"]) * (1 if not String(first["cell"]).is_empty() else ROOMS.size() * TIERS.size())
	if not _expect(records.size() == expected, "farm aggregation is missing cases (got %d/%d)" % [records.size(), expected]):
		return
	var expected_identities := _expected_identity_keys(int(first["seed_start"]), int(first["seed_count"]), String(first["cell"]))
	var actual_identities := {}
	for record: Dictionary in records:
		var identity_key := "%d|%s|%s|%d" % [int(record.get("generator", -1)), record.get("room", ""), record.get("tier", ""), int(record.get("seed", -1))]
		if not _expect(expected_identities.has(identity_key), "farm aggregation contains an unexpected identity: %s" % identity_key):
			return
		actual_identities[identity_key] = true
	if not _expect(actual_identities.size() == expected_identities.size(), "farm aggregation is missing expected identities"):
		return
	var aggregation := _aggregate_records(records, generator_version)
	if not _expect(bool(aggregation.get("ok", false)), String(aggregation.get("error", "farm aggregation failed"))):
		return
	var output_path := OS.get_environment("PC_DIVERSITY_OUTPUT")
	if not output_path.is_empty() and not _expect(_write_json(output_path, {"format": FARM_FORMAT, "manifest": first, "summary": aggregation["summary"], "records": records}), "could not write aggregate output to %s" % output_path):
		return
	print("TRACK_DIVERSITY_AGGREGATE " + JSON.stringify(aggregation["summary"], "", true))
	if not _expect(int((aggregation["summary"]["statuses"] as Dictionary).get("ok", 0)) == expected, "farm contains generation failures or invalid circuits"):
		return
	print("TRACK_DIVERSITY_SWEEP_TEST PASS aggregate_shards=%d cases=%d" % [documents.size(), records.size()])
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
	if not _expect(_shape_distance(shape, _normalized_shape(oval)) > DISTINCT_SHAPE_DISTANCE, "shape metric must distinguish a dogleg from an oval"):
		return false
	var descriptor := _shape_descriptor(shape)
	var synthetic: Array[Dictionary] = [
		{"generator": 7, "room": "classic", "tier": "compact", "seed": 2, "status": "ok", "route_sequence": "L1.S.R1", "rhythm_signature": "L.S.R", "rejection_classes": {"self_distance": 1}, "shape_descriptor": descriptor},
		{"generator": 7, "room": "classic", "tier": "compact", "seed": 1, "status": "ok", "route_sequence": "L1.S.R1", "rhythm_signature": "L.S.R", "rejection_classes": {}, "shape_descriptor": descriptor},
	]
	var aggregation := _aggregate_records(synthetic, 7)
	if not _expect(bool(aggregation.get("ok", false)) and int(aggregation["summary"]["cases"]) == 2 and int(aggregation["summary"]["cells"]["classic/compact"]["shape_clusters"]) == 1, "farm aggregation should sort records and cluster cached shape descriptors"):
		return false
	synthetic[0]["module_class_histogram"] = {"straight_link": 3, "s_offset": 2}
	synthetic[1]["module_class_histogram"] = {"straight_link": 1}
	var class_summary: Dictionary = _aggregate_records(synthetic, 7)["summary"]
	if not _expect(class_summary["accepted_module_instances"] == {"straight_link": 4, "s_offset": 2} and class_summary["cells"]["classic/compact"]["accepted_class_layouts"] == {"straight_link": 2, "s_offset": 1}, "accepted class coverage must distinguish instances from layouts containing each class"):
		return false
	var duplicate: Array[Dictionary] = synthetic.duplicate(true)
	duplicate.append(synthetic[0].duplicate(true))
	if not _expect(not bool(_aggregate_records(duplicate, 7).get("ok", false)), "farm aggregation should reject duplicate identities"):
		return false
	if not _expect(not bool(_aggregate_records(synthetic, 8).get("ok", false)), "farm aggregation should reject mixed generator versions"):
		return false
	var invalid: Array[Dictionary] = synthetic.duplicate(true)
	for record: Dictionary in invalid:
		record["status"] = "invalid"
	var failed_summary: Dictionary = _aggregate_records(invalid, 7)["summary"]
	return _expect(int(failed_summary["cases"]) == 2 and int(failed_summary["cells"]["classic/compact"]["shape_clusters"]) == 0 and int(failed_summary["cells"]["classic/compact"]["successes"]) == 0 and (failed_summary["accepted_module_instances"] as Dictionary).is_empty() and _packed_points_digest(PackedVector2Array()).is_empty(), "invalid cases must remain in denominators without earning diversity or class coverage; empty output has no digest")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_DIVERSITY_SWEEP_TEST FAIL: " + message)
	quit(1)
	return false
