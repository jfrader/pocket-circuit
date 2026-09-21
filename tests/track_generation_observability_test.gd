extends SceneTree

const TRACK_SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")
const CATALOG := preload("res://scripts/race/track_builder_catalog.gd")
const ROOM_RECT := Rect2(-940.0, -540.0, 1880.0, 1080.0)
const FIXTURE_SEED := 246810


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var profile := TRACK_SEED_GEN.length_profile(&"compact")
	var scaled_room := PackedVector2Array()
	for point: Vector2 in CATALOG.ROOM_SHAPES["wide"]:
		scaled_room.append(point * float(profile["room_scale"]))
	var params := {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1900.0 * TRACK_SEED_GEN.WORLD_SCALE,
		"room_polygon": scaled_room,
		"room_shape": &"wide",
		"length_tier": &"compact",
	}
	var baseline := TRACK_SEED_GEN.generate_with_retries(FIXTURE_SEED, ROOM_RECT, params)
	if not _expect(not baseline.has("generation_diagnostics"), "instrumentation must be absent by default"):
		return
	var observed_params := params.duplicate(true)
	observed_params["instrument_rejections"] = true
	var observed := TRACK_SEED_GEN.generate_with_retries(FIXTURE_SEED, ROOM_RECT, observed_params)
	var diagnostics: Dictionary = observed.get("generation_diagnostics", {})
	var observed_generation := observed.duplicate(true)
	observed_generation.erase("generation_diagnostics")
	if not _expect(observed_generation == baseline, "enabling instrumentation must not change any v7 generation output"):
		return
	if not _expect(diagnostics.get("room") == "wide" and diagnostics.get("tier") == "compact" and diagnostics.get("seed") == FIXTURE_SEED, "diagnostics should identify their room/tier/seed cell"):
		return
	var rejections: Array = diagnostics.get("rejections", [])
	var counts: Dictionary = diagnostics.get("rejection_counts", {})
	var counted := 0
	for category: String in counts:
		counted += int(counts[category])
	if not _expect(not rejections.is_empty() and counted == rejections.size(), "every rejected attempt should contribute exactly one category count"):
		return
	for index in rejections.size():
		var rejection: Dictionary = rejections[index]
		if not _expect(int(rejection.get("attempt", -1)) == index and not String(rejection.get("category", "")).is_empty() and not String(rejection.get("reason", "")).is_empty(), "rejection %d should preserve attempt order, category, and reason" % index):
			return
	print("TRACK_GENERATION_OBSERVABILITY_TEST PASS rejections=%d categories=%s" % [rejections.size(), counts])
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_GENERATION_OBSERVABILITY_TEST FAIL: " + message)
	quit(1)
	return false
