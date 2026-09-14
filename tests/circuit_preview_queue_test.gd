extends SceneTree

const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const PREVIEW_QUEUE := preload("res://scripts/race/circuit_preview_queue.gd")

class FrameTicker extends Node:
	var frames := 0

	func _process(_delta: float) -> void:
		frames += 1

var _results: Dictionary = {}
var _expected: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var queue := PREVIEW_QUEUE.new()
	var ticker := FrameTicker.new()
	root.add_child(queue)
	root.add_child(ticker)
	var shared := _identity(101)
	for index in 3:
		_capture(queue, shared, "shared_%d" % index)
		_expected["shared_%d" % index] = shared["fingerprint"]
	await process_frame
	for index in 6:
		var identity := _identity(200 + index)
		var key := "rapid_%d" % index
		_capture(queue, identity, key)
		_expected[key] = identity["fingerprint"]
	# 600 frames was written as a 10-second budget under the 60 fps assumption,
	# but a headless run can elapse frames far faster (~7 ms), shrinking the real
	# deadline to ~4 s. A monotonic 10 s deadline restores the intended budget
	# without changing any correctness assertion (dedupe, cache, bounded-out, and
	# single-worker serialization are still verified below).
	var start_msec := Time.get_ticks_msec()
	var deadline_msec := start_msec + 10000
	while _results.size() < _expected.size() and Time.get_ticks_msec() < deadline_msec:
		await process_frame
	if not _expect(_results.size() == _expected.size(), "every completed, deduplicated, or bounded-out request should resolve"):
		var unresolved: Array[String] = []
		for key: String in _expected:
			if not _results.has(key):
				unresolved.append(key)
		push_error("CIRCUIT_PREVIEW_QUEUE_TEST: unresolved=%s elapsed_ms=%d metrics=%s" % [str(unresolved), Time.get_ticks_msec() - start_msec, str(queue.call("get_debug_metrics"))])
		return
	for index in 3:
		var shared_result: Dictionary = _results["shared_%d" % index]
		if not _expect(String(shared_result.get("identity_fingerprint", "")) == String(shared["fingerprint"]), "deduplicated callers should receive the shared preview"):
			return
	var latest: Dictionary = _results["rapid_5"]
	if not _expect(String(latest.get("identity_fingerprint", "")) == String(_expected["rapid_5"]), "the newest request must survive queue pressure and resolve without stale data"):
		return
	for key: String in _results:
		var result: Dictionary = _results[key]
		if not result.is_empty() and not _expect(String(result.get("identity_fingerprint", "")) == String(_expected[key]), "a waiter must never receive another identity's stale preview"):
			return
	var metrics: Dictionary = queue.call("get_debug_metrics")
	if not _expect(int(metrics["max_concurrent_workers"]) == 1 and int(metrics["job_count"]) <= 4 and int(metrics["pending_count"]) == 0 and ticker.frames > 0, "preview jobs should stay serialized, bounded, and off the main thread"):
		return
	var jobs_before := int(metrics["job_count"])
	var cached: Dictionary = await queue.call("request", shared)
	metrics = queue.call("get_debug_metrics")
	if not _expect(String(cached.get("identity_fingerprint", "")) == String(shared["fingerprint"]) and int(metrics["job_count"]) == jobs_before, "a completed preview should be served from the bounded cache"):
		return
	root.remove_child(queue)
	root.remove_child(ticker)
	queue.free()
	ticker.free()
	print("CIRCUIT_PREVIEW_QUEUE_TEST PASS jobs=%d" % jobs_before)
	quit(0)


func _capture(queue: Node, identity: Dictionary, key: String) -> void:
	_results[key] = await queue.call("request", identity)


func _identity(seed: int) -> Dictionary:
	return IDENTITIES.create(&"kitchen", IDENTITIES.room_for_route_seed(seed), seed, false, 1)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("CIRCUIT_PREVIEW_QUEUE_TEST FAIL: " + message)
	quit(1)
	return false