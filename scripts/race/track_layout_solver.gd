class_name TrackLayoutSolver
extends RefCounted

const MODULES := preload("res://scripts/race/track_module_catalog.gd")
const ROOM_MODEL := preload("res://scripts/race/track_room_model.gd")
const VALIDATION := preload("res://scripts/race/track_layout_validation.gd")
const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const SIGNATURES := preload("res://scripts/race/track_layout_signatures.gd")

const MAX_GRAPH_CANDIDATES := 24
const MAX_PLACEMENT_EXPANSIONS_PER_GRAPH := 2048
const MAX_CLOSURE_CANDIDATES := 24
const MAX_NARROW_PHASE_OPERATIONS := 50000
const CLOSURE_RADII: Array[float] = [180.0, 240.0, 360.0, 520.0]
const CLOSURE_FAMILIES: Array[StringName] = [&"LSL", &"RSR", &"LSR", &"RSL", &"LRL", &"RLR"]
const FAMILY_LABELS: Array[StringName] = [&"courtyard", &"crossing", &"workbench", &"switchyard", &"ribbon", &"alcove"]


static func solve(request: Dictionary) -> Dictionary:
	var resolved := _resolve_request(request)
	if not bool(resolved.get("ok", false)):
		return resolved
	var room: Dictionary = resolved["room"]
	var identity: Dictionary = resolved["identity"]
	var band: Dictionary = resolved["band"]
	var limits := _limits(request.get("solver_limits", {}))
	var counters := {
		"graph_candidates": 0,
		"graph_rejections": 0,
		"placement_expansions": 0,
		"placement_backtracks": 0,
		"closure_candidates": 0,
		"closure_rejections": 0,
		"narrow_phase_operations": 0,
		"repair_passes": 0,
		"last_rejection": &"none",
		"limits": limits.duplicate(true),
	}
	var portal_check := _required_portals_are_feasible(room)
	if not bool(portal_check.get("ok", false)):
		return _failure(identity, &"region_assignment", portal_check.get("kind", &"portal_infeasible"), String(portal_check.get("reason", "Required room portal is infeasible.")), counters)
	var candidates := _graph_candidates(room, identity)
	for graph_index in mini(candidates.size(), int(limits["graph_candidates"])):
		counters["graph_candidates"] = int(counters["graph_candidates"]) + 1
		var graph: Dictionary = candidates[graph_index]
		if not bool(graph.get("ok", false)):
			counters["graph_rejections"] = int(counters["graph_rejections"]) + 1
			continue
		var search := _place_graph(graph, room, band, counters, limits)
		if bool(search.get("budget_exhausted", false)):
			return _failure(identity, StringName(search.get("stage", &"placement")), &"search_budget_exhausted", String(search.get("reason", "The deterministic search budget was exhausted.")), counters)
		if not bool(search.get("ok", false)):
			counters["graph_rejections"] = int(counters["graph_rejections"]) + 1
			continue
		var route: Dictionary = search["route"]
		var assignments := _assign_regions_and_portals(graph, room, route)
		if not bool(assignments.get("ok", false)):
			counters["last_rejection"] = assignments.get("kind", &"region_assignment")
			counters["graph_rejections"] = int(counters["graph_rejections"]) + 1
			continue
		var continuous := VALIDATION.validate_continuous(route, room["outer"])
		if not bool(continuous.get("valid", false)):
			counters["last_rejection"] = continuous.get("kind", &"continuous_validation")
			counters["graph_rejections"] = int(counters["graph_rejections"]) + 1
			continue
		var sampling := MODULES.sample_route(route, 260, 35.0, 0.25)
		var sampled := VALIDATION.validate_sampled(route, sampling, room["outer"])
		if not bool(sampled.get("valid", false)):
			counters["last_rejection"] = sampled.get("kind", &"sampled_validation")
			counters["graph_rejections"] = int(counters["graph_rejections"]) + 1
			continue
		var length := float(route["length"])
		if length < float(band["min_length"]) or length > float(band["max_length"]):
			counters["graph_rejections"] = int(counters["graph_rejections"]) + 1
			continue
		var completed_graph := _complete_cycle(graph, route)
		var signatures := SIGNATURES.describe(route)
		var reserved_room := room.duplicate(true)
		reserved_room["reserved_passages"] = assignments["portal_traversals"]
		return {
			"ok": true,
			"identity": identity,
			"room_model": reserved_room,
			"room_digest": room["polygon_digest"],
			"gameplay_cycle": completed_graph,
			"region_visits": assignments["region_visits"],
			"portal_traversals": assignments["portal_traversals"],
			"analytic_route": route,
			"points": sampling["points"],
			"sampling": sampling,
			"analytic_validation": continuous,
			"sampled_validation": sampled,
			"metrics": {
				"length": length,
				"signed_turn": float(route["signed_turn"]),
				"module_count": (route["modules"] as Array).size(),
				"primitive_count": (route["primitives"] as Array).size(),
				"sample_count": int(sampling["sample_count"]),
				"closure_position_residual": float(search["closure_position_residual"]),
				"closure_heading_residual": float(search["closure_heading_residual"]),
			},
			"search": counters.duplicate(true),
			"structural_signature": signatures["structural"],
			"profile_signature": signatures["profile"],
		}
	var reason := "No graph candidate produced a valid closed route within %d graphs, %d placements, %d closures, and %d narrow-phase operations (last rejection: %s)." % [int(counters["graph_candidates"]), int(counters["placement_expansions"]), int(counters["closure_candidates"]), int(counters["narrow_phase_operations"]), counters["last_rejection"]]
	return _failure(identity, &"candidate_search", &"no_feasible_layout", reason, counters)


static func _resolve_request(request: Dictionary) -> Dictionary:
	var room_shape := StringName(request.get("room_shape", &""))
	var tier := StringName(request.get("length_tier", &""))
	var seed := int(request.get("seed", -1))
	var room_seed := int(request.get("room_geometry_seed", -1))
	var identity := {
		"schema_version": 2,
		"generator_version": 8,
		"room_shape": room_shape,
		"length_tier": tier,
		"seed": seed,
		"room_geometry_seed": room_seed,
	}
	if seed < 0 or room_seed < 0:
		return _failure(identity, &"identity", &"invalid_identity", "v8 route and room geometry seeds must be non-negative.", {})
	var band := GENERATED_RULES.length_profile(String(tier))
	if band.is_empty():
		return _failure(identity, &"identity", &"unknown_tier", "Unknown v8 length tier '%s'." % tier, {})
	var room: Dictionary = request.get("room_model", {})
	if room.is_empty():
		room = ROOM_MODEL.generate_recipe(room_shape, room_seed, tier)
	if not bool(room.get("valid", false)):
		return _failure(identity, &"room", StringName(room.get("kind", &"invalid_room")), String(room.get("reason", "Could not construct the v8 room.")), {})
	if StringName(room.get("recipe_family", &"")) != room_shape or StringName(room.get("tier", &"")) != tier or int(room.get("room_seed", -1)) != room_seed:
		return _failure(identity, &"identity", &"room_identity_mismatch", "The supplied room model does not match the requested room, tier, and room seed.", {})
	if request.has("room_recipe_id") and int(request["room_recipe_id"]) != int(room["recipe_id"]):
		return _failure(identity, &"identity", &"room_recipe_mismatch", "The requested room recipe ID does not belong to the encoded room family.", {})
	if request.has("room_recipe_revision") and int(request["room_recipe_revision"]) != int(room["recipe_revision"]):
		return _failure(identity, &"identity", &"room_recipe_mismatch", "The requested room recipe revision is not supported.", {})
	identity["room_recipe_id"] = int(room["recipe_id"])
	identity["room_recipe_revision"] = int(room["recipe_revision"])
	identity["room_digest"] = String(room["polygon_digest"])
	identity["family"] = FAMILY_LABELS[_hash_index(identity, "family", 0, FAMILY_LABELS.size())]
	return {"ok": true, "identity": identity, "room": room, "band": band}


static func _limits(value: Variant) -> Dictionary:
	var override: Dictionary = value if value is Dictionary else {}
	return {
		"graph_candidates": clampi(int(override.get("graph_candidates", MAX_GRAPH_CANDIDATES)), 0, MAX_GRAPH_CANDIDATES),
		"placement_expansions_per_graph": clampi(int(override.get("placement_expansions_per_graph", MAX_PLACEMENT_EXPANSIONS_PER_GRAPH)), 0, MAX_PLACEMENT_EXPANSIONS_PER_GRAPH),
		"closure_candidates_per_frontier": clampi(int(override.get("closure_candidates_per_frontier", MAX_CLOSURE_CANDIDATES)), 0, MAX_CLOSURE_CANDIDATES),
		"narrow_phase_operations": clampi(int(override.get("narrow_phase_operations", MAX_NARROW_PHASE_OPERATIONS)), 0, MAX_NARROW_PHASE_OPERATIONS),
	}


static func _required_portals_are_feasible(room: Dictionary) -> Dictionary:
	var required_regions := _required_region_ids(room)
	for portal: Dictionary in room.get("portals", []):
		if not required_regions.has(portal["region_a"]) or not required_regions.has(portal["region_b"]):
			continue
		if int(portal.get("traversal_capacity", 0)) < 2 or (portal.get("lane_centers", PackedVector2Array()) as PackedVector2Array).size() < 2:
			return {"ok": false, "kind": &"portal_capacity", "reason": "Required portal '%s' cannot reserve entry and exit lanes." % portal.get("id", &"unknown")}
	return {"ok": true}


static func _graph_candidates(room: Dictionary, identity: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for variant: int in [0, 1]:
		for radius: float in [240.0, 180.0]:
			var graph := _build_el_graph(room, radius, identity, variant) if identity["room_shape"] == &"el" else _build_classic_graph(room, radius, identity, variant)
			graph["candidate_index"] = result.size()
			result.append(graph)
	return result


static func _build_classic_graph(room: Dictionary, radius: float, identity: Dictionary, variant: int) -> Dictionary:
	if StringName(room.get("recipe_family", &"")) != &"classic" or StringName(room.get("tier", &"")) != &"standard":
		return {"ok": false, "kind": &"unsupported_first_lap_cell"}
	var bounds := _ring_bounds(room["outer"])
	var center := bounds.get_center()
	var half_x := minf(1200.0, bounds.size.x * 0.5 - 200.0)
	var half_y := 300.0
	var vertical := 2.0 * (half_y - radius)
	if vertical < 180.0:
		return {"ok": false, "kind": &"module_domain"}
	var horizontal := 2.0 * (half_x - radius)
	var chicane_radius := 180.0
	var chicane_angle := 30.0
	var chicane_distance := 180.0 + float(_hash_index(identity, "classic_chicane", 0, 9)) * 10.0
	var chicane_advance := 4.0 * chicane_radius * sin(deg_to_rad(chicane_angle)) + chicane_distance
	var first_setup := 1030.0 + float(_hash_index(identity, "classic_finish_approach", 0, 5)) * 10.0
	var remaining_top := horizontal - first_setup - chicane_advance
	if remaining_top < 180.0 or horizontal < 1000.0:
		return {"ok": false, "kind": &"module_domain"}
	var top_slots: Array[Dictionary] = [
		_slot(&"straight_setup", {"length": first_setup}, &"opening"),
		_slot(&"chicane_return", {"radius": chicane_radius, "angle_deg": chicane_angle, "distance": chicane_distance, "hand": -1.0}, &"technical"),
		_slot(&"straight_link", {"length": remaining_top}, &"connection"),
	]
	if variant == 1:
		var chicane: Dictionary = top_slots.pop_at(1)
		top_slots.append(chicane)
	var ordinary: Array[Dictionary] = top_slots
	ordinary.append_array([
		_slot(&"corner_tight", {"radius": radius, "angle_deg": 90.0, "hand": 1.0}, &"conflict"),
		_slot(&"straight_link", {"length": vertical}, &"connection"),
		_slot(&"corner_tight", {"radius": radius, "angle_deg": 90.0, "hand": 1.0}, &"technical"),
		_slot(&"straight_setup", {"length": horizontal, "finish": true}, &"finish"),
	])
	return _finalize_graph(ordinary, center + Vector2(-half_x + radius, -half_y), 0.0, radius, StringName("classic_crossing_%d" % variant))


static func _build_el_graph(room: Dictionary, radius: float, identity: Dictionary, variant: int) -> Dictionary:
	if StringName(room.get("recipe_family", &"")) != &"el" or StringName(room.get("tier", &"")) != &"compact":
		return {"ok": false, "kind": &"unsupported_first_lap_cell"}
	var concave := _concave_vertex(room["outer"])
	if not is_finite(concave.x):
		return {"ok": false, "kind": &"missing_concavity"}
	var inner := concave + Vector2(-520.0, 160.0)
	var left_extent := 880.0 + float(_hash_index(identity, "el_vertical_arm", 0, 3)) * 10.0
	var right_extent := 950.0 + float(_hash_index(identity, "el_horizontal_arm", 0, 6)) * 10.0
	var vertices := PackedVector2Array([
		inner + Vector2(-left_extent, -700.0),
		inner + Vector2(0.0, -700.0),
		inner,
		inner + Vector2(right_extent, 0.0),
		inner + Vector2(right_extent, 620.0),
		inner + Vector2(-left_extent, 620.0),
	])
	var lengths := PackedFloat64Array()
	for index in vertices.size():
		lengths.append(vertices[index].distance_to(vertices[(index + 1) % vertices.size()]) - 2.0 * radius)
	for length: float in lengths:
		if length < 180.0:
			return {"ok": false, "kind": &"module_domain"}
	var ordinary: Array[Dictionary]
	var start: Vector2
	var heading: float
	if variant == 0:
		ordinary = [
			_slot(&"straight_setup", {"length": lengths[0]}, &"opening"),
			_slot(&"corner_tight", {"radius": radius, "angle_deg": 90.0, "hand": 1.0}, &"conflict"),
			_slot(&"straight_link", {"length": lengths[1]}, &"connection"),
			_slot(&"corner_tight", {"radius": radius, "angle_deg": 90.0, "hand": -1.0}, &"technical"),
			_slot(&"straight_link", {"length": lengths[2]}, &"connection"),
			_slot(&"corner_tight", {"radius": radius, "angle_deg": 90.0, "hand": 1.0}, &"conflict"),
			_slot(&"straight_link", {"length": lengths[3]}, &"connection"),
			_slot(&"corner_tight", {"radius": radius, "angle_deg": 90.0, "hand": 1.0}, &"technical"),
			_slot(&"straight_setup", {"length": lengths[4], "finish": true}, &"finish"),
		]
		start = vertices[0] + Vector2(radius, 0.0)
		heading = 0.0
	else:
		ordinary = [
			_slot(&"straight_link", {"length": lengths[3]}, &"connection"),
			_slot(&"corner_tight", {"radius": radius, "angle_deg": 90.0, "hand": 1.0}, &"technical"),
			_slot(&"straight_setup", {"length": lengths[4], "finish": true}, &"finish"),
			_slot(&"corner_tight", {"radius": radius, "angle_deg": 90.0, "hand": 1.0}, &"conflict"),
			_slot(&"straight_setup", {"length": lengths[5]}, &"opening"),
			_slot(&"corner_tight", {"radius": radius, "angle_deg": 90.0, "hand": 1.0}, &"conflict"),
			_slot(&"straight_setup", {"length": lengths[0]}, &"opening"),
			_slot(&"corner_tight", {"radius": radius, "angle_deg": 90.0, "hand": 1.0}, &"conflict"),
			_slot(&"straight_link", {"length": lengths[1]}, &"connection"),
		]
		start = vertices[3] + Vector2(0.0, radius)
		heading = PI * 0.5
	return _finalize_graph(ordinary, start, heading, radius, StringName("el_two_arm_%d" % variant))


static func _slot(module_id: StringName, parameters: Dictionary, moment: StringName) -> Dictionary:
	return {"module_id": module_id, "parameters": parameters, "moment": moment, "closure": false}


static func _finalize_graph(ordinary: Array[Dictionary], start: Vector2, heading: float, closure_radius: float, graph_id: StringName) -> Dictionary:
	var slots: Array[Dictionary] = ordinary.duplicate(true)
	for role: StringName in [&"closure_turn", &"closure_link", &"closure_turn"]:
		slots.append({"module_id": &"closure", "parameters": {}, "moment": role, "closure": true})
	for index in slots.size():
		slots[index]["index"] = index
		slots[index]["predecessor"] = posmod(index - 1, slots.size())
		slots[index]["successor"] = (index + 1) % slots.size()
	return {
		"ok": true,
		"id": graph_id,
		"slots": slots,
		"ordinary_slots": ordinary,
		"start_position": start,
		"start_heading": heading,
		"closure_radius": closure_radius,
		"closure_slot_count": 3,
	}


static func _place_graph(graph: Dictionary, room: Dictionary, band: Dictionary, counters: Dictionary, limits: Dictionary) -> Dictionary:
	var modules: Array[Dictionary] = []
	var state := {
		"budget_exhausted": false,
		"stage": &"placement",
		"reason": "",
		"placement_start": int(counters["placement_expansions"]),
		"closure_start": int(counters["closure_candidates"]),
	}
	var placed := _place_slot_recursive(graph, room, band, counters, limits, 0, modules, state)
	if bool(state["budget_exhausted"]):
		return state
	if not bool(placed.get("ok", false)):
		return {"ok": false}
	return placed


static func _place_slot_recursive(graph: Dictionary, room: Dictionary, band: Dictionary, counters: Dictionary, limits: Dictionary, slot_index: int, modules: Array[Dictionary], state: Dictionary) -> Dictionary:
	var ordinary: Array = graph["ordinary_slots"]
	if slot_index >= ordinary.size():
		return _solve_closure(graph, room, band, counters, limits, modules, state)
	if int(counters["placement_expansions"]) - int(state["placement_start"]) >= int(limits["placement_expansions_per_graph"]):
		state.merge({"budget_exhausted": true, "stage": &"placement", "reason": "Placement reached its bounded expansion cap."}, true)
		return {}
	var slot: Dictionary = ordinary[slot_index]
	for option: Dictionary in _slot_options(slot, graph, slot_index):
		counters["placement_expansions"] = int(counters["placement_expansions"]) + 1
		var module := MODULES.instantiate(slot["module_id"], option)
		if not bool(module.get("ok", false)):
			continue
		modules.append(module)
		var partial := MODULES.compose(modules, graph["start_position"], float(graph["start_heading"]))
		if not _consume_narrow_phase(partial, room, counters, limits):
			state.merge({"budget_exhausted": true, "stage": &"narrow_phase", "reason": "Placement reached the shared narrow-phase operation cap."}, true)
			return {}
		if _partial_route_valid(partial, room) and _remaining_feasible(partial, ordinary, slot_index + 1, band):
			var solved := _place_slot_recursive(graph, room, band, counters, limits, slot_index + 1, modules, state)
			if bool(state["budget_exhausted"]) or bool(solved.get("ok", false)):
				return solved
		modules.pop_back()
		counters["placement_backtracks"] = int(counters["placement_backtracks"]) + 1
		if int(counters["placement_expansions"]) - int(state["placement_start"]) >= int(limits["placement_expansions_per_graph"]):
			state.merge({"budget_exhausted": true, "stage": &"placement", "reason": "Placement reached its bounded expansion cap."}, true)
			return {}
	return {}


static func _slot_options(slot: Dictionary, graph: Dictionary, slot_index: int) -> Array[Dictionary]:
	var target: Dictionary = slot["parameters"]
	var options: Array[Dictionary] = [target.duplicate(true)]
	var module_id: StringName = slot["module_id"]
	if module_id in [&"straight_link", &"straight_setup"]:
		var minimum := 1000.0 if bool(target.get("finish", false)) else (520.0 if module_id == &"straight_setup" else 180.0)
		var maximum := 2400.0
		for length: float in [minimum, (minimum + maximum) * 0.5, maximum]:
			var parameters := target.duplicate(true)
			parameters["length"] = length
			options.append(parameters)
		for draw in 4:
			var parameters := target.duplicate(true)
			var unit := float(_hash_index(graph, "slot_length", slot_index * 8 + draw, 35521)) / 35520.0
			parameters["length"] = snappedf(lerpf(minimum, maximum, unit), 1.0 / 16.0)
			options.append(parameters)
	elif module_id.begins_with("corner_"):
		var bounds := {&"corner_tight": Vector2(180.0, 259.9375), &"corner_medium": Vector2(260.0, 519.9375), &"corner_sweeper": Vector2(520.0, 1000.0)}[module_id] as Vector2
		for candidate_radius: float in [bounds.x, (bounds.x + bounds.y) * 0.5, bounds.y]:
			var parameters := target.duplicate(true)
			parameters["radius"] = snappedf(candidate_radius, 1.0 / 16.0)
			options.append(parameters)
		for draw in 4:
			var parameters := target.duplicate(true)
			var unit := float(_hash_index(graph, "slot_radius", slot_index * 8 + draw, 4161)) / 4160.0
			parameters["radius"] = snappedf(lerpf(bounds.x, bounds.y, unit), 1.0 / 16.0)
			options.append(parameters)
	elif module_id == &"chicane_return":
		for tuple: Dictionary in [
			{"radius": 180.0, "angle_deg": 30.0, "distance": 180.0},
			{"radius": 350.0, "angle_deg": 45.0, "distance": 540.0},
			{"radius": 520.0, "angle_deg": 60.0, "distance": 900.0},
		]:
			var parameters := target.duplicate(true)
			parameters.merge(tuple, true)
			options.append(parameters)
		for draw in 4:
			var parameters := target.duplicate(true)
			var radius_unit := float(_hash_index(graph, "slot_chicane_radius", slot_index * 8 + draw, 5441)) / 5440.0
			var distance_unit := float(_hash_index(graph, "slot_chicane_distance", slot_index * 8 + draw, 11521)) / 11520.0
			parameters["radius"] = snappedf(lerpf(180.0, 520.0, radius_unit), 1.0 / 16.0)
			parameters["distance"] = snappedf(lerpf(180.0, 900.0, distance_unit), 1.0 / 16.0)
			parameters["angle_deg"] = [30.0, 45.0, 60.0][_hash_index(graph, "slot_chicane_angle", slot_index * 8 + draw, 3)]
			options.append(parameters)
	return _deduplicate_options(options)


static func _deduplicate_options(options: Array[Dictionary]) -> Array[Dictionary]:
	var seen := {}
	var result: Array[Dictionary] = []
	for option: Dictionary in options:
		var key := JSON.stringify(option, "", true)
		if not seen.has(key):
			seen[key] = true
			result.append(option)
	return result


static func _remaining_feasible(partial: Dictionary, slots: Array, next_slot: int, band: Dictionary) -> bool:
	var minimum_remaining := 0.0
	var maximum_remaining := 0.0
	var minimum_turn := 0.0
	var maximum_turn := 0.0
	for index in range(next_slot, slots.size()):
		var slot: Dictionary = slots[index]
		var parameters: Dictionary = slot["parameters"]
		if slot["module_id"] in [&"straight_link", &"straight_setup"]:
			minimum_remaining += 180.0 if slot["module_id"] == &"straight_link" else (1000.0 if bool(parameters.get("finish", false)) else 520.0)
			maximum_remaining += 2400.0
		elif slot["module_id"] == &"chicane_return":
			minimum_remaining += 4.0 * 180.0 * deg_to_rad(30.0) + 180.0
			maximum_remaining += 4.0 * 520.0 * deg_to_rad(60.0) + 900.0
		else:
			var turn := deg_to_rad(float(parameters.get("angle_deg", 90.0))) * signf(float(parameters.get("hand", 1.0)))
			minimum_remaining += 180.0 * absf(turn)
			maximum_remaining += 1000.0 * absf(turn)
			minimum_turn += turn
			maximum_turn += turn
	var exit: Dictionary = partial["exit_port"]
	var entry: Dictionary = partial["entry_port"]
	var closure_lower := (exit["position"] as Vector2).distance_to(entry["position"])
	minimum_remaining += closure_lower
	maximum_remaining += 2.0 * PI * 1000.0 + 2400.0
	var current_length := float(partial["length"])
	if current_length + minimum_remaining > float(band["max_length"]) or current_length + maximum_remaining < float(band["min_length"]):
		return false
	var current_turn := float(partial["signed_turn"])
	var closure_turn_allowance := 3.0 * PI
	return current_turn + minimum_turn - closure_turn_allowance <= TAU and current_turn + maximum_turn + closure_turn_allowance >= TAU


static func _solve_closure(graph: Dictionary, room: Dictionary, band: Dictionary, counters: Dictionary, limits: Dictionary, modules: Array[Dictionary], state: Dictionary) -> Dictionary:
	var partial := MODULES.compose(modules, graph["start_position"], float(graph["start_heading"]))
	var frontier: Dictionary = partial["exit_port"]
	var target: Dictionary = partial["entry_port"]
	for radius: float in CLOSURE_RADII:
		for family: StringName in CLOSURE_FAMILIES:
			if int(counters["closure_candidates"]) - int(state["closure_start"]) >= int(limits["closure_candidates_per_frontier"]):
				state.merge({"budget_exhausted": true, "stage": &"closure", "reason": "Closure reached its bounded candidate cap."}, true)
				return {}
			counters["closure_candidates"] = int(counters["closure_candidates"]) + 1
			var connector := _dubins_connector(frontier, target, radius, family)
			if not bool(connector.get("ok", false)):
				counters["closure_rejections"] = int(counters["closure_rejections"]) + 1
				continue
			var all_modules: Array[Dictionary] = modules.duplicate()
			all_modules.append_array(connector["modules"])
			var route := MODULES.compose(all_modules, graph["start_position"], float(graph["start_heading"]))
			var join := MODULES.validate_join(route["exit_port"], route["entry_port"])
			if not bool(join.get("valid", false)) or float(route["length"]) < float(band["min_length"]) or float(route["length"]) > float(band["max_length"]):
				counters["closure_rejections"] = int(counters["closure_rejections"]) + 1
				continue
			if not _consume_narrow_phase(route, room, counters, limits):
				state.merge({"budget_exhausted": true, "stage": &"narrow_phase", "reason": "Closure reached the shared narrow-phase operation cap."}, true)
				return {}
			if not bool(ROOM_MODEL.route_fits(room, route, MODULES.RESERVED_RADIUS).get("valid", false)):
				counters["closure_rejections"] = int(counters["closure_rejections"]) + 1
				continue
			route["closure"] = {"family": family, "radius": radius, "module_count": (connector["modules"] as Array).size(), "candidate_index": int(counters["closure_candidates"]) - 1}
			return {"ok": true, "route": route, "closure_position_residual": float(join["position_residual"]), "closure_heading_residual": float(join["heading_residual"])}
	return {"ok": false}


static func _dubins_connector(start: Dictionary, goal: Dictionary, radius: float, family: StringName) -> Dictionary:
	var start_position: Vector2 = start["position"]
	var start_heading := float(start["heading"])
	var local_goal := ((goal["position"] as Vector2) - start_position).rotated(-start_heading)
	var local_heading := _wrapped_angle(float(goal["heading"]) - start_heading)
	var distance := local_goal.length() / radius
	var theta := local_goal.angle()
	var alpha := fposmod(-theta, TAU)
	var beta := fposmod(local_heading - theta, TAU)
	var parameters := _dubins_parameters(family, alpha, beta, distance)
	if not bool(parameters.get("ok", false)):
		return parameters
	var normalized: PackedFloat64Array = parameters["parameters"]
	var kinds: Array[StringName] = parameters["kinds"]
	var connector_modules: Array[Dictionary] = []
	for index in kinds.size():
		var amount := float(normalized[index])
		if kinds[index] == &"S":
			var length := amount * radius
			if length < 180.0 or length > 2400.0:
				return {"ok": false, "kind": &"closure_domain"}
			connector_modules.append(MODULES.instantiate(&"straight_link", {"length": length}))
		else:
			if amount <= MODULES.HEADING_TOLERANCE or amount > PI + MODULES.HEADING_TOLERANCE:
				return {"ok": false, "kind": &"closure_arc_domain"}
			var turn := amount if kinds[index] == &"L" else -amount
			connector_modules.append(MODULES.instantiate_closure_arc(radius, turn))
	for module: Dictionary in connector_modules:
		if not bool(module.get("ok", false)):
			return {"ok": false, "kind": &"closure_module"}
	var local_route := MODULES.compose(connector_modules)
	var residual_position := (local_route["exit_port"]["position"] as Vector2).distance_to(local_goal)
	var residual_heading := absf(_wrapped_angle(float(local_route["exit_port"]["heading"]) - local_heading))
	if residual_position > MODULES.POSITION_TOLERANCE or residual_heading > MODULES.HEADING_TOLERANCE:
		return {"ok": false, "kind": &"closure_residual"}
	return {"ok": true, "modules": connector_modules, "position_residual": residual_position, "heading_residual": residual_heading}


static func _dubins_parameters(family: StringName, alpha: float, beta: float, distance: float) -> Dictionary:
	var sa := sin(alpha)
	var sb := sin(beta)
	var ca := cos(alpha)
	var cb := cos(beta)
	var cab := cos(alpha - beta)
	var t := 0.0
	var p := 0.0
	var q := 0.0
	match family:
		&"LSL":
			var p2 := 2.0 + distance * distance - 2.0 * cab + 2.0 * distance * (sa - sb)
			if p2 < 0.0: return {"ok": false}
			var angle := atan2(cb - ca, distance + sa - sb)
			t = fposmod(-alpha + angle, TAU)
			p = sqrt(p2)
			q = fposmod(beta - angle, TAU)
		&"RSR":
			var p2 := 2.0 + distance * distance - 2.0 * cab + 2.0 * distance * (-sa + sb)
			if p2 < 0.0: return {"ok": false}
			var angle := atan2(ca - cb, distance - sa + sb)
			t = fposmod(alpha - angle, TAU)
			p = sqrt(p2)
			q = fposmod(-beta + angle, TAU)
		&"LSR":
			var p2 := -2.0 + distance * distance + 2.0 * cab + 2.0 * distance * (sa + sb)
			if p2 < 0.0: return {"ok": false}
			p = sqrt(p2)
			var angle := atan2(-ca - cb, distance + sa + sb) - atan2(-2.0, p)
			t = fposmod(-alpha + angle, TAU)
			q = fposmod(-beta + angle, TAU)
		&"RSL":
			var p2 := distance * distance - 2.0 + 2.0 * cab - 2.0 * distance * (sa + sb)
			if p2 < 0.0: return {"ok": false}
			p = sqrt(p2)
			var angle := atan2(ca + cb, distance - sa - sb) - atan2(2.0, p)
			t = fposmod(alpha - angle, TAU)
			q = fposmod(beta - angle, TAU)
		&"RLR":
			var value := (6.0 - distance * distance + 2.0 * cab + 2.0 * distance * (sa - sb)) / 8.0
			if absf(value) > 1.0: return {"ok": false}
			p = fposmod(TAU - acos(clampf(value, -1.0, 1.0)), TAU)
			t = fposmod(alpha - atan2(ca - cb, distance - sa + sb) + p * 0.5, TAU)
			q = fposmod(alpha - beta - t + p, TAU)
		&"LRL":
			var value := (6.0 - distance * distance + 2.0 * cab + 2.0 * distance * (-sa + sb)) / 8.0
			if absf(value) > 1.0: return {"ok": false}
			p = fposmod(TAU - acos(clampf(value, -1.0, 1.0)), TAU)
			t = fposmod(-alpha - atan2(ca - cb, distance + sa - sb) + p * 0.5, TAU)
			q = fposmod(beta - alpha - t + p, TAU)
		_:
			return {"ok": false}
	var kinds: Array[StringName]
	match family:
		&"LSL": kinds = [&"L", &"S", &"L"]
		&"RSR": kinds = [&"R", &"S", &"R"]
		&"LSR": kinds = [&"L", &"S", &"R"]
		&"RSL": kinds = [&"R", &"S", &"L"]
		&"LRL": kinds = [&"L", &"R", &"L"]
		&"RLR": kinds = [&"R", &"L", &"R"]
	return {"ok": true, "parameters": PackedFloat64Array([t, p, q]), "kinds": kinds}


static func _partial_route_valid(route: Dictionary, room: Dictionary) -> bool:
	if not bool(ROOM_MODEL.route_fits(room, route, MODULES.RESERVED_RADIUS).get("valid", false)):
		return false
	var primitives: Array = route["primitives"]
	for first in primitives.size():
		for second in range(first + 2, primitives.size()):
			if not VALIDATION._primitive_intersections(primitives[first], primitives[second]).is_empty():
				return false
	return true


static func _consume_narrow_phase(route: Dictionary, room: Dictionary, counters: Dictionary, limits: Dictionary) -> bool:
	var primitive_count := (route.get("primitives", []) as Array).size()
	var boundary_edges := (room.get("outer", PackedVector2Array()) as PackedVector2Array).size()
	for hole: PackedVector2Array in room.get("solid_exclusions", []):
		boundary_edges += hole.size()
	var operations := primitive_count * boundary_edges + primitive_count * maxi(primitive_count - 1, 0) / 2
	counters["narrow_phase_operations"] = int(counters["narrow_phase_operations"]) + operations
	return int(counters["narrow_phase_operations"]) <= int(limits["narrow_phase_operations"])


static func _assign_regions_and_portals(graph: Dictionary, room: Dictionary, route: Dictionary) -> Dictionary:
	var visits: Array[Dictionary] = []
	var required_regions := _required_region_ids(room)
	for region: Dictionary in room.get("regions", []):
		var slot_indices := PackedInt32Array()
		for module: Dictionary in route["modules"]:
			var midpoint := (module["entry_port"]["position"] as Vector2).lerp(module["exit_port"]["position"], 0.5)
			if Geometry2D.is_point_in_polygon(midpoint, region["polygon"]):
				slot_indices.append(int(module["index"]))
		if bool(region.get("required", false)) and slot_indices.is_empty():
			return {"ok": false, "kind": &"required_region_unvisited"}
		visits.append({"region_id": region["id"], "required": bool(region.get("required", false)), "slot_indices": slot_indices})
	var traversals: Array[Dictionary] = []
	for portal: Dictionary in room.get("portals", []):
		if not required_regions.has(portal["region_a"]) or not required_regions.has(portal["region_b"]):
			continue
		var crossings := _portal_crossings(route, portal)
		if (crossings["points"] as PackedVector2Array).size() != 2:
			return {"ok": false, "kind": &"portal_traversal_count"}
		var lanes: PackedVector2Array = crossings["points"]
		if lanes[0].distance_to(lanes[1]) < ROOM_MODEL.LANE_SEPARATION:
			return {"ok": false, "kind": &"portal_lane_spacing"}
		traversals.append({
			"portal_id": portal["id"],
			"region_a": portal["region_a"],
			"region_b": portal["region_b"],
			"lane_centers": lanes,
			"slot_indices": crossings["slot_indices"],
			"clear_width": float(portal.get("clear_width", 0.0)),
		})
	return {"ok": true, "region_visits": visits, "portal_traversals": traversals}


static func _required_region_ids(room: Dictionary) -> Dictionary:
	var result := {}
	for region: Dictionary in room.get("regions", []):
		if bool(region.get("required", false)):
			result[region["id"]] = true
	return result


static func _portal_crossings(route: Dictionary, portal: Dictionary) -> Dictionary:
	var portal_line := {
		"kind": &"line",
		"start": portal["segment_from"],
		"end": portal["segment_to"],
	}
	var records: Array[Dictionary] = []
	var segment: Vector2 = portal["segment_to"] - portal["segment_from"]
	for primitive: Dictionary in route["primitives"]:
		for point: Vector2 in VALIDATION._primitive_intersections(primitive, portal_line):
			var fraction := (point - (portal["segment_from"] as Vector2)).dot(segment) / segment.length_squared()
			records.append({"point": point, "fraction": fraction, "module_index": int(primitive["module_index"])})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["fraction"]) < float(b["fraction"]))
	var points := PackedVector2Array()
	var slots := PackedInt32Array()
	for record: Dictionary in records:
		if not points.is_empty() and points[points.size() - 1].distance_to(record["point"]) <= MODULES.POSITION_TOLERANCE:
			continue
		points.append(record["point"])
		slots.append(int(record["module_index"]))
	return {"points": points, "slot_indices": slots}


static func _complete_cycle(graph: Dictionary, route: Dictionary) -> Array[Dictionary]:
	var slots: Array[Dictionary] = graph["slots"].duplicate(true)
	var modules: Array = route["modules"]
	for index in slots.size():
		if index < modules.size():
			slots[index]["module_id"] = modules[index]["id"]
			slots[index]["parameters"] = (modules[index]["parameters"] as Dictionary).duplicate(true)
	return slots


static func _ring_bounds(ring: PackedVector2Array) -> Rect2:
	var bounds := Rect2(ring[0], Vector2.ZERO)
	for point: Vector2 in ring:
		bounds = bounds.expand(point)
	return bounds


static func _concave_vertex(ring: PackedVector2Array) -> Vector2:
	for index in ring.size():
		var incoming := (ring[index] - ring[posmod(index - 1, ring.size())]).normalized()
		var outgoing := (ring[(index + 1) % ring.size()] - ring[index]).normalized()
		if incoming.cross(outgoing) < -0.5:
			return ring[index]
	return Vector2(INF, INF)


static func _hash_index(identity: Dictionary, domain: String, index: int, count: int) -> int:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(("v8|%s|%s|%s|%s|%d" % [domain, identity.get("room_shape", identity.get("id", "")), identity.get("length_tier", ""), identity.get("seed", 0), index]).to_utf8_buffer())
	var digest := context.finish()
	var value := (int(digest[0]) << 24) | (int(digest[1]) << 16) | (int(digest[2]) << 8) | int(digest[3])
	return posmod(value, count)


static func _wrapped_angle(angle: float) -> float:
	return wrapf(angle, -PI, PI)


static func _failure(identity: Dictionary, stage: StringName, kind: StringName, reason: String, counters: Dictionary) -> Dictionary:
	return {"ok": false, "valid": false, "identity": identity.duplicate(true), "stage": stage, "kind": kind, "reason": reason, "error": reason, "search": counters.duplicate(true)}
