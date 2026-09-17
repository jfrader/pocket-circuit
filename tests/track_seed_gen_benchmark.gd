extends SceneTree

## TrackSeedGen benchmark: times generate_with_retries across a seed sample
## (classic room) and the full room-shape matrix, and can dump per-seed
## SHA-256 fingerprints of the canonical result for before/after byte-identity
## diffs.
##
## Knobs:
##   PC_BENCH_SEEDS   seed count per room (default 60, min 1)
##   PC_BENCH_MATRIX  0 to skip the room-shape matrix (default: run it)
##   PC_SEEDGEN_FP    1 to dump fingerprints instead of timing
##
## Outputs SEEDGEN_BENCH rows plus medians (timing mode), or SEEDGEN_FP rows
## (fingerprint mode). Both quit 0.

const TRACK_SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const ROOM_RECT := Rect2(-940.0, -540.0, 1880.0, 1080.0)

static var ROOM_SHAPES := TRACK_BUILDER.ROOM_SHAPES


func _initialize() -> void:
	call_deferred("_run_benchmark")


func _run_benchmark() -> void:
	var seed_count := 60
	if OS.get_environment("PC_BENCH_SEEDS").is_valid_int():
		seed_count = clampi(int(OS.get_environment("PC_BENCH_SEEDS")), 1, 1000)
	var run_matrix := OS.get_environment("PC_BENCH_MATRIX") != "0"
	var fingerprint_mode := OS.get_environment("PC_SEEDGEN_FP") == "1"

	var rooms: Array[String] = ["classic"]
	if run_matrix:
		for room_name: String in ROOM_SHAPES:
			if room_name != "classic":
				rooms.append(room_name)

	for room_name: String in rooms:
		var params := _room_params(room_name)
		var times := PackedFloat32Array()
		var attempts_total := 0
		for seed in seed_count:
			var started := Time.get_ticks_usec()
			var result: Dictionary = TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			times.append(elapsed)
			attempts_total += int(result.get("attempt", -1)) + 1
			if fingerprint_mode:
				print("SEEDGEN_FP %s %d %s" % [room_name, seed, _fingerprint(result)])
			print("SEEDGEN_BENCH room=%s seed=%d ms=%.2f attempts=%d fallback=%s family=%s" % [
				room_name, seed, elapsed,
				int(result.get("attempt", -1)) + 1,
				result.get("fallback", false),
				result.get("family", "none"),
			])
		times.sort()
		print("SEEDGEN_BENCH room=%s n=%d median_ms=%.2f mean_ms=%.2f max_ms=%.2f avg_attempts=%.2f" % [
			room_name, times.size(), times[times.size() / 2],
			_times_sum(times) / float(times.size()), times[times.size() - 1],
			float(attempts_total) / float(times.size()),
		])
	quit(0)


func _times_sum(times: PackedFloat32Array) -> float:
	var total := 0.0
	for value: float in times:
		total += value
	return total


## Canonical byte-comparable digest of a generation result. Every field that
## can vary with the generated circuit is folded in with fixed-format float
## strings, so two runs over the same seeds must produce identical digests.
func _fingerprint(result: Dictionary) -> String:
	var canon := "%d|%s|%d|%d|%.6f|%.6f|%s|%s|%s|%s|%s" % [
		int(result.get("seed", -1)),
		result.get("family", "none"),
		int(result.get("attempt", -1)),
		1 if bool(result.get("fallback", false)) else 0,
		float(result.get("length", 0.0)),
		float(result.get("target_length", 0.0)),
		result.get("length_tier", ""),
		result.get("length_profile", ""),
		result.get("realization", ""),
		result.get("route_recipe", ""),
		result.get("route_program", ""),
	]
	var controls: PackedVector2Array = result.get("points", PackedVector2Array())
	for point: Vector2 in controls:
		canon += "%.6f,%.6f;" % [point.x, point.y]
	canon += "|" + String(result.get("route_sequence", ""))
	var motif_names := PackedStringArray()
	for motif: String in result.get("motifs", []):
		motif_names.append(motif)
	canon += "|" + ".".join(motif_names)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canon.to_utf8_buffer())
	return context.finish().hex_encode()


func _room_params(room_name: String) -> Dictionary:
	var params := {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1900.0 * TRACK_SEED_GEN.WORLD_SCALE,
		"room_polygon": ROOM_SHAPES[room_name],
		"room_shape": StringName(room_name),
	}
	match room_name:
		"el":
			params["min_loop_length"] = 1500.0 * TRACK_SEED_GEN.WORLD_SCALE
		"long":
			params["min_loop_length"] = 2000.0 * TRACK_SEED_GEN.WORLD_SCALE
		"square":
			params["min_loop_length"] = 2200.0 * TRACK_SEED_GEN.WORLD_SCALE
	return params
