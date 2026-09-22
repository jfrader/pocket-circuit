extends SceneTree

const MODULES := preload("res://scripts/race/track_module_catalog.gd")
const ROOM_MODEL := preload("res://scripts/race/track_room_model.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const V8_DEVELOPMENT_GENERATOR := preload("res://scripts/race/track_v8_development_generator.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _test_legacy_fixtures():
		return
	if not _test_holes_and_erosion_components():
		return
	if not _test_two_lane_portals():
		return
	if not _test_el_notch_and_catalog_placement():
		return
	if not _test_independent_recipes():
		return
	print("TRACK_ROOM_MODEL_TEST PASS legacy_round_trips=6 offset_contours=1 erosion_components=2 portal_width=590 notch_guard=1 concave_fixture=1 recipes=30")
	quit(0)


func _test_legacy_fixtures() -> bool:
	for family: StringName in [&"classic", &"wide", &"tall", &"el", &"long", &"square"]:
		var base := ROOM_MODEL.legacy_fixture(family, 1.0)
		var runtime := ROOM_MODEL.legacy_fixture(family, TRACK_BUILDER.WORLD_SCALE)
		if not _expect(bool(base.get("valid", false)) and base["outer"] == TRACK_BUILDER.BASE_ROOM_SHAPES[String(family)], "%s base fixture should reproduce the frozen v7 polygon byte-for-byte" % family):
			return false
		if not _expect(bool(runtime.get("valid", false)) and runtime["outer"] == TRACK_BUILDER.ROOM_SHAPES[String(family)], "%s runtime fixture should reproduce the frozen scaled v7 polygon byte-for-byte" % family):
			return false
	return true


func _test_holes_and_erosion_components() -> bool:
	var offsets := ROOM_MODEL.offset_ring(_rect(Vector2.ZERO, Vector2(1000, 1000)), -135.0)
	if not _expect(offsets.size() == 1 and is_equal_approx(absf(_polygon_area(offsets[0])), 730.0 * 730.0), "polygon offset should preserve every surviving inset contour"):
		return false
	var room := ROOM_MODEL.create({
		"outer": _rect(Vector2.ZERO, Vector2(2000, 1200)),
		"solid_exclusions": [_rect(Vector2.ZERO, Vector2(200, 300))],
	})
	if not _expect(bool(room.get("valid", false)) and ROOM_MODEL.contains_point(room, Vector2(700, 0)) and not ROOM_MODEL.contains_point(room, Vector2.ZERO), "room membership should retain solid hole ownership"):
		return false
	var touching := ROOM_MODEL.create({"outer": _rect(Vector2.ZERO, Vector2(1000, 600)), "solid_exclusions": [PackedVector2Array([Vector2(400, -100), Vector2(500, -100), Vector2(500, 100), Vector2(400, 100)])]})
	if not _expect(not bool(touching.get("valid", false)) and touching.get("kind") == &"hole_outside", "holes touching the outer contour should fail closed"):
		return false
	var eroded := ROOM_MODEL.erode(room, 135.0)
	if not _expect(bool(eroded.get("valid", false)) and (eroded["free_components"] as Array).size() == 1 and ((eroded["free_components"] as Array)[0]["holes"] as Array).size() == 1, "erosion should retain the inflated hole in its free-space component"):
		return false
	var merging_holes := ROOM_MODEL.create({
		"outer": _rect(Vector2.ZERO, Vector2(2000, 1200)),
		"solid_exclusions": [_rect(Vector2(-120, 0), Vector2(100, 200)), _rect(Vector2(120, 0), Vector2(100, 200))],
	})
	var merged_erosion := ROOM_MODEL.erode(merging_holes, 100.0)
	if not _expect(bool(merged_erosion.get("valid", false)) and ((merged_erosion["free_components"] as Array)[0]["holes"] as Array).size() == 1, "overlapping inflated holes should merge into one owned exclusion contour"):
		return false
	var split_room := ROOM_MODEL.create({
		"outer": _rect(Vector2.ZERO, Vector2(1000, 600)),
		"solid_exclusions": [_rect(Vector2.ZERO, Vector2(200, 500))],
	})
	var split := ROOM_MODEL.erode(split_room, 50.0)
	return _expect(bool(split.get("valid", false)) and (split["free_components"] as Array).size() == 2, "an inflated hole meeting the eroded boundary should preserve both split components")


func _test_two_lane_portals() -> bool:
	var room := ROOM_MODEL.create({"outer": _rect(Vector2.ZERO, Vector2(1600, 1600)), "solid_exclusions": []})
	var exact := ROOM_MODEL.query_portal(room, Vector2(-295, 0), Vector2(295, 0), 2)
	if not _expect(bool(exact.get("valid", false)) and is_equal_approx(float(exact["clear_width"]), 590.0) and int(exact["traversal_capacity"]) == 2 and is_equal_approx((exact["lane_centers"] as PackedVector2Array)[0].distance_to((exact["lane_centers"] as PackedVector2Array)[1]), 320.0), "a 590-wide portal should reserve two radius-135 lanes separated by 320: %s" % exact):
		return false
	var narrow := ROOM_MODEL.query_portal(room, Vector2(-294.5, 0), Vector2(294.5, 0), 2)
	if not _expect(not bool(narrow.get("valid", false)) and int(narrow["traversal_capacity"]) == 1, "a 589-wide portal should reject two traversals"):
		return false
	var holed := ROOM_MODEL.create({"outer": _rect(Vector2.ZERO, Vector2(1600, 1600)), "solid_exclusions": [_rect(Vector2.ZERO, Vector2(100, 300))]})
	var interrupted := ROOM_MODEL.query_portal(holed, Vector2(-500, 0), Vector2(500, 0), 2)
	return _expect(not bool(interrupted.get("valid", false)) and is_equal_approx(float(interrupted["clear_width"]), 450.0), "a hole should split a nominally wide portal into its actual clear intervals: %s" % interrupted)


func _test_el_notch_and_catalog_placement() -> bool:
	var room := ROOM_MODEL.legacy_fixture(&"el", TRACK_BUILDER.WORLD_SCALE)
	if not _expect(ROOM_MODEL.contains_point(room, Vector2(1000, 500)) and not ROOM_MODEL.contains_point(room, Vector2(1000, -500)), "EL fixture should retain the missing upper-right notch"):
		return false
	var route := V8_DEVELOPMENT_GENERATOR.place_catalog_kernel(room)
	if not _expect(bool(route.get("ok", false)) and (route["room_placement"] as Dictionary).get("method") == &"eroded_free_polygon", "catalog kernel should fit the concave EL through free-polygon queries"):
		return false
	var crossing_instances: Array[Dictionary] = []
	for module: Dictionary in route["modules"]:
		var parameters: Dictionary = module["parameters"]
		crossing_instances.append(MODULES.instantiate(module["id"], parameters, module["transform"]))
	var notch_crossing := MODULES.compose(crossing_instances, Vector2(-800, -500), 0.0)
	var rejected := ROOM_MODEL.route_fits(room, notch_crossing)
	return _expect(not bool(rejected.get("valid", false)) and rejected.get("kind") == &"route_outside_free_space", "free-polygon placement should reject a sweep crossing the EL notch even when route vertices are in bounds")


func _test_independent_recipes() -> bool:
	var first_digests := {}
	for family: StringName in [&"classic", &"wide", &"tall", &"el", &"long", &"square"]:
		for tier: StringName in [&"compact", &"standard", &"long", &"endurance", &"marathon"]:
			var room := ROOM_MODEL.generate_recipe(family, 928, tier)
			if not _expect(bool(room.get("valid", false)) and (room["regions"] as Array).size() >= 2 and (room["portals"] as Array).size() >= 1 and int((room["portals"] as Array)[0]["traversal_capacity"]) >= 2, "%s/%s polygon recipe should independently produce regions and a two-lane portal" % [family, tier]):
				return false
			if family == &"el" and tier == &"compact":
				for region: Dictionary in room["regions"]:
					if not _expect(float(region["available_route_depth"]) >= 450.0, "compact EL should budget at least 450 route units beyond the junction in both arms"):
						return false
			first_digests[family] = room["polygon_digest"]
		var repeated := ROOM_MODEL.generate_recipe(family, 928, &"marathon")
		if not _expect(repeated["polygon_digest"] == first_digests[family], "%s recipe should be deterministic and independent of route generation" % family):
			return false
		var different_seed := ROOM_MODEL.generate_recipe(family, 929, &"marathon")
		if not _expect(different_seed["polygon_digest"] != first_digests[family], "%s room seed should vary polygon geometry without consulting a route" % family):
			return false
		if family != &"el":
			var boundary_styles := {}
			for seed in 48:
				var varied := ROOM_MODEL.generate_recipe(family, seed, &"compact")
				if not _expect(bool(varied.get("valid", false)), "%s compact boundary variant %d should preserve its polygon and portals" % [family, seed]):
					return false
				boundary_styles[varied["boundary_style"]] = true
			if not _expect(boundary_styles.size() == 3, "%s should expose all three authored boundary styles in the fixed development window" % family):
				return false
	return true


func _rect(center: Vector2, size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([center - half, center + Vector2(half.x, -half.y), center + half, center + Vector2(-half.x, half.y)])


func _polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for index in points.size():
		area += points[index].cross(points[(index + 1) % points.size()])
	return area * 0.5


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_ROOM_MODEL_TEST FAIL: " + message)
	quit(1)
	return false
