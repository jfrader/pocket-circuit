extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const CIRCUITS := preload("res://scripts/progression/championship_circuit_identity.gd")
const MASTERY := preload("res://scripts/progression/mastery_run.gd")
const GHOST := preload("res://scripts/race/personal_ghost.gd")


func _initialize() -> void:
	var event := CIRCUITS.apply_to_event(
		CATALOG.get_event("kitchen_crumb_rush"),
		CIRCUITS.event_identity(CIRCUITS.create_championship(661), "kitchen_crumb_rush")
	)
	var identity := MASTERY.create_identity(event, "rustbug", MASTERY.prepare_circuit_metrics(event))
	var samples := [
		GHOST.sample(0.0, Transform2D(0.0, Vector2(10.0, 20.0))),
		GHOST.sample(0.1, Transform2D(0.2, Vector2(20.0, 30.0))),
		GHOST.sample(0.2, Transform2D(0.4, Vector2(30.0, 40.0))),
	]
	var stored := GHOST.store_best([], identity, 0.2, samples)
	if not _expect(stored["saved"] and stored["ghosts"].size() == 1, "a valid mastery sample stream should save"):
		return
	var compatible := GHOST.compatible_best(stored["ghosts"], identity)
	if not _expect(compatible["samples"] == samples, "the compatible personal best ghost should round-trip compact samples"):
		return
	var slower := GHOST.store_best(stored["ghosts"], identity, 0.3, samples)
	if not _expect(not slower["saved"] and is_equal_approx(float(slower["ghosts"][0]["race_time"]), 0.2), "a slower ghost should not replace the compatible best"):
		return
	var truncated := GHOST.store_best([], identity, 1.0, samples)
	if not _expect(not truncated["saved"] and truncated["ghosts"].is_empty(), "a truncated stream that does not reach finish time within one sample interval must be rejected"):
		return
	var trailing_samples := samples.duplicate(true)
	trailing_samples.append(GHOST.sample(0.3, Transform2D(0.6, Vector2(40.0, 50.0))))
	var trimmed := GHOST.store_best([], identity, 0.2, trailing_samples)
	if not _expect(trimmed["saved"] and is_equal_approx(float(trimmed["ghosts"][0]["samples"].back()[0]), 0.2) and trimmed["ghosts"][0]["samples"].size() == samples.size(), "storage should defensively discard every sample after the reported finish"):
		return

	var bounded: Array = []
	for index in GHOST.MAX_GHOSTS + 3:
		var distinct := identity.duplicate(true)
		distinct["circuit"]["fingerprint"] = "bounded-%02d" % index
		bounded = GHOST.store_best(bounded, distinct, 1.0 + index, [samples[0], GHOST.sample(1.0 + index, Transform2D(0.0, Vector2(index, index)))])["ghosts"]
	if not _expect(bounded.size() == GHOST.MAX_GHOSTS and String(bounded[0]["identity"]["circuit"]["fingerprint"]) == "bounded-03", "ghost storage should evict oldest entries at its hard bound"):
		return
	var oversized_samples: Array = []
	for index in GHOST.MAX_SAMPLES + 5:
		oversized_samples.append([float(index) * 0.1, 0.0, 0.0, 0.0])
	if not _expect(GHOST.normalize_samples(oversized_samples).size() == GHOST.MAX_SAMPLES, "sample normalization should enforce its hard bound"):
		return
	var corrupt := compatible.duplicate(true)
	corrupt["samples"] = [[0.0, 1.0, 2.0, 0.0], [0.0, 3.0, 4.0, 0.0]]
	var wrong_version := compatible.duplicate(true)
	wrong_version["version"] = 999
	if not _expect(GHOST.normalize_ghosts([corrupt, wrong_version]).is_empty(), "corrupt and incompatible ghost payloads should be ignored safely"):
		return

	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var playback := GHOST.new() as PersonalGhost
	root.add_child(playback)
	if not _expect(playback.configure(compatible, ImageTexture.create_from_image(image)), "a compatible ghost should configure a replay visual"):
		return
	playback.set_playback_time(0.15)
	if not _expect(playback.position.is_equal_approx(Vector2(25.0, 35.0)) and is_equal_approx(playback.rotation, 0.3), "ghost replay should interpolate deterministically between samples"):
		return
	root.remove_child(playback)
	playback.free()
	print("PERSONAL_GHOST_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("PERSONAL_GHOST_TEST FAIL: " + message)
	quit(1)
	return false