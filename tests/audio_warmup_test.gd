extends SceneTree

const DIRECTOR := preload("res://scripts/audio/audio_director.gd")
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
	assert(not await director.call("warm_vehicle_audio", "rustbug", _checkpoint))
	assert(checkpoints.is_empty(), "normal headless warming must remain a no-op")
	# Exercise real synthesis without needing a listener or wall-clock timing.
	director.set("_headless", false)
	assert(await director.call("warm_vehicle_audio", "scrapjaw", _checkpoint))
	assert(checkpoints.size() == 2 and checkpoints[1] > checkpoints[0], "voice, loop and effects must not share one preparation frame")
	var cached: Variant = director.call("warm_vehicle_audio", "scrapjaw")
	assert(cached is bool and cached, "cached callers without progress must retain the synchronous path")
	director.queue_free()
	await process_frame
	print("AUDIO_WARMUP_TEST PASS yielded_synthesis_headless_noop_cached_compatibility")
	quit(0)

func _checkpoint() -> void:
	checkpoints.append(frame_signals)
	await process_frame
