extends SceneTree

const SOLVER := preload("res://scripts/race/track_layout_solver.gd")
const GENERATOR := preload("res://scripts/race/track_v8_development_generator.gd")
const ROOM_MODEL := preload("res://scripts/race/track_room_model.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")

const CASES: Array[Dictionary] = [
	{"room": &"classic", "tier": &"standard", "seed": 928},
	{"room": &"el", "tier": &"compact", "seed": 1001},
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for test_case: Dictionary in CASES:
		var started := Time.get_ticks_usec()
		var generated := GENERATOR.generate_route(test_case["room"], test_case["tier"], int(test_case["seed"]))
		var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
		if not _verify_case(test_case, generated, elapsed_ms):
			return
		var repeated := GENERATOR.generate_route(test_case["room"], test_case["tier"], int(test_case["seed"]))
		if not _expect(
			generated.get("identity") == repeated.get("identity")
			and generated.get("points") == repeated.get("points")
			and generated.get("search") == repeated.get("search"),
			"%s/%s should reproduce identity, geometry, and bounded-search evidence exactly" % [test_case["room"], test_case["tier"]]
		):
			return
		var options := {
			"schema_version": 2,
			"generator_version": 8,
			"length_tier": test_case["tier"],
			"room_geometry_seed": int(generated["identity"]["room_geometry_seed"]),
			"obstacles_enabled": false,
		}
		var prepared := TRACK_BUILDER.prepare_layout(&"kitchen", test_case["room"], int(test_case["seed"]), options)
		if not _expect(not prepared.is_empty() and prepared["centerline"] == generated["points"] and int(prepared["spec"]["generator_version"]) == 8, "%s/%s should be available through the explicit v8 preparation seam" % [test_case["room"], test_case["tier"]]):
			return
	if not _test_bounded_failure():
		return
	print("TRACK_LAYOUT_SOLVER_TEST PASS cases=2 bounded_failure=1")
	quit(0)


func _verify_case(test_case: Dictionary, generated: Dictionary, elapsed_ms: float) -> bool:
	var label := "%s/%s" % [test_case["room"], test_case["tier"]]
	if not _expect(bool(generated.get("ok", false)), "%s should solve: %s" % [label, generated.get("reason", "unknown")]):
		return false
	var identity: Dictionary = generated["identity"]
	if not _expect(int(identity["schema_version"]) == 2 and int(identity["generator_version"]) == 8 and identity["room_shape"] == test_case["room"] and identity["length_tier"] == test_case["tier"] and int(identity["seed"]) == int(test_case["seed"]), "%s should retain its complete requested identity" % label):
		return false
	var cycle: Array = generated["gameplay_cycle"]
	if not _expect(cycle.size() >= 6 and cycle.size() <= 12, "%s should stay inside its initial semantic-slot budget (got %d)" % [label, cycle.size()]):
		return false
	for index in cycle.size():
		if not _expect(int(cycle[index]["predecessor"]) == posmod(index - 1, cycle.size()) and int(cycle[index]["successor"]) == (index + 1) % cycle.size(), "%s slot %d should have exactly one cyclic predecessor and successor" % [label, index]):
			return false
	var required_visits := 0
	for visit: Dictionary in generated["region_visits"]:
		if bool(visit["required"]):
			required_visits += 1
			if not _expect(not (visit["slot_indices"] as PackedInt32Array).is_empty(), "%s should assign every required region to route slots" % label):
				return false
	for traversal: Dictionary in generated["portal_traversals"]:
		var slots: PackedInt32Array = traversal["slot_indices"]
		var lanes: PackedVector2Array = traversal["lane_centers"]
		if not _expect(slots.size() == 2 and slots[0] != slots[1] and lanes.size() == 2 and lanes[0].distance_to(lanes[1]) >= 320.0 and float(traversal["clear_width"]) >= 590.0, "%s should reserve two distinct full-width portal traversals" % label):
			return false
	var search: Dictionary = generated["search"]
	if not _expect(int(search["graph_candidates"]) <= SOLVER.MAX_GRAPH_CANDIDATES and int(search["placement_expansions"]) <= SOLVER.MAX_PLACEMENT_EXPANSIONS_PER_GRAPH and int(search["closure_candidates"]) <= SOLVER.MAX_CLOSURE_CANDIDATES and int(search["narrow_phase_operations"]) <= SOLVER.MAX_NARROW_PHASE_OPERATIONS, "%s should stay inside every deterministic work cap" % label):
		return false
	var metrics: Dictionary = generated["metrics"]
	if not _expect(float(metrics["closure_position_residual"]) <= 0.01 and float(metrics["closure_heading_residual"]) <= 0.0001 and absf(absf(float(metrics["signed_turn"])) - TAU) <= 0.0001, "%s should close analytically at the exact pose with +/-2PI winding" % label):
		return false
	var has_left := false
	var has_right := false
	for primitive: Dictionary in generated["analytic_route"]["primitives"]:
		has_left = has_left or float(primitive["signed_turn"]) > 0.0001
		has_right = has_right or float(primitive["signed_turn"]) < -0.0001
	if not _expect(has_left and has_right, "%s should include mixed-handed analytic sections" % label):
		return false
	print("V8_SOLVED_CASE room=%s tier=%s seed=%d room_seed=%d digest=%s length=%.2f closure=%s/r%.0f residual=%.6f/%.8f graphs=%d expansions=%d backtracks=%d closures=%d narrow=%d samples=%d digest=%s elapsed_ms=%.2f required_regions=%d" % [
		test_case["room"], test_case["tier"], int(test_case["seed"]), int(identity["room_geometry_seed"]), String(identity["room_digest"]).substr(0, 12), float(metrics["length"]), String(generated["analytic_route"]["closure"]["family"]), float(generated["analytic_route"]["closure"]["radius"]), float(metrics["closure_position_residual"]), float(metrics["closure_heading_residual"]), int(search["graph_candidates"]), int(search["placement_expansions"]), int(search["placement_backtracks"]), int(search["closure_candidates"]), int(search["narrow_phase_operations"]), int(metrics["sample_count"]), _points_digest(generated["points"]).substr(0, 16), elapsed_ms, required_visits,
	])
	return true


func _test_bounded_failure() -> bool:
	var generated := GENERATOR.generate_route(&"classic", &"standard", 928)
	if not bool(generated.get("ok", false)):
		return _expect(false, "bounded failure fixture needs the solved classic identity")
	var identity: Dictionary = generated["identity"]
	var room := ROOM_MODEL.generate_recipe(&"classic", int(identity["room_geometry_seed"]), &"standard")
	var failed := SOLVER.solve({
		"seed": 928,
		"room_shape": &"classic",
		"length_tier": &"standard",
		"room_geometry_seed": int(identity["room_geometry_seed"]),
		"room_model": room,
		"solver_limits": {"placement_expansions_per_graph": 0},
	})
	return _expect(not bool(failed.get("ok", false)) and failed.get("kind") == &"search_budget_exhausted" and failed.get("stage") == &"placement" and failed.get("identity") == identity and int((failed["search"] as Dictionary)["placement_expansions"]) == 0, "budget exhaustion should report the exact identity, stage, cap, and zero consumed expansions")


func _points_digest(points: PackedVector2Array) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(points.to_byte_array())
	return context.finish().hex_encode()


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_LAYOUT_SOLVER_TEST FAIL: " + message)
	quit(1)
	return false
