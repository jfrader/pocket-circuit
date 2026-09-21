extends SceneTree

const CRASH_GENERATOR := preload("res://scripts/audio/sfx/crash_voice_generator.gd")
const BOOST_GENERATOR := preload("res://scripts/audio/sfx/boost_voice_generator.gd")
const RUSTBUG := preload("res://data/vehicles/rustbug.tres")
const ANVIL := preload("res://data/vehicles/anvil.tres")
const FLICKER := preload("res://data/vehicles/flicker.tres")


func _initialize() -> void:
	var errors := PackedStringArray()
	errors.append_array(_check_crash_shape())
	errors.append_array(_check_crash_character())
	errors.append_array(_check_crash_determinism())
	errors.append_array(_check_boost())
	if errors.is_empty():
		print("SFX_VOICE_GENERATOR_TEST PASS")
		quit(0)
		return
	for error in errors:
		push_error("SFX_VOICE_GENERATOR_TEST FAIL: " + error)
	quit(1)


func _check_crash_shape() -> PackedStringArray:
	var errors := PackedStringArray()
	var voice := CRASH_GENERATOR.new().generate(RUSTBUG, "rustbug")
	errors.append_array(_expect(voice.tiers.size() == 4, "a crash should carry four strength tiers; got %d" % voice.tiers.size()))
	errors.append_array(_expect(voice.tier_thresholds.size() == 4, "every tier needs a selection threshold"))
	errors.append_array(_expect(not voice.signature.is_empty(), "a crash voice needs a signature"))
	var ascending := true
	for index in range(1, voice.tier_thresholds.size()):
		if voice.tier_thresholds[index] <= voice.tier_thresholds[index - 1]:
			ascending = false
	errors.append_array(_expect(ascending, "tier thresholds must ascend"))
	errors.append_array(_expect(voice.tier_for(0.05) == 0, "a light tap should pick the lightest tier"))
	errors.append_array(_expect(voice.tier_for(1.0) == 3, "the hardest hit should pick the heaviest tier"))
	errors.append_array(_expect(voice.tier_for(0.5) > voice.tier_for(0.2), "harder hits should pick heavier tiers"))
	for tier in voice.tiers:
		var stats := _sample_stats(tier)
		errors.append_array(_expect(bool(stats["finite"]), "crash samples must be finite"))
		errors.append_array(_expect(float(stats["peak"]) <= 1.0, "crash samples must stay inside full scale; peak %.4f" % float(stats["peak"])))
		errors.append_array(_expect(float(stats["peak"]) > 0.7, "every tier should be normalized to a usable peak; got %.3f" % float(stats["peak"])))
	return errors


func _check_crash_character() -> PackedStringArray:
	var errors := PackedStringArray()
	var voice := CRASH_GENERATOR.new().generate(RUSTBUG, "rustbug")
	var light := _brightness(voice.tiers[0])
	var heavy := _brightness(voice.tiers[3])
	errors.append_array(_expect(heavy > light * 1.15, "a heavy hit must be brighter than a light one; %.4f vs %.4f" % [heavy, light]))
	var heavy_car := CRASH_GENERATOR.new().generate(ANVIL, "anvil")
	var light_car := CRASH_GENERATOR.new().generate(FLICKER, "flicker")
	errors.append_array(_expect(_brightness(heavy_car.tiers[3]) < _brightness(light_car.tiers[3]), "a heavier car must ring lower than a light one"))
	errors.append_array(_expect(heavy_car.signature != light_car.signature, "different cars must have different crash voices"))
	return errors


func _check_crash_determinism() -> PackedStringArray:
	var errors := PackedStringArray()
	var first := CRASH_GENERATOR.new().generate(RUSTBUG, "rustbug")
	var second := CRASH_GENERATOR.new().generate(RUSTBUG, "rustbug")
	errors.append_array(_expect(first.signature == second.signature, "the same car must always sign the same crash"))
	errors.append_array(_expect(_digest(first.tiers[3]) == _digest(second.tiers[3]), "the same car must always crash the same way"))
	return errors


func _check_boost() -> PackedStringArray:
	var errors := PackedStringArray()
	var voice := BOOST_GENERATOR.new().generate(RUSTBUG, "rustbug")
	errors.append_array(_expect(voice.tiers.size() == 1, "a boost should be a single voice"))
	var stats := _sample_stats(voice.tiers[0])
	errors.append_array(_expect(bool(stats["finite"]), "boost samples must be finite"))
	errors.append_array(_expect(float(stats["peak"]) <= 1.0, "boost samples must stay inside full scale; got %.3f" % float(stats["peak"])))
	errors.append_array(_expect(float(stats["peak"]) > 0.7, "the boost should be normalized to a usable peak; got %.3f" % float(stats["peak"])))
	var other := BOOST_GENERATOR.new().generate(ANVIL, "anvil")
	errors.append_array(_expect(other.signature != voice.signature, "a stronger machine should have its own boost"))
	errors.append_array(_expect(_digest(other.tiers[0]) != _digest(voice.tiers[0]), "boost_power must shape the boost"))
	return errors


func _sample_stats(samples: PackedFloat32Array) -> Dictionary:
	var peak := 0.0
	var finite := true
	for sample in samples:
		if is_nan(sample) or is_inf(sample):
			finite = false
		peak = maxf(peak, absf(sample))
	return {"peak": peak, "finite": finite}


## Mean absolute slope: a cheap brightness proxy that needs no FFT.
func _brightness(samples: PackedFloat32Array) -> float:
	var total := 0.0
	for index in range(1, samples.size()):
		total += absf(samples[index] - samples[index - 1])
	return total / float(maxi(samples.size() - 1, 1))


func _digest(samples: PackedFloat32Array) -> String:
	var value := 2166136261
	for sample in samples:
		value = ((value ^ int(absf(sample) * 1000000.0)) * 16777619) & 0xffffffff
	return "%08x" % value


func _expect(condition: bool, message: String) -> PackedStringArray:
	if condition:
		return PackedStringArray()
	return PackedStringArray([message])
