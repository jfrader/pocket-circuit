extends SceneTree

const SOLVER := preload("res://scripts/race/track_layout_solver.gd")
const GENERATOR := preload("res://scripts/race/track_v8_development_generator.gd")
const ROOM_MODEL := preload("res://scripts/race/track_room_model.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const MODULES := preload("res://scripts/race/track_module_catalog.gd")
const SIGNATURES := preload("res://scripts/race/track_layout_signatures.gd")
const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")

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
	if not _test_resumed_search() or not _test_incremental_checks() or not _test_corner_trims() or not _test_reserved_connector() or not _test_canonical_band_cases() or not _test_exclusive_visits():
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
	print("TRACK_LAYOUT_SOLVER_TEST PASS cases=2 bounded_failure=1 resumed_seeds=3 incremental_crossing=1 diagonal_trims=1 reserved_closure=1 canonical_band=2")
	quit(0)


func _verify_case(test_case: Dictionary, generated: Dictionary, elapsed_ms: float) -> bool:
	var label := "%s/%s" % [test_case["room"], test_case["tier"]]
	if not _expect(bool(generated.get("ok", false)), "%s should solve: %s" % [label, generated.get("reason", "unknown")]):
		return false
	var identity: Dictionary = generated["identity"]
	if not _expect(int(identity["schema_version"]) == 2 and int(identity["generator_version"]) == 8 and identity["room_shape"] == test_case["room"] and identity["length_tier"] == test_case["tier"] and int(identity["seed"]) == int(test_case["seed"]), "%s should retain its complete requested identity" % label):
		return false
	var cycle: Array = generated["gameplay_cycle"]
	var slot_ceiling := int((SOLVER.GRAPHS.TIER_SLOT_BUDGETS[StringName(test_case["tier"])] as Vector2i).y)
	if not _expect(cycle.size() >= 6 and cycle.size() <= slot_ceiling, "%s should stay inside its published semantic-slot budget of at most %d (got %d)" % [label, slot_ceiling, cycle.size()]):
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
	var route: Dictionary = generated["analytic_route"]
	if not _expect(route.has("finish_primitive_index"), "%s must sample from its protected finish straight" % label):
		return false
	var finish: Dictionary = route["primitives"][int(route["finish_primitive_index"])]
	var finish_midpoint := (finish["start"] as Vector2).lerp(finish["end"], 0.5)
	if not _expect((generated["points"][0] as Vector2).distance_to(finish_midpoint) <= MODULES.POSITION_TOLERANCE, "%s runtime start must coincide with the midpoint of the reserved finish straight" % label):
		return false
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
	room["regions"] = []
	room["portals"] = []
	var graph := {"start_position": Vector2(-800, -300), "start_heading": 0.0}
	var corner := MODULES.instantiate(&"corner_tight", {"radius": 180.0, "angle_deg": 90.0, "hand": 1.0})
	var straight := MODULES.instantiate(&"straight_setup", {"length": 1600.0})
	var instances: Array[Dictionary] = [straight, corner, MODULES.instantiate(&"straight_link", {"length": 240.0}), corner, straight]
	var counters := {"closure_candidates": SOLVER.MAX_CLOSURE_CANDIDATES, "closure_rejections": 0, "narrow_phase_operations": 0}
	var state := {"budget_exhausted": false, "closure_start": 0}
	var closed := SOLVER._solve_closure(graph, room, {"min_length": 4375.0, "max_length": 9625.0}, counters, SOLVER._limits({}), instances, state)
	return _expect(bool(closed.get("ok", false)) and not bool(state["budget_exhausted"]) and int(counters["closure_candidates"]) == SOLVER.MAX_CLOSURE_CANDIDATES + 1, "a new frontier must get its own closure allowance after a previous frontier consumed 24 candidates")


func _test_resumed_search() -> bool:
	for seed in [2, 3, 8]:
		var identity := IDENTITIES.create_v8(&"kitchen", &"classic", seed, false, 1, "", "", {}, "long")
		var room_seed := int(identity["room_geometry_seed"])
		var generated := GENERATOR.generate_route(&"classic", &"long", seed, room_seed)
		if not _expect(bool(generated.get("ok", false)), "long seed %d must reach a valid alternative instead of starving behind a rejected graph: %s" % [seed, generated.get("reason", "")]):
			return false
		if not _expect(bool(generated["analytic_validation"]["valid"]) and bool(generated["sampled_validation"]["valid"]) and int(generated["search"]["narrow_phase_operations"]) <= SOLVER.MAX_NARROW_PHASE_OPERATIONS, "resumed search must retain full validation and the original operation limit"):
			return false
		var repeated := GENERATOR.generate_route(&"classic", &"long", seed, room_seed)
		if not _expect(generated["points"] == repeated.get("points") and generated["search"] == repeated.get("search"), "resumed candidate search must reproduce geometry and counters"):
			return false
	return true


func _test_incremental_checks() -> bool:
	var room := ROOM_MODEL.generate_recipe(&"classic", 1494245235, &"marathon")
	var corner := MODULES.instantiate(&"corner_tight", {"radius": 180.0, "angle_deg": 90.0, "hand": 1.0})
	var instances: Array[Dictionary] = []
	var validated_count := 0
	var sequence: Array[Dictionary] = [
		MODULES.instantiate(&"straight_setup", {"length": 1600.0}), corner,
		MODULES.instantiate(&"straight_setup", {"length": 600.0}), corner,
		MODULES.instantiate(&"straight_setup", {"length": 1000.0}), corner,
		MODULES.instantiate(&"straight_setup", {"length": 1200.0}),
	]
	for index in sequence.size():
		instances.append(sequence[index])
		var route := MODULES.compose(instances, Vector2(-800, -300))
		var complete_check := SOLVER._partial_route_valid(route, room)
		var incremental_check := SOLVER._partial_route_valid(route, room, validated_count)
		if not _expect(complete_check == incremental_check and complete_check == (index < sequence.size() - 1), "incremental checks must accept valid extensions and reject a new limb crossing the validated prefix"):
			return false
		validated_count = (route["primitives"] as Array).size()
	return true


func _test_corner_trims() -> bool:
	for definition: Dictionary in MODULES.definitions():
		if definition["family"] not in [&"corner", &"profile"]:
			continue
		for angle_deg in [45.0, 90.0, 135.0]:
			for hand in [-1.0, 1.0]:
				var parameters := MODULES.proposal_parameters(definition["id"], {"hand": hand}, {"radius": 0.0, "inner_radius": 0.0, "outer_radius": 0.0})
				parameters["angle_deg"] = angle_deg
				var corner := MODULES.instantiate(definition["id"], parameters)
				var trims := SOLVER.GRAPHS._corner_trims(corner)
				var expected_exit := Vector2(trims.x, 0.0) + Vector2.RIGHT.rotated(deg_to_rad(angle_deg) * hand) * trims.y
				if not _expect(expected_exit.distance_to(corner["exit_port"]["position"]) <= MODULES.POSITION_TOLERANCE, "corner trims must reproduce the tangent intersection for %s at %s degrees, hand %s" % [definition["id"], angle_deg, hand]):
					return false
	var ring := PackedVector2Array([Vector2(-2000, -600), Vector2(1000, -600), Vector2(1800, 200), Vector2(1800, 1000), Vector2(-2000, 1000)])
	var graph := SOLVER.GRAPHS._embed_ring(ring, {"seed": 928, "length_tier": &"long"}, 0)
	if not _expect(bool(graph.get("ok", false)), "diagonal ring must embed with sufficient straight and bend space"):
		return false
	var instances: Array[Dictionary] = []
	for slot: Dictionary in (graph["ordinary_slots"] as Array) + (graph["closure_targets"] as Array):
		instances.append(MODULES.instantiate(slot["module_id"], slot["parameters"]))
	var route := MODULES.compose(instances, graph["start_position"], float(graph["start_heading"]))
	if not _expect(bool(MODULES.validate_join(route["exit_port"], route["entry_port"])["valid"]), "embedded diagonal ring must return to its exact starting pose before closure search"):
		return false
	return true


func _test_reserved_connector() -> bool:
	var room := ROOM_MODEL.generate_recipe(&"classic", 1494245235, &"standard")
	var identity := {"room_shape": &"classic", "length_tier": &"standard", "seed": 928}
	var band := SOLVER.GENERATED_RULES.length_profile("standard")
	var resolved: Dictionary = {}
	for graph: Dictionary in SOLVER._graph_candidates(room, identity):
		if bool(graph.get("ok", false)) and not (graph.get("closure_targets", []) as Array).is_empty():
			var target_modules: Array[Dictionary] = []
			for slot: Dictionary in (graph["ordinary_slots"] as Array) + (graph["closure_targets"] as Array):
				target_modules.append(MODULES.instantiate(slot["module_id"], slot["parameters"]))
			var route := MODULES.compose(target_modules, graph["start_position"], float(graph["start_heading"]))
			if float(route["length"]) < float(band["min_length"]) or float(route["length"]) > float(band["max_length"]):
				continue
			if not bool(ROOM_MODEL.route_fits(room, route).get("valid", false)) or not bool(SOLVER._assign_regions_and_portals(graph, room, route).get("ok", false)):
				continue
			if not bool(SOLVER.VALIDATION.validate_continuous(route, room["outer"]).get("valid", false)) or not bool(SOLVER.VALIDATION.validate_sampled(route, MODULES.sample_route(route, 260, 35.0, 0.25), room["outer"]).get("valid", false)):
				continue
			resolved = graph
			break
	if not _expect(not resolved.is_empty(), "a real classic/standard graph must expose a reserved closure connector"):
		return false
	var modules: Array[Dictionary] = []
	for slot: Dictionary in resolved["ordinary_slots"]:
		modules.append(MODULES.instantiate(slot["module_id"], slot["parameters"]))
	var counters := {"closure_candidates": 0, "closure_rejections": 0, "narrow_phase_operations": 0, "last_rejection": &"none"}
	var limits := SOLVER._limits({"closure_candidates_per_frontier": 1})
	var state := {"budget_exhausted": false}
	var closed := SOLVER._solve_closure(resolved, room, band, counters, limits, modules, state)
	if not _expect(bool(closed.get("ok", false)) and not bool(state["budget_exhausted"]), "the reserved connector must close a real graph through the full validator stack (last rejection: %s)" % [counters.get("last_rejection", &"none")]):
		return false
	return _expect((closed["route"]["closure"] as Dictionary)["family"] == &"reserved" and int(counters["closure_candidates"]) == 1, "the reserved connector must be accepted as the single closure proposal (family=%s candidates=%d)" % [(closed["route"]["closure"] as Dictionary)["family"], int(counters["closure_candidates"])])


func _test_canonical_band_cases() -> bool:
	for test_case: Dictionary in [{"room": &"tall", "tier": &"long"}, {"room": &"classic", "tier": &"marathon"}]:
		var room: StringName = test_case["room"]
		var tier: StringName = test_case["tier"]
		var label := "%s/%s" % [room, tier]
		var identity := IDENTITIES.create_v8(&"kitchen", room, 0, false, 1, "", "", {}, String(tier))
		if not _expect(not identity.is_empty(), "%s seed 0 must have a canonical v8 identity" % label):
			return false
		var room_seed := int(identity["room_geometry_seed"])
		var generated := GENERATOR.generate_route(room, tier, 0, room_seed)
		if not _expect(bool(generated.get("ok", false)), "%s seed 0 must solve: %s" % [label, generated.get("reason", "unknown")]):
			return false
		var gen_identity: Dictionary = generated["identity"]
		if not _expect(int(gen_identity["room_geometry_seed"]) == room_seed and gen_identity["room_shape"] == room and gen_identity["length_tier"] == tier and int(gen_identity["seed"]) == 0, "%s seed 0 must retain its canonical identity" % label):
			return false
		var band := SOLVER.GENERATED_RULES.length_profile(String(tier))
		var length := float(generated["metrics"]["length"])
		if not _expect(length >= float(band["min_length"]) and length <= float(band["max_length"]), "%s seed 0 must land inside its requested length band (%.2f in [%.0f, %.0f])" % [label, length, float(band["min_length"]), float(band["max_length"])]):
			return false
		var required := 0
		for visit: Dictionary in generated["region_visits"]:
			if bool(visit["required"]):
				required += 1
				if not _expect(not (visit["slot_indices"] as PackedInt32Array).is_empty(), "%s seed 0 must assign every required region to route slots" % label):
					return false
		if not _expect(required > 0, "%s seed 0 must carry at least one required region" % label):
			return false
		var search: Dictionary = generated["search"]
		if not _expect(int(search["graph_candidates"]) <= SOLVER.MAX_GRAPH_CANDIDATES and int(search["placement_expansions"]) <= SOLVER.MAX_PLACEMENT_EXPANSIONS_PER_GRAPH * int(search["graph_candidates"]) and int(search["closure_candidates"]) <= SOLVER.MAX_CLOSURE_CANDIDATES * int(search["placement_expansions"]) and int(search["narrow_phase_operations"]) <= SOLVER.MAX_NARROW_PHASE_OPERATIONS, "%s seed 0 must respect the original per-graph, per-frontier, and shared caps" % label):
			return false
		var repeated := GENERATOR.generate_route(room, tier, 0, room_seed)
		if not _expect(generated["identity"] == repeated.get("identity") and generated["points"] == repeated.get("points") and generated["search"] == repeated.get("search"), "%s seed 0 must reproduce its canonical identity, geometry, and counters" % label):
			return false
	return true


func _test_exclusive_visits() -> bool:
	var corner := MODULES.instantiate(&"corner_tight", {"radius": 180.0, "angle_deg": 90.0, "hand": 1.0})
	var modules: Array[Dictionary] = [
		MODULES.instantiate(&"straight_setup", {"length": 1000.0}), corner,
		MODULES.instantiate(&"straight_link", {"length": 180.0}), corner,
		MODULES.instantiate(&"straight_setup", {"length": 1000.0}), corner,
		MODULES.instantiate(&"straight_link", {"length": 180.0}), corner,
	]
	var route := MODULES.compose(modules, Vector2(-800, 0))
	var room := {"regions": [
		{"id": &"first", "required": true, "polygon": ROOM_MODEL._rectangle_ring(Vector2.ZERO, Vector2(4000, 3000))},
		{"id": &"second", "required": true, "polygon": ROOM_MODEL._rectangle_ring(Vector2(0, 500), Vector2(4000, 2000))},
	], "portals": []}
	var rejected := SOLVER._assign_regions_and_portals({}, room, route)
	if not _expect(not bool(rejected.get("ok", false)) and rejected.get("kind") == &"required_region_length", "counting module midpoints inside a shared junction must not count as visiting both arms"):
		return false
	room["regions"][0]["polygon"] = ROOM_MODEL._rectangle_ring(Vector2(-1000, 0), Vector2(2000, 3000))
	room["regions"][1]["polygon"] = ROOM_MODEL._rectangle_ring(Vector2(750, 0), Vector2(2500, 3000))
	var accepted := SOLVER._assign_regions_and_portals({}, room, route)
	if not _expect(bool(accepted.get("ok", false)) and int(accepted["query_operations"]) > 0, "exclusive route lengths must certify a real visit to both overlapping required regions"):
		return false
	for visit: Dictionary in accepted["region_visits"]:
		if not _expect(float(visit["exclusive_length"]) >= 450.0, "each certified required arm must carry at least 450 exclusive route units"):
			return false
	var exhausted := SOLVER._assign_regions_and_portals({}, room, route, 0)
	return _expect(not bool(exhausted.get("ok", false)) and bool(exhausted.get("budget_exhausted", false)) and int(exhausted["query_operations"]) == 0, "region certification must respect the remaining query allowance")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_LAYOUT_SOLVER_TEST FAIL: " + message)
	quit(1)
	return false
