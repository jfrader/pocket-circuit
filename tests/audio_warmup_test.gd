extends SceneTree

const DIRECTOR := preload("res://scripts/audio/audio_director.gd")


class StatsVehicle extends Node:
	var stats: VehicleStats = preload("res://data/vehicles/rustbug.tres")
	var speed := 0.0

	func get_engine_load() -> float:
		return 0.0

	func get_throttle_input() -> float:
		return 0.0

var checkpoints: Array[int] = []
var frame_signals := 0

func _initialize() -> void:
	process_frame.connect(func() -> void: frame_signals += 1)
	call_deferred("_run")

func _run() -> void:
	var director := DIRECTOR.new()
	root.add_child(director)
	await process_frame
	var supports_progress := false
	for method: Dictionary in director.get_method_list():
		if method["name"] == "warm_vehicle_audio":
			supports_progress = method["args"].size() == 2
	if not supports_progress:
		push_error("AUDIO_WARMUP_TEST FAIL synthesis needs a yielded progress boundary")
		quit(1)
		return
	director.set("_headless", true)
	if not _expect(not await director.call("warm_vehicle_audio", "rustbug", _checkpoint), "normal headless warming must remain a no-op"):
		return
	if not _expect(checkpoints.is_empty(), "headless warming must not yield synthesis checkpoints"):
		return
	EngineVoiceGenerator.clear_cache()
	var silent_vehicle := StatsVehicle.new()
	director.set_local_vehicle(silent_vehicle, "rustbug")
	var vehicle_bound: bool = director.get("_local_vehicle") == silent_vehicle and is_equal_approx(float(director.get("_vehicle_max_speed")), silent_vehicle.stats.max_speed)
	var silent: bool = not director.has_engine_voice() and not director.has_generated_sfx(&"impact") and not director.has_generated_sfx(&"boost") and EngineVoiceGenerator._cache.is_empty()
	director.clear_local_vehicle()
	silent_vehicle.free()
	if not _expect(vehicle_bound, "headless handoff must retain the vehicle and its speed range"):
		return
	if not _expect(silent, "headless handoff must not synthesize vehicle audio"):
		return
	# Exercise real synthesis without needing a listener or wall-clock timing.
	var stats := load("res://data/vehicles/scrapjaw.tres") as VehicleStats
	var recipe := EngineRecipeLibrary.resolve("scrapjaw", stats)
	var expected_voice := EngineVoiceGenerator.new().generate(recipe)
	EngineVoiceGenerator.clear_cache()
	EngineLoopGenerator.clear_cache()
	director.set("_headless", false)
	if not _expect(await director.call("warm_vehicle_audio", "scrapjaw", _checkpoint), "real synthesis must warm the vehicle"):
		return
	if not _expect(checkpoints.size() == EngineVoiceGenerator.RPM_BAND_RATIOS.size() + 2, "cold voice synthesis must yield between RPM banks as well as loop and effects preparation"):
		return
	for index in range(1, checkpoints.size()):
		if not _expect(checkpoints[index] > checkpoints[index - 1], "each synthesis checkpoint must give the loading screen a frame"):
			return
	var prepared_voice := EngineVoiceGenerator.generate_cached(recipe)
	if not _expect(prepared_voice.tables == expected_voice.tables and prepared_voice.mechanical == expected_voice.mechanical, "yielded synthesis must preserve every generated sample"):
		return
	if not _expect(prepared_voice.rpm_bands == expected_voice.rpm_bands and prepared_voice.load_bands == expected_voice.load_bands and prepared_voice.signature == expected_voice.signature, "yielded synthesis must preserve the recipe identity and bands"):
		return
	checkpoints.clear()
	if not _expect(await director.call("warm_vehicle_audio", "scrapjaw", _checkpoint) and checkpoints.size() == 2, "a cached voice should skip bank generation and keep only loop and effects checkpoints"):
		return
	var cached: Variant = director.call("warm_vehicle_audio", "scrapjaw")
	if not _expect(cached is bool and cached, "cached callers without progress must retain the synchronous path"):
		return
	var voiced_vehicle := StatsVehicle.new()
	voiced_vehicle.stats = stats
	director.set_local_vehicle(voiced_vehicle, "scrapjaw")
	if not _expect(director.has_engine_voice() and String(director.get_engine_voice_signature()).contains("scrapjaw") and director.has_generated_sfx(&"impact") and director.has_generated_sfx(&"boost"), "a listening handoff must still bind its generated engine and effects"):
		return
	director.clear_local_vehicle()
	voiced_vehicle.free()
	if not await _check_voice_cache_recency():
		return
	director.queue_free()
	await process_frame
	print("AUDIO_WARMUP_TEST PASS yielded_synthesis_headless_noop_cached_compatibility")
	quit(0)

func _checkpoint() -> void:
	checkpoints.append(frame_signals)
	await process_frame


func _check_voice_cache_recency() -> bool:
	var recipes: Array[EngineRecipe] = []
	for vehicle_id: String in ["rustbug", "spindle", "dustmite", "thimble", "flicker"]:
		var stats := load("res://data/vehicles/%s.tres" % vehicle_id) as VehicleStats
		recipes.append(EngineRecipeLibrary.resolve(vehicle_id, stats))
	for yielded: bool in [false, true]:
		EngineVoiceGenerator.clear_cache()
		var banks: Array[EngineVoice] = []
		for index in EngineVoiceGenerator.CACHE_LIMIT:
			banks.append(await _cached_voice(recipes[index], yielded))
		for index in [0, 3, 2]:
			if not _expect(await _cached_voice(recipes[index], yielded) == banks[index], "warming a reused recipe must keep its cached voice"):
				return false
		await _cached_voice(recipes.back(), yielded)
		var evicted_unused := not EngineVoiceGenerator._cache.has(recipes[1].signature())
		var retained_count := EngineVoiceGenerator._cache.size()
		var player_rebound := EngineVoiceGenerator.generate_cached(recipes[0])
		EngineVoiceGenerator.clear_cache()
		if not _expect(player_rebound == banks[0], "a fresh opponent must not evict the player voice just warmed for that grid (yielded=%s)" % yielded):
			return false
		if not _expect(evicted_unused and retained_count == EngineVoiceGenerator.CACHE_LIMIT, "the bounded cache must evict the unused previous opponent instead"):
			return false
	return await _check_overlapping_voice_cache(recipes)


func _check_overlapping_voice_cache(recipes: Array[EngineRecipe]) -> bool:
	EngineVoiceGenerator.clear_cache()
	var overlapping: Array[EngineVoice] = []
	var checkpoint := func() -> void:
		if overlapping.is_empty():
			overlapping.append(EngineVoiceGenerator.generate_cached(recipes[0]))
			for index in range(1, EngineVoiceGenerator.CACHE_LIMIT):
				EngineVoiceGenerator.generate_cached(recipes[index])
		await process_frame
	var prepared := await EngineVoiceGenerator.prepare_cached(recipes[0], checkpoint)
	EngineVoiceGenerator.generate_cached(recipes.back())
	var player_rebound := EngineVoiceGenerator.generate_cached(recipes[0])
	EngineVoiceGenerator.clear_cache()
	return _expect(prepared == overlapping[0] and player_rebound == prepared, "overlapping warm-up must reuse and retain the bank another caller cached during its yield")


func _cached_voice(recipe: EngineRecipe, yielded: bool) -> EngineVoice:
	if yielded:
		return await EngineVoiceGenerator.prepare_cached(recipe, _checkpoint)
	return EngineVoiceGenerator.generate_cached(recipe)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AUDIO_WARMUP_TEST FAIL: " + message)
	quit(1)
	return false
