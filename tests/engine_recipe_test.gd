extends SceneTree

const RUSTBUG_STATS := preload("res://data/vehicles/rustbug.tres")
const RECIPE_LIBRARY := preload("res://scripts/audio/engine/engine_recipe_library.gd")


func _initialize() -> void:
	var errors := _check_validation()
	if not errors.is_empty():
		_fail(errors)
		return
	errors = _check_derivation()
	if not errors.is_empty():
		_fail(errors)
		return
	errors = _check_override()
	if not errors.is_empty():
		_fail(errors)
		return
	print("ENGINE_RECIPE_TEST PASS")
	quit(0)


func _check_validation() -> PackedStringArray:
	var errors := PackedStringArray()
	var recipe := EngineRecipe.from_vehicle("rustbug", RUSTBUG_STATS)
	errors.append_array(_expect(recipe.is_valid(), "derived recipe should validate: %s" % str(recipe.validate())))
	var base := recipe.duplicate() as EngineRecipe
	base.cylinder_count = 3
	base.firing_order = PackedInt32Array([0, 1, 2])
	var bad_order := base.duplicate() as EngineRecipe
	bad_order.firing_order = PackedInt32Array([0, 0, 1])
	errors.append_array(_expect(_has_error(bad_order, "repeats cylinder"), "duplicate firing order must be rejected"))
	var short_order := base.duplicate() as EngineRecipe
	short_order.firing_order = PackedInt32Array([0, 1])
	errors.append_array(_expect(_has_error(short_order, "firing_order must hold"), "short firing order must be rejected"))
	var stray_order := base.duplicate() as EngineRecipe
	stray_order.firing_order = PackedInt32Array([0, 1, 7])
	errors.append_array(_expect(_has_error(stray_order, "outside 0..2"), "out-of-range firing order must be rejected"))
	var bad_gears := recipe.duplicate() as EngineRecipe
	bad_gears.gear_ratios = PackedFloat32Array([1.0, 2.0, 3.0])
	errors.append_array(_expect(_has_error(bad_gears, "must decrease"), "rising gear ratios must be rejected"))
	var bad_rev := recipe.duplicate() as EngineRecipe
	bad_rev.redline_rpm = bad_rev.idle_rpm
	errors.append_array(_expect(_has_error(bad_rev, "redline_rpm must be greater"), "redline at idle must be rejected"))
	var bad_cam := recipe.duplicate() as EngineRecipe
	bad_cam.cam = 1.4
	errors.append_array(_expect(_has_error(bad_cam, "cam must be within"), "out-of-range cam must be rejected"))
	var unnamed := recipe.duplicate() as EngineRecipe
	unnamed.recipe_id = ""
	errors.append_array(_expect(_has_error(unnamed, "recipe_id must not be empty"), "empty recipe_id must be rejected"))
	return errors


func _check_derivation() -> PackedStringArray:
	var errors := PackedStringArray()
	var first := EngineRecipe.from_vehicle("rustbug", RUSTBUG_STATS)
	var second := EngineRecipe.from_vehicle("rustbug", RUSTBUG_STATS)
	errors.append_array(_expect(first.signature() == second.signature(), "derivation must be deterministic"))
	var pinbolt_stats := load("res://data/vehicles/pinbolt.tres") as VehicleStats
	var pinbolt := EngineRecipe.from_vehicle("pinbolt", pinbolt_stats)
	errors.append_array(_expect(pinbolt.is_valid(), "pinbolt derivation should validate: %s" % str(pinbolt.validate())))
	errors.append_array(_expect(pinbolt.signature() != first.signature(), "different vehicles must derive different voices"))
	errors.append_array(_expect(pinbolt.firing_order.size() == pinbolt.cylinder_count, "derived firing order must cover every cylinder"))
	var heavy := EngineRecipe.from_vehicle("anvil", load("res://data/vehicles/anvil.tres") as VehicleStats)
	var light := EngineRecipe.from_vehicle("flicker", load("res://data/vehicles/flicker.tres") as VehicleStats)
	errors.append_array(_expect(heavy.cylinder_count >= light.cylinder_count, "a bigger engine must not derive fewer cylinders"))
	errors.append_array(_expect(heavy.redline_rpm <= light.redline_rpm, "a peakier engine must not derive a higher redline"))
	errors.append_array(_expect(EngineRecipe.default_firing_order(4) == PackedInt32Array([0, 1, 2, 3]), "default firing order should count up"))
	return errors


func _check_override() -> PackedStringArray:
	var errors := PackedStringArray()
	var resolved := RECIPE_LIBRARY.resolve("rustbug", RUSTBUG_STATS)
	errors.append_array(_expect(resolved.is_valid(), "rustbug override should validate: %s" % str(resolved.validate())))
	errors.append_array(_expect(resolved.cylinder_count == 3, "rustbug override should keep 3 cylinders"))
	errors.append_array(_expect(resolved.firing_order == PackedInt32Array([0, 2, 1]), "rustbug override should keep the [0,2,1] order"))
	errors.append_array(_expect(is_equal_approx(resolved.displacement_l, 0.78), "rustbug override should keep 0.78 L"))
	errors.append_array(_expect(is_equal_approx(resolved.exhaust_primary_m, 0.46), "rustbug override should keep the 0.46 m primary"))
	errors.append_array(_expect(is_equal_approx(resolved.redline_rpm, 7600.0), "rustbug override should keep the 7600 rpm redline"))
	errors.append_array(_expect(is_equal_approx(resolved.gear_ratios[0], 3.15), "rustbug override should keep its first gear"))
	errors.append_array(_expect(RECIPE_LIBRARY.vehicle_id_for(RUSTBUG_STATS) == "rustbug", "vehicle id should come from the stats resource name"))
	var derived := RECIPE_LIBRARY.resolve("spindle", load("res://data/vehicles/spindle.tres") as VehicleStats)
	errors.append_array(_expect(derived.recipe_id == "spindle", "vehicles without an override should derive from stats"))
	return errors


func _has_error(recipe: EngineRecipe, fragment: String) -> bool:
	for error in recipe.validate():
		if error.contains(fragment):
			return true
	return false


func _expect(condition: bool, message: String) -> PackedStringArray:
	if condition:
		return PackedStringArray()
	return PackedStringArray([message])


func _fail(errors: PackedStringArray) -> void:
	for error in errors:
		push_error("ENGINE_RECIPE_TEST FAIL: " + error)
	quit(1)
