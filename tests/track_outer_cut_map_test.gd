extends SceneTree

const CORE := preload("res://scripts/race/track_builder_core.gd")
const IDS := preload("res://scripts/race/generated_circuit_identity.gd")
const CUT_MAP := preload("res://scripts/race/track_outer_cut_map.gd")
const MAX_SCAN_MS := 8000.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var identity := IDS.create(&"office", IDS.room_for_route_seed(1), 1)
	var prepared := CORE.prepare_layout(&"office", StringName(identity["room"]), 1, IDS.generation_options(identity))
	var line: PackedVector2Array = prepared["centerline"]
	if not _check_open_bounds(line):
		quit(1)
		return
	var start := Time.get_ticks_usec()
	var cuts := CUT_MAP.candidates(prepared["centerline"], prepared["edges"]["outer_boundary"], prepared["spec"]["environment_island_polygon"], CORE.HALF_WIDTH, int(prepared["spec"]["environment_plan"]["diagnostics"]["open_sector"]), WorldEnvironmentCatalog.boundary_density()["corner_cuts"])
	var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
	if cuts.is_empty() or elapsed_ms >= MAX_SCAN_MS:
		push_error("TRACK_OUTER_CUT_MAP_TEST FAIL: office/1 scan %.1f ms exceeds %.1f ms with %d candidates" % [elapsed_ms, MAX_SCAN_MS, cuts.size()])
		quit(1)
		return
	print("TRACK_OUTER_CUT_MAP_TEST PASS scan_ms=%.1f candidates=%d" % [elapsed_ms, cuts.size()])
	quit()


func _check_open_bounds(line: PackedVector2Array) -> bool:
	var probe_lines: Array[PackedVector2Array] = [line, PackedVector2Array([
		Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)
	]), PackedVector2Array([
		Vector2(0, 0), Vector2(0, 0), Vector2(800000, 0), Vector2(800000, 0),
		Vector2(800000, 800000), Vector2(-800000, 800000), Vector2(-800000, -800000), Vector2(0, 0)
	])]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1309
	for route_number in 6:
		var random_route := PackedVector2Array()
		var scale := 100.0 if route_number % 2 == 0 else 1000000.0
		for vertex in 21:
			random_route.append(Vector2(rng.randf_range(-scale, scale), rng.randf_range(-scale, scale)))
		probe_lines.append(random_route)
	var extra_pruned := 0
	for route in probe_lines:
		var points := PackedVector2Array([Vector2.ZERO, Vector2(100, 0), Vector2(-100, -100)])
		var prefix := PackedFloat64Array()
		prefix.resize(route.size() + 1)
		for index in route.size():
			prefix[index + 1] = prefix[index] + route[index].distance_to(route[(index + 1) % route.size()])
		var curve := CUT_MAP._route_curve(route, prefix[route.size()])
		for index in route.size():
			if index % maxi(1, floori(float(route.size()) / 32.0)) == 0:
				points.append(route[index])
				points.append(route[index].lerp(route[(index + 1) % route.size()], 0.5))
				points.append(route[index] + Vector2(43, -71))
				points.append(route[index].lerp(route[(index + 1) % route.size()], 0.001))
		for probe in 20:
			points.append(Vector2(rng.randf_range(-1000000.0, 1000000.0), rng.randf_range(-1000000.0, 1000000.0)))
		for sector in range(CUT_MAP.SECTOR_COUNT):
			var bounds := CUT_MAP._open_segment_bounds(route, sector)
			var whole := Rect2()
			if not bounds.is_empty():
				whole = bounds[0]
				for box in bounds:
					whole = whole.merge(box)
			for point in points:
				var nearest := CORE._closest_point_on_loop(point, route)
				var expected := mini(CUT_MAP.SECTOR_COUNT - 1, int(float(nearest["index"]) / route.size() * CUT_MAP.SECTOR_COUNT)) == sector
				for start_index: int in [0, floori(float(route.size()) / 4.0), floori(float(route.size()) / 2.0), route.size() - 1]:
					var finish_index := (start_index + floori(float(route.size()) / 3.0)) % route.size()
					var rejected := CUT_MAP._cannot_be_nearest_open(point, route, start_index, finish_index, bounds, curve, prefix)
					if rejected and expected:
						push_error("TRACK_OUTER_CUT_MAP_TEST FAIL: bounds rejected nearest open sector %d at %s" % [sector, point])
						return false
					var upper := minf(point.distance_squared_to(route[start_index]), point.distance_squared_to(route[finish_index]))
					var old_lower := point.distance_squared_to(point.clamp(whole.position, whole.end))
					if route == line and rejected and (old_lower <= upper or is_equal_approx(old_lower, upper)):
						extra_pruned += 1
	if extra_pruned == 0:
		push_error("TRACK_OUTER_CUT_MAP_TEST FAIL: office/1 broadphase did not improve on the whole-sector box")
		return false
	return true
