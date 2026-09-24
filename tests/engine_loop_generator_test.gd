extends SceneTree

const GENERATOR := preload("res://scripts/audio/engine/engine_loop_generator.gd")
const LIBRARY := preload("res://scripts/audio/engine/engine_recipe_library.gd")
const CATALOG := preload("res://data/championship/catalog.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var errors := PackedStringArray()
	if not is_equal_approx(GENERATOR.pitch_for_rpm(4000.0, 2000.0), 1.7):
		errors.append("pitch should clamp at the top of the opponent range")
	if not is_equal_approx(GENERATOR.pitch_for_rpm(1000.0, 4000.0), 0.5):
		errors.append("pitch should clamp at the bottom of the opponent range")
	var stats := CATALOG.create_vehicle_stats("rustbug")
	var recipe := LIBRARY.resolve("rustbug", stats)
	var first := GENERATOR.generate_cached(recipe)
	var second := GENERATOR.generate_cached(recipe)
	if first != second:
		errors.append("the same recipe must reuse one loop")
	if first == null or not first is AudioStreamWAV:
		errors.append("opponent engine loop must be a WAV")
	elif first.loop_mode != AudioStreamWAV.LOOP_FORWARD or first.loop_end <= first.loop_begin:
		errors.append("opponent engine loop must have forward loop points")
	elif not first.has_meta("base_rpm") or float(first.get_meta("base_rpm")) <= 0.0:
		errors.append("opponent engine loop must remember the rpm it was rendered at")
	elif String(first.get_meta("recipe_signature")) != recipe.signature():
		errors.append("opponent engine loop must carry its recipe signature")
	var other := LIBRARY.resolve("anvil", CATALOG.create_vehicle_stats("anvil"))
	var other_loop := GENERATOR.generate_cached(other)
	if other_loop == first:
		errors.append("different recipes must not share a loop")
	if errors.is_empty():
		print("ENGINE_LOOP_GENERATOR_TEST PASS")
		quit(0)
		return
	for error in errors:
		push_error("ENGINE_LOOP_GENERATOR_TEST FAIL: " + error)
	quit(1)
