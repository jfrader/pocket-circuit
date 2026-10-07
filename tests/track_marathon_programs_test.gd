extends SceneTree

## Regression cover for the marathon route programs (GURI-961 / GURI-974).
## Two layers:
##  1. Each program, at full marathon size, must realise controls and its
##     unfitted length must reach the marathon band floor, so it can actually
##     be selected (a program shorter than the band can never realise and is
##     silently dead).
##  2. Through the full generator, a marathon seed sweep must realise the new
##     programs in band, and the programs must not collapse to one silhouette.

const TRACK_ROUTE_GRAMMAR := preload("res://scripts/race/track_route_grammar.gd")
const TRACK_SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")

const ROOM_RECT := Rect2(-940.0, -540.0, 1880.0, 1080.0)
const MARATHON_BOUNDS := Rect2(-7402.0, -4252.0, 14805.0, 8505.0)
const MARATHON_BAND_FLOOR := 32000.0
const MARATHON_BAND_CEILING := 48000.0
const NEW_PROGRAMS: Array[String] = ["serpentine", "multi_comb", "multi_lobe"]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _test_programs_reach_band():
		return
	if not _test_programs_are_distinct():
		return
	if not _test_generator_realises_new_programs():
		return
	if not _test_el_reaches_folded_program():
		return
	print("TRACK_MARATHON_PROGRAMS_TEST PASS")
	quit(0)


func _test_programs_reach_band() -> bool:
	for index in TRACK_ROUTE_GRAMMAR.MARATHON_NAMES.size():
		var program := String(TRACK_ROUTE_GRAMMAR.MARATHON_NAMES[index])
		var definition: Dictionary = TRACK_ROUTE_GRAMMAR.construct_marathon(index, 12345, 0.0, MARATHON_BOUNDS)
		var rounded: Dictionary = TRACK_ROUTE_GRAMMAR.round_corners_profiled(definition["anchors"], definition["radii"], 12345)
		var controls: PackedVector2Array = rounded["controls"]
		if not _expect(controls.size() >= 8, "program %s must realise controls at marathon size" % program):
			return false
		var centerline := TRACK_SEED_GEN.centerline_checkpoints(controls)
		var length := TRACK_SEED_GEN._polyline_length(centerline)
		if not _expect(length >= MARATHON_BAND_FLOOR, "program %s full-size length %.0f is below the marathon band floor %.0f and can never be selected" % [program, length, MARATHON_BAND_FLOOR]):
			return false
		var corners := 0
		var counts: Dictionary = rounded.get("profiles", {})
		for kind: String in counts:
			corners += int(counts[kind])
		if not _expect(corners >= 12 and corners <= 32, "program %s realised %d corners, expected 12..32" % [program, corners]):
			return false
	return true


func _test_programs_are_distinct() -> bool:
	var signatures := {}
	for index in TRACK_ROUTE_GRAMMAR.MARATHON_NAMES.size():
		var definition: Dictionary = TRACK_ROUTE_GRAMMAR.construct_marathon(index, 12345, 0.0, MARATHON_BOUNDS)
		var rounded: Dictionary = TRACK_ROUTE_GRAMMAR.round_corners_profiled(definition["anchors"], definition["radii"], 12345)
		var controls: PackedVector2Array = rounded["controls"]
		if controls.is_empty():
			continue
		signatures[_run_length_signature(controls)] = true
	if not _expect(signatures.size() >= 4, "marathon programs must expose at least 4 distinct fold signatures (got %d)" % signatures.size()):
		return false
	return true


func _test_generator_realises_new_programs() -> bool:
	var params := _marathon_params()
	var seen := {}
	for seed in range(100004, 100010):
		var result: Dictionary = TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
		var length := float(result.get("length", 0.0))
		if not _expect(length >= MARATHON_BAND_FLOOR and length <= MARATHON_BAND_CEILING, "marathon seed %d realised length %.0f outside the %d..%d band" % [seed, length, int(MARATHON_BAND_FLOOR), int(MARATHON_BAND_CEILING)]):
			return false
		var program := _program_of(String(result.get("route_recipe", "none")))
		seen[program] = int(seen.get(program, 0)) + 1
	for program: String in NEW_PROGRAMS:
		if not _expect(int(seen.get(program, 0)) >= 1, "new marathon program %s never realised across 6 seeds (seen %s)" % [program, str(seen)]):
			return false
	return true


func _test_el_reaches_folded_program() -> bool:
	var params := _el_marathon_params()
	var folded := 0
	var total := 0
	for seed in range(100004, 100010):
		var result: Dictionary = TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
		var length := float(result.get("length", 0.0))
		if not _expect(length >= MARATHON_BAND_FLOOR and length <= MARATHON_BAND_CEILING, "el marathon seed %d realised length %.0f outside the %d..%d band" % [seed, length, int(MARATHON_BAND_FLOOR), int(MARATHON_BAND_CEILING)]):
			return false
		total += 1
		if String(result.get("route_recipe", "")).begins_with("el_folded"):
			folded += 1
	if not _expect(folded == total, "marathon el must realise the folded L program instead of the plain perimeter (folded %d/%d)" % [folded, total]):
		return false
	return true


func _marathon_params() -> Dictionary:
	var room: PackedVector2Array = TRACK_BUILDER.ROOM_SHAPES["classic"]
	var profile := TRACK_SEED_GEN.length_profile(&"marathon")
	var room_scale := float(profile.get("room_scale", 1.0))
	var scaled := PackedVector2Array()
	for point: Vector2 in room:
		scaled.append(point * room_scale)
	return {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1900.0 * 1.75,
		"room_polygon": scaled,
		"room_shape": &"classic",
		"length_tier": &"marathon",
	}


func _el_marathon_params() -> Dictionary:
	var room: PackedVector2Array = TRACK_BUILDER.ROOM_SHAPES["el"]
	var profile := TRACK_SEED_GEN.length_profile(&"marathon")
	var room_scale := float(profile.get("room_scale", 1.0))
	var scaled := PackedVector2Array()
	for point: Vector2 in room:
		scaled.append(point * room_scale)
	return {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1900.0 * 1.75,
		"room_polygon": scaled,
		"room_shape": &"el",
		"length_tier": &"marathon",
	}


func _program_of(recipe: String) -> String:
	for name: StringName in TRACK_ROUTE_GRAMMAR.MARATHON_NAMES:
		if recipe.begins_with(String(name)):
			return String(name)
	if recipe.begins_with("el_safe"):
		return "el_safe"
	if recipe.begins_with("technical_perimeter"):
		return "technical_perimeter"
	return recipe


## Run-length encoding of the raw L/R turn tokens (straights skipped). Two
## programs are topologically different only if this differs; a plain
## alternating LRLR string of any length is NOT a different fold.
func _run_length_signature(controls: PackedVector2Array) -> String:
	var signature := ""
	var last := ""
	var run := 0
	for token: String in TRACK_SEED_GEN._raw_turn_tokens(controls):
		if token == "S":
			continue
		var direction := token.substr(0, 1)
		if direction == last:
			run += 1
		else:
			if run > 0:
				signature += "%s%d" % [last, run]
			last = direction
			run = 1
	if run > 0:
		signature += "%s%d" % [last, run]
	return signature


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_MARATHON_PROGRAMS_TEST FAIL: " + message)
	quit(1)
	return false
