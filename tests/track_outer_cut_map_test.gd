extends SceneTree

const CORE := preload("res://scripts/race/track_builder_core.gd")
const IDS := preload("res://scripts/race/generated_circuit_identity.gd")
const CUT_MAP := preload("res://scripts/race/track_outer_cut_map.gd")
const MAX_SCAN_MS := 8000.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _check_samples():
		quit(1)
		return
	var identity := IDS.create(&"office", IDS.room_for_route_seed(1), 1)
	var prepared := CORE.prepare_layout(&"office", StringName(identity["room"]), 1, IDS.generation_options(identity))
	var start := Time.get_ticks_usec()
	var cuts := CUT_MAP.candidates(prepared["centerline"], prepared["edges"]["outer_boundary"], prepared["spec"]["environment_island_polygon"], CORE.HALF_WIDTH, int(prepared["spec"]["environment_plan"]["diagnostics"]["open_sector"]), WorldEnvironmentCatalog.boundary_density()["corner_cuts"])
	var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
	if cuts.is_empty() or elapsed_ms >= MAX_SCAN_MS:
		push_error("TRACK_OUTER_CUT_MAP_TEST FAIL: office/1 scan %.1f ms exceeds %.1f ms with %d candidates" % [elapsed_ms, MAX_SCAN_MS, cuts.size()])
		quit(1)
		return
	print("TRACK_OUTER_CUT_MAP_TEST PASS scan_ms=%.1f candidates=%d" % [elapsed_ms, cuts.size()])
	quit()


func _check_samples() -> bool:
	var polygons: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)]),
		PackedVector2Array([Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(20, 100), Vector2(20, -20), Vector2(-20, -20), Vector2(-20, 100), Vector2(-100, 100)]),
		PackedVector2Array([Vector2(-100, 100), Vector2(100, 100), Vector2(100, -100), Vector2(-100, -100), Vector2(-100, 100)]),
		PackedVector2Array([Vector2(1000000, 1000000), Vector2(1000200, 1000000), Vector2(1000200, 1000200), Vector2(1000000, 1000200)]),
		PackedVector2Array([Vector2(-0.001, -0.001), Vector2(0.001, -0.001), Vector2(0.001, 0.001), Vector2(-0.001, 0.001)])
	]
	var chords: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-200, 0), Vector2(200, 0)]),
		PackedVector2Array([Vector2(200, 0), Vector2(-200, 0)]),
		PackedVector2Array([Vector2(-100, -100), Vector2(100, 100)]),
		PackedVector2Array([Vector2(-200, 100), Vector2(200, 100)]),
		PackedVector2Array([Vector2(-200, -200), Vector2(-100, -100)]),
		PackedVector2Array([Vector2(-100, 0), Vector2(-100, 0)]),
		PackedVector2Array([Vector2(1000000, 1000100), Vector2(1000300, 1000100)]),
		PackedVector2Array([Vector2(-0.002, 0), Vector2(0.002, 0)])
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1309
	for case in 768:
		var scale := 0.003 if case % 3 == 0 else (1000300.0 if case % 3 == 1 else 250.0)
		var origin := Vector2(1000000, 1000000) if case % 3 == 1 else Vector2.ZERO
		chords.append(PackedVector2Array([
			origin + Vector2(rng.randf_range(-scale, scale), rng.randf_range(-scale, scale)),
			origin + Vector2(rng.randf_range(-scale, scale), rng.randf_range(-scale, scale))
		]))
	for polygon in polygons:
		for chord in chords:
			var fragments: Array[PackedVector2Array] = Geometry2D.clip_polyline_with_polygon(chord, polygon)
			var actual := CUT_MAP._outside_samples(chord[0], chord[1], polygon, fragments)
			var expected := PackedVector2Array()
			for sample in CORE.CUT_SAMPLES:
				var point := chord[0].lerp(chord[1], float(sample) / float(CORE.CUT_SAMPLES - 1))
				if not Geometry2D.is_point_in_polygon(point, polygon):
					expected.append(point)
			if actual != expected:
				push_error("TRACK_OUTER_CUT_MAP_TEST FAIL: sampled outside points differ, polygon=%s chord=%s actual=%s expected=%s" % [polygon, chord, actual, expected])
				return false
	return true
