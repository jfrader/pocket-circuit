extends SceneTree

## Loose debris varies per circuit without losing calm-stretch placement or
## deterministic replay of its count, footprint and lateral position.

const CORE := preload("res://scripts/race/track_builder_core.gd")
const IDS := preload("res://scripts/race/generated_circuit_identity.gd")

const CASES := [
	{"theme": "kitchen", "seed": 0},
	{"theme": "kitchen", "seed": 5},
	{"theme": "workshop", "seed": 2},
	{"theme": "workshop", "seed": 4},
	{"theme": "office", "seed": 1},
]

func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _expect(int(CORE.GRIP_PATCH_MIN_COUNT) == 0 and int(CORE.GRIP_PATCH_MAX_COUNT) >= 8, "the debris range must allow a clean track and a busy one, not a fixed count"):
		return
	var straight := PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(40, 0), Vector2(60, 0), Vector2(80, 0), Vector2(100, 0), Vector2(120, 0), Vector2(120, 120), Vector2(0, 120)])
	var rectangle := TrackBuilderDressing.surface_strip(straight, 3, 2, 13.0)
	if not _expect(rectangle.size() == 4 and _valid_footprint(rectangle), "a straight debris strip should retain its valid four-corner footprint"):
		return
	if not _expect(not _valid_footprint(PackedVector2Array([Vector2.ZERO, Vector2(10, 0), Vector2(20, 0), Vector2(30, 0)])), "a collapsed debris footprint must fail"):
		return
	var widths := {}
	var counts := {}
	var left_signed := false
	var right_signed := false
	var total_patches := 0
	for case: Dictionary in CASES:
		var theme: String = case["theme"]
		var seed_value: int = case["seed"]
		var identity := IDS.create(StringName(theme), IDS.room_for_route_seed(seed_value), seed_value)
		var built := CORE.build_packed(StringName(theme), StringName(identity["room"]), seed_value, IDS.generation_options(identity))
		var track := (built["scene"] as PackedScene).instantiate()
		var definitions: Array = track.get_meta("generated_surfaces", [])
		var centerline := (track.get_node("TrackSurface") as Line2D).points
		var clearance := TrackCornerMap.clearances(centerline)
		var patches: Array[Dictionary] = []
		var roles := {}
		for definition: Dictionary in definitions:
			roles[String(definition.get("role", ""))] = true
			if String(definition.get("role", "")) == "patch":
				patches.append(definition)
		if not _expect(roles.has("shortcut"), "%s/%d must retain its designed shortcut" % [theme, seed_value]):
			track.free()
			return
		if not _expect(patches.size() <= CORE.GRIP_PATCH_MAX_COUNT, "%s/%d debris exceeds the per-track budget" % [theme, seed_value]):
			track.free()
			return
		counts[patches.size()] = true
		total_patches += patches.size()
		for patch: Dictionary in patches:
			var half_span := int(patch.get("half_span", -1))
			if not _expect(half_span >= TrackBuilderDressing.GRIP_PATCH_MIN_HALF_SPAN and half_span <= TrackBuilderDressing.GRIP_PATCH_MAX_HALF_SPAN and TrackCornerMap.is_calm(clearance, int(patch["centerline_index"]), half_span), "%s/%d debris must keep its complete footprint on a calm stretch" % [theme, seed_value]):
				track.free()
				return
			var lateral := float(patch.get("lateral_mm", 0.0))
			if not _expect(not is_zero_approx(lateral), "%s/%d debris must not sit exactly on the racing line" % [theme, seed_value]):
				track.free()
				return
			left_signed = left_signed or lateral < 0.0
			right_signed = right_signed or lateral > 0.0
			var points: PackedVector2Array = patch["points"]
			if not _expect(_valid_footprint(points), "%s/%d debris needs a nondegenerate footprint (got %d points)" % [theme, seed_value, points.size()]):
				track.free()
				return
			for point: Vector2 in points:
				if not _expect(CORE._distance_to_centerline(point, centerline) <= CORE.HALF_WIDTH + 0.5, "%s/%d debris must stay inside the drivable corridor instead of becoming an edge wall" % [theme, seed_value]):
					track.free()
					return
			var bounds := CORE._polygon_bounds_rect(points)
			widths["%.1f" % minf(bounds.size.x, bounds.size.y)] = true
		var replay := (CORE.build_packed(StringName(theme), StringName(identity["room"]), seed_value, IDS.generation_options(identity))["scene"] as PackedScene).instantiate()
		var replay_definitions: Array = replay.get_meta("generated_surfaces", [])
		var deterministic := definitions == replay_definitions
		replay.free()
		if not _expect(deterministic, "%s/%d must replay identical debris and surface definitions" % [theme, seed_value]):
			track.free()
			return
		print("DEBRIS_CASE %s seed=%d patches=%d" % [theme, seed_value, patches.size()])
		track.free()
	if not _expect(left_signed and right_signed, "debris should appear on both sides of the road across the corpus"):
		return
	if not _expect(widths.size() >= 3, "debris should vary in size, not repeat one footprint (saw %d distinct)" % widths.size()):
		return
	if not _expect(counts.size() >= 3 and counts.has(0) and int(counts.keys().max()) >= 4, "the corpus should include clean and busy tracks with at least three counts, saw %s" % [counts.keys()]):
		return
	print("TRACK_DEBRIS_VARIATION_TEST PASS pinned_cases=", CASES.size(), " pieces=", total_patches, " distinct_widths=", widths.size())
	quit(0)


func _valid_footprint(points: PackedVector2Array) -> bool:
	return points.size() >= 4 and not Geometry2D.triangulate_polygon(points).is_empty()


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_DEBRIS_VARIATION_TEST FAIL: " + message)
	quit(1)
	return false
