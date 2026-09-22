extends SceneTree

const SOLVER := preload("res://scripts/race/track_layout_solver.gd")
const GENERATOR := preload("res://scripts/race/track_v8_development_generator.gd")
const ROOM_MODEL := preload("res://scripts/race/track_room_model.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const MODULES := preload("res://scripts/race/track_module_catalog.gd")
const SIGNATURES := preload("res://scripts/race/track_layout_signatures.gd")

const CASES: Array[Dictionary] = [
	{"room": &"classic", "tier": &"standard", "seed": 928},
	{"room": &"el", "tier": &"compact", "seed": 1001},
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _test_signatures():
		return
	if not _test_general_graphs() or not _test_catalog_search() or not _test_technical_embeds() or not _test_remaining_bounds() or not _test_frontier_budget():
		return
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
	if not _expect(int(search["graph_candidates"]) <= SOLVER.MAX_GRAPH_CANDIDATES and int(search["placement_expansions"]) <= SOLVER.MAX_PLACEMENT_EXPANSIONS_PER_GRAPH * int(search["graph_candidates"]) and int(search["closure_candidates"]) <= SOLVER.MAX_CLOSURE_CANDIDATES * int(search["placement_expansions"]) and int(search["narrow_phase_operations"]) <= SOLVER.MAX_NARROW_PHASE_OPERATIONS, "%s should stay inside the per-graph placement, per-frontier closure, and shared narrow-phase caps" % label):
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


func _test_signatures() -> bool:
	var parameters := {"radius": 240.0, "depth_1": 600.0, "depth_2": 800.0, "width": 500.0, "hand": 1.0}
	var compound := MODULES.instantiate(&"switchback", parameters)
	var route := MODULES.compose([compound])
	var signature := SIGNATURES.describe(route)
	if not _expect(int(signature["semantic_count"]) == 6 and String(signature["structural"]).contains("R"), "zero-net-turn compounds must expand into their internal turn and straight arrangement"):
		return false
	for mirror in [false, true]:
		for reverse in [false, true]:
			var transformed := MODULES.compose([MODULES.instantiate(&"switchback", parameters, {"mirror": mirror, "reverse": reverse})], Vector2(170, -230), 0.7)
			if not _expect(SIGNATURES.describe(transformed) == signature, "signatures must discount mirror, reversal, rotation and translation"):
				return false
	var expanded: Array[Dictionary] = []
	for primitive: Dictionary in compound["primitives"]:
		if primitive["kind"] == &"line":
			expanded.append(MODULES.instantiate(&"straight_link", {"length": float(primitive["length"]) * 0.5}))
			expanded.append(MODULES.instantiate(&"straight_link", {"length": float(primitive["length"]) * 0.5}))
		else:
			expanded.append(MODULES.instantiate_closure_arc(float(primitive["radius"]), float(primitive["signed_turn"])))
	if not _expect(SIGNATURES.describe(MODULES.compose(expanded)) == signature, "equivalent primitive composition and artificial straight splits must not earn new arrangements"):
		return false
	var rotated: Array = (route["primitives"] as Array).duplicate()
	rotated.append(rotated.pop_front())
	if not _expect(SIGNATURES.describe({"primitives": rotated}) == signature, "canonical signatures must merge runs across a cyclic seam"):
		return false
	var opening := {"inner_radius": 240.0, "outer_radius": 360.0, "angle_deg": 90.0, "split": 0.5, "hand": 1.0}
	var original := MODULES.compose([MODULES.instantiate(&"corner_opening", opening)])
	var reversed := MODULES.compose([MODULES.instantiate(&"corner_opening", opening, {"reverse": true})])
	return _expect(SIGNATURES.describe(original) == SIGNATURES.describe(reversed), "profile canonicalization must exchange opening and tightening under reversal")


func _test_catalog_search() -> bool:
	for definition: Dictionary in MODULES.definitions():
		var id: StringName = definition["id"]
		var target := MODULES.proposal_parameters(id, {"hand": -1.0}, {})
		var slot := {"module_id": id, "parameters": target}
		var graph := {"id": "catalog_search", "seed": 928}
		var options := SOLVER._slot_options(slot, graph, 0)
		if not _expect(options.size() >= 3 and options.size() <= 8 and options == SOLVER._slot_options(slot, graph, 0), "%s needs bounded deterministic parameter alternatives" % id):
			return false
		if not _expect(options != SOLVER._slot_options(slot, {"id": "catalog_search", "seed": 929}, 0), "%s alternatives must consume the requested route seed" % id):
			return false
		for parameters: Dictionary in options:
			if not _expect(bool(MODULES.instantiate(id, parameters).get("ok", false)), "%s search option must be inside its authored domain: %s" % [id, parameters]):
				return false
		slot["options"] = options
		var bounds := SOLVER._option_bounds(slot)
		for parameters: Dictionary in options:
			var instance := MODULES.instantiate(id, parameters)
			if not _expect(float(instance["length"]) >= float(bounds["min_length"]) and float(instance["length"]) <= float(bounds["max_length"]) and float(instance["signed_turn"]) >= float(bounds["min_turn"]) and float(instance["signed_turn"]) <= float(bounds["max_turn"]), "%s bounds must enclose every actual search option" % id):
				return false
		if id in [&"s_offset", &"chicane_return", &"switchback"]:
			if not _expect(absf(float(bounds["min_turn"])) < 0.000001 and absf(float(bounds["max_turn"])) < 0.000001, "%s must not be budgeted as a corner" % id):
				return false
	return true


func _test_general_graphs() -> bool:
	var counts := {}
	var classes := {}
	for family: String in SOLVER.GENERATED_RULES.ROOMS:
		for tier: String in SOLVER.GENERATED_RULES.LENGTH_TIERS:
			var room := ROOM_MODEL.generate_recipe(StringName(family), 928, StringName(tier))
			var identity := {"room_shape": family, "length_tier": tier, "seed": 928}
			var graphs := SOLVER._graph_candidates(room, identity)
			if not _expect(graphs.size() == SOLVER.MAX_GRAPH_CANDIDATES, "%s/%s should enumerate the general graph budget" % [family, tier]):
				return false
			var feasible := 0
			for graph: Dictionary in graphs:
				if not bool(graph["ok"]):
					if not _expect(graph.has("reason") and graph.get("kind") != &"unsupported_first_lap_cell", "graph failure must explain a geometric or budget constraint, never a cell whitelist"):
						return false
					continue
				feasible += 1
				counts[(graph["slots"] as Array).size()] = true
				for slot: Dictionary in graph["ordinary_slots"]:
					classes[slot["module_id"]] = true
					if not _expect(bool(MODULES.instantiate(slot["module_id"], slot["parameters"]).get("ok", false)), "region turns must leave links inside the strict catalog domain"):
						return false
					if not _expect((MODULES.definition(slot["module_id"])["allowed_moment_tags"] as Array).has(slot["moment"]), "graph moments must obey the selected catalog class"):
						return false
				if not _expect((graph["region_budgets"] as Array).size() == SOLVER._required_region_ids(room).size() and not (graph["portal_counts"] as Dictionary).is_empty(), "graph must retain its region allocation and portal reservations"):
					return false
			if not _expect(feasible > 0, "%s/%s must have a constructible region graph" % [family, tier]):
				return false
	return _expect(counts.size() >= 3, "region and length budgets must produce variable cycle counts") and _expect(classes.size() == MODULES.definitions().size(), "general graph proposals must reach all authored classes: %s" % [classes.keys()])


func _test_remaining_bounds() -> bool:
	var partial := {"length": 1000.0, "signed_turn": PI, "entry_port": {"position": Vector2.ZERO}, "exit_port": {"position": Vector2(1200, 0)}}
	var slots: Array = [{"module_id": &"straight_link", "parameters": {"length": 1200.0}}]
	if not _expect(SOLVER._remaining_feasible(partial, slots, 0, {"min_length": 0.0, "max_length": 2300.0}), "suffix progress toward the start must not be charged again as closure distance"):
		return false
	return _expect(not SOLVER._remaining_feasible(partial, slots, 0, {"min_length": 0.0, "max_length": 2100.0}), "the exact remaining slot minimum must still prune an over-length branch")


func _test_technical_embeds() -> bool:
	var hands := {}
	var classes := {}
	for seed in 12:
		for candidate in 3:
			var slots := SOLVER.GRAPHS._technical_slots({"seed": seed}, candidate, 0, 2000.0)
			var modules: Array[Dictionary] = []
			for slot: Dictionary in slots:
				modules.append(MODULES.instantiate(slot["module_id"], slot["parameters"]))
				classes[slot["module_id"]] = true
				hands[slot["parameters"]["hand"]] = true
			var route := MODULES.compose(modules)
			var exit: Vector2 = route["exit_port"]["position"]
			if not _expect(absf(exit.y) <= MODULES.POSITION_TOLERANCE and exit.x <= 2000.0 and absf(float(route["signed_turn"])) <= MODULES.HEADING_TOLERANCE, "either-handed technical sections must return to the reserved straight pose within their span"):
				return false
	return _expect(hands.size() == 2 and classes.size() == 3, "seeded technical embeddings must exercise both hands and all three compound programs")


func _test_frontier_budget() -> bool:
	var room := ROOM_MODEL.generate_recipe(&"classic", 1494245235, &"standard")
	var graph := {"start_position": Vector2(-800, -300), "start_heading": 0.0}
	var corner := MODULES.instantiate(&"corner_tight", {"radius": 180.0, "angle_deg": 90.0, "hand": 1.0})
	var straight := MODULES.instantiate(&"straight_setup", {"length": 1600.0})
	var instances: Array[Dictionary] = [straight, corner, MODULES.instantiate(&"straight_link", {"length": 240.0}), corner, straight]
	var counters := {"closure_candidates": SOLVER.MAX_CLOSURE_CANDIDATES, "closure_rejections": 0, "narrow_phase_operations": 0}
	var state := {"budget_exhausted": false, "closure_start": 0}
	var closed := SOLVER._solve_closure(graph, room, {"min_length": 4375.0, "max_length": 9625.0}, counters, SOLVER._limits({}), instances, state)
	return _expect(bool(closed.get("ok", false)) and not bool(state["budget_exhausted"]) and int(counters["closure_candidates"]) == SOLVER.MAX_CLOSURE_CANDIDATES + 1, "a new frontier must get its own closure allowance after a previous frontier consumed 24 candidates")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_LAYOUT_SOLVER_TEST FAIL: " + message)
	quit(1)
	return false
