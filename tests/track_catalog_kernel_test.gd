extends SceneTree

const MODULES := preload("res://scripts/race/track_module_catalog.gd")
const VALIDATION := preload("res://scripts/race/track_layout_validation.gd")
const V8_DEVELOPMENT_GENERATOR := preload("res://scripts/race/track_v8_development_generator.gd")
const REGISTRY := preload("res://scripts/race/track_generator_registry.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _test_catalog_contract():
		return
	var room_polygon: PackedVector2Array = TRACK_BUILDER.ROOM_SHAPES["el"]
	var route := V8_DEVELOPMENT_GENERATOR.catalog_kernel_fixture()
	if not _expect(bool(route.get("ok", false)), "hand-composed catalog route should close"):
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
	var unavailable := REGISTRY.dispatch({"schema_version": 2, "generator_version": 8}, {"room_shape": &"el", "room_polygon": room_polygon}, Callable(), Callable(V8_DEVELOPMENT_GENERATOR, "generate"))
	if not _expect(unavailable.get("kind") == &"v8_not_implemented", "v8 should remain unavailable without an explicit development fixture"):
		return
	var dispatched := REGISTRY.dispatch(
		{"schema_version": 2, "generator_version": 8},
		{"seed": 928, "room_shape": &"el", "room_polygon": room_polygon, "development_fixture": &"catalog_kernel", "generation_options": {"length_tier": &"standard"}},
		Callable(),
		Callable(V8_DEVELOPMENT_GENERATOR, "generate")
	)
	if not _expect(bool(dispatched.get("ok", false)) and dispatched["points"] == sampling["points"], "explicit v8 registry dispatch should reach only the catalog fixture"):
		return
	var prepared := TRACK_BUILDER.prepare_layout(&"kitchen", &"el", 928, {"schema_version": 2, "generator_version": 8, "development_fixture": &"catalog_kernel", "length_tier": &"standard", "obstacles_enabled": false})
	if not _expect(not prepared.is_empty() and bool(prepared["spec"].get("centerline_is_sampled", false)) and prepared["centerline"] == sampling["points"], "TrackBuilderCore should retain authoritative v8 samples without Catmull-Rom reinterpretation"):
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
