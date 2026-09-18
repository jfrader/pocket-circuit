extends SceneTree

const TRACK_ROUTE_GRAMMAR := preload("res://scripts/race/track_route_grammar.gd")
const TRACK_SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")

func _init() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var bounds := Rect2(-1300, -800, 2600, 1600)
	var required_patterns := {}
	var realized_corners_by_program := {}
	
	for i in range(5):
		var program = TRACK_ROUTE_GRAMMAR.MARATHON_NAMES[i]
		var seeds_passed = 0
		var corners_realized = 0
		for seed in range(50):
			var res = TRACK_ROUTE_GRAMMAR.construct_marathon(i, seed, 0.0, bounds)
			var rounded = TRACK_ROUTE_GRAMMAR.round_corners_profiled(res.anchors, res.radii, seed)
			var controls = rounded.controls
			if not controls.is_empty():
				seeds_passed += 1
				var tokens = TRACK_SEED_GEN._raw_turn_tokens(controls)
				var pattern = _collapse_tokens(tokens)
				corners_realized = res.anchors.size()
				required_patterns[pattern] = true
				realized_corners_by_program[program] = corners_realized
		if not _expect(seeds_passed > 0, "program " + str(program) + " must realise controls (not empty)"): return
		var count = realized_corners_by_program[program]
		if not _expect(count >= 12 and count <= 32, "program " + str(program) + " realised corner count " + str(count) + " must be within 12..32"): return

	if not _expect(required_patterns.size() >= 4, "must have AT LEAST 4 distinct patterns, got " + str(required_patterns.size())): return
	print("TRACK_MARATHON_PROGRAMS_TEST PASS")
	quit(0)

func _collapse_tokens(tokens: Array) -> String:
	var s = ""
	for t in tokens:
		if t.begins_with("L"):
			if s.is_empty() or s[-1] != "L": s += "L"
		elif t.begins_with("R"):
			if s.is_empty() or s[-1] != "R": s += "R"
	if s.length() > 1 and s[0] == s[-1]:
		s = s.substr(0, s.length() - 1)
	return s

func _expect(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("TRACK_MARATHON_PROGRAMS_TEST FAIL: " + message)
	quit(1)
	return false
