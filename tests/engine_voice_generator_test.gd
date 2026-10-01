extends SceneTree

const RUSTBUG_STATS := preload("res://data/vehicles/rustbug.tres")
const RECIPE_LIBRARY := preload("res://scripts/audio/engine/engine_recipe_library.gd")
const TABLE_BUDGET_BYTES := 80 * 1024


func _initialize() -> void:
	var errors := PackedStringArray()
	var recipe := RECIPE_LIBRARY.resolve("rustbug", RUSTBUG_STATS)
	var voice := EngineVoiceGenerator.new().generate(recipe)
	errors.append_array(_check_shape(voice))
	errors.append_array(_check_content(voice))
	errors.append_array(_check_determinism(recipe, voice))
	errors.append_array(_check_seed_sensitivity(recipe))
	if errors.is_empty():
		print("ENGINE_VOICE_GENERATOR_TEST PASS")
		quit(0)
		return
	for error in errors:
		push_error("ENGINE_VOICE_GENERATOR_TEST FAIL: " + error)
	quit(1)


func _check_shape(voice: EngineVoice) -> PackedStringArray:
	var errors := PackedStringArray()
	errors.append_array(_expect(voice.rpm_band_count() == 4, "voice should hold 4 rpm bands"))
	errors.append_array(_expect(voice.load_band_count() == 4, "voice should hold 4 load bands"))
	errors.append_array(_expect(voice.tables.size() == 4, "voice should hold one table layer per rpm band"))
	errors.append_array(_expect(voice.sample_count == 1024, "one firing cycle should be 1024 samples"))
	errors.append_array(_expect(voice.mechanical.size() == 1024, "mechanical table should be one cycle long"))
	errors.append_array(_expect(voice.table_bytes() <= TABLE_BUDGET_BYTES, "voice bank should stay inside the 80 KiB budget; got %d" % voice.table_bytes()))
	errors.append_array(_expect(is_equal_approx(voice.rpm_bands[0], voice.recipe.idle_rpm), "lowest rpm band should sit at idle"))
	errors.append_array(_expect(is_equal_approx(voice.rpm_bands[3], voice.recipe.redline_rpm), "highest rpm band should sit at redline"))
	return errors


func _check_content(voice: EngineVoice) -> PackedStringArray:
	var errors := PackedStringArray()
	var peak := 0.0
	var total := 0.0
	var count := 0
	var finite := true
	var dc := 0.0
	for layer in voice.tables:
		for table: PackedFloat32Array in layer:
			var mean := 0.0
			for sample in table:
				if is_nan(sample) or is_inf(sample):
					finite = false
				peak = maxf(peak, absf(sample))
				total += absf(sample)
				count += 1
				mean += sample
			dc = maxf(dc, absf(mean / float(table.size())))
	errors.append_array(_expect(finite, "generated tables must be finite"))
	errors.append_array(_expect(peak > 0.1, "generated tables must carry signal; peak %.4f" % peak))
	errors.append_array(_expect(peak <= 1.0, "generated tables must stay inside full scale; peak %.4f" % peak))
	errors.append_array(_expect(total / float(maxi(count, 1)) > 0.001, "generated tables must not be near-silent"))
	errors.append_array(_expect(dc < 0.001, "generated tables must be DC-free; worst %.5f" % dc))
	var idle_layer: Array = voice.tables[0]
	var redline_layer: Array = voice.tables[3]
	errors.append_array(_expect(idle_layer[0] != redline_layer[0], "load and rpm bands must not generate identical tables"))
	return errors


func _check_determinism(recipe: EngineRecipe, first: EngineVoice) -> PackedStringArray:
	var errors := PackedStringArray()
	var generator := EngineVoiceGenerator.new()
	var second := generator.generate(recipe)
	errors.append_array(_expect(_digest(first) == _digest(second), "same recipe must generate an identical bank"))
	errors.append_array(_expect(first.signature == second.signature, "same recipe must produce the same signature"))
	var reused := generator.generate(recipe)
	errors.append_array(_expect(_digest(second) == _digest(reused), "reusing a generator must reset its band and runner state"))
	return errors


func _check_seed_sensitivity(recipe: EngineRecipe) -> PackedStringArray:
	var errors := PackedStringArray()
	var reseeded := recipe.duplicate() as EngineRecipe
	reseeded.identity_seed = "pc:rustbug:engine-v1:factory-b"
	var reseeded_voice := EngineVoiceGenerator.new().generate(reseeded)
	errors.append_array(_expect(reseeded_voice.signature != recipe.signature(), "a new identity seed must change the signature"))
	errors.append_array(_expect(_digest(reseeded_voice) != _digest(EngineVoiceGenerator.new().generate(recipe)), "a new identity seed must change the runner variation"))
	return errors


func _digest(voice: EngineVoice) -> String:
	var value := 2166136261
	for layer in voice.tables:
		for table: PackedFloat32Array in layer:
			for sample in table:
				value = ((value ^ int(absf(sample) * 1000000.0)) * 16777619) & 0xffffffff
	for sample in voice.mechanical:
		value = ((value ^ int(absf(sample) * 1000000.0)) * 16777619) & 0xffffffff
	return "%08x" % value


func _expect(condition: bool, message: String) -> PackedStringArray:
	if condition:
		return PackedStringArray()
	return PackedStringArray([message])
