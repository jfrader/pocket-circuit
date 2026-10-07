extends SceneTree

const CORE := preload("res://scripts/race/track_builder_core.gd")
const IDS := preload("res://scripts/race/generated_circuit_identity.gd")
const CUT_MAP := preload("res://scripts/race/track_outer_cut_map.gd")
# 15000 ms gives real headroom on loaded/shared 8-core hosts (isolated ~7.7s,
# observed flake 8.8s). tools/benchmark_track_seed_gen.gd owns the fine-grained
# perf measurement; this is only a coarse regression guard. Keep the assertion.
const MAX_SCAN_MS := 15000.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
