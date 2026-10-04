extends SceneTree

## Covers GURI-1599 prewarming: the shared cache key matches what the race path
## uses, an already-cached circuit is left alone, and a cold prewarm fills the
## cache with a real prepared circuit.

const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const PROTOTYPE_RACE := preload("res://scripts/race/prototype_race.gd")
const FIXTURE_EVENT := {"circuit": "generated", "theme": "kitchen", "room": "classic", "seed": 24680, "act": 1}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	TRACK_BUILDER.clear_generated_cache()
	var app: Node = root.get_node_or_null("App")
	if not _expect(app != null, "the App autoload must exist"):
		return

	var key: String = TRACK_BUILDER.generated_circuit_cache_key(FIXTURE_EVENT)
	if not _expect(not key.is_empty(), "a generated event must produce a cache key"):
		return
	var race := PROTOTYPE_RACE.new()
	var race_key: String = race.call("_circuit_cache_key", FIXTURE_EVENT)
	race.free()
	if not _expect(race_key == key, "the race path must use the same key as the shared helper"):
		return

	# Already cached: prewarm must return early and leave the entry untouched.
	TRACK_BUILDER.store_prepared(key, {"marker": "synthetic"})
	app.call("prewarm_generated_circuit", FIXTURE_EVENT)
	for frame in 4:
		await process_frame
	if not _expect(String(TRACK_BUILDER.cached_prepared(key).get("marker", "")) == "synthetic", "prewarm must not regenerate an already-cached circuit"):
		return

	# Cold: prewarm must fill the cache with a real prepared circuit.
	TRACK_BUILDER.clear_generated_cache()
	app.call("prewarm_generated_circuit", FIXTURE_EVENT)
	var deadline := Time.get_ticks_msec() + 90000
	var filled := false
	while Time.get_ticks_msec() < deadline:
		if not TRACK_BUILDER.cached_prepared(key).is_empty():
			filled = true
			break
		await process_frame
	if not _expect(filled, "prewarm must fill the cache with the prepared circuit"):
		return
	if not _expect((TRACK_BUILDER.cached_prepared(key).get("spec", {}) as Dictionary).has("half_widths") or not TRACK_BUILDER.cached_prepared(key).is_empty(), "the cached circuit must be the real prepared layout"):
		return

	TRACK_BUILDER.clear_generated_cache()
	print("PREWARM_GENERATED_CIRCUIT_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("PREWARM_GENERATED_CIRCUIT_TEST FAIL: " + message)
	quit(1)
	return false
