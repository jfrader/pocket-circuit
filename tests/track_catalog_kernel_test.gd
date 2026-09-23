extends SceneTree

const MODULES := preload("res://scripts/race/track_module_catalog.gd")
const VALIDATION := preload("res://scripts/race/track_layout_validation.gd")
const V8_DEVELOPMENT_GENERATOR := preload("res://scripts/race/track_v8_development_generator.gd")
const REGISTRY := preload("res://scripts/race/track_generator_registry.gd")
const ROOM_MODEL := preload("res://scripts/race/track_room_model.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _test_catalog_contract():
		return
	var room_polygon: PackedVector2Array = TRACK_BUILDER.ROOM_SHAPES["el"]
	var room := ROOM_MODEL.legacy_fixture(&"el", TRACK_BUILDER.WORLD_SCALE)
	var route := V8_DEVELOPMENT_GENERATOR.place_catalog_kernel(room)
	if not _expect(bool(route.get("ok", false)), "hand-composed catalog route should close"):
		return
	if not _expect((route["room_placement"] as Dictionary).get("method") == &"eroded_free_polygon", "catalog fixture should be placed through the free-polygon erosion query"):
		return
	var continuous := VALIDATION.validate_continuous(route, room_polygon)
	if not _expect(bool(continuous.get("valid", false)), "continuous validator should accept the fixture: %s" % continuous.get("reason", "unknown")):
		return
	var sampling := MODULES.sample_route(route, 260, 35.0, 0.25)
	if not _expect(bool(sampling.get("ok", false)) and int(sampling["sample_count"]) >= 260 and float(sampling["maximum_arc_step"]) <= 35.0 and float(sampling["maximum_chord_deviation"]) <= 0.25, "runtime sampling should honor section 5.3"):
		return
	var sampled := VALIDATION.validate_sampled(route, sampling, room_polygon)
	if not _expect(bool(sampled.get("valid", false)), "sampled and gameplay validators should accept the fixture: %s" % sampled.get("reason", "unknown")):
		return
	if not _expect(int(continuous["setup_straight_count"]) >= 2 and int(sampled["setup_straight_count"]) >= 2 and float(continuous["minimum_radius"]) >= 147.0 and float(continuous["minimum_nonlocal_distance"]) >= 320.0, "fixture should retain two setups, radius 147, and self-distance 320"):
		return
	var unavailable := REGISTRY.dispatch({"schema_version": 2, "generator_version": 8}, {"room_shape": &"el", "room_polygon": room_polygon, "room_model": room}, Callable(), Callable(V8_DEVELOPMENT_GENERATOR, "generate"))
	if not _expect(unavailable.get("kind") == &"invalid_identity", "v8 should reject an incomplete explicit request instead of inferring a room identity or falling back to v7"):
		return
	var dispatched := REGISTRY.dispatch(
		{"schema_version": 2, "generator_version": 8},
		{"seed": 928, "room_shape": &"el", "room_polygon": room_polygon, "room_model": room, "development_fixture": &"catalog_kernel", "generation_options": {"length_tier": &"standard"}},
		Callable(),
		Callable(V8_DEVELOPMENT_GENERATOR, "generate")
	)
	if not _expect(bool(dispatched.get("ok", false)) and dispatched["points"] == sampling["points"], "explicit v8 registry dispatch should reach only the catalog fixture"):
		return
	var prepared := TRACK_BUILDER.prepare_layout(&"kitchen", &"el", 928, {"schema_version": 2, "generator_version": 8, "development_fixture": &"catalog_kernel", "length_tier": &"standard", "obstacles_enabled": false})
	if not _expect(not prepared.is_empty() and bool(prepared["spec"].get("centerline_is_sampled", false)) and prepared["centerline"] == sampling["points"], "TrackBuilderCore should retain authoritative v8 samples without Catmull-Rom reinterpretation"):
		return
	if not _test_skip_invariants():
		return
	if not _test_equivalence(route, room_polygon, sampling):
		return
	if not _test_differential():
		return
	if not _test_finish_origin():
		return
	if not _test_exclusive_region_lengths():
		return
	print("TRACK_CATALOG_KERNEL_TEST PASS catalog_classes=11 route_modules=%d primitives=%d samples=%d length=%.2f setups=%d radius=%.2f corridor_half=%.0f continuous_min_distance=%.2f sampled_min_distance=%.2f" % [(route["modules"] as Array).size(), (route["primitives"] as Array).size(), int(sampling["sample_count"]), float(route["length"]), int(continuous["setup_straight_count"]), float(continuous["minimum_radius"]), float(continuous["corridor_half_width"]), float(continuous["minimum_nonlocal_distance"]), float(sampled["minimum_nonlocal_distance"])])
	quit(0)


func _test_catalog_contract() -> bool:
	var fixtures := {
		&"straight_link": {"length": 180.0},
		&"straight_setup": {"length": 1000.0, "finish": true},
		&"corner_tight": {"radius": 180.0, "angle_deg": 45.0, "hand": 1.0},
		&"corner_medium": {"radius": 300.0, "angle_deg": 90.0, "hand": -1.0},
		&"corner_sweeper": {"radius": 700.0, "angle_deg": 135.0, "hand": 1.0},
		&"corner_opening": {"inner_radius": 240.0, "outer_radius": 360.0, "angle_deg": 90.0, "split": 0.5, "hand": 1.0},
		&"corner_tightening": {"inner_radius": 240.0, "outer_radius": 360.0, "angle_deg": 90.0, "split": 0.5, "hand": -1.0},
		&"u_return": {"radius": 180.0, "hand": 1.0},
		&"s_offset": {"radius": 240.0, "angle_deg": 45.0, "distance": 300.0, "hand": 1.0},
		&"chicane_return": {"radius": 240.0, "angle_deg": 45.0, "distance": 300.0, "hand": -1.0},
		&"switchback": {"radius": 240.0, "depth_1": 600.0, "depth_2": 800.0, "width": 500.0, "hand": 1.0},
	}
	if not _expect(MODULES.definitions().size() == 11, "catalog should expose exactly eleven authored classes"):
		return false
	for module_id: StringName in fixtures:
		for unit: float in [0.0, 0.5, 1.0]:
			var units := {}
			for key: String in MODULES.definition(module_id)["parameter_domains"]:
				units["angle_deg" if key == "angles_deg" else key] = unit
			var proposal := MODULES.proposal_parameters(module_id, fixtures[module_id], units)
			if not _expect(bool(MODULES.instantiate(module_id, proposal).get("ok", false)), "%s minimum/midpoint/maximum proposals must respect the catalog domain: %s" % [module_id, proposal]):
				return false
		var module := MODULES.instantiate(module_id, fixtures[module_id])
		if not _expect(bool(module.get("ok", false)), "%s should instantiate inside its authored domain: %s" % [module_id, module.get("reason", "unknown")]):
			return false
		var entry: Dictionary = module["entry_port"]
		var exit: Dictionary = module["exit_port"]
		if not _expect((entry["left"] as Vector2).distance_to(entry["right"]) == 250.0 and float(entry["elevation"]) == 0.0 and is_equal_approx((exit["tangent"] as Vector2).length(), 1.0), "%s ports should carry the full connector contract" % module_id):
			return false
		if not _expect((module["sweeps"] as Array).size() == (module["primitives"] as Array).size() * 2 and (module["validation_hooks"] as Array).size() == 4, "%s should expose radius-125/135 sweeps and validation hooks" % module_id):
			return false
		if not _expect((module["curvature_bounds"] as Vector2).x <= (module["curvature_bounds"] as Vector2).y, "%s should report parameter-specific curvature bounds" % module_id):
			return false
	var rejected := MODULES.instantiate(&"corner_tight", {"radius": 146.9, "angle_deg": 90.0, "hand": 1.0})
	if not _expect(not bool(rejected.get("ok", false)) and rejected.get("kind") == "parameter_domain", "sub-domain radius should fail before composition"):
		return false
	var asymmetric := MODULES.proposal_parameters(&"switchback", fixtures[&"switchback"], {"depth_1": 0.0, "depth_2": 1.0})
	if not _expect(float(asymmetric["depth_1"]) == 450.0 and float(asymmetric["depth_2"]) == 1600.0, "switchback limb depths must vary independently"):
		return false
	var merged_links := MODULES.compose([
		MODULES.instantiate(&"straight_link", {"length": 180.0}),
		MODULES.instantiate(&"straight_link", {"length": 240.0}),
	])
	if not _expect((merged_links["straight_intervals"] as Array).size() == 1 and is_equal_approx(float(merged_links["straight_intervals"][0]["to"]), 420.0), "adjacent collinear links should form one maximal straight interval"):
		return false
	var valid_join: Dictionary = (MODULES.instantiate(&"straight_link", {"length": 180.0}))["exit_port"]
	var shifted_join := valid_join.duplicate(true)
	shifted_join["position"] = (shifted_join["position"] as Vector2) + Vector2(0.011, 0.0)
	if not _expect(not bool(MODULES.validate_join(valid_join, shifted_join)["valid"]), "connector position residuals above 0.01 should fail"):
		return false
	var transformed := MODULES.instantiate(&"corner_opening", fixtures[&"corner_opening"], {"mirror": true, "reverse": true})
	return _expect(bool(transformed.get("ok", false)) and transformed["family"] == &"tightening", "mirror/reverse should rebuild ports and exchange opening semantics")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_CATALOG_KERNEL_TEST FAIL: " + message)
	quit(1)
	return false


func _test_skip_invariants() -> bool:
	# Each case is a pair of segments with per-cell flatten errors. We verify the
	# two properties that make the nonlocal AABB skip exact:
	#   (1) the AABB gap is a lower bound on the exact segment distance, and
	#   (2) a pair is only skipped when its certified distance provably cannot
	#       lower the current running minimum (or trip the threshold).
	var cases: Array[Dictionary] = [
		# nearby crossing just below the 320 threshold (must never be skipped).
		{"a0": Vector2(0, 0), "a1": Vector2(100, 0), "b0": Vector2(0, 319.9), "b1": Vector2(100, 319.9), "ea": 0.0, "eb": 0.0},
		# exactly at the boundary: certified distance is exactly 320.0.
		{"a0": Vector2(0, 0), "a1": Vector2(100, 0), "b0": Vector2(0, 320.0), "b1": Vector2(100, 320.0), "ea": 0.0, "eb": 0.0},
		# arc error allowance: 320.04 raw separation minus two 0.02 errors -> 320.0.
		{"a0": Vector2(0, 0), "a1": Vector2(100, 0), "b0": Vector2(0, 320.04), "b1": Vector2(100, 320.04), "ea": 0.02, "eb": 0.02},
		# far apart: safe to skip.
		{"a0": Vector2(0, 0), "a1": Vector2(100, 0), "b0": Vector2(0, 1000.0), "b1": Vector2(100, 1000.0), "ea": 0.02, "eb": 0.02},
		# diagonal approach where the AABB lower bound is loose: still a valid bound.
		{"a0": Vector2(0, 0), "a1": Vector2(10, 10), "b0": Vector2(5, 320.0), "b1": Vector2(15, 310.0), "ea": 0.02, "eb": 0.02},
	]
	for case: Dictionary in cases:
		var a0: Vector2 = case["a0"]
		var a1: Vector2 = case["a1"]
		var b0: Vector2 = case["b0"]
		var b1: Vector2 = case["b1"]
		var ea := float(case["ea"])
		var eb := float(case["eb"])
		var distance := float((VALIDATION._segment_closest(a0, a1, b0, b1) as Dictionary)["distance"])
		var gap := VALIDATION._aabb_gap_distance(VALIDATION._segment_bounds(a0, a1), VALIDATION._segment_bounds(b0, b1))
		if gap > distance + 0.000001:
			return _expect(false, "AABB gap %.6f must be a lower bound on segment distance %.6f" % [gap, distance])
		var certified := distance - ea - eb
		for current_minimum: float in [INF, 400.0, 340.0, 320.0, 319.5]:
			if VALIDATION._nonlocal_skip_safe(VALIDATION._segment_bounds(a0, a1), VALIDATION._segment_bounds(b0, b1), ea, eb, current_minimum) and certified < current_minimum:
				return _expect(false, "skip reported safe at current_min=%.4f but certified %.6f would lower the minimum" % [current_minimum, certified])
	var nearby := VALIDATION._segment_bounds(Vector2(0, 0), Vector2(100, 0))
	var nearby_other := VALIDATION._segment_bounds(Vector2(0, 319.9), Vector2(100, 319.9))
	if VALIDATION._nonlocal_skip_safe(nearby, nearby_other, 0.0, 0.0, 350.0):
		return _expect(false, "nearby-crossing pair (319.9) below current minimum 350.0 was incorrectly skipped")
	var boundary := VALIDATION._segment_bounds(Vector2(0, 320.0), Vector2(100, 320.0))
	if VALIDATION._nonlocal_skip_safe(nearby, boundary, 0.0, 0.0, 350.0):
		return _expect(false, "exactly-at-boundary pair (320.0) below current minimum 350.0 was incorrectly skipped")
	return true


func _test_finish_origin() -> bool:
	var instances: Array[Dictionary] = [
		MODULES.instantiate(&"corner_tight", {"radius": 180.0, "angle_deg": 90.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_setup", {"length": 1000.0, "finish": true}),
		MODULES.instantiate(&"corner_tight", {"radius": 180.0, "angle_deg": 90.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_link", {"length": 1000.0}),
		MODULES.instantiate(&"corner_tight", {"radius": 180.0, "angle_deg": 90.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_link", {"length": 1000.0}),
		MODULES.instantiate(&"corner_tight", {"radius": 180.0, "angle_deg": 90.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_link", {"length": 1000.0}),
	]
	var route := MODULES.compose(instances)
	if not _expect(bool(route.get("ok", false)), "finish-origin fixture should compose"):
		return false
	var primitives: Array = route["primitives"]
	var finish_index := -1
	for index in primitives.size():
		var primitive: Dictionary = primitives[index]
		if primitive["kind"] == &"line" and (route["modules"][primitive["module_index"]] as Dictionary)["id"] == &"straight_setup":
			finish_index = index
			break
	if not _expect(finish_index == 1, "fixture finish straight should be the second primitive, got %d" % finish_index):
		return false
	var default_sampling := MODULES.sample_route(route, 260, 35.0, 0.25)
	if not _expect(bool(default_sampling.get("ok", false)), "default sampling should succeed"):
		return false
	if not _expect((default_sampling["points"] as PackedVector2Array)[0] == ((primitives[0] as Dictionary)["start"] as Vector2), "default sampling should start at the first primitive's analytic start"):
		return false
	if not _check_sampled_boundaries(route, default_sampling, "default"):
		return false
	var finish_route := route.duplicate(true)
	finish_route["finish_primitive_index"] = finish_index
	var midpoint: Vector2 = ((primitives[finish_index] as Dictionary)["start"] as Vector2).lerp((primitives[finish_index] as Dictionary)["end"] as Vector2, 0.5)
	var finish_sampling := MODULES.sample_route(finish_route, 260, 35.0, 0.25)
	if not _expect(bool(finish_sampling.get("ok", false)), "finish-origin sampling should succeed"):
		return false
	if not _expect((finish_sampling["points"] as PackedVector2Array)[0].distance_to(midpoint) <= 0.000001, "finish-origin sampling should start at the finish-line midpoint"):
		return false
	if not _check_sampled_boundaries(finish_route, finish_sampling, "finish-origin"):
		return false
	if not _expect(int(finish_sampling["sample_count"]) >= 260 and float(finish_sampling["maximum_step"]) <= 35.0 and float(finish_sampling["maximum_arc_step"]) <= 35.0 and float(finish_sampling["maximum_chord_deviation"]) <= 0.25, "finish-origin sampling should preserve step/arc/deviation bounds"):
		return false
	var arc_origin := route.duplicate(true)
	arc_origin["finish_primitive_index"] = 0
	var arc_rejected := MODULES.sample_route(arc_origin, 260, 35.0, 0.25)
	if not _expect(not bool(arc_rejected.get("ok", false)) and arc_rejected.get("kind") == "finish_primitive_index", "nonline finish origin should be rejected"):
		return false
	var over_origin := route.duplicate(true)
	over_origin["finish_primitive_index"] = primitives.size()
	var over_rejected := MODULES.sample_route(over_origin, 260, 35.0, 0.25)
	if not _expect(not bool(over_rejected.get("ok", false)) and over_rejected.get("kind") == "finish_primitive_index", "out-of-range finish origin should be rejected"):
		return false
	var negative_origin := route.duplicate(true)
	negative_origin["finish_primitive_index"] = -1
	var negative_rejected := MODULES.sample_route(negative_origin, 260, 35.0, 0.25)
	if not _expect(not bool(negative_rejected.get("ok", false)) and negative_rejected.get("kind") == "finish_primitive_index", "negative finish origin should be rejected"):
		return false
	var typed_origin := route.duplicate(true)
	typed_origin["finish_primitive_index"] = 1.0
	var typed_rejected := MODULES.sample_route(typed_origin, 260, 35.0, 0.25)
	if not _expect(not bool(typed_rejected.get("ok", false)) and typed_rejected.get("kind") == "finish_primitive_index", "non-integer finish origin should be rejected"):
		return false
	return true


func _check_sampled_boundaries(route: Dictionary, sampling: Dictionary, label: String) -> bool:
	var primitives: Array = route["primitives"]
	var points: PackedVector2Array = sampling["points"]
	var boundaries: PackedInt32Array = sampling["primitive_boundaries"]
	if not _expect(boundaries.size() == primitives.size(), "%s sampling should expose one boundary per primitive" % label):
		return false
	for index in primitives.size():
		var start: Vector2 = (primitives[index] as Dictionary)["start"]
		if not _expect(boundaries[index] >= 0 and boundaries[index] < points.size() and points[boundaries[index]].distance_to(start) <= 0.01, "%s boundary %d should resolve primitive %d's analytic start" % [label, index, index]):
			return false
	return true


## Exact exclusive-region lengths: overlapping rectangles keep only the
## non-overlapping line portions, a route wholly inside an overlap yields zero,
## a quarter-arc cut by a horizontal boundary yields known analytic arc lengths,
## and a query cap below the required primitive-edge count returns an incomplete
## (budget-exhausted, never `ok`) result.
func _test_exclusive_region_lengths() -> bool:
	var line_primitive := {"kind": &"line", "start": Vector2(0.0, 50.0), "end": Vector2(150.0, 50.0), "length": 150.0}
	var route := {"ok": true, "primitives": [line_primitive]}
	var west := {"id": &"west", "polygon": PackedVector2Array([Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0), Vector2(0.0, 100.0)])}
	var east := {"id": &"east", "polygon": PackedVector2Array([Vector2(50.0, 0.0), Vector2(150.0, 0.0), Vector2(150.0, 100.0), Vector2(50.0, 100.0)])}
	var result: Dictionary = VALIDATION.exclusive_region_lengths(route, [west, east])
	if not _expect(bool(result.get("ok", false)) and not bool(result.get("budget_exhausted", false)) and int(result.get("query_operations", 0)) == 8, "overlapping-rectangle exclusive query should complete with 8 primitive-edge queries"):
		return false
	if not _expect(is_equal_approx(float(result["lengths"][&"west"]), 50.0) and is_equal_approx(float(result["lengths"][&"east"]), 50.0), "overlapping rectangles should keep only the exclusive 50/50 line portions: %s" % result["lengths"]):
		return false

	var inner := {"kind": &"line", "start": Vector2(60.0, 50.0), "end": Vector2(90.0, 50.0), "length": 30.0}
	var inner_route := {"ok": true, "primitives": [inner]}
	var inner_result: Dictionary = VALIDATION.exclusive_region_lengths(inner_route, [west, east])
	if not _expect(bool(inner_result.get("ok", false)) and is_equal_approx(float(inner_result["lengths"][&"west"]), 0.0) and is_equal_approx(float(inner_result["lengths"][&"east"]), 0.0), "route wholly inside the overlap should yield zero exclusive length: %s" % inner_result["lengths"]):
		return false

	var radius := 600.0
	var arc_primitive := {
		"kind": &"arc",
		"start": Vector2(radius, 0.0),
		"end": Vector2(0.0, radius),
		"center": Vector2.ZERO,
		"radius": radius,
		"signed_turn": PI * 0.5,
		"start_angle": 0.0,
		"length": radius * PI * 0.5,
	}
	var arc_route := {"ok": true, "primitives": [arc_primitive]}
	var lower := {"id": &"lower", "polygon": PackedVector2Array([Vector2(-1000.0, -1000.0), Vector2(1000.0, -1000.0), Vector2(1000.0, 300.0), Vector2(-1000.0, 300.0)])}
	var upper := {"id": &"upper", "polygon": PackedVector2Array([Vector2(-1000.0, 300.0), Vector2(1000.0, 300.0), Vector2(1000.0, 1000.0), Vector2(-1000.0, 1000.0)])}
	var arc_result: Dictionary = VALIDATION.exclusive_region_lengths(arc_route, [lower, upper])
	var expected_lower := radius * PI / 6.0
	var expected_upper := radius * PI / 3.0
	if not _expect(bool(arc_result.get("ok", false)) and is_equal_approx(float(arc_result["lengths"][&"lower"]), expected_lower) and is_equal_approx(float(arc_result["lengths"][&"upper"]), expected_upper), "quarter-arc cut by a horizontal boundary should give exact arc lengths %.6f/%.6f: %s" % [expected_lower, expected_upper, arc_result["lengths"]]):
		return false

	var capped: Dictionary = VALIDATION.exclusive_region_lengths(route, [west, east], 2)
	if not _expect(not bool(capped.get("ok", false)) and bool(capped.get("budget_exhausted", false)) and int(capped.get("query_operations", 0)) == 2, "query cap below the required edge count should return an incomplete budget-exhausted result: %s" % capped):
		return false
	return true


func _test_equivalence(route: Dictionary, room_polygon: PackedVector2Array, sampling: Dictionary) -> bool:
	var continuous: Dictionary = VALIDATION.validate_continuous(route, room_polygon)
	var brute: Dictionary = _brute_force_continuous(route)
	if not bool(continuous.get("valid", false)):
		return _expect(false, "catalog route should stay valid for the equivalence check: %s" % continuous.get("reason", "unknown"))
	if not _expect(float(continuous["minimum_nonlocal_distance"]) == float(brute["minimum_nonlocal"]), "continuous minimum_nonlocal %.8f should equal brute force %.8f" % [float(continuous["minimum_nonlocal_distance"]), float(brute["minimum_nonlocal"])]):
		return false
	if not _expect(float(continuous["minimum_return_limb_distance"]) == float(brute["minimum_return_limb"]), "continuous minimum_return_limb %.8f should equal brute force %.8f" % [float(continuous["minimum_return_limb_distance"]), float(brute["minimum_return_limb"])]):
		return false
	if not _expect(float(brute["minimum_nonlocal"]) >= VALIDATION.MIN_SELF_DISTANCE and float(brute["minimum_return_limb"]) >= VALIDATION.MIN_SELF_DISTANCE, "brute-force minima must stay at or above the 320 threshold"):
		return false
	var points: PackedVector2Array = sampling["points"]
	var sampled_check: Dictionary = VALIDATION._sampled_segment_checks(points, float(route["length"]), room_polygon, float(sampling["maximum_chord_deviation"]))
	var sampled_brute := _brute_force_sampled(points, float(route["length"]), float(sampling["maximum_chord_deviation"]))
	if not bool(sampled_check.get("valid", false)):
		return _expect(false, "sampled route should stay valid for the equivalence check: %s" % sampled_check.get("reason", "unknown"))
	return _expect(float(sampled_check["minimum_nonlocal_distance"]) == sampled_brute, "sampled minimum_nonlocal %.8f should equal brute force %.8f" % [float(sampled_check["minimum_nonlocal_distance"]), sampled_brute])


func _brute_force_continuous(route: Dictionary) -> Dictionary:
	var cells: Array = VALIDATION._flatten_route(route)
	var primitives: Array = route["primitives"]
	var minimum_nonlocal := INF
	var minimum_return_limb := VALIDATION._minimum_endpoint_return_distance(primitives)
	for first in cells.size():
		var a: Dictionary = cells[first]
		for second in range(first + 1, cells.size()):
			var b: Dictionary = cells[second]
			var midpoint_separation := VALIDATION._cyclic_separation((float(a["s0"]) + float(a["s1"])) * 0.5, (float(b["s0"]) + float(b["s1"])) * 0.5, float(route["length"]))
			var possible_separation := midpoint_separation + (float(a["s1"]) - float(a["s0"]) + float(b["s1"]) - float(b["s0"])) * 0.5
			var closest: Dictionary = VALIDATION._segment_closest(a["from"], a["to"], b["from"], b["to"])
			var certified_distance := float(closest["distance"]) - float(a["error"]) - float(b["error"])
			if possible_separation >= VALIDATION.LOCAL_ARC_CUTOFF:
				minimum_nonlocal = minf(minimum_nonlocal, certified_distance)
			elif VALIDATION._stationary_return_pair(a, b, closest, primitives.size()):
				minimum_return_limb = minf(minimum_return_limb, certified_distance)
	return {"minimum_nonlocal": minimum_nonlocal, "minimum_return_limb": minimum_return_limb}


func _brute_force_sampled(points: PackedVector2Array, total_length: float, approximation_error: float) -> float:
	var cumulative := PackedFloat64Array([0.0])
	for index in points.size():
		cumulative.append(cumulative[index] + points[index].distance_to(points[(index + 1) % points.size()]))
	var sampled_length := float(cumulative[cumulative.size() - 1])
	var minimum_nonlocal := INF
	for first in points.size():
		var first_next := (first + 1) % points.size()
		for second in range(first + 1, points.size()):
			var second_next := (second + 1) % points.size()
			if first_next == second or second_next == first:
				continue
			var first_s := (float(cumulative[first]) + float(cumulative[first + 1])) * 0.5
			var second_s := (float(cumulative[second]) + float(cumulative[second + 1])) * 0.5
			var half_lengths := (points[first].distance_to(points[first_next]) + points[second].distance_to(points[second_next])) * 0.5
			if VALIDATION._cyclic_separation(first_s, second_s, sampled_length) + half_lengths < VALIDATION.LOCAL_ARC_CUTOFF:
				continue
			var distance := float((VALIDATION._segment_closest(points[first], points[first_next], points[second], points[second_next]) as Dictionary)["distance"]) - approximation_error * 2.0
			minimum_nonlocal = minf(minimum_nonlocal, distance)
	return minimum_nonlocal


## Differential coverage of the continuous x-sorted sweep and the arc-near
## return-limb windows: the optimized validator must reproduce the exhaustive
## brute-force minima bit-for-bit across rotations, a reversed route, loop-seam
## shifts, and routes that sit just above and just below the 320 threshold.
func _test_differential() -> bool:
	var instances: Array[Dictionary] = _catalog_instances()
	var fixtures: Array[Dictionary] = []
	fixtures.append({"label": "base", "route": MODULES.compose(instances, Vector2(-800.0, 100.0), 0.0)})
	for heading_deg: float in [37.0, 91.0, 173.0, 251.0]:
		fixtures.append({"label": "rot%d" % int(heading_deg), "route": MODULES.compose(instances, Vector2(120.0, -40.0), deg_to_rad(heading_deg))})
	var reversed: Array[Dictionary] = []
	for index in range(instances.size() - 1, -1, -1):
		var source: Dictionary = instances[index]
		reversed.append(MODULES.instantiate(source["id"], (source["parameters"] as Dictionary).duplicate(true), {"reverse": true}))
	fixtures.append({"label": "reverse", "route": MODULES.compose(reversed, Vector2(120.0, -40.0), deg_to_rad(37.0))})
	for shift: int in [1, 3, 5, 7]:
		var reordered: Array[Dictionary] = []
		for index in instances.size():
			reordered.append(instances[(index + shift) % instances.size()])
		fixtures.append({"label": "seam%d" % shift, "route": MODULES.compose(reordered, Vector2(120.0, -40.0), deg_to_rad(37.0))})
	var chicane := MODULES.instantiate(&"chicane_return", {"radius": 180.0, "angle_deg": 60.0, "distance": 400.0, "hand": 1.0})
	var upper_half := (1600.0 + 180.0 + (chicane["exit_port"]["position"] as Vector2).x) * 0.5
	var near_instances: Array[Dictionary] = [
		MODULES.instantiate(&"straight_setup", {"length": 1600.0, "finish": true}),
		chicane,
		MODULES.instantiate(&"straight_link", {"length": 180.0}),
		MODULES.instantiate(&"u_return", {"radius": 251.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_setup", {"length": upper_half}),
		MODULES.instantiate(&"straight_setup", {"length": upper_half}),
		MODULES.instantiate(&"u_return", {"radius": 251.0, "hand": 1.0}),
	]
	var near_route := MODULES.compose(near_instances)
	var near_continuous := VALIDATION.validate_continuous(near_route, _bounding_room(near_route))
	if not _expect(bool(near_continuous.get("valid", false)), "near-320 authored fixture should start valid"):
		return false
	var near_minimum := float(near_continuous["minimum_nonlocal_distance"])
	fixtures.append({"label": "near320_valid", "route": _scale_route(near_route, 321.0 / near_minimum)})
	fixtures.append({"label": "near320_fail", "route": _scale_route(near_route, 319.0 / near_minimum)})
	for fixture: Dictionary in fixtures:
		var fixture_route: Dictionary = fixture["route"]
		if not bool(fixture_route.get("ok", false)):
			return _expect(false, "%s fixture should compose: %s" % [fixture["label"], fixture_route.get("reason", "?")])
		var continuous: Dictionary = VALIDATION.validate_continuous(fixture_route, _bounding_room(fixture_route))
		var brute: Dictionary = _brute_force_continuous(fixture_route)
		var brute_nonlocal := float(brute["minimum_nonlocal"])
		var brute_return_limb := float(brute["minimum_return_limb"])
		if brute_nonlocal >= VALIDATION.MIN_SELF_DISTANCE and brute_return_limb >= VALIDATION.MIN_SELF_DISTANCE:
			if not _expect(bool(continuous.get("valid", false)), "%s should stay valid: %s" % [fixture["label"], continuous.get("reason", "?")]):
				return false
			if not _expect(float(continuous["minimum_nonlocal_distance"]) == brute_nonlocal, "%s minimum_nonlocal %.8f should equal brute force %.8f" % [fixture["label"], float(continuous["minimum_nonlocal_distance"]), brute_nonlocal]):
				return false
			if not _expect(float(continuous["minimum_return_limb_distance"]) == brute_return_limb, "%s minimum_return_limb %.8f should equal brute force %.8f" % [fixture["label"], float(continuous["minimum_return_limb_distance"]), brute_return_limb]):
				return false
		else:
			if not _expect(not bool(continuous.get("valid", false)), "%s should fail when brute minimum %.6f is below %.0f" % [fixture["label"], minf(brute_nonlocal, brute_return_limb), VALIDATION.MIN_SELF_DISTANCE]):
				return false
			if brute_nonlocal < VALIDATION.MIN_SELF_DISTANCE:
				if not _expect(continuous.get("kind") == &"self_distance", "%s should fail as self_distance, got %s" % [fixture["label"], continuous.get("kind", &"?")]):
					return false
			else:
				if not _expect(continuous.get("kind") == &"return_limb_spacing", "%s should fail as return_limb_spacing, got %s" % [fixture["label"], continuous.get("kind", &"?")]):
					return false
	return true


func _catalog_instances() -> Array[Dictionary]:
	return [
		MODULES.instantiate(&"straight_setup", {"length": 1600.0, "finish": true}),
		MODULES.instantiate(&"corner_medium", {"radius": 300.0, "angle_deg": 90.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_link", {"length": 300.0}),
		MODULES.instantiate(&"corner_medium", {"radius": 300.0, "angle_deg": 90.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_setup", {"length": 1600.0}),
		MODULES.instantiate(&"corner_medium", {"radius": 300.0, "angle_deg": 90.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_link", {"length": 300.0}),
		MODULES.instantiate(&"corner_medium", {"radius": 300.0, "angle_deg": 90.0, "hand": 1.0}),
	]


func _bounding_room(route: Dictionary) -> PackedVector2Array:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for primitive: Dictionary in route["primitives"]:
		var points: Array = [primitive["start"], primitive["end"]]
		if primitive["kind"] == &"arc":
			points.append(primitive["center"])
		for point: Vector2 in points:
			minimum = Vector2(minf(minimum.x, point.x), minf(minimum.y, point.y))
			maximum = Vector2(maxf(maximum.x, point.x), maxf(maximum.y, point.y))
	var pad := 2000.0
	return PackedVector2Array([Vector2(minimum.x - pad, minimum.y - pad), Vector2(maximum.x + pad, minimum.y - pad), Vector2(maximum.x + pad, maximum.y + pad), Vector2(minimum.x - pad, maximum.y + pad)])


## Uniformly scales a route's geometry (positions, lengths, radii, arc-length
## coordinates, ports, and declared separations) so a near-threshold route can
## be pushed across the 320 boundary without rebuilding it. Angles and headings
## are unchanged, so G1 joins and winding stay intact.
func _scale_route(route: Dictionary, factor: float) -> Dictionary:
	var scaled := route.duplicate(true)
	var primitives: Array = []
	for primitive: Dictionary in scaled["primitives"]:
		var copy := primitive.duplicate(true)
		copy["length"] = float(copy["length"]) * factor
		copy["s_start"] = float(copy["s_start"]) * factor
		copy["s_end"] = float(copy["s_end"]) * factor
		copy["start"] = (copy["start"] as Vector2) * factor
		copy["end"] = (copy["end"] as Vector2) * factor
		if copy["kind"] == &"arc":
			copy["center"] = (copy["center"] as Vector2) * factor
			copy["radius"] = float(copy["radius"]) * factor
			copy["minimum_radius"] = float(copy.get("minimum_radius", copy["radius"])) * factor
		primitives.append(copy)
	scaled["primitives"] = primitives
	scaled["length"] = float(scaled["length"]) * factor
	for port_key: String in ["entry_port", "exit_port"]:
		var port: Dictionary = (scaled[port_key] as Dictionary).duplicate(true)
		port["position"] = (port["position"] as Vector2) * factor
		port["left"] = (port["left"] as Vector2) * factor
		port["right"] = (port["right"] as Vector2) * factor
		scaled[port_key] = port
	var return_pairs: Array = []
	for pair: Dictionary in scaled.get("return_limb_pairs", []):
		var copy := pair.duplicate(true)
		copy["separation"] = float(copy["separation"]) * factor
		return_pairs.append(copy)
	scaled["return_limb_pairs"] = return_pairs
	var protected_intervals: Array = []
	for interval: Dictionary in scaled.get("protected_setup_intervals", []):
		var copy := interval.duplicate(true)
		copy["from"] = float(copy["from"]) * factor
		copy["to"] = float(copy["to"]) * factor
		protected_intervals.append(copy)
	scaled["protected_setup_intervals"] = protected_intervals
	return scaled
